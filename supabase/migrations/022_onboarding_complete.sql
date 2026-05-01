-- migration 022: onboarding_complete flag + fix trigger + partial unique index
-- run this in supabase sql editor or via supabase db push

-- 1. add onboarding flag to users_public
alter table public.users_public
  add column if not exists onboarding_complete boolean not null default false;

-- 2. drop old constraint (must drop constraint, not index directly)
alter table public.users_public
  drop constraint if exists unique_username;

-- also drop the index if it exists independently
drop index if exists public.unique_username;

-- 3. recreate as partial unique index (nulls allowed, only non-null usernames must be unique)
create unique index unique_username
  on public.users_public (username)
  where username is not null;

-- 4. recreate trigger function — NOTE: use new.id not [new.id](http://new.id)
create or replace function public.handle_new_user()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
declare
  _display_name text;
begin
  _display_name := coalesce(
    new.raw_user_meta_data->>'full_name',
    new.raw_user_meta_data->>'name'
  );

  insert into public.users_public (
    id,
    username,
    display_name,
    trust_tier,
    trust_score,
    echo_count,
    proof_count,
    is_public,
    onboarding_complete,
    created_at
  ) values (
    new.id,
    null,
    _display_name,
    'unverified',
    0,
    0,
    0,
    true,
    false,
    now()
  )
  on conflict (id) do nothing;

  insert into public.users_private (
    id,
    email,
    is_identity_verified,
    created_at
  ) values (
    new.id,
    coalesce(new.email, ''),
    false,
    now()
  )
  on conflict (id) do nothing;

  return new;
exception
  when others then
    raise log 'handle_new_user error for id=%: % (sqlstate=%)', new.id, sqlerrm, sqlstate;
    return new;
end;
$$;

-- 5. backfill: fix any existing rows that have username=null but were incorrectly
--    set to onboarding_complete=true (safety net)
update public.users_public
  set onboarding_complete = false
  where username is null and onboarding_complete = true;