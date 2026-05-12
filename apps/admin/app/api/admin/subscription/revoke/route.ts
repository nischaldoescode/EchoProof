import { requireAdmin } from "@/lib/auth/require-admin";
import { createAdminClient } from "@/lib/supabase/admin";
import { adminPath } from "@/lib/routes";
import { NextRequest, NextResponse } from "next/server";

export async function POST(req: NextRequest) {
  const admin = await requireAdmin();
  if (!admin.ok) return admin.response;

  const supabase = createAdminClient();
  const body = await req.formData();
  const subscriptionId = body.get("subscription_id") as string | null;

  if (!subscriptionId) {
    return NextResponse.json(
      { error: "subscription_id is required" },
      { status: 400 },
    );
  }

  const { data: subscription, error: fetchError } = await supabase
    .from("subscriptions")
    .select("id, user_id")
    .eq("id", subscriptionId)
    .single();

  if (fetchError || !subscription) {
    return NextResponse.json(
      { error: "subscription not found" },
      { status: 404 },
    );
  }

  const { error } = await supabase
    .from("subscriptions")
    .update({
      status: "cancelled",
      expires_at: new Date().toISOString(),
      updated_at: new Date().toISOString(),
    })
    .eq("id", subscriptionId);

  if (error) {
    return NextResponse.json({ error: error.message }, { status: 500 });
  }

  await supabase
    .from("users_public")
    .update({
      is_pro: false,
      pro_plan: null,
      pro_expires_at: null,
    })
    .eq("id", subscription.user_id);

  await supabase.from("notifications").insert({
    user_id: subscription.user_id,
    type: "subscription_update",
    title: "Pro access updated",
    body: "Your manual Pro grant was revoked by an administrator.",
    data: { route: "/subscription" },
  });

  return NextResponse.redirect(new URL(adminPath("/subscription"), req.url));
}
