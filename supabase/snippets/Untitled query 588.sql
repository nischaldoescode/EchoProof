-- Marks the official Echoproof support account as verified, elite, and premium.
-- This runs only after support@echoproof.online has signed in at least once.

alter table public.subscriptions
  drop constraint if exists subscriptions_plan_check;

alter table public.subscriptions
  add constraint subscriptions_plan_check
  check (plan in ('pro', 'lifetime', 'pro_monthly', 'pro_yearly'));

alter table public.subscriptions
  drop constraint if exists subscriptions_status_check;

alter table public.subscriptions
  add constraint subscriptions_status_check
  check (status in (
    'active',
    'cancelled',
    'canceled',
    'expired',
    'grace_period',
    'on_hold',
    'paused'
  ));

do $$
declare
  v_user_id uuid;
  v_username_taken boolean;
begin
  select id
  into v_user_id
  from public.users_private
  where lower(email) = 'support@echoproof.online'
  limit 1;

  if v_user_id is null then
    raise notice 'support@echoproof.online has no user row yet; skipping official admin mark';
    return;
  end if;

  select exists (
    select 1
    from public.users_public
    where lower(username) = 'echoproof'
      and id <> v_user_id
  )
  into v_username_taken;

  update public.users_public
  set
    username = case when v_username_taken then username else 'echoproof' end,
    display_name = 'Echoproof 🛡️',
    avatar_url = 'https://echoproof.online/logo.png',
    bio = 'Official Echoproof admin and support account.',
    trust_tier = 'elite',
    trust_score = greatest(trust_score, 1000),
    is_pro = true,
    pro_plan = 'pro_yearly',
    pro_expires_at = '2099-12-31 23:59:59+00',
    is_public = true,
    onboarding_complete = true,
    updated_at = now()
  where id = v_user_id;

  update public.users_private
  set
    is_identity_verified = true,
    identity_score = 100,
    ip_risk_score = 0,
    updated_at = now()
  where id = v_user_id;

  insert into public.subscriptions (
    user_id,
    plan,
    status,
    granted_by,
    expires_at
  )
  values (
    v_user_id,
    'lifetime',
    'active',
    'admin',
    null
  )
  on conflict (user_id) do update
  set
    plan = 'lifetime',
    status = 'active',
    granted_by = 'admin',
    expires_at = null,
    updated_at = now();
end $$;
