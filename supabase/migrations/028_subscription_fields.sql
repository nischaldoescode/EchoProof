-- Subscription purchase history and invoice storage
-- run order: 028

create table if not exists public.purchase_history (
  id                  uuid primary key default gen_random_uuid(),
  user_id             uuid not null references auth.users(id) on delete cascade,
  order_id            text not null,
  product_id          text not null,
  purchase_token      text not null,
  plan_type           text not null check (plan_type in ('pro_monthly', 'pro_yearly')),
  status              text not null default 'pending'
                      check (status in (
                        'pending', 'active', 'acknowledged', 'canceled',
                        'expired', 'declined', 'refunded', 'grace_period',
                        'on_hold', 'paused'
                      )),
  -- Google Play response codes for declined purchases
  error_code          integer,
  error_message       text,
  -- Billing period
  purchase_time_ms    bigint not null,
  expires_time_ms     bigint,
  -- Obfuscated account id sent during purchase for fraud prevention
  obfuscated_account_id text,
  -- Invoice fields
  amount_micros       bigint,   -- price in micro-units (e.g. 49900000 = $4.99)
  currency_code       text,
  country_code        text,
  -- Upgrade/downgrade tracking
  replaced_purchase_token text,
  -- Server validation metadata
  acknowledged        boolean not null default false,
  verified_at         timestamptz,
  -- Upgrade bonus: extra month granted on upgrade
  upgrade_bonus_days  integer not null default 0,
  created_at          timestamptz not null default now(),
  updated_at          timestamptz not null default now(),
  unique(order_id)
);

alter table public.purchase_history enable row level security;

create policy "users read own purchase history"
  on public.purchase_history for select
  to authenticated
  using (auth.uid() = user_id);

create policy "service role manages purchase history"
  on public.purchase_history for all
  to service_role
  using (true) with check (true);

-- Index for fast user history lookups
create index purchase_history_user_idx on public.purchase_history(user_id);
create index purchase_history_token_idx on public.purchase_history(purchase_token);
create index purchase_history_order_idx on public.purchase_history(order_id);

-- Add Pro badge fields to users_public
alter table public.users_public
  add column if not exists is_pro boolean not null default false,
  add column if not exists pro_expires_at timestamptz,
  add column if not exists pro_plan text check (pro_plan in ('pro_monthly', 'pro_yearly'));

-- Add re-verification cooldown to users_private
-- Stores when user last submitted a verification request
-- Used server-side so cache clearing can't bypass it
alter table public.users_private
  add column if not exists last_verification_request_at timestamptz,
  add column if not exists verification_rejection_at timestamptz,
  add column if not exists verification_attempt_count integer not null default 0;