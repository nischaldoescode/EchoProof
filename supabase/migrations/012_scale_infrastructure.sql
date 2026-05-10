-- scale infrastructure migrations
-- implements: version numbers, batch scoring queue, pg_cron schedules
-- run order: 012

create extension if not exists pg_cron;

-- version column on echoes — flutter compares this to detect stale data
alter table echoes add column if not exists version integer not null default 1;

-- auto-increment version on every score update
create or replace function increment_echo_version()
returns trigger language plpgsql as $$
begin
  new.version = old.version + 1;
  return new;
end;
$$;

create trigger echo_version_increment
  before update of trust_score, confidence_score, controversy_score, report_score, status
  on echoes
  for each row
  execute function increment_echo_version();

-- scoring queue — tracks which echoes need recalculation
-- more efficient than calling recalculate_echo_scores inline on every interaction
create table echo_score_queue (
  echo_id    uuid primary key references echoes(id) on delete cascade,
  queued_at  timestamptz not null default now(),
  priority   integer not null default 1  -- higher = more urgent
);

create index echo_score_queue_priority_idx on echo_score_queue(priority desc, queued_at asc);

-- function to enqueue an echo for scoring
-- called by interaction and report triggers instead of direct recalculation
create or replace function enqueue_echo_scoring(
  p_echo_id uuid,
  p_priority integer default 1
) returns void language plpgsql security definer as $$
begin
  insert into echo_score_queue (echo_id, priority)
  values (p_echo_id, p_priority)
  on conflict (echo_id) do update
    set queued_at = now(),
        priority  = greatest(echo_score_queue.priority, excluded.priority);
end;
$$;

-- batch scoring function — processes up to 100 echoes from the queue
-- called by trust-engine edge function every 30 seconds
create or replace function process_score_queue(p_batch_size integer default 100)
returns integer language plpgsql security definer as $$
declare
  v_echo_ids uuid[];
  v_processed integer := 0;
begin
  -- lock and claim a batch atomically
  with claimed as (
    delete from echo_score_queue
    where echo_id in (
      select echo_id from echo_score_queue
      order by priority desc, queued_at asc
      limit p_batch_size
      for update skip locked
    )
    returning echo_id
  )
  select array_agg(echo_id) into v_echo_ids from claimed;

  if v_echo_ids is null then
    return 0;
  end if;

  -- recalculate scores for all claimed echoes
  for i in 1..array_length(v_echo_ids, 1) loop
    perform recalculate_echo_scores(v_echo_ids[i]);
    v_processed := v_processed + 1;
  end loop;

  return v_processed;
end;
$$;

-- pg_cron: refresh materialized view every 30 minutes
-- requires pg_cron extension: supabase dashboard > extensions > pg_cron
select cron.schedule(
  'refresh-category-affinity',
  '*/30 * * * *',
  $$refresh materialized view concurrently user_category_affinity$$
);

-- pg_cron: process score queue every 30 seconds
-- this replaces inline recalculate_echo_scores calls at high scale
select cron.schedule(
  'process-score-queue',
  '*/1 * * * *',  -- every minute (pg_cron minimum is 1 minute)
  $$select process_score_queue(100)$$
);

-- pg_cron: settle matured truth bonds daily
select cron.schedule(
  'settle-matured-bonds',
  '0 2 * * *',  -- 2am daily
  $$select settle_matured_bonds()$$
);

-- pg_cron: expire zero-engagement echoes daily
select cron.schedule(
  'expire-zero-engagement',
  '0 3 * * *',  -- 3am daily
  $$select expire_zero_engagement_echoes()$$
);