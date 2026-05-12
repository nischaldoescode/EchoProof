-- Let the home feed include the viewer's own visible echoes.
-- Previously, get_personalized_feed filtered out e.user_id = p_user_id,
-- which made a user's profile show echoes while Home stayed empty.

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

  select coalesce(
    array(
      select c::text
      from unnest(coalesce(up.categories, '{}'::echo_category[])) as c
    ),
    '{}'::text[]
  )
  into v_user_categories
  from users_public up
  where up.id = p_user_id;

  v_user_categories := coalesce(v_user_categories, '{}'::text[]);

  return query
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

  base as (
    select
      e.id as echo_id,
      e.user_id as author_id,
      up.trust_tier as author_tier,
      up.is_pro as author_is_pro,
      extract(epoch from (now() - e.created_at)) / 3600.0 as age_hours,
      (
        (ln(1.0 + greatest(0.0, least(coalesce(e.trust_score, 0)::numeric, 100.0))) / ln(101.0)) * 40.0
        + coalesce(ua.affinity_score, 10.0) * 0.30
        + (coalesce(e.confidence_score, 0) * 0.15)
        + (coalesce(e.controversy_score, 0) * 0.05)
        + case
            when e.category::text = any(v_user_categories) then 15.0
            else 0.0
          end
        + case
            when e.user_id = p_user_id then 12.0
            else 0.0
          end
        - case
            when e.user_id <> p_user_id and exists (
              select 1
              from echo_interactions ei
              where ei.echo_id = e.id
                and ei.user_id = p_user_id
            ) then 30.0
            else 0.0
          end
      ) as base_score
    from echoes e
    inner join users_public up on up.id = e.user_id
    left join user_affinities ua on ua.category = e.category::text
    where e.status not in ('hidden', 'rejected')
      and e.created_at > now() - interval '30 days'
  ),

  decayed as (
    select
      b.echo_id,
      b.author_id,
      b.author_tier,
      b.author_is_pro,
      b.age_hours,
      b.base_score * case
        when b.age_hours < 24    then 1.00
        when b.age_hours < 72    then 0.85
        when b.age_hours < 168   then 0.50 + (0.35 * (1.0 - (b.age_hours - 72.0) / 96.0))
        else                          0.30
      end as final_score
    from base b
  ),

  ranked as (
    select
      d.echo_id,
      d.final_score
      * case
          when d.author_is_pro and d.author_tier::text in ('high', 'elite') then 1.25
          when d.author_is_pro then 1.15
          when d.author_tier::text in ('high', 'elite') then 1.10
          when d.author_tier::text = 'medium' then 1.05
          else 1.0
        end as personalized_score
    from decayed d
    order by personalized_score desc, d.age_hours asc
    offset p_offset
    limit v_ranked_limit
  ),

  exploration as (
    select
      d.echo_id,
      d.final_score * 0.30 as personalized_score
    from decayed d
    where random() < 0.05
      and not exists (
        select 1 from ranked r where r.echo_id = d.echo_id
      )
    limit v_random_limit
  )

  select r.echo_id, r.personalized_score::numeric from ranked r
  union all
  select e.echo_id, e.personalized_score::numeric from exploration e;
end;
$$;
