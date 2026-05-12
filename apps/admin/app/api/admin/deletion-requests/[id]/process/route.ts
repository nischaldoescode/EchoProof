import { requireAdmin } from "@/lib/auth/require-admin";
import { createAdminClient } from "@/lib/supabase/admin";
import { NextRequest, NextResponse } from "next/server";

type RouteContext = {
  params: Promise<{ id: string }> | { id: string };
};

export async function POST(req: NextRequest, context: RouteContext) {
  const admin = await requireAdmin();
  if (!admin.ok) return admin.response;

  const { id } = await Promise.resolve(context.params);
  const body = (await req.json().catch(() => ({}))) as {
    delete_account?: boolean;
  };

  const supabase = createAdminClient();

  const { data: request, error: requestError } = await supabase
    .from("deletion_requests")
    .select("id, email, status")
    .eq("id", id)
    .single();

  if (requestError || !request) {
    return NextResponse.json(
      { error: "deletion request not found" },
      { status: 404 },
    );
  }

  if (body.delete_account) {
    const { data: privateRow } = await supabase
      .from("users_private")
      .select("id")
      .eq("email", request.email)
      .maybeSingle();

    if (privateRow?.id) {
      await deleteUserAccount(supabase, privateRow.id);
    }
  }

  const { error } = await supabase
    .from("deletion_requests")
    .update({ status: "processed" })
    .eq("id", id);

  if (error) {
    return NextResponse.json({ error: error.message }, { status: 500 });
  }

  return NextResponse.json({ success: true });
}

async function deleteUserAccount(
  supabase: ReturnType<typeof createAdminClient>,
  userId: string,
) {
  await supabase.functions
    .invoke("send-notification", {
      body: {
        user_id: userId,
        title: "Account deleted",
        body: "Your Echoproof account has been deleted as requested.",
        data: { type: "account_deleted" },
        route: "/login",
      },
    })
    .catch(() => {
      // Push is best-effort. The account deletion continues either way.
    });

  await ignoreMissing(
    supabase.from("signal_responses").delete().eq("user_id", userId),
  );
  await ignoreMissing(
    supabase.from("echo_interactions").delete().eq("user_id", userId),
  );
  await ignoreMissing(supabase.from("echo_replies").delete().eq("user_id", userId));

  const { data: echoes } = await supabase
    .from("echoes")
    .select("id")
    .eq("user_id", userId);

  const echoIds = (echoes ?? []).map((echo) => echo.id);
  if (echoIds.length > 0) {
    await ignoreMissing(supabase.from("echo_proofs").delete().in("echo_id", echoIds));
    await ignoreMissing(supabase.from("echo_signals").delete().in("echo_id", echoIds));
    await ignoreMissing(supabase.from("echo_reports").delete().in("echo_id", echoIds));
  }

  await ignoreMissing(supabase.from("truth_bonds").delete().eq("user_id", userId));
  await ignoreMissing(supabase.from("notifications").delete().eq("user_id", userId));
  await ignoreMissing(supabase.from("device_tokens").delete().eq("user_id", userId));
  await ignoreMissing(supabase.from("purchase_history").delete().eq("user_id", userId));
  await ignoreMissing(supabase.from("subscriptions").delete().eq("user_id", userId));
  await ignoreMissing(supabase.from("echoes").delete().eq("user_id", userId));
  await ignoreMissing(supabase.from("users_public").delete().eq("id", userId));
  await ignoreMissing(supabase.from("users_private").delete().eq("id", userId));

  const { error } = await supabase.auth.admin.deleteUser(userId);
  if (error) throw error;
}

async function ignoreMissing(query: PromiseLike<{ error: any }>) {
  const { error } = await query;
  if (!error) return;
  if (error.code === "42P01" || error.code === "42703") return;
  throw error;
}
