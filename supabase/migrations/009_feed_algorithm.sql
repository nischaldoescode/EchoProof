-- user interaction tracking for feed personalization
-- stores which categories, signals, and users each person engages with
-- run order: 009
create extension if not exists "pgcrypto";
create extension if not exists "pg_trgm";

create table if not exists user_feed_signals (
  id           uuid primary key default gen_random_uuid(),
  user_id      uuid not null references users_public(id) on delete cascade,
  signal_type  text not null check (signal_type in (
    'category_view',
    'category_support',
    'category_challenge',
    'signal_view',
    'user_follow',
    'echo_view',
    'echo_support',
    'echo_challenge',
    'echo_bond'
  )),
  signal_value text not null,
  weight       numeric(4,2) not null default 1.0,
  created_at   timestamptz not null default now()
);

create index if not exists user_feed_signals_user_idx on user_feed_signals(user_id);
create index if not exists  user_feed_signals_type_idx on user_feed_signals(signal_type, signal_value);

-- materialized view for user category affinity scores
-- refreshed by trust engine every hour
create materialized view user_category_affinity as
select
  user_id,
  signal_value as category,
  sum(weight)  as affinity_score,
  count(*)     as interaction_count,
  max(created_at) as last_interacted_at
from user_feed_signals
where signal_type in ('category_view', 'category_support', 'category_challenge')
  and created_at > now() - interval '30 days'
group by user_id, signal_value;

create index if not exists user_category_affinity_user_idx
  on user_category_affinity(user_id);

create unique index user_category_affinity_unique_idx
  on user_category_affinity(user_id, category);

-- function to record a feed signal (called from edge function)
create or replace function record_feed_signal(
  p_user_id     uuid,
  p_signal_type text,
  p_signal_value text,
  p_weight      numeric default 1.0
) returns void language plpgsql security definer as $$
begin
  insert into user_feed_signals (user_id, signal_type, signal_value, weight)
  values (p_user_id, p_signal_type, p_signal_value, p_weight);
end;
$$;

-- personalized feed scoring function
-- combines: trust score, user affinity, recency, novelty
-- returns echoes ranked for a specific user
create or replace function get_personalized_feed(
  p_user_id uuid,
  p_offset  integer default 0,
  p_limit   integer default 20
) returns table (
  echo_id         uuid,
  personalized_score numeric
) language plpgsql security definer as $$
begin
  return query
  select
    e.id as echo_id,
    (
      -- base trust score (40% weight)
      (e.trust_score::numeric * 0.40)

      -- category affinity bonus (30% weight)
      + coalesce(
          (select affinity_score from user_category_affinity
           where user_id = p_user_id and category = e.category
           limit 1),
          0
        ) * 0.30

      -- recency score (20% weight)
      -- echoes from last 24h get full score, decays over 7 days
      + (20.0 * greatest(0, 1 - extract(epoch from (now() - e.created_at)) / 604800)) * 0.20

      -- confidence bonus for verified echoes (10% weight)
      + (e.confidence_score * 0.10)

      -- small controversy boost — keeps feed interesting
      + (e.controversy_score * 0.05)

      -- user's selected categories get a static boost
+ case when e.category = any(
    select unnest(categories)
    from users_public
    where id = p_user_id
  ) then 15 else 0 end

      -- penalty for already-interacted echoes
      - case when exists (
          select 1 from echo_interactions
          where echo_id = e.id and user_id = p_user_id
        ) then 30 else 0 end

    ) as personalized_score
  from echoes e
  where e.status not in ('hidden', 'rejected')
    -- do not show user's own echoes in main feed
    and e.user_id != p_user_id
  order by personalized_score desc
  offset p_offset
  limit p_limit;
end;
$$;