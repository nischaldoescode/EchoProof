-- Private-profile follow requests, social graph privacy, and feed feedback.

create table if not exists public.follow_requests (
  id uuid primary key default gen_random_uuid(),
  requester_id uuid not null references public.users_public(id) on delete cascade,
  target_id uuid not null references public.users_public(id) on delete cascade,
  status text not null default 'pending'
    check (status in ('pending', 'accepted', 'rejected')),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  unique (requester_id, target_id),
  check (requester_id <> target_id)
);

create index if not exists follow_requests_requester_idx
  on public.follow_requests(requester_id, status);
create index if not exists follow_requests_target_idx
  on public.follow_requests(target_id, status);

alter table public.follow_requests enable row level security;

drop policy if exists "users see relevant follow requests" on public.follow_requests;
create policy "users see relevant follow requests"
  on public.follow_requests for select
  to authenticated
  using (auth.uid() = requester_id or auth.uid() = target_id);

drop policy if exists "users request private follows" on public.follow_requests;
create policy "users request private follows"
  on public.follow_requests for insert
  to authenticated
  with check (auth.uid() = requester_id and status = 'pending');

drop policy if exists "targets resolve follow requests" on public.follow_requests;
create policy "targets resolve follow requests"
  on public.follow_requests for update
  to authenticated
  using (auth.uid() = target_id)
  with check (auth.uid() = target_id and status in ('accepted', 'rejected'));

drop policy if exists "requesters reopen follow requests" on public.follow_requests;
create policy "requesters reopen follow requests"
  on public.follow_requests for update
  to authenticated
  using (auth.uid() = requester_id and status in ('pending', 'rejected'))
  with check (auth.uid() = requester_id and status = 'pending');

drop policy if exists "request participants delete follow requests" on public.follow_requests;
create policy "request participants delete follow requests"
  on public.follow_requests for delete
  to authenticated
  using (auth.uid() = requester_id or auth.uid() = target_id);

drop trigger if exists set_follow_requests_updated_at on public.follow_requests;
create trigger set_follow_requests_updated_at
  before update on public.follow_requests
  for each row execute function public.set_updated_at();

create table if not exists public.user_blocks (
  id uuid primary key default gen_random_uuid(),
  blocker_id uuid not null references public.users_public(id) on delete cascade,
  blocked_id uuid not null references public.users_public(id) on delete cascade,
  created_at timestamptz not null default now(),
  unique (blocker_id, blocked_id),
  check (blocker_id <> blocked_id)
);

create index if not exists user_blocks_blocker_idx
  on public.user_blocks(blocker_id);
create index if not exists user_blocks_blocked_idx
  on public.user_blocks(blocked_id);

alter table public.user_blocks enable row level security;

drop policy if exists "users manage own blocks select" on public.user_blocks;
create policy "users manage own blocks select"
  on public.user_blocks for select
  to authenticated
  using (auth.uid() = blocker_id);

drop policy if exists "users manage own blocks insert" on public.user_blocks;
create policy "users manage own blocks insert"
  on public.user_blocks for insert
  to authenticated
  with check (auth.uid() = blocker_id);

drop policy if exists "users manage own blocks delete" on public.user_blocks;
create policy "users manage own blocks delete"
  on public.user_blocks for delete
  to authenticated
  using (auth.uid() = blocker_id);

create table if not exists public.user_feed_feedback (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references public.users_public(id) on delete cascade,
  echo_id uuid not null references public.echoes(id) on delete cascade,
  author_id uuid references public.users_public(id) on delete set null,
  feedback_type text not null
    check (feedback_type in ('not_interested', 'report', 'block_author')),
  weight integer not null default 1,
  created_at timestamptz not null default now(),
  unique (user_id, echo_id, feedback_type)
);

create index if not exists user_feed_feedback_user_idx
  on public.user_feed_feedback(user_id, feedback_type);
create index if not exists user_feed_feedback_author_idx
  on public.user_feed_feedback(user_id, author_id, feedback_type);

alter table public.user_feed_feedback enable row level security;

drop policy if exists "users see own feed feedback" on public.user_feed_feedback;
create policy "users see own feed feedback"
  on public.user_feed_feedback for select
  to authenticated
  using (auth.uid() = user_id);

drop policy if exists "users create own feed feedback" on public.user_feed_feedback;
create policy "users create own feed feedback"
  on public.user_feed_feedback for insert
  to authenticated
  with check (auth.uid() = user_id);

drop policy if exists "users update own feed feedback" on public.user_feed_feedback;
create policy "users update own feed feedback"
  on public.user_feed_feedback for update
  to authenticated
  using (auth.uid() = user_id)
  with check (auth.uid() = user_id);

create or replace function public.handle_follow_request_change()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
declare
  v_requester_username text;
  v_target_username text;
begin
  select username into v_requester_username
  from public.users_public
  where id = new.requester_id;

  select username into v_target_username
  from public.users_public
  where id = new.target_id;

  if tg_op = 'INSERT' then
    insert into public.notifications(user_id, type, title, body, data)
    values (
      new.target_id,
      'follow_request',
      'Follow request',
      '@' || coalesce(v_requester_username, 'Someone') || ' requested to follow you.',
      jsonb_build_object(
        'request_id', new.id,
        'requester_id', new.requester_id,
        'requester_username', v_requester_username,
        'target_id', new.target_id
      )
    );
    return new;
  end if;

  if tg_op = 'UPDATE' and old.status <> new.status then
    update public.notifications
    set read = true,
        data = coalesce(data, '{}'::jsonb)
          || jsonb_build_object('handled', true, 'status', new.status)
    where user_id = new.target_id
      and type = 'follow_request'
      and data ->> 'request_id' = new.id::text;

    if new.status = 'accepted' then
      insert into public.user_follows(follower_id, following_id)
      values (new.requester_id, new.target_id)
      on conflict (follower_id, following_id) do nothing;

      insert into public.notifications(user_id, type, title, body, data)
      values (
        new.requester_id,
        'follow_request_accepted',
        'Follow request accepted',
        '@' || coalesce(v_target_username, 'Someone') || ' accepted your follow request.',
        jsonb_build_object(
          'target_id', new.target_id,
          'target_username', v_target_username,
          'request_id', new.id
        )
      );
    end if;
  end if;

  return new;
end;
$$;

drop trigger if exists on_follow_request_change on public.follow_requests;
create trigger on_follow_request_change
  after insert or update on public.follow_requests
  for each row execute function public.handle_follow_request_change();

create or replace function public.cleanup_after_block()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
begin
  delete from public.user_follows
  where (follower_id = new.blocker_id and following_id = new.blocked_id)
     or (follower_id = new.blocked_id and following_id = new.blocker_id);

  delete from public.follow_requests
  where (requester_id = new.blocker_id and target_id = new.blocked_id)
     or (requester_id = new.blocked_id and target_id = new.blocker_id);

  return new;
end;
$$;

drop trigger if exists on_user_block_insert on public.user_blocks;
create trigger on_user_block_insert
  after insert on public.user_blocks
  for each row execute function public.cleanup_after_block();

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
    and not exists (
      select 1
      from public.user_blocks ub
      where (ub.blocker_id = auth.uid() and ub.blocked_id = echoes.user_id)
         or (ub.blocked_id = auth.uid() and ub.blocker_id = echoes.user_id)
    )
  );

create or replace function get_personalized_feed(
  p_user_id uuid,
  p_offset  integer default 0,
  p_limit   integer default 20
) returns table (
  echo_id            uuid,
  personalized_score numeric
) language plpgsql security definer as $$
declare
  v_ranked_limit integer;
  v_random_limit integer;
  v_user_categories text[];
begin
  v_ranked_limit := greatest(p_limit - greatest(p_limit / 10, 1), 1);
  v_random_limit := p_limit - v_ranked_limit;

  select coalesce(
    array(
      select c::text
      from unnest(coalesce(up.categories, '{}'::echo_category[])) as c
    ),
    '{}'::text[]
  )
  into v_user_categories
  from users_public up
  where up.id = p_user_id;

  v_user_categories := coalesce(v_user_categories, '{}'::text[]);

  return query
  with user_affinities as (
    select
      signal_value as category,
      sum(weight * exp(-extract(epoch from (now() - created_at)) / 172800.0)) as affinity_score
    from user_feed_signals
    where user_id = p_user_id
      and signal_type in ('category_view', 'category_support', 'category_challenge', 'category_click')
      and created_at > now() - interval '7 days'
    group by signal_value
  ),

  base as (
    select
      e.id as echo_id,
      e.user_id as author_id,
      up.trust_tier as author_tier,
      up.is_pro as author_is_pro,
      extract(epoch from (now() - e.created_at)) / 3600.0 as age_hours,
      (
        (ln(1.0 + greatest(0.0, least(coalesce(e.trust_score, 0)::numeric, 100.0))) / ln(101.0)) * 40.0
        + coalesce(ua.affinity_score, 10.0) * 0.30
        + (coalesce(e.confidence_score, 0) * 0.15)
        + (coalesce(e.controversy_score, 0) * 0.05)
        + case
            when e.category::text = any(v_user_categories) then 15.0
            else 0.0
          end
        + case
            when e.user_id = p_user_id then 12.0
            else 0.0
          end
        - case
            when e.user_id <> p_user_id and exists (
              select 1
              from echo_interactions ei
              where ei.echo_id = e.id
                and ei.user_id = p_user_id
            ) then 30.0
            else 0.0
          end
      ) as base_score
    from echoes e
    inner join users_public up on up.id = e.user_id
    left join user_affinities ua on ua.category = e.category::text
    where e.status not in ('hidden', 'rejected')
      and e.created_at > now() - interval '30 days'
      and (
        up.is_public = true
        or e.user_id = p_user_id
        or exists (
          select 1
          from public.user_follows uf
          where uf.follower_id = p_user_id
            and uf.following_id = e.user_id
        )
      )
      and not exists (
        select 1
        from public.user_blocks ub
        where (ub.blocker_id = p_user_id and ub.blocked_id = e.user_id)
           or (ub.blocked_id = p_user_id and ub.blocker_id = e.user_id)
      )
      and not exists (
        select 1
        from public.user_feed_feedback uff
        where uff.user_id = p_user_id
          and (
            uff.echo_id = e.id
            or uff.author_id = e.user_id
          )
          and uff.feedback_type in ('not_interested', 'report', 'block_author')
      )
  ),

  decayed as (
    select
      b.echo_id,
      b.author_id,
      b.author_tier,
      b.author_is_pro,
      b.age_hours,
      b.base_score * case
        when b.age_hours < 24    then 1.00
        when b.age_hours < 72    then 0.85
        when b.age_hours < 168   then 0.50 + (0.35 * (1.0 - (b.age_hours - 72.0) / 96.0))
        else                          0.30
      end as final_score
    from base b
  ),

  ranked as (
    select
      d.echo_id,
      d.final_score
      * case
          when d.author_is_pro and d.author_tier::text in ('high', 'elite') then 1.25
          when d.author_is_pro then 1.15
          when d.author_tier::text in ('high', 'elite') then 1.10
          when d.author_tier::text = 'medium' then 1.05
          else 1.0
        end as personalized_score
    from decayed d
    order by personalized_score desc, d.age_hours asc
    offset p_offset
    limit v_ranked_limit
  ),

  exploration as (
    select
      d.echo_id,
      d.final_score * 0.30 as personalized_score
    from decayed d
    where random() < 0.05
      and not exists (
        select 1 from ranked r where r.echo_id = d.echo_id
      )
    limit v_random_limit
  )

  select r.echo_id, r.personalized_score::numeric from ranked r
  union all
  select e.echo_id, e.personalized_score::numeric from exploration e;
end;
$$;
