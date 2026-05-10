-- Feed ranking v3: fixes performance issues + uses decayed affinity.
-- Changes from v2:
--   - Pre-join category affinity (no per-row subquery)
--   - Use e.category = any(up.categories) directly (no subquery)
--   - Use not exists instead of not in for exploration
--   - Cold start baseline via get_category_affinity
--   - Remove double recency (keep only decay, remove linear recency from base)
--   - Cap trust_score to prevent gaming (log scale + hard cap)
--   - Exploration uses 30% of score, not 0
--   - Probabilistic sampling for exploration (not order by random())
-- run order: 035

create or replace function get_personalized_feed(
  p_user_id uuid,
  p_offset  integer default 0,
  p_limit   integer default 20
) returns table (
  echo_id            uuid,
  personalized_score numeric
) language plpgsql security definer as $$
declare
  v_ranked_limit integer;
  v_random_limit integer;
  v_user_categories text[];
begin
  -- 90% ranked, 10% exploration (min 1 random slot).
  v_ranked_limit := greatest(p_limit - greatest(p_limit / 10, 1), 1);
  v_random_limit := p_limit - v_ranked_limit;

  -- Cache user's selected categories to avoid per-row lookup.
  select categories into v_user_categories
  from users_public where id = p_user_id;

  return query
  -- CTE 1: Pre-join affinity scores once (not per-row subquery).
  with user_affinities as (
    select
      signal_value as category,
      sum(weight * exp(-extract(epoch from (now() - created_at)) / 172800.0)) as affinity_score
    from user_feed_signals
    where user_id = p_user_id
      and signal_type in ('category_view', 'category_support', 'category_challenge', 'category_click')
      and created_at > now() - interval '7 days'
    group by signal_value
  ),

  -- CTE 2: Base scores — tier-agnostic quality signal.
  -- NOTE: No linear recency here. Time decay handles freshness in CTE 3.
  base as (
    select
      e.id                                              as echo_id,
      e.user_id                                         as author_id,
      up.trust_tier                                     as author_tier,
      up.is_pro                                         as author_is_pro,
      extract(epoch from (now() - e.created_at)) / 3600.0 as age_hours,
      (
        -- Trust score: capped + log-scaled to prevent gaming.
        -- log(1 + min(trust, 100)) maps 0→0, 10→2.4, 100→4.6, 1000→4.6 (capped).
        (ln(1.0 + least(e.trust_score::numeric, 100.0)) / ln(101.0)) * 40.0

        -- Category affinity (pre-joined, not subquery).
        + coalesce(ua.affinity_score, 10.0) * 0.30

        -- Confidence: % of weighted interactions supportive.
        + (e.confidence_score * 0.15)

        -- Controversy: slight boost (keeps feed interesting).
        + (e.controversy_score * 0.05)

        -- Category preference bonus: user explicitly selected this category.
        + case when e.category = any(v_user_categories) then 15.0 else 0.0 end

        -- Already-interacted penalty.
        - case when exists (
            select 1 from echo_interactions ei
            where ei.echo_id = e.id and ei.user_id = p_user_id
          ) then 30.0 else 0.0 end
      ) as base_score
    from echoes e
    inner join users_public up on up.id = e.user_id
    -- Pre-join affinity once via category match (no per-row subquery).
    left join user_affinities ua on ua.category = e.category
    where e.status not in ('hidden', 'rejected')
      and e.user_id != p_user_id
      and e.created_at > now() - interval '30 days'
  ),

  -- CTE 3: Non-linear time decay (replaces linear recency from base score).
  decayed as (
    select
      echo_id,
      author_id,
      author_tier,
      author_is_pro,
      age_hours,
      base_score * case
        when age_hours < 24    then 1.00
        when age_hours < 72    then 0.85
        when age_hours < 168   then 0.50 + (0.35 * (1.0 - (age_hours - 72.0) / 96.0))
        else                        0.30
      end as decayed_score
    from base
  ),

  -- CTE 4: Tier soft boost — max 1.25x cap prevents pay-to-win.
  boosted as (
    select
      echo_id,
      author_id,
      author_tier,
      author_is_pro,
      decayed_score * case
        when author_is_pro and author_tier in ('high', 'elite') then 1.25
        when author_is_pro                                       then 1.15
        when author_tier in ('high', 'elite')                   then 1.10
        when author_tier = 'medium'                             then 1.05
        else                                                         1.00
      end as boosted_score
    from decayed
  ),

  -- CTE 5: Creator diversity — penalize second and third+ posts per creator.
  diversity as (
    select
      echo_id,
      author_id,
      author_is_pro,
      boosted_score,
      row_number() over (
        partition by author_id
        order by boosted_score desc
      ) as author_rank
    from boosted
  ),

  -- CTE 6: Diversity penalty.
  penalised as (
    select
      echo_id,
      author_id,
      author_is_pro,
      boosted_score * case
        when author_rank = 1 then 1.00
        when author_rank = 2 then 0.70
        else                      0.40
      end as final_score
    from diversity
  ),

  -- CTE 7: Ranked portion (90% of results).
  ranked_posts as (
    select
      echo_id,
      final_score as personalized_score
    from penalised
    order by final_score desc
    offset p_offset
    limit v_ranked_limit
  ),

  -- CTE 8: Exploration portion (10% random using probabilistic sampling).
  -- Uses random() < threshold instead of ORDER BY random() — much cheaper.
  -- Score is 30% of actual score, not 0 — avoids showing junk content.
  random_posts as (
    select
      echo_id,
      final_score * 0.3 as personalized_score
    from penalised
    where
      -- Probabilistic sample: each row has ~5% chance of being included.
      random() < 0.05
      -- Exclude posts already in the ranked portion.
      and not exists (
        select 1 from ranked_posts rp
        where rp.echo_id = penalised.echo_id
      )
    limit v_random_limit
  )

  -- Final: ranked posts first, then exploration.
  select echo_id, personalized_score from ranked_posts
  union all
  select echo_id, personalized_score from random_posts;
end;
$$;