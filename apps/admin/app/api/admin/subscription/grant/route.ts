import { createServerClient } from '@/lib/supabase/client';
import { NextRequest, NextResponse } from 'next/server';

export async function POST(req: NextRequest) {
  const supabase = createServerClient();
  const body     = await req.formData();
  const username = (body.get('username') as string)?.replace('@', '');
  const days     = parseInt(body.get('days') as string ?? '30', 10);

  // find user by username
  const { data: user, error: userError } = await supabase
    .from('users_public')
    .select('id')
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
    user_id:    user.id,
    plan:       'pro',
    status:     'active',
    expires_at: expiresAt.toISOString(),
    granted_by: 'admin',
  }, { onConflict: 'user_id' });

  if (error) {
    return NextResponse.json({ error: error.message }, { status: 500 });
  }

  return NextResponse.redirect(
    new URL('/subscriptions', req.url),
  );
}