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
  const rawDays = parseInt((body.get('days') as string | null) ?? '30', 10);
  const days = Number.isFinite(rawDays)
    ? Math.min(Math.max(rawDays, 1), 3650)
    : 30;
  const planType =
    body.get('plan_type') === 'pro_yearly' ? 'pro_yearly' : 'pro_monthly';
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

  // find user by username
  const { data: user, error: userError } = await supabase
    .from('users_public')
    .select('id, username')
    .eq('username', username)
    .single();

  if (userError || !user) {
    return NextResponse.json(
      { error: `user @${username} not found` },
      { status: 404 },
    );
  }

  const expiresAt = new Date();
  expiresAt.setDate(expiresAt.getDate() + days);

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
        amount_micros: planType === 'pro_yearly' ? 39990000 : 4990000,
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
