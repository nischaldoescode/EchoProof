import { NextRequest, NextResponse } from "next/server";
import { supabaseAdmin as supabase } from "@/lib/supabase";

export const dynamic = "force-dynamic";
export const runtime = "nodejs";

/**
 * sanitizes user input by trimming and removing unsafe characters.
 * prevents basic injection and email/html abuse.
 */
function sanitize(input: string, maxLength = 500) {
  return input
    .replace(/[<>]/g, "") // strip html brackets
    .replace(/\s+/g, " ") // normalize whitespace
    .trim()
    .slice(0, maxLength);
}

/**
 * verifies cloudflare turnstile token using server-side secret key.
 * also validates hostname to prevent token reuse across domains.
 */
async function verifyTurnstile(token: string, ip?: string | null) {
  const res = await fetch(
    "https://challenges.cloudflare.com/turnstile/v0/siteverify",
    {
      method: "POST",
      headers: {
        "Content-Type": "application/x-www-form-urlencoded",
      },
      body: new URLSearchParams({
        secret: process.env.TURNSTILE_SECRET_KEY!,
        response: token,
        remoteip: ip ?? "",
      }),
    },
  );

  const data = await res.json();

  return (
    data.success === true &&
    (data.hostname === "echoproof.online" ||
      data.hostname === "www.echoproof.online")
  );
}

/**
 * basic rate limiting using database.
 * limits:
 * - max 3 requests per IP per hour
 * - max 1 request per email per 24h (already exists)
 */
async function checkRateLimit(ip: string | null) {
  if (!ip) return false;

  const oneHourAgo = new Date();
  oneHourAgo.setHours(oneHourAgo.getHours() - 1);

  const { count } = await supabase
    .from("deletion_requests")
    .select("*", { count: "exact", head: true })
    .eq("ip", ip)
    .gte("created_at", oneHourAgo.toISOString());

  return (count ?? 0) >= 3;
}

/**
 * handles deletion request submission with validation, sanitization,
 * deduplication, rate limiting, and bot protection.
 */
export async function POST(req: NextRequest) {
  try {
    const body = await req.json();

    const {
      email,
      reason: rawReason,
      description: rawDescription,
      token,
    } = body as {
      email: string;
      reason: string;
      description: string;
      token: string;
    };

    if (!email || !rawReason || !token) {
      return NextResponse.json(
        { error: "Missing required fields." },
        { status: 400 },
      );
    }

    const ip =
      req.headers.get("x-forwarded-for")?.split(",")[0]?.trim() ?? null;

    const isHuman = await verifyTurnstile(token, ip);

    if (!isHuman) {
      return NextResponse.json(
        { error: "Verification failed. Please refresh and try again." },
        { status: 403 },
      );
    }

    // rate limit by IP
    const limited = await checkRateLimit(ip);
    if (limited) {
      return NextResponse.json(
        { error: "Too many requests. Please try again later." },
        { status: 429 },
      );
    }

    // normalize + sanitize
    const normalizedEmail = sanitize(email.toLowerCase(), 120);
    const reason = sanitize(rawReason, 120);
    const description = sanitize(rawDescription ?? "", 500);

    const emailRegex = /^[^\s@]+@[^\s@]+\.[^\s@]+$/;
    if (!emailRegex.test(normalizedEmail)) {
      return NextResponse.json(
        { error: "Invalid email address." },
        { status: 400 },
      );
    }

    // email-based 24h dedup
    const yesterday = new Date();
    yesterday.setHours(yesterday.getHours() - 24);

    const { data: existing } = await supabase
      .from("deletion_requests")
      .select("id")
      .eq("email", normalizedEmail)
      .gte("created_at", yesterday.toISOString())
      .maybeSingle();

    if (existing) {
      return NextResponse.json(
        { error: "Request already submitted in last 24 hours." },
        { status: 429 },
      );
    }

    await supabase.from("deletion_requests").insert({
      email: normalizedEmail,
      reason,
      description,
      status: "pending",
      ip: ip ?? "unknown",
    });

    await supabase.functions.invoke("send-support-email", {
      body: {
        to: "support@echoproof.online",
        subject: `[Echoproof] Account deletion request — ${normalizedEmail}`,
        html: `
          <div style="font-family: 'Josefin Sans', sans-serif; max-width: 600px; margin: 0 auto;">
            <h2 style="color: #1a1a1a;">Account Deletion Request</h2>
            <table style="width: 100%; border-collapse: collapse; margin: 16px 0;">
              <tr>
                <td style="padding: 10px; background: #f5f5f5; font-weight: 600; width: 140px;">Email</td>
                <td style="padding: 10px; border-bottom: 1px solid #e5e5e5;">${normalizedEmail}</td>
              </tr>
              <tr>
                <td style="padding: 10px; background: #f5f5f5; font-weight: 600;">Reason</td>
                <td style="padding: 10px; border-bottom: 1px solid #e5e5e5;">${reason}</td>
              </tr>
              <tr>
                <td style="padding: 10px; background: #f5f5f5; font-weight: 600;">Details</td>
                <td style="padding: 10px; border-bottom: 1px solid #e5e5e5;">${description || "—"}</td>
              </tr>
              <tr>
                <td style="padding: 10px; background: #f5f5f5; font-weight: 600;">Submitted</td>
                <td style="padding: 10px;">${new Date().toUTCString()}</td>
              </tr>
            </table>
            <p style="color: #6b7280; font-size: 13px;">
              Please process this deletion request within 30 days.
              Look up the user in Supabase by email and delete their account data.
            </p>
          </div>
        `,
      },
    });

    return NextResponse.json({ success: true }, { status: 200 });
  } catch (err) {
    console.error("delete-request API error:", err);
    return NextResponse.json(
      { error: "Internal server error." },
      { status: 500 },
    );
  }
}
