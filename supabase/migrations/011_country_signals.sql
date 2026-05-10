-- country-based signal trending
-- signals are tagged with country_code when a user from that country uses them
-- allows showing "trending in India" vs "trending globally"
-- run order: 011

alter table echo_signals
  add column if not exists country_code text; -- iso 3166-1 alpha-2, e.g. 'IN', 'US', 'GB'

create index echo_signals_country_idx on echo_signals(country_code)
  where country_code is not null;

-- trending signals by country for last 24 hours
create or replace view trending_signals_by_country as
select
  signal,
  country_code,
  count(*)        as echo_count,
  max(created_at) as last_used_at
from echo_signals
where created_at   > now() - interval '24 hours'
  and country_code is not null
group by signal, country_code
order by echo_count desc;

-- global trending (no country filter)
create or replace view trending_signals_global as
select
  signal,
  count(*)        as echo_count,
  max(created_at) as last_used_at
from echo_signals
where created_at > now() - interval '24 hours'
group by signal
order by echo_count desc
limit 30;