-- production solana anchoring fields for echoes, proofs, and truth bonds
-- tracks lifecycle state separately from the transaction signatures

alter table echoes
  add column if not exists created_record_tx text,
  add column if not exists created_record_at timestamptz,
  add column if not exists solana_status text not null default 'pending',
  add column if not exists solana_error text,
  add column if not exists verified_record_status text not null default 'pending',
  add column if not exists verified_record_error text;

comment on column echoes.created_record_tx is
  'solana memo transaction signature for the immutable echo creation record';

comment on column echoes.solana_status is
  'solana anchoring state for echo creation: pending, recording, anchored, failed';

comment on column echoes.verified_record_status is
  'solana anchoring state for community verification: pending, recording, anchored, failed';

alter table echo_proofs
  add column if not exists solana_status text not null default 'pending',
  add column if not exists solana_record_at timestamptz,
  add column if not exists solana_error text;

comment on column echo_proofs.solana_status is
  'solana anchoring state for evidence proof: pending, recording, anchored, failed';

alter table truth_bonds
  add column if not exists solana_status text not null default 'pending',
  add column if not exists solana_record_at timestamptz,
  add column if not exists solana_error text;

comment on column truth_bonds.solana_status is
  'solana anchoring state for truth bond: pending, recording, anchored, failed';

create index if not exists echoes_created_record_tx_idx
  on echoes(created_record_tx)
  where created_record_tx is not null;

create index if not exists echo_proofs_stake_tx_idx
  on echo_proofs(stake_tx)
  where stake_tx is not null;

create index if not exists truth_bonds_mint_tx_idx
  on truth_bonds(mint_tx)
  where mint_tx is not null;
