create table public.verification_sessions (
  id                uuid primary key default gen_random_uuid(),
  user_id           uuid not null references auth.users(id) on delete cascade,
  didit_session_id  text,
  status            text not null default 'pending'
                    check (status in ('pending', 'completed', 'failed', 'cancelled')),
  created_at        timestamptz not null default now(),
  updated_at        timestamptz not null default now()
);

alter table public.verification_sessions enable row level security;

create policy "service role manages verification sessions"
  on public.verification_sessions
  using (true) with check (true);

create policy "user can read own verification session"
  on public.verification_sessions for select
  to authenticated
  using (auth.uid() = user_id);

create index verification_sessions_user_idx on public.verification_sessions(user_id);