-- Production hardening for Supabase Auth user creation.
-- Fixes older trigger functions that referenced users_public without schema.
-- Also prevents Auth from failing with a 500 if profile tables are temporarily missing.

do $$
begin
  if to_regclass('public.users_public') is not null then
    execute 'alter table public.users_public alter column username drop not null';
    execute 'alter table public.users_public add column if not exists display_name text';
    execute 'alter table public.users_public add column if not exists is_public boolean not null default true';
    execute 'alter table public.users_public add column if not exists onboarding_complete boolean not null default false';
  end if;

  if to_regclass('public.users_private') is not null then
    execute 'alter table public.users_private alter column email drop not null';
  end if;
end $$;

create or replace function public.handle_new_user()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
declare
  _display_name text;
  _email text;
  _username text;
  _attempt int := 0;
begin
  if to_regclass('public.users_public') is null
     or to_regclass('public.users_private') is null then
    raise warning 'handle_new_user skipped for id=% because profile tables are missing', new.id;
    return new;
  end if;

  _email := coalesce(new.email, '');
  _display_name := coalesce(
    new.raw_user_meta_data->>'full_name',
    new.raw_user_meta_data->>'name'
  );

  _username := lower(regexp_replace(split_part(_email, '@', 1), '[^a-zA-Z0-9]', '', 'g'));
  _username := nullif(left(_username, 16), '');

  while _username is not null
    and exists (
      select 1 from public.users_public up
      where lower(up.username) = lower(_username)
        and up.id <> new.id
    )
  loop
    _username := left(
      lower(regexp_replace(split_part(_email, '@', 1), '[^a-zA-Z0-9]', '', 'g')),
      12
    ) || floor(random() * 9000 + 1000)::text;
    _attempt := _attempt + 1;

    if _attempt > 10 then
      _username := 'user' || floor(random() * 900000 + 100000)::text;
      exit;
    end if;
  end loop;

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
    _username,
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
    nullif(_email, ''),
    false,
    now()
  )
  on conflict (id) do nothing;

  return new;
exception
  when others then
    raise warning 'handle_new_user error for id=%: % (sqlstate=%)', new.id, sqlerrm, sqlstate;
    return new;
end;
$$;

drop trigger if exists on_auth_user_created on auth.users;
create trigger on_auth_user_created
  after insert on auth.users
  for each row execute function public.handle_new_user();
