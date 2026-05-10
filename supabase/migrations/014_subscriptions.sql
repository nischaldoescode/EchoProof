-- subscriptions table
create table subscriptions (
  id           uuid primary key default gen_random_uuid(),
  user_id      uuid not null references auth.users(id) on delete cascade,
  plan         text not null default 'pro' check (plan in ('pro', 'lifetime')),
  status       text not null default 'active' check (status in ('active', 'cancelled', 'expired')),
  granted_by   text,  -- 'stripe', 'admin', 'promo'
  expires_at   timestamptz,
  created_at   timestamptz not null default now(),
  updated_at   timestamptz not null default now(),
  unique(user_id)
);

-- subscription pricing — single row, admin editable
create table subscription_pricing (
  id                   integer primary key default 1,
  monthly_usd          numeric(6,2) not null default 4.99,
  yearly_usd           numeric(6,2) not null default 39.99,
  new_user_discount_pct integer not null default 30,
  trial_days           integer not null default 7,
  updated_at           timestamptz not null default now(),
  constraint single_row check (id = 1)
);

insert into subscription_pricing (id, monthly_usd, yearly_usd) values (1, 4.99, 39.99);

-- RLS
alter table subscriptions enable row level security;

create policy "users read own subscription" on subscriptions
  for select using (auth.uid() = user_id);

create policy "service role manages subscriptions" on subscriptions
  using (true) with check (true);

-- helper: check if user has active pro subscription
create or replace function is_pro_user(p_user_id uuid)
returns boolean language sql security definer as $$
  select exists (
    select 1 from subscriptions
    where user_id = p_user_id
      and status = 'active'
      and (expires_at is null or expires_at > now())
  );
$$;

-- age and gender columns on users_public
alter table users_public
  add column if not exists age integer,
  add column if not exists gender text check (gender in ('male', 'female', 'non_binary', 'prefer_not_to_say'));