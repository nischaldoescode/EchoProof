// admin API: update echo status and notify the author
// requires service role — never expose to users

import { requireAdmin } from "@/lib/auth/require-admin";
import { createAdminClient } from "@/lib/supabase/admin";
import { adminPath } from "@/lib/routes";
import { NextRequest, NextResponse } from "next/server";

type RouteContext = {
  params: Promise<{ id: string }> | { id: string };
};

type StatusPayload = {
  status?: string;
  admin_note?: string | null;
  admin_verified?: boolean | null;
  resolve_reports?: boolean;
  notify?: boolean;
};

const allowed = new Set([
  "verified",
  "disputed",
  "hidden",
  "rejected",
  "active",
  "under_review",
]);

export async function POST(req: NextRequest, context: RouteContext) {
  const admin = await requireAdmin();
  if (!admin.ok) return admin.response;

  const { id } = await Promise.resolve(context.params);
  const payload = await readPayload(req);
  const status = payload.status;

  if (!status || !allowed.has(status)) {
    return NextResponse.json({ error: "invalid status" }, { status: 400 });
  }

  const supabase = createAdminClient();

  const { data: echo, error: echoError } = await supabase
    .from("echoes")
    .select("id, user_id, title, content, status")
    .eq("id", id)
    .single();

  if (echoError || !echo) {
    return NextResponse.json({ error: "echo not found" }, { status: 404 });
  }

  const updates: Record<string, unknown> = {
    status,
    admin_note: payload.admin_note ?? null,
  };

  if ("admin_verified" in payload) {
    updates.admin_verified = payload.admin_verified;
  } else if (status === "verified") {
    updates.admin_verified = true;
  } else if (status === "rejected") {
    updates.admin_verified = false;
  }

  const { error } = await supabase.from("echoes").update(updates).eq("id", id);

  if (error) {
    return NextResponse.json({ error: error.message }, { status: 500 });
  }

  if (payload.resolve_reports) {
    await supabase
      .from("echo_reports")
      .update({ resolved: true })
      .eq("echo_id", id)
      .eq("resolved", false);
  }

  if (payload.notify ?? true) {
    await notifyEchoAuthor({
      supabase,
      userId: echo.user_id,
      echoId: id,
      status,
      title: echo.title || echo.content.slice(0, 60),
    });
  }

  if (isJsonRequest(req)) {
    return NextResponse.json({ success: true, status });
  }

  return NextResponse.redirect(new URL(adminPath(`/echoes/${id}`), req.url));
}

async function readPayload(req: NextRequest): Promise<StatusPayload> {
  if (isJsonRequest(req)) {
    return (await req.json()) as StatusPayload;
  }

  const body = await req.formData();
  const rawAdminVerified = body.get("admin_verified");
  return {
    status: body.get("status") as string | undefined,
    admin_note: (body.get("admin_note") as string | null) ?? null,
    resolve_reports: body.get("resolve_reports") === "true",
    notify: body.get("notify") !== "false",
    admin_verified:
      rawAdminVerified === null
        ? undefined
        : rawAdminVerified === "true"
          ? true
          : rawAdminVerified === "false"
            ? false
            : null,
  };
}

function isJsonRequest(req: NextRequest) {
  return req.headers.get("content-type")?.includes("application/json") ?? false;
}

async function notifyEchoAuthor({
  supabase,
  userId,
  echoId,
  status,
  title,
}: {
  supabase: ReturnType<typeof createAdminClient>;
  userId: string;
  echoId: string;
  status: string;
  title: string;
}) {
  const copy = notificationCopy(status, title);

  await supabase.from("notifications").insert({
    user_id: userId,
    type: "echo_moderation",
    title: copy.title,
    body: copy.body,
    data: { echo_id: echoId, status, route: `/echo/${echoId}` },
  });

  await supabase.functions
    .invoke("send-notification", {
      body: {
        user_id: userId,
        title: copy.title,
        body: copy.body,
        data: { echo_id: echoId, status },
        route: `/echo/${echoId}`,
      },
    })
    .catch(() => {
      // Push is best-effort; the in-app notification above is the source of truth.
    });
}

function notificationCopy(status: string, echoTitle: string) {
  switch (status) {
    case "hidden":
      return {
        title: "Your echo is under moderation",
        body: `"${echoTitle}" was temporarily hidden while reports are reviewed.`,
      };
    case "rejected":
      return {
        title: "Your echo was removed",
        body: `"${echoTitle}" was removed after moderation review.`,
      };
    case "under_review":
      return {
        title: "Your echo is being reviewed",
        body: `"${echoTitle}" received reports and is now in review.`,
      };
    case "verified":
      return {
        title: "Your echo was verified",
        body: `"${echoTitle}" was verified by moderation.`,
      };
    default:
      return {
        title: "Your echo status changed",
        body: `"${echoTitle}" is now ${status.replace(/_/g, " ")}.`,
      };
  }
}
