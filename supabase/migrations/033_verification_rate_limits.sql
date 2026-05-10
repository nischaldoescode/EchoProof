-- Verification rate limits and IP-based controls.
-- run order: 033

-- Add IP tracking to verification_sessions.
alter table public.verification_sessions
  add column if not exists ip_address text,
  add column if not exists country_code text;

-- IP-based attempt tracking (separate from user-based).
create table if not exists public.verification_ip_log (
  id         uuid primary key default gen_random_uuid(),
  ip_address text not null,
  user_id    uuid not null references auth.users(id) on delete cascade,
  created_at timestamptz not null default now()
);

create index verification_ip_log_ip_idx on verification_ip_log(ip_address, created_at desc);
create index verification_ip_log_user_idx on verification_ip_log(user_id, created_at desc);

alter table public.verification_ip_log enable row level security;

create policy "service role manages ip log"
  on verification_ip_log for all
  to service_role
  using (true) with check (true);

-- Helper: count verification attempts from an IP in the past 30 days.
create or replace function count_verification_attempts_by_ip(
  p_ip text,
  p_days integer default 30
) returns integer language sql security definer as $$
  select count(*)::integer
  from verification_ip_log
  where ip_address = p_ip
    and created_at > now() - (p_days || ' days')::interval;
$$;

-- Helper: count verification attempts by user in the past 30 days.
create or replace function count_verification_attempts_by_user(
  p_user_id uuid,
  p_days integer default 30
) returns integer language sql security definer as $$
  select count(*)::integer
  from verification_ip_log
  where user_id = p_user_id
    and created_at > now() - (p_days || ' days')::interval;
$$;