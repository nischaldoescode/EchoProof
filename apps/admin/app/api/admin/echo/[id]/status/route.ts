// admin API: update echo status
// requires service role — never expose to users

import { createServerClient } from '@/lib/supabase/client';
import { NextRequest, NextResponse } from 'next/server';

export async function POST(
  req:     NextRequest,
  { params }: { params: { id: string } },
) {
  const supabase = createServerClient();
  const body     = await req.formData();
  const status   = body.get('status') as string;

  const allowed = ['verified', 'disputed', 'hidden', 'rejected', 'active', 'under_review'];
  if (!allowed.includes(status)) {
    return NextResponse.json({ error: 'invalid status' }, { status: 400 });
  }

  const { error } = await supabase
    .from('echoes')
    .update({ status })
    .eq('id', params.id);

  if (error) {
    return NextResponse.json({ error: error.message }, { status: 500 });
  }

  return NextResponse.redirect(
    new URL(`/echoes/${params.id}`, req.url),
  );
}