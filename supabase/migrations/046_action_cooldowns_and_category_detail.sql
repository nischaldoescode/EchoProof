-- Action cooldowns and explicit "Other" category detail.
-- Adds server-side guards for auth pacing, echo creation, and profile edits.

alter table public.echoes
  add column if not exists category_detail text;

update public.echoes
   set category_detail = 'Other'
 where category = 'other'
   and (category_detail is null or btrim(category_detail) = '');

do $$
begin
  alter table public.echoes
    add constraint echoes_category_detail_length
    check (
      category_detail is null
      or char_length(btrim(category_detail)) between 0 and 10
    );
exception when duplicate_object then null;
end $$;

do $$
begin
  alter table public.echoes
    add constraint echoes_other_category_detail_required
    check (
      category <> 'other'
      or (
        category_detail is not null
        and char_length(btrim(category_detail)) between 1 and 10
      )
    );
exception when duplicate_object then null;
end $$;

create table if not exists public.action_cooldown_events (
  id uuid primary key default gen_random_uuid(),
  action text not null,
  subject_hash text not null,
  user_id uuid references auth.users(id) on delete cascade,
  ip_address text,
  created_at timestamptz not null default now()
);

create index if not exists action_cooldown_events_lookup_idx
  on public.action_cooldown_events(action, subject_hash, created_at desc);

create index if not exists action_cooldown_events_user_idx
  on public.action_cooldown_events(user_id, created_at desc);

alter table public.action_cooldown_events enable row level security;

drop policy if exists "service role manages action cooldowns"
  on public.action_cooldown_events;

create policy "service role manages action cooldowns"
  on public.action_cooldown_events
  for all
  to service_role
  using (true)
  with check (true);

create or replace function public.current_request_ip()
returns text
language plpgsql
stable
as $$
declare
  v_headers jsonb;
  v_forwarded text;
begin
  begin
    v_headers := nullif(current_setting('request.headers', true), '')::jsonb;
  exception when others then
    v_headers := '{}'::jsonb;
  end;

  v_forwarded := coalesce(
    v_headers ->> 'cf-connecting-ip',
    v_headers ->> 'x-real-ip',
    v_headers ->> 'x-forwarded-for',
    'unknown'
  );

  return nullif(btrim(split_part(v_forwarded, ',', 1)), '');
end;
$$;

create or replace function public.action_cooldown_hash(
  p_action text,
  p_subject text default null,
  p_include_ip boolean default false
) returns text
language plpgsql
stable
security definer
set search_path = public
as $$
declare
  v_subject text;
  v_ip text;
begin
  v_subject := lower(btrim(coalesce(p_subject, auth.uid()::text, 'anonymous')));
  if v_subject = '' then
    v_subject := coalesce(auth.uid()::text, 'anonymous');
  end if;

  v_ip := case when p_include_ip then coalesce(public.current_request_ip(), 'unknown') else '' end;

  return encode(digest(lower(btrim(p_action)) || '|' || v_subject || '|' || v_ip, 'sha256'), 'hex');
end;
$$;

create or replace function public.get_action_cooldown_status(
  p_action text,
  p_subject text default null,
  p_window_seconds integer default 1800,
  p_max_actions integer default 1,
  p_include_ip boolean default false
) returns jsonb
language plpgsql
stable
security definer
set search_path = public
as $$
declare
  v_action text := lower(btrim(p_action));
  v_hash text;
  v_count integer;
  v_oldest timestamptz;
  v_retry integer := 0;
  v_window interval;
begin
  if v_action not in (
    'auth_login',
    'auth_logout',
    'create_echo',
    'profile_update'
  ) then
    raise exception 'unsupported_cooldown_action' using errcode = '22023';
  end if;

  if p_window_seconds < 1 or p_max_actions < 1 then
    raise exception 'invalid_cooldown_config' using errcode = '22023';
  end if;

  v_hash := public.action_cooldown_hash(v_action, p_subject, p_include_ip);
  v_window := make_interval(secs => p_window_seconds);

  select count(*)::integer, min(created_at)
    into v_count, v_oldest
    from public.action_cooldown_events
   where action = v_action
     and subject_hash = v_hash
     and created_at > now() - v_window;

  if v_count >= p_max_actions and v_oldest is not null then
    v_retry := greatest(
      0,
      ceil(extract(epoch from (v_oldest + v_window - now())))::integer
    );
  end if;

  return jsonb_build_object(
    'allowed', v_count < p_max_actions,
    'retry_after_seconds', v_retry,
    'window_seconds', p_window_seconds,
    'max_actions', p_max_actions
  );
end;
$$;

create or replace function public.consume_action_cooldown(
  p_action text,
  p_subject text default null,
  p_window_seconds integer default 1800,
  p_max_actions integer default 1,
  p_include_ip boolean default false
) returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_action text := lower(btrim(p_action));
  v_status jsonb;
  v_hash text;
  v_ip text := public.current_request_ip();
begin
  v_status := public.get_action_cooldown_status(
    v_action,
    p_subject,
    p_window_seconds,
    p_max_actions,
    p_include_ip
  );

  if not ((v_status ->> 'allowed')::boolean) then
    return v_status || jsonb_build_object('recorded', false);
  end if;

  v_hash := public.action_cooldown_hash(v_action, p_subject, p_include_ip);

  insert into public.action_cooldown_events(action, subject_hash, user_id, ip_address)
  values (v_action, v_hash, auth.uid(), v_ip);

  return v_status || jsonb_build_object('recorded', true);
end;
$$;

create or replace function public.enforce_echo_create_cooldown()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
declare
  v_status jsonb;
begin
  v_status := public.get_action_cooldown_status(
    'create_echo',
    new.user_id::text,
    1200,
    1,
    false
  );

  if not ((v_status ->> 'allowed')::boolean) then
    raise exception 'create_echo_cooldown'
      using errcode = 'P0001',
            detail = v_status ->> 'retry_after_seconds';
  end if;

  perform public.consume_action_cooldown(
    'create_echo',
    new.user_id::text,
    1200,
    1,
    false
  );

  return new;
end;
$$;

drop trigger if exists echoes_create_cooldown_before_insert
  on public.echoes;

create trigger echoes_create_cooldown_before_insert
  before insert on public.echoes
  for each row
  execute function public.enforce_echo_create_cooldown();

create or replace function public.enforce_profile_update_cooldown()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
declare
  v_status jsonb;
  v_changed boolean;
begin
  -- Let onboarding and service-role maintenance complete without locking users out.
  if old.onboarding_complete is distinct from true then
    return new;
  end if;

  if auth.uid() is null or auth.uid() <> new.id then
    return new;
  end if;

  v_changed :=
    old.username is distinct from new.username
    or old.display_name is distinct from new.display_name
    or old.gender is distinct from new.gender
    or old.date_of_birth is distinct from new.date_of_birth
    or old.bio is distinct from new.bio
    or old.avatar_url is distinct from new.avatar_url;

  if not v_changed then
    return new;
  end if;

  v_status := public.get_action_cooldown_status(
    'profile_update',
    new.id::text,
    1200,
    1,
    false
  );

  if not ((v_status ->> 'allowed')::boolean) then
    raise exception 'profile_update_cooldown'
      using errcode = 'P0001',
            detail = v_status ->> 'retry_after_seconds';
  end if;

  perform public.consume_action_cooldown(
    'profile_update',
    new.id::text,
    1200,
    1,
    false
  );

  return new;
end;
$$;

drop trigger if exists users_public_profile_update_cooldown_before_update
  on public.users_public;

create trigger users_public_profile_update_cooldown_before_update
  before update on public.users_public
  for each row
  execute function public.enforce_profile_update_cooldown();

revoke all on function public.action_cooldown_hash(text, text, boolean) from public;
revoke all on function public.current_request_ip() from public;

grant execute on function public.get_action_cooldown_status(text, text, integer, integer, boolean)
  to anon, authenticated;
grant execute on function public.consume_action_cooldown(text, text, integer, integer, boolean)
  to anon, authenticated;
