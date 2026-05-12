-- Reply likes, child counts, and server-validated own-reply deletion.
-- Mirrors echo deletion behavior: one successful reply deletion per user per day.

alter table public.echo_replies
  add column if not exists like_count integer not null default 0,
  add column if not exists child_reply_count integer not null default 0;

create table if not exists public.echo_reply_interactions (
  id uuid primary key default gen_random_uuid(),
  reply_id uuid not null references public.echo_replies(id) on delete cascade,
  user_id uuid not null references public.users_public(id) on delete cascade,
  type text not null default 'like' check (type in ('like')),
  created_at timestamptz not null default now(),
  unique(reply_id, user_id, type)
);

create index if not exists echo_reply_interactions_reply_idx
  on public.echo_reply_interactions(reply_id);

create index if not exists echo_reply_interactions_user_idx
  on public.echo_reply_interactions(user_id, created_at desc);

alter table public.echo_reply_interactions enable row level security;

grant select on table public.echo_reply_interactions to authenticated;

drop policy if exists "authenticated read reply interactions" on public.echo_reply_interactions;
create policy "authenticated read reply interactions"
  on public.echo_reply_interactions for select
  to authenticated
  using (true);

drop policy if exists "users create own reply interaction" on public.echo_reply_interactions;
create policy "users create own reply interaction"
  on public.echo_reply_interactions for insert
  to authenticated
  with check (auth.uid() = user_id);

drop policy if exists "users delete own reply interaction" on public.echo_reply_interactions;
create policy "users delete own reply interaction"
  on public.echo_reply_interactions for delete
  to authenticated
  using (auth.uid() = user_id);

create table if not exists public.echo_reply_deletions (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references public.users_public(id) on delete cascade,
  reply_id uuid not null,
  deleted_at timestamptz not null default now()
);

create index if not exists echo_reply_deletions_user_deleted_at_idx
  on public.echo_reply_deletions(user_id, deleted_at desc);

alter table public.echo_reply_deletions enable row level security;

grant select on table public.echo_reply_deletions to authenticated;

drop policy if exists "users see own reply deletions" on public.echo_reply_deletions;
create policy "users see own reply deletions"
  on public.echo_reply_deletions for select
  to authenticated
  using (auth.uid() = user_id);

create or replace function public.sync_echo_reply_like_count()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
begin
  if TG_OP = 'INSERT' then
    update public.echo_replies
       set like_count = like_count + 1
     where id = NEW.reply_id;
  elsif TG_OP = 'DELETE' then
    update public.echo_replies
       set like_count = greatest(like_count - 1, 0)
     where id = OLD.reply_id;
  end if;

  return null;
end;
$$;

drop trigger if exists on_echo_reply_interaction_change on public.echo_reply_interactions;
create trigger on_echo_reply_interaction_change
  after insert or delete on public.echo_reply_interactions
  for each row execute function public.sync_echo_reply_like_count();

create or replace function public.sync_child_reply_count()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
begin
  if TG_OP = 'INSERT' and NEW.parent_reply_id is not null then
    update public.echo_replies
       set child_reply_count = child_reply_count + 1
     where id = NEW.parent_reply_id;
  elsif TG_OP = 'DELETE' and OLD.parent_reply_id is not null then
    update public.echo_replies
       set child_reply_count = greatest(child_reply_count - 1, 0)
     where id = OLD.parent_reply_id;
  end if;

  return null;
end;
$$;

drop trigger if exists on_echo_reply_child_change on public.echo_replies;
create trigger on_echo_reply_child_change
  after insert or delete on public.echo_replies
  for each row execute function public.sync_child_reply_count();

create or replace function public.toggle_echo_reply_like(
  p_reply_id uuid
) returns table (
  liked boolean,
  like_count integer
)
language plpgsql
security definer
set search_path = public
as $$
declare
  v_user uuid := auth.uid();
  v_next_count integer;
begin
  if v_user is null then
    raise exception 'not_authenticated' using errcode = '28000';
  end if;

  perform 1
    from public.echo_replies
   where id = p_reply_id;

  if not found then
    raise exception 'reply_not_found' using errcode = 'P0002';
  end if;

  if exists (
    select 1
      from public.echo_reply_interactions
     where reply_id = p_reply_id
       and user_id = v_user
       and type = 'like'
  ) then
    delete from public.echo_reply_interactions
     where reply_id = p_reply_id
       and user_id = v_user
       and type = 'like';

    select er.like_count into v_next_count
      from public.echo_replies er
     where er.id = p_reply_id;

    return query select false, coalesce(v_next_count, 0);
    return;
  end if;

  insert into public.echo_reply_interactions(reply_id, user_id, type)
  values (p_reply_id, v_user, 'like')
  on conflict (reply_id, user_id, type) do nothing;

  select er.like_count into v_next_count
    from public.echo_replies er
   where er.id = p_reply_id;

  return query select true, coalesce(v_next_count, 0);
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
       and deleted_at >= date_trunc('day', now())
       and deleted_at < date_trunc('day', now()) + interval '1 day'
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

revoke all on function public.toggle_echo_reply_like(uuid) from public;
revoke all on function public.delete_own_reply_limited(uuid) from public;
grant execute on function public.toggle_echo_reply_like(uuid) to authenticated;
grant execute on function public.delete_own_reply_limited(uuid) to authenticated;
