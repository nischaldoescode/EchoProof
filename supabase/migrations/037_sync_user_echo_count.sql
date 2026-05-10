-- keeps users_public.echo_count in sync with visible echoes.
-- fixes profiles showing 0 echoes while the echoes tab has rows.

create or replace function public.sync_user_echo_count()
returns trigger
language plpgsql
security definer
as $$
begin
  if tg_op = 'DELETE' then
    update public.users_public
    set echo_count = (
      select count(*)::int
      from public.echoes e
      where e.user_id = old.user_id
        and e.status not in ('hidden', 'rejected')
    )
    where id = old.user_id;

    return old;
  end if;

  update public.users_public
  set echo_count = (
    select count(*)::int
    from public.echoes e
    where e.user_id = new.user_id
      and e.status not in ('hidden', 'rejected')
  )
  where id = new.user_id;

  if tg_op = 'UPDATE' and old.user_id is distinct from new.user_id then
    update public.users_public
    set echo_count = (
      select count(*)::int
      from public.echoes e
      where e.user_id = old.user_id
        and e.status not in ('hidden', 'rejected')
    )
    where id = old.user_id;
  end if;

  return new;
end;
$$;

drop trigger if exists sync_user_echo_count_on_echoes_write on public.echoes;
drop trigger if exists sync_user_echo_count_on_echoes_update on public.echoes;

create trigger sync_user_echo_count_on_echoes_write
after insert or delete
on public.echoes
for each row
execute function public.sync_user_echo_count();

create trigger sync_user_echo_count_on_echoes_update
after update of user_id, status
on public.echoes
for each row
execute function public.sync_user_echo_count();

update public.users_public up
set echo_count = counts.echo_count
from (
  select
    up2.id,
    count(e.id)::int as echo_count
  from public.users_public up2
  left join public.echoes e
    on e.user_id = up2.id
   and e.status not in ('hidden', 'rejected')
  group by up2.id
) counts
where up.id = counts.id;
