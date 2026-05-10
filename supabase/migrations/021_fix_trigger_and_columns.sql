-- remove is_identity_verified from users_public (it belongs in users_private)
-- add missing columns safely
alter table public.users_public
  add column if not exists display_name    text,
  add column if not exists is_public       boolean not null default true,
  add column if not exists bio             text,
  add column if not exists is_suspended    boolean not null default false,
  add column if not exists is_shadow_banned boolean not null default false,
  add column if not exists wallet_address  text;

-- update the trigger to NOT insert is_identity_verified into users_public
-- and to handle display_name from Google OAuth metadata
create or replace function public.handle_new_user()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
declare
  _username     text;
  _display_name text;
  _attempt      int := 0;
begin
  -- Google OAuth provides name in raw_user_meta_data
  _display_name := coalesce(
    new.raw_user_meta_data->>'full_name',
    new.raw_user_meta_data->>'name'
  );

  -- generate username from email prefix
  _username := lower(regexp_replace(
    split_part(coalesce(new.email, ''), '@', 1),
    '[^a-zA-Z0-9]', '', 'g'
  ));
  _username := left(_username, 16);

  if _username = '' then
    _username := 'user';
  end if;

  -- ensure uniqueness
  while exists (select 1 from public.users_public where username = _username) loop
    _username := left(
      lower(regexp_replace(
        split_part(coalesce(new.email, ''), '@', 1),
        '[^a-zA-Z0-9]', '', 'g'
      )), 12
    ) || floor(random() * 9000 + 1000)::text;
    _attempt := _attempt + 1;
    if _attempt > 10 then
      _username := 'user' || floor(random() * 900000 + 100000)::text;
      exit;
    end if;
  end loop;

  -- create users_public row
  -- NOTE: username here is temporary — user will set their real username in onboarding
  -- we mark onboarding_complete = false so router sends them to onboarding
  insert into public.users_public (
    id,
    username,
    display_name,
    trust_tier,
    trust_score,
    echo_count,
    proof_count,
    is_public,
    created_at
  ) values (
    new.id,
    _username,
    _display_name,
    'unverified',
    0,
    0,
    0,
    true,
    now()
  )
  on conflict (id) do nothing;

  -- create users_private row
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

drop trigger if exists on_auth_user_created on auth.users;
create trigger on_auth_user_created
  after insert on auth.users
  for each row execute procedure public.handle_new_user();