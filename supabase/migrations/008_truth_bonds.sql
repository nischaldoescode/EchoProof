-- truth bonds — users stake reputation on verified echoes
-- a bond is a compressed nft minted on solana when status = verified
-- after 30 days with no admin downgrade: bond settles (reputation boost)
-- if echo is downgraded: bond is contested (no boost, public record)
-- run order: 008

create type bond_status as enum ('active', 'settled', 'contested');

create table truth_bonds (
  id              uuid primary key default uuid_generate_v4(),
  echo_id         uuid not null references echoes(id) on delete cascade,
  user_id         uuid not null references users_public(id) on delete cascade,
  mint_tx         text,            -- solana compressed nft mint transaction
  bond_status     bond_status not null default 'active',
  settles_at      timestamptz not null default (now() + interval '30 days'),
  settled_at      timestamptz,
  contested_at    timestamptz,
  created_at      timestamptz not null default now(),

  unique(echo_id, user_id)  -- one bond per user per echo
);

create index truth_bonds_user_id_idx on truth_bonds(user_id);
create index truth_bonds_echo_id_idx on truth_bonds(echo_id);
create index truth_bonds_settles_at_idx on truth_bonds(settles_at)
  where bond_status = 'active';

-- add bond count to echoes for fast feed display
alter table echoes add column if not exists bond_count integer not null default 0;

-- function called when admin downgrades a verified echo
-- marks all active bonds on that echo as contested
create or replace function contest_echo_bonds(p_echo_id uuid)
returns void language plpgsql security definer as $$
begin
  update truth_bonds
  set bond_status  = 'contested',
      contested_at = now()
  where echo_id    = p_echo_id
    and bond_status = 'active';
end;
$$;

-- function called by scheduled trust engine run
-- settles bonds that have passed their 30-day window
create or replace function settle_matured_bonds()
returns void language plpgsql security definer as $$
begin
  update truth_bonds
  set bond_status = 'settled',
      settled_at  = now()
  where bond_status = 'active'
    and settles_at  <= now();

  -- give reputation boost to users whose bonds just settled
  update users_public
  set trust_score = trust_score + 2
  where id in (
    select user_id from truth_bonds
    where bond_status = 'settled'
      and settled_at  >= now() - interval '1 hour'
  );
end;
$$;

-- increment bond count on echo — called after truth_bonds insert
create or replace function increment_bond_count(p_echo_id uuid)
returns void language plpgsql security definer as $$
begin
  update echoes set bond_count = bond_count + 1 where id = p_echo_id;
end;
$$;