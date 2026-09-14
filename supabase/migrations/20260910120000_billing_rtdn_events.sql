create table if not exists public.billing_rtdn_events (
  message_id text primary key,
  package_name text not null,
  notification_type integer,
  purchase_token text,
  status text not null default 'processing',
  received_at timestamptz not null default now(),
  processed_at timestamptz,
  error_message text
);

alter table public.billing_rtdn_events enable row level security;

comment on table public.billing_rtdn_events is
  'Idempotency and audit records for Google Play RTDN Pub/Sub messages.';

alter table public.purchase_history
  drop constraint if exists purchase_history_status_check;

alter table public.purchase_history
  add constraint purchase_history_status_check check (status in (
    'pending', 'active', 'acknowledged', 'canceled', 'expired', 'declined',
    'refunded', 'grace_period', 'on_hold', 'paused', 'pending_canceled',
    'deferred', 'unknown'
  ));

alter table public.subscriptions
  drop constraint if exists subscriptions_status_check;

alter table public.subscriptions
  add constraint subscriptions_status_check check (status in (
    'active', 'cancelled', 'canceled', 'expired', 'grace_period', 'on_hold',
    'paused', 'pending', 'pending_canceled', 'deferred', 'unknown'
  ));
