// delete account request API
// sends email to support@echoproof.online
// deduplicates using supabase — prevents spam from same email
// rate limit: one request per email per 24 hours

import { NextRequest, NextResponse } from "next/server";
import { createClient }              from "@supabase/supabase-js";

const supabase = createClient(
  process.env.NEXT_PUBLIC_SUPABASE_URL!,
  process.env.SUPABASE_SERVICE_ROLE_KEY!,
);

export async function POST(req: NextRequest) {
  try {
    const body = await req.json();
    const { email, reason, description } = body as {
      email:       string;
      reason:      string;
      description: string;
    };

    if (!email || !reason) {
      return NextResponse.json(
        { error: "Email and reason are required." },
        { status: 400 },
      );
    }

    // normalize
    const normalizedEmail = email.trim().toLowerCase();

    // validate email format
    const emailRegex = /^[^\s@]+@[^\s@]+\.[^\s@]+$/;
    if (!emailRegex.test(normalizedEmail)) {
      return NextResponse.json(
        { error: "Invalid email address." },
        { status: 400 },
      );
    }

    // check for duplicate request in last 24 hours
    const yesterday = new Date();
    yesterday.setHours(yesterday.getHours() - 24);

    const { data: existing } = await supabase
      .from("deletion_requests")
      .select("id, created_at")
      .eq("email", normalizedEmail)
      .gte("created_at", yesterday.toISOString())
      .maybeSingle();

    if (existing) {
      return NextResponse.json(
        {
          error:
            "A deletion request for this email was already submitted in the last 24 hours. Please check your email for confirmation or contact support@echoproof.online.",
        },
        { status: 429 },
      );
    }

    // save request to database
    await supabase.from("deletion_requests").insert({
      email:       normalizedEmail,
      reason,
      description: description ?? "",
      status:      "pending",
      ip:          req.headers.get("x-forwarded-for") ?? "unknown",
    });

    // send email notification to support team
    // using supabase edge function so we don't need an SMTP server here
    await supabase.functions.invoke("send-support-email", {
      body: {
        to:      "support@echoproof.online",
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
      { error: "Internal server error. Please try again later." },
      { status: 500 },
    );
  }
}