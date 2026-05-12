import { requireAdmin } from "@/lib/auth/require-admin";
import { createAdminClient } from "@/lib/supabase/admin";
import { adminUrl } from "@/lib/public-url";
import { NextRequest, NextResponse } from "next/server";

export async function POST(req: NextRequest) {
  const admin = await requireAdmin();
  if (!admin.ok) return admin.response;

  const supabase = createAdminClient();
  const body = await req.formData();

  const monthlyUsd = Number(body.get("monthly_usd") ?? 4.99);
  const discountPct = Number(body.get("new_user_discount_pct") ?? 30);
  const trialDays = Number(body.get("trial_days") ?? 7);
  const yearlyUsd = Number(body.get("yearly_usd") ?? 39.99);

  const { error } = await supabase.from("subscription_pricing").upsert(
    {
      id: 1,
      monthly_usd: Number.isFinite(monthlyUsd) ? monthlyUsd : 4.99,
      yearly_usd: Number.isFinite(yearlyUsd) ? yearlyUsd : 39.99,
      new_user_discount_pct: Number.isFinite(discountPct) ? discountPct : 30,
      trial_days: Number.isFinite(trialDays) ? trialDays : 7,
      updated_at: new Date().toISOString(),
    },
    { onConflict: "id" },
  );

  if (error) {
    return NextResponse.json({ error: error.message }, { status: 500 });
  }

  return NextResponse.redirect(adminUrl(req, "/subscription"));
}
