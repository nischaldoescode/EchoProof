-- Lightweight interaction signals for feed personalization.
-- These flow into user_category_affinity via the record_feed_signal function.
-- Signals decay over 48 hours to prevent stale behavior locking the feed.
-- run order: 034

-- Add dwell_time tracking to user_feed_signals for implicit interest detection.
alter table public.user_feed_signals
  add column if not exists echo_id uuid references echoes(id) on delete cascade,
  add column if not exists dwell_seconds integer default 0;

-- Decayed affinity view: applies exponential decay to recent signals.
-- Used by the feed ranking function instead of the raw materialized view.
-- Decay half-life: ~48 hours. Signal fully fades in ~7 days.
create or replace view user_category_affinity_decayed as
select
  user_id,
  signal_value as category,
  sum(
    weight * exp(-extract(epoch from (now() - created_at)) / 172800.0)
  ) as affinity_score,
  count(*)     as interaction_count,
  max(created_at) as last_interacted_at
from user_feed_signals
where signal_type in ('category_view', 'category_support', 'category_challenge', 'category_click')
  and created_at > now() - interval '7 days'
group by user_id, signal_value;

-- Index for decayed view performance.
create index if not exists user_feed_signals_decay_idx
  on user_feed_signals(user_id, signal_type, created_at desc);

-- Cold start baseline: new users with no affinity get a neutral default.
-- This prevents the ranking from being 100% trust_score driven for new users.
create or replace function get_category_affinity(
  p_user_id uuid,
  p_category text
) returns numeric language sql stable security definer as $$
  select coalesce(
    (select affinity_score
     from user_category_affinity_decayed
     where user_id = p_user_id
       and category = p_category
     limit 1),
    10.0  -- cold start baseline: neutral affinity for unknown categories
  );
$$;

-- Record a dwell-time signal when a user spends >3 seconds on an echo.
-- Called client-side when scroll position implies reading.
create or replace function record_dwell_signal(
  p_user_id  uuid,
  p_echo_id  uuid,
  p_category text,
  p_seconds  integer
) returns void language plpgsql security definer as $$
declare
  v_weight numeric;
begin
  -- Weight based on dwell time: >10s = strong interest, 3-10s = mild.
  v_weight := case
    when p_seconds > 10 then 1.5
    when p_seconds > 5  then 0.8
    else                     0.3
  end;

  -- Fade very quickly — dwell is a weak signal.
  insert into user_feed_signals (user_id, signal_type, signal_value, weight, echo_id, dwell_seconds)
  values (p_user_id, 'category_view', p_category, v_weight, p_echo_id, p_seconds);
end;
$$;