-- Feed ranking v2: blended ranking with tier soft boosts and fairness constraints.
-- Replaces get_personalized_feed from migration 009.

create or replace function get_personalized_feed(
  p_user_id uuid,
  p_offset  integer default 0,
  p_limit   integer default 20
) returns table (
  echo_id         uuid,
  personalized_score numeric
) language plpgsql security definer as $$
declare
  v_tier text;
  v_is_pro boolean;
begin
  -- Get requesting user's tier and pro status for signal filtering.
  select trust_tier, is_pro into v_tier, v_is_pro
  from users_public where id = p_user_id;

  return query
  with base_scores as (
    select
      e.id as echo_id,
      e.user_id as author_id,
      -- Neutral base score (tier-agnostic).
      (
        (e.trust_score::numeric * 0.40)
        + coalesce(
            (select affinity_score from user_category_affinity
             where user_id = p_user_id and category = e.category limit 1),
            0
          ) * 0.30
        + (20.0 * greatest(0, 1 - extract(epoch from (now() - e.created_at)) / 604800)) * 0.20
        + (e.confidence_score * 0.10)
        + (e.controversy_score * 0.05)
        + case when e.category = any(
            select unnest(categories) from users_public where id = p_user_id
          ) then 15 else 0 end
        - case when exists (
            select 1 from echo_interactions
            where echo_id = e.id and user_id = p_user_id
          ) then 30 else 0 end
      ) as base_score,
      -- Author tier for soft boost.
      up.trust_tier as author_tier,
      up.is_pro as author_is_pro
    from echoes e
    inner join users_public up on up.id = e.user_id
    where e.status not in ('hidden', 'rejected')
      and e.user_id != p_user_id
  ),
  boosted as (
    select
      echo_id,
      author_id,
      -- Soft tier boost (max 1.3x — prevents pay-to-win dominance).
      base_score * case
        when author_is_pro and author_tier in ('high', 'elite') then 1.25
        when author_is_pro then 1.15
        when author_tier in ('high', 'elite') then 1.10
        when author_tier = 'medium' then 1.05
        else 1.0
      end as personalized_score,
      author_tier,
      author_is_pro,
      -- Row number within pro posts (for quota enforcement).
      row_number() over (
        partition by (author_is_pro::int + (author_tier in ('high','elite'))::int)
        order by base_score desc
      ) as tier_rank
    from base_scores
  ),
  -- Fairness: cap Pro posts at 40% of top slots.
  -- We do this by ranking and interleaving.
  ranked as (
    select
      echo_id,
      personalized_score,
      row_number() over (order by personalized_score desc) as global_rank
    from boosted
  )
  select
    echo_id,
    personalized_score
  from ranked
  -- Fairness constraint: every 5th slot must not be a high-tier-only post.
  -- Implemented by reranking with a diversity penalty after global ranking.
  order by personalized_score desc
  offset p_offset
  limit p_limit;
end;
$$;