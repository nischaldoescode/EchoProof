-- Tighten block behavior after the initial follow-request migration.
-- Blocks now hide profile rows both ways and prevent direct interactions/replies.

create or replace function public.users_are_blocked(
  p_viewer uuid,
  p_target uuid
) returns boolean
language sql
stable
security definer
set search_path = public
as $$
  select exists (
    select 1
    from public.user_blocks ub
    where (ub.blocker_id = p_viewer and ub.blocked_id = p_target)
       or (ub.blocker_id = p_target and ub.blocked_id = p_viewer)
  );
$$;

grant execute on function public.users_are_blocked(uuid, uuid) to authenticated;

create or replace function public.echo_author_id(p_echo_id uuid)
returns uuid
language sql
stable
security definer
set search_path = public
as $$
  select e.user_id
  from public.echoes e
  where e.id = p_echo_id;
$$;

grant execute on function public.echo_author_id(uuid) to authenticated;

drop policy if exists "anyone authenticated can read public profiles"
  on public.users_public;
drop policy if exists "authenticated can read unblocked profile rows"
  on public.users_public;

create policy "authenticated can read unblocked profile rows"
  on public.users_public for select
  to authenticated
  using (
    auth.uid() = id
    or exists (
      select 1
      from public.user_blocks ub
      where ub.blocker_id = auth.uid()
        and ub.blocked_id = users_public.id
    )
    or not public.users_are_blocked(auth.uid(), id)
  );

drop policy if exists "anyone can read active echoes" on public.echoes;
drop policy if exists "authenticated can read visible echoes" on public.echoes;

create policy "authenticated can read visible echoes"
  on public.echoes for select
  to authenticated
  using (
    status not in ('hidden', 'rejected')
    and (
      user_id = auth.uid()
      or exists (
        select 1
        from public.users_public up
        where up.id = echoes.user_id
          and up.is_public = true
      )
      or exists (
        select 1
        from public.user_follows uf
        where uf.follower_id = auth.uid()
          and uf.following_id = echoes.user_id
      )
    )
    and not public.users_are_blocked(auth.uid(), user_id)
  );

drop policy if exists "users can see follows" on public.user_follows;
create policy "users can see follows"
  on public.user_follows for select
  to authenticated
  using (
    not public.users_are_blocked(auth.uid(), follower_id)
    and not public.users_are_blocked(auth.uid(), following_id)
  );

drop policy if exists "authenticated can create interaction"
  on public.echo_interactions;
create policy "authenticated can create interaction"
  on public.echo_interactions for insert
  to authenticated
  with check (
    auth.uid() = user_id
    and not public.users_are_blocked(
      auth.uid(),
      public.echo_author_id(echo_interactions.echo_id)
    )
  );

drop policy if exists "user can update own interaction"
  on public.echo_interactions;
create policy "user can update own interaction"
  on public.echo_interactions for update
  to authenticated
  using (auth.uid() = user_id)
  with check (
    auth.uid() = user_id
    and not public.users_are_blocked(
      auth.uid(),
      public.echo_author_id(echo_interactions.echo_id)
    )
  );

drop policy if exists "authenticated can read replies"
  on public.echo_replies;
create policy "authenticated can read replies"
  on public.echo_replies for select
  to authenticated
  using (
    not public.users_are_blocked(auth.uid(), user_id)
    and not public.users_are_blocked(
      auth.uid(),
      public.echo_author_id(echo_replies.echo_id)
    )
  );

drop policy if exists "authenticated can create reply"
  on public.echo_replies;
create policy "authenticated can create reply"
  on public.echo_replies for insert
  to authenticated
  with check (
    auth.uid() = user_id
    and not public.users_are_blocked(
      auth.uid(),
      public.echo_author_id(echo_replies.echo_id)
    )
  );
