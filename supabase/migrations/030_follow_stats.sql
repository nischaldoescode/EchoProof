-- user follow relationships
-- run order: 030

create table if not exists public.user_follows (
  id          uuid primary key default gen_random_uuid(),
  follower_id uuid not null references users_public(id) on delete cascade,
  following_id uuid not null references users_public(id) on delete cascade,
  created_at  timestamptz not null default now(),
  unique(follower_id, following_id),
  check (follower_id != following_id)
);

create index user_follows_follower_idx on user_follows(follower_id);
create index user_follows_following_idx on user_follows(following_id);

alter table public.user_follows enable row level security;

create policy "users can see follows"
  on user_follows for select
  to authenticated
  using (true);

create policy "users can follow"
  on user_follows for insert
  to authenticated
  with check (auth.uid() = follower_id);

create policy "users can unfollow"
  on user_follows for delete
  to authenticated
  using (auth.uid() = follower_id);

-- Add follower/following counts to users_public for fast display.
alter table public.users_public
  add column if not exists follower_count integer not null default 0,
  add column if not exists following_count integer not null default 0;

-- Trigger to keep counts in sync.
create or replace function sync_follow_counts()
returns trigger language plpgsql security definer as $$
begin
  if TG_OP = 'INSERT' then
    update users_public set follower_count = follower_count + 1 where id = NEW.following_id;
    update users_public set following_count = following_count + 1 where id = NEW.follower_id;
  elsif TG_OP = 'DELETE' then
    update users_public set follower_count = greatest(follower_count - 1, 0) where id = OLD.following_id;
    update users_public set following_count = greatest(following_count - 1, 0) where id = OLD.follower_id;
  end if;
  return null;
end;
$$;

create trigger on_follow_change
  after insert or delete on user_follows
  for each row execute function sync_follow_counts();