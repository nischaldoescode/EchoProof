-- supabase/migrations/016_deletion_requests.sql
create table deletion_requests (
  id          uuid primary key default gen_random_uuid(),
  email       text not null,
  reason      text not null,
  description text not null default '',
  status      text not null default 'pending' check (status in ('pending', 'processed')),
  ip          text,
  created_at  timestamptz not null default now()
);

create index deletion_requests_email_idx on deletion_requests(email, created_at);

-- no rls — this table is only accessed via service role from the API