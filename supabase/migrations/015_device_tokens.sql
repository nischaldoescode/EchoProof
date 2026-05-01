-- stores FCM device tokens per user
-- one user can have multiple devices
create table device_tokens (
  id          uuid primary key default gen_random_uuid(),
  user_id     uuid not null references auth.users(id) on delete cascade,
  token       text not null,
  platform    text not null check (platform in ('android', 'ios')),
  updated_at  timestamptz not null default now(),
  unique(user_id, token)
);

-- index for fast lookup by user
create index device_tokens_user_idx on device_tokens(user_id);

-- rls: users can only see and manage their own tokens
alter table device_tokens enable row level security;

create policy "users manage own tokens" on device_tokens
  using (auth.uid() = user_id)
  with check (auth.uid() = user_id);

-- service role can read all tokens for sending notifications
create policy "service role reads all" on device_tokens
  for select using (true);