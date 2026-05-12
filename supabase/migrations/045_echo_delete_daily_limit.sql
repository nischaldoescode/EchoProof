-- Server-validated own-echo deletion with a hard daily limit.

create table if not exists public.echo_deletions (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references public.users_public(id) on delete cascade,
  echo_id uuid not null,
  deleted_at timestamptz not null default now()
);

create index if not exists echo_deletions_user_deleted_at_idx
  on public.echo_deletions(user_id, deleted_at desc);

alter table public.echo_deletions enable row level security;

grant select on table public.echo_deletions to authenticated;

drop policy if exists "users see own echo deletions" on public.echo_deletions;
create policy "users see own echo deletions"
  on public.echo_deletions for select
  to authenticated
  using (auth.uid() = user_id);

create or replace function public.delete_own_echo_limited(
  p_echo_id uuid
) returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  v_user uuid := auth.uid();
  v_author uuid;
begin
  if v_user is null then
    raise exception 'not_authenticated' using errcode = '28000';
  end if;

  select user_id
    into v_author
    from public.echoes
   where id = p_echo_id
   for update;

  if not found then
    raise exception 'echo_not_found' using errcode = 'P0002';
  end if;

  if v_author <> v_user then
    raise exception 'not_echo_owner' using errcode = '42501';
  end if;

  if exists (
    select 1
      from public.echo_deletions
     where user_id = v_user
       and deleted_at >= date_trunc('day', now())
       and deleted_at < date_trunc('day', now()) + interval '1 day'
  ) then
    raise exception 'daily_echo_delete_limit' using errcode = 'P0001';
  end if;

  insert into public.echo_deletions(user_id, echo_id)
  values (v_user, p_echo_id);

  delete from public.echoes
   where id = p_echo_id
     and user_id = v_user;
end;
$$;

revoke all on function public.delete_own_echo_limited(uuid) from public;
grant execute on function public.delete_own_echo_limited(uuid) to authenticated;
