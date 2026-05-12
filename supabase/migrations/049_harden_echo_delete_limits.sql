-- Harden user-facing deletion limits.
-- The app must delete echoes/replies through RPCs so the cooldown is enforced
-- even if a future client accidentally tries a direct table delete.

revoke delete, truncate on table public.echoes from anon, authenticated;
revoke delete, truncate on table public.echo_replies from anon, authenticated;

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
       and deleted_at > now() - interval '24 hours'
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

create or replace function public.delete_own_reply_limited(
  p_reply_id uuid
) returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  v_user uuid := auth.uid();
  v_author uuid;
  v_echo_id uuid;
  v_delete_count integer := 1;
begin
  if v_user is null then
    raise exception 'not_authenticated' using errcode = '28000';
  end if;

  select user_id, echo_id
    into v_author, v_echo_id
    from public.echo_replies
   where id = p_reply_id
   for update;

  if not found then
    raise exception 'reply_not_found' using errcode = 'P0002';
  end if;

  if v_author <> v_user then
    raise exception 'not_reply_owner' using errcode = '42501';
  end if;

  if exists (
    select 1
      from public.echo_reply_deletions
     where user_id = v_user
       and deleted_at > now() - interval '24 hours'
  ) then
    raise exception 'daily_reply_delete_limit' using errcode = 'P0001';
  end if;

  with recursive doomed as (
    select id
      from public.echo_replies
     where id = p_reply_id
    union all
    select child.id
      from public.echo_replies child
      join doomed parent on child.parent_reply_id = parent.id
  )
  select count(*) into v_delete_count from doomed;

  insert into public.echo_reply_deletions(user_id, reply_id)
  values (v_user, p_reply_id);

  delete from public.echo_replies
   where id = p_reply_id
     and user_id = v_user;

  update public.echoes
     set reply_count = greatest(reply_count - coalesce(v_delete_count, 1), 0)
   where id = v_echo_id;
end;
$$;

revoke all on function public.delete_own_echo_limited(uuid) from public;
revoke all on function public.delete_own_reply_limited(uuid) from public;
grant execute on function public.delete_own_echo_limited(uuid) to authenticated;
grant execute on function public.delete_own_reply_limited(uuid) to authenticated;
