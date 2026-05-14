import { requireAdmin } from '@/lib/auth/require-admin';
import { createAdminClient } from '@/lib/supabase/admin';
import { adminUrl } from '@/lib/public-url';
import { NextRequest, NextResponse } from 'next/server';

export async function POST(req: NextRequest) {
  const admin = await requireAdmin();
  if (!admin.ok) return admin.response;

  const supabase = createAdminClient();
  const body = await req.formData();
  const username = ((body.get('username') as string | null) ?? '')
    .trim()
    .replace(/^@+/, '')
    .toLowerCase();
  const planType =
    body.get('plan_type') === 'pro_yearly' ? 'pro_yearly' : 'pro_monthly';
  const rawDurationCount = parseInt(
    ((body.get('duration_count') as string | null) ??
      (body.get('days') as string | null) ??
      '1'),
    10,
  );
  const durationCount = Number.isFinite(rawDurationCount)
    ? rawDurationCount
    : 1;
  const historyMode =
    body.get('purchase_history_mode') === 'acknowledged'
      ? 'acknowledged'
      : body.get('purchase_history_mode') === 'active'
        ? 'active'
        : 'none';

  if (!username) {
    return NextResponse.json(
      { error: 'username is required' },
      { status: 400 },
    );
  }

  const { data: user, error: userError } = await supabase
    .from('users_public')
    .select('id, username, onboarding_complete, is_pro, pro_expires_at')
    .eq('username', username)
    .maybeSingle();

  if (userError || !user) {
    return NextResponse.json(
      { error: `user @${username} not found` },
      { status: 404 },
    );
  }

  if (!user.onboarding_complete) {
    return NextResponse.json(
      {
        error:
          `@${username} has not completed onboarding, so Pro cannot be granted yet`,
      },
      { status: 400 },
    );
  }

  if (isActiveProfilePro(user)) {
    return NextResponse.json(
      { error: `@${username} already has active Pro` },
      { status: 400 },
    );
  }

  const { data: activeSubscription } = await supabase
    .from('subscriptions')
    .select('id, expires_at, status')
    .eq('user_id', user.id)
    .eq('status', 'active')
    .maybeSingle();

  if (
    activeSubscription &&
    (!activeSubscription.expires_at ||
      new Date(activeSubscription.expires_at).getTime() > Date.now())
  ) {
    return NextResponse.json(
      { error: `@${username} already has an active subscription row` },
      { status: 400 },
    );
  }

  const { data: privateProfile, error: privateProfileError } = await supabase
    .from('users_private')
    .select('id')
    .eq('id', user.id)
    .maybeSingle();

  if (privateProfileError || !privateProfile) {
    return NextResponse.json(
      {
        error:
          `@${username} does not have a signed-up private profile row yet, so Pro cannot be granted`,
      },
      { status: 400 },
    );
  }

  if (planType === 'pro_monthly' && (durationCount < 1 || durationCount > 2)) {
    return NextResponse.json(
      { error: 'Monthly manual grants can only be 1 or 2 months.' },
      { status: 400 },
    );
  }

  if (planType === 'pro_yearly' && durationCount !== 1) {
    return NextResponse.json(
      { error: 'Yearly manual grants can only be 1 year.' },
      { status: 400 },
    );
  }

  const expiresAt = new Date();
  if (planType === 'pro_yearly') {
    expiresAt.setFullYear(expiresAt.getFullYear() + 1);
  } else {
    expiresAt.setMonth(expiresAt.getMonth() + durationCount);
  }

  const { error } = await supabase.from('subscriptions').upsert({
    user_id: user.id,
    plan: planType,
    status: 'active',
    expires_at: expiresAt.toISOString(),
    granted_by: 'admin',
  }, { onConflict: 'user_id' });

  if (error) {
    return NextResponse.json({ error: error.message }, { status: 500 });
  }

  await supabase
    .from('users_public')
    .update({
      is_pro: true,
      pro_plan: planType,
      pro_expires_at: expiresAt.toISOString(),
    })
    .eq('id', user.id);

  if (historyMode !== 'none') {
    const nowMs = Date.now();
    const { error: purchaseError } = await supabase
      .from('purchase_history')
      .insert({
        user_id: user.id,
        order_id: `ADMIN-${nowMs}-${user.id.slice(0, 8)}`,
        product_id: planType,
        purchase_token: `admin_mock_${crypto.randomUUID()}`,
        plan_type: planType,
        status: historyMode,
        purchase_time_ms: nowMs,
        expires_time_ms: expiresAt.getTime(),
        obfuscated_account_id: user.id,
        amount_micros:
          planType === 'pro_yearly' ? 39990000 : 4990000 * durationCount,
        currency_code: 'USD',
        country_code: 'US',
        acknowledged: historyMode === 'acknowledged',
        verified_at: new Date().toISOString(),
      });

    if (purchaseError) {
      return NextResponse.json(
        { error: purchaseError.message },
        { status: 500 },
      );
    }
  }

  return NextResponse.redirect(
    adminUrl(req, '/subscription'),
    { status: 303 },
  );
}

function isActiveProfilePro(user: {
  is_pro?: boolean | null;
  pro_expires_at?: string | null;
}) {
  if (!user.is_pro) return false;
  if (!user.pro_expires_at) return true;
  return new Date(user.pro_expires_at).getTime() > Date.now();
}
