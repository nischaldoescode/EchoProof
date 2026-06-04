// web delete request api
// @params none

import { NextRequest, NextResponse } from "next/server";
import { supabaseAdmin as supabase } from "@/lib/supabase";
import { normalizeEmail, validateDeletionEmail } from "@/lib/email-validation";

export const dynamic = "force-dynamic";
export const runtime = "nodejs";

const allowedReasons = new Set([
  "I no longer use Echoproof",
  "I have privacy concerns",
  "The app is not working correctly",
  "I found a better alternative",
  "I created a duplicate account",
  "Other",
]);

/*
 * sanitizes user input by trimming and removing unsafe characters
 * prevents basic injection and email/html abuse
 */
function sanitize(input: string, maxLength = 500) {
  return input
    .replace(/[<>]/g, "") // strip html brackets
    .replace(/\s+/g, " ") // normalize whitespace
    .trim()
    .slice(0, maxLength);
}

function escapeHtml(input: string) {
  return input
    .replace(/&/g, "&amp;")
    .replace(/</g, "&lt;")
    .replace(/>/g, "&gt;")
    .replace(/"/g, "&quot;")
    .replace(/'/g, "&#39;");
}

function getAllowedTurnstileHosts() {
  const configured = process.env.TURNSTILE_ALLOWED_HOSTNAMES;
  const hosts = (configured || "echoproof.online,www.echoproof.online")
    .split(",")
    .map((host) => host.trim().toLowerCase())
    .filter(Boolean);

  if (process.env.NODE_ENV !== "production") {
    hosts.push("localhost", "127.0.0.1");
  }

  return new Set(hosts);
}

/**
 * verifies cloudflare turnstile token using server-side secret key.
 * also validates hostname to prevent token reuse across domains.
 */
async function verifyTurnstile(token: string, ip?: string | null) {
  const secret = process.env.TURNSTILE_SECRET_KEY;
  if (!secret) {
    console.error("delete-request: TURNSTILE_SECRET_KEY is not configured");
    return false;
  }

  try {
    const res = await fetch(
      "https://challenges.cloudflare.com/turnstile/v0/siteverify",
      {
        method: "POST",
        headers: {
          "Content-Type": "application/x-www-form-urlencoded",
        },
        body: new URLSearchParams({
          secret,
          response: token,
          remoteip: ip ?? "",
        }),
      },
    );

    if (!res.ok) return false;

    const data = (await res.json()) as {
      success?: boolean;
      hostname?: string;
    };
    const hostname = data.hostname?.toLowerCase();

    return (
      data.success === true &&
      !!hostname &&
      getAllowedTurnstileHosts().has(hostname)
    );
  } catch (err) {
    console.error("delete-request: turnstile verification failed", err);
    return false;
  }
}

/*
 * basic rate limiting using database
 * limits:
 * max 3 requests per ip per hour
 * max 1 request per email per 24h (already exists)
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

async function accountExistsForEmail(email: string) {
  const { data, error } = await supabase
    .from("users_private")
    .select("id,email")
    .ilike("email", email)
    .limit(5);

  if (error) {
    console.error("delete-request: account lookup failed", error);
    throw new Error("account_lookup_failed");
  }

  return (data ?? []).some(
    (row) => row.email?.trim().toLowerCase() === email,
  );
}

function getClientIp(req: NextRequest) {
  return (
    req.headers.get("cf-connecting-ip") ||
    req.headers.get("x-real-ip") ||
    req.headers.get("x-forwarded-for")?.split(",")[0]?.trim() ||
    null
  );
}

/*
 * handles deletion request submission with validation, sanitization,
 * deduplication, rate limiting, and bot protection
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

    // normalize + sanitize
    const normalizedEmail = normalizeEmail(sanitize(email, 254));
    const reason = sanitize(rawReason, 120);
    const description = sanitize(rawDescription ?? "", 500);

    const emailError = validateDeletionEmail(normalizedEmail);
    if (emailError) {
      return NextResponse.json(
        { error: emailError },
        { status: 400 },
      );
    }

    if (!allowedReasons.has(reason)) {
      return NextResponse.json(
        { error: "Select a valid deletion reason." },
        { status: 400 },
      );
    }

    const ip = getClientIp(req);

    // rate limit by ip before the external verification call
    const limited = await checkRateLimit(ip);
    if (limited) {
      return NextResponse.json(
        { error: "Too many requests. Please try again later." },
        { status: 429 },
      );
    }

    const isHuman = await verifyTurnstile(token, ip);

    if (!isHuman) {
      return NextResponse.json(
        { error: "Verification failed. Please refresh and try again." },
        { status: 403 },
      );
    }

    const accountExists = await accountExistsForEmail(normalizedEmail);
    if (!accountExists) {
      return NextResponse.json(
        {
          error:
            "No Echoproof account is associated with this email. It may already have been deleted, or the account may use a different email.",
        },
        { status: 404 },
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

    const { error: insertError } = await supabase.from("deletion_requests").insert({
      email: normalizedEmail,
      reason,
      description,
      status: "pending",
      ip: ip ?? "unknown",
    });

    if (insertError) {
      console.error("delete-request: insert failed", insertError);
      return NextResponse.json(
        { error: "Could not save the request. Please try again." },
        { status: 500 },
      );
    }

    const safeEmail = escapeHtml(normalizedEmail);
    const safeReason = escapeHtml(reason);
    const safeDescription = escapeHtml(description || "-");

    const { error: emailInvokeError } = await supabase.functions.invoke(
      "send-support-email",
      {
        body: {
          to: "support@echoproof.online",
          subject: `[Echoproof] Account deletion request - ${normalizedEmail}`,
          html: `
          <div style="font-family: 'Josefin Sans', sans-serif; max-width: 600px; margin: 0 auto;">
            <h2 style="color: #1a1a1a;">Account Deletion Request</h2>
            <table style="width: 100%; border-collapse: collapse; margin: 16px 0;">
              <tr>
                <td style="padding: 10px; background: #f5f5f5; font-weight: 600; width: 140px;">Email</td>
                <td style="padding: 10px; border-bottom: 1px solid #e5e5e5;">${safeEmail}</td>
              </tr>
              <tr>
                <td style="padding: 10px; background: #f5f5f5; font-weight: 600;">Reason</td>
                <td style="padding: 10px; border-bottom: 1px solid #e5e5e5;">${safeReason}</td>
              </tr>
              <tr>
                <td style="padding: 10px; background: #f5f5f5; font-weight: 600;">Details</td>
                <td style="padding: 10px; border-bottom: 1px solid #e5e5e5;">${safeDescription}</td>
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
      },
    );

    if (emailInvokeError) {
      console.error("delete-request: support email failed", emailInvokeError);
    }

    return NextResponse.json({ success: true }, { status: 200 });
  } catch (err) {
    console.error("delete-request API error:", err);
    return NextResponse.json(
      { error: "Internal server error." },
      { status: 500 },
    );
  }
}
