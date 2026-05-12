-- Adds echo-level proof counts for feed queries and fairer trending signal views.

alter table public.echoes
  add column if not exists proof_count integer not null default 0;

update public.echoes e
set proof_count = p.count
from (
  select echo_id, count(*)::integer as count
  from public.echo_proofs
  group by echo_id
) p
where e.id = p.echo_id;

create or replace function public.sync_echo_proof_count()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
begin
  if tg_op = 'INSERT' then
    update public.echoes
    set proof_count = proof_count + 1
    where id = new.echo_id;
    return new;
  end if;

  if tg_op = 'DELETE' then
    update public.echoes
    set proof_count = greatest(proof_count - 1, 0)
    where id = old.echo_id;
    return old;
  end if;

  if tg_op = 'UPDATE' and new.echo_id is distinct from old.echo_id then
    update public.echoes
    set proof_count = greatest(proof_count - 1, 0)
    where id = old.echo_id;

    update public.echoes
    set proof_count = proof_count + 1
    where id = new.echo_id;
  end if;

  return new;
end;
$$;

drop trigger if exists echo_proofs_sync_count on public.echo_proofs;

create trigger echo_proofs_sync_count
after insert or delete or update of echo_id on public.echo_proofs
for each row execute function public.sync_echo_proof_count();

create or replace view public.trending_signals_by_country as
select
  es.signal,
  es.country_code,
  count(*) as echo_count,
  max(es.created_at) as last_used_at,
  count(distinct e.user_id) as author_count,
  round(
    count(*)::numeric * 0.65
    + count(distinct e.user_id)::numeric * 1.80
    + greatest(
        0,
        6 - extract(epoch from (now() - max(es.created_at))) / 3600.0
      )::numeric * 0.35,
    2
  ) as fair_score
from public.echo_signals es
join public.echoes e on e.id = es.echo_id
where es.created_at > now() - interval '24 hours'
  and es.country_code is not null
  and e.status not in ('hidden', 'rejected')
group by es.signal, es.country_code
order by fair_score desc, echo_count desc, last_used_at desc;

create or replace view public.trending_signals_global as
select
  es.signal,
  count(*) as echo_count,
  max(es.created_at) as last_used_at,
  count(distinct e.user_id) as author_count,
  round(
    count(*)::numeric * 0.65
    + count(distinct e.user_id)::numeric * 1.80
    + greatest(
        0,
        6 - extract(epoch from (now() - max(es.created_at))) / 3600.0
      )::numeric * 0.35,
    2
  ) as fair_score
from public.echo_signals es
join public.echoes e on e.id = es.echo_id
where es.created_at > now() - interval '24 hours'
  and e.status not in ('hidden', 'rejected')
group by es.signal
order by fair_score desc, echo_count desc, last_used_at desc
limit 30;
