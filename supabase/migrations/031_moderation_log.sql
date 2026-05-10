-- Tracks moderation API calls per user for rate limiting.
create table if not exists public.moderation_log (
  id         uuid primary key default gen_random_uuid(),
  user_id    uuid not null references auth.users(id) on delete cascade,
  echo_id    uuid references echoes(id) on delete set null,
  created_at timestamptz not null default now()
);

create index moderation_log_user_idx on moderation_log(user_id, created_at desc);

alter table public.moderation_log enable row level security;

create policy "service role manages moderation log"
  on moderation_log for all
  to service_role
  using (true) with check (true);