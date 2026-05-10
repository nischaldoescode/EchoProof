-- adds signals (hashtag equivalent) support to echoproof
-- signals use ~ prefix in content and are indexed for search
-- run order: 007 (after 006_solana_fields)

create extension if not exists "pgcrypto";
create extension if not exists "pg_trgm";

create table echo_signals (
  id         uuid primary key default gen_random_uuid(),
  echo_id    uuid not null references echoes(id) on delete cascade,
  signal     text not null check (signal ~ '^~[a-z0-9_]+$'),
  created_at timestamptz not null default now()
);

create index echo_signals_signal_idx on echo_signals(signal);
create index echo_signals_echo_id_idx on echo_signals(echo_id);

-- signals can't be duplicated on same echo
create unique index echo_signals_unique_idx on echo_signals(echo_id, signal);

-- trending signals view — used by the discover feed
create or replace view trending_signals as
select
  signal,
  count(*) as echo_count,
  max(created_at) as last_used_at
from echo_signals
where created_at > now() - interval '24 hours'
group by signal
order by echo_count desc
limit 20;