-- signal responses — the echoproof equivalent of comments
-- each response can contain text AND optional proof attachment
-- weighted by author trust tier
-- run order: 010
create extension if not exists "pgcrypto";
create extension if not exists "pg_trgm";

create table signal_responses (
  id           uuid primary key default gen_random_uuid(),
  echo_id      uuid not null references echoes(id) on delete cascade,
  user_id      uuid not null references users_public(id) on delete cascade,
  content      text not null check (char_length(content) between 1 and 500),
  proof_url    text,
  proof_type   text check (proof_type in ('url', 'image', 'document')),
  stance       text not null default 'neutral'
                check (stance in ('support', 'challenge', 'neutral')),
  author_weight integer not null default 1,
  created_at   timestamptz not null default now()
);

create index signal_responses_echo_id_idx on signal_responses(echo_id);
create index signal_responses_user_id_idx on signal_responses(user_id);

-- add response count to echoes for display
alter table echoes add column if not exists response_count integer not null default 0;

create or replace function increment_response_count(p_echo_id uuid)
returns void language plpgsql security definer as $$
begin
  update echoes set response_count = response_count + 1 where id = p_echo_id;
end;
$$;