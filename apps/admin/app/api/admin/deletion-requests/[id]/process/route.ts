// admin deletion request process api
// @params none

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
    .select("id, email, status, reason")
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
      const { data, error } = await supabase.rpc("admin_soft_delete_account", {
        p_user_id: privateRow.id,
        p_reason: "email_delete_request",
      });

      if (error) {
        return NextResponse.json({ error: error.message }, { status: 500 });
      }

      const result = (data ?? {}) as {
        restore_until?: string;
        email?: string;
      };

      await notifyDeletionScheduled(
        supabase,
        privateRow.id,
        result.restore_until,
      );
      await sendRecoveryEmail(
        result.email ?? request.email,
        result.restore_until ?? "",
      );
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

async function notifyDeletionScheduled(
  supabase: ReturnType<typeof createAdminClient>,
  userId: string,
  restoreUntil?: string,
) {
  await supabase.functions
    .invoke("send-notification", {
      body: {
        user_id: userId,
        title: "Account scheduled for deletion",
        body:
          "Your Echoproof account is in a 7-day recovery window. Sign in to keep it.",
        data: { type: "account_deleted" },
        route: "/login",
        restore_until: restoreUntil,
      },
    })
    .catch(() => {
      // push is best-effort. account scheduling continues either way
    });
}

async function sendRecoveryEmail(email: string, restoreUntil: string) {
  const apiKey = process.env.RESEND_API_KEY;
  const from =
    process.env.ACCOUNT_DELETION_FROM_EMAIL ??
    "EchoProof <support@echoproof.online>";

  if (!apiKey || !email) return;

  const deadline = formatDeadline(restoreUntil);
  const subject = "Your EchoProof account is scheduled for deletion";
  const text = [
    "We are sorry to see you go.",
    "",
    "Your EchoProof account has been scheduled for deletion. For the next 7 days, you can sign back in with this email and choose Keep account to restore your profile, echoes, and trust history.",
    "",
    `Recovery window: ${deadline}`,
    "",
    "If you do nothing, the account and related data will be permanently removed after the recovery window ends.",
    "",
    "EchoProof Support",
  ].join("\n");

  const html = `
    <div style="font-family:Inter,Arial,sans-serif;line-height:1.55;color:#24332d;max-width:560px;margin:0 auto;padding:24px">
      <h1 style="font-size:22px;margin:0 0 12px">We are sorry to see you go.</h1>
      <p>Your EchoProof account has been scheduled for deletion.</p>
      <p>For the next <strong>7 days</strong>, you can sign back in with this email and choose <strong>Keep account</strong> to restore your profile, echoes, and trust history.</p>
      <p style="background:#edf7f1;border:1px solid #cde8d7;border-radius:12px;padding:12px 14px">
        <strong>Recovery window:</strong><br>${escapeHtml(deadline)}
      </p>
      <p>If you do nothing, the account and related data will be permanently removed after the recovery window ends.</p>
      <p style="color:#60766b">EchoProof Support</p>
    </div>
  `;

  const res = await fetch("https://api.resend.com/emails", {
    method: "POST",
    headers: {
      Authorization: `Bearer ${apiKey}`,
      "Content-Type": "application/json",
    },
    body: JSON.stringify({
      from,
      to: email,
      subject,
      text,
      html,
    }),
  });

  if (!res.ok) {
    console.error("account deletion recovery email failed", await res.text());
  }
}

function formatDeadline(value: string) {
  if (!value) return "7 days from the deletion request";
  const parsed = new Date(value);
  if (Number.isNaN(parsed.getTime())) return "7 days from the deletion request";
  return parsed.toLocaleString("en-IN", {
    dateStyle: "medium",
    timeStyle: "short",
    timeZone: "Asia/Kolkata",
  });
}

function escapeHtml(value: string) {
  return value
    .replaceAll("&", "&amp;")
    .replaceAll("<", "&lt;")
    .replaceAll(">", "&gt;")
    .replaceAll('"', "&quot;")
    .replaceAll("'", "&#039;");
}
