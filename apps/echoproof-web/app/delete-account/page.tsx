"use client";

import { useEffect, useRef, useState } from "react";
import Nav from "@/components/Nav";
import Footer from "@/components/Footer";

const reasons = [
  "I no longer use Echoproof",
  "I have privacy concerns",
  "The app is not working correctly",
  "I found a better alternative",
  "I created a duplicate account",
  "Other",
];

/**
 * in-memory set to prevent duplicate submissions within the same session.
 * server-side deduplication is handled in the API route.
 */
const submittedEmails = new Set<string>();

declare global {
  interface Window {
    turnstile: any;
  }
}

export default function DeleteAccountPage() {
  const [email, setEmail] = useState("");
  const [reason, setReason] = useState("");
  const [description, setDescription] = useState("");
  const [loading, setLoading] = useState(false);
  const [done, setDone] = useState(false);
  const [error, setError] = useState("");

  const turnstileRef = useRef<HTMLDivElement | null>(null);
  const tokenRef = useRef<string | null>(null);

  /**
   * loads cloudflare turnstile script and renders widget.
   * token is stored in tokenRef for submission.
   */
  useEffect(() => {
    const script = document.createElement("script");
    script.src = "https://challenges.cloudflare.com/turnstile/v0/api.js";
    script.async = true;
    script.defer = true;

    script.onload = () => {
      if (window.turnstile && turnstileRef.current) {
        window.turnstile.render(turnstileRef.current, {
          sitekey: process.env.TURNSTILE_SITE_KEY!,
          callback: (token: string) => {
            tokenRef.current = token;
          },
          "expired-callback": () => {
            tokenRef.current = null;
          },
          "error-callback": () => {
            tokenRef.current = null;
          },
        });
      }
    };

    document.body.appendChild(script);

    return () => {
      document.body.removeChild(script);
    };
  }, []);

  /**
   * handles form submission including turnstile verification token.
   */
  const handleSubmit = async (e: React.FormEvent) => {
    e.preventDefault();
    setError("");

    if (!email || !reason) {
      setError("Please fill in all required fields.");
      return;
    }

    if (!tokenRef.current) {
      setError("Verification failed. Please try again.");
      return;
    }

    const normalizedEmail = email.trim().toLowerCase();

    if (submittedEmails.has(normalizedEmail)) {
      setError(
        "A deletion request for this email was already submitted in this session.",
      );
      return;
    }

    setLoading(true);

    try {
      const res = await fetch("/api/delete-request", {
        method: "POST",
        headers: { "Content-Type": "application/json" },
        body: JSON.stringify({
          email: normalizedEmail,
          reason,
          description: description.trim(),
          token: tokenRef.current,
        }),
      });

      const data = await res.json();

      if (!res.ok) {
        setError(data.error ?? "Something went wrong. Please try again.");
        setLoading(false);
        return;
      }

      submittedEmails.add(normalizedEmail);
      if (window.turnstile) {
        window.turnstile.reset();
      }
      tokenRef.current = null;
      setDone(true);
    } catch {
      setError("Network error. Please check your connection and try again.");
    } finally {
      setLoading(false);
    }
  };

  return (
    <>
      <Nav />
      <main className="pt-24 pb-20 max-w-lg mx-auto px-6">
        {done ? (
          <div className="text-center py-16">
            <div
              className="w-16 h-16 rounded-2xl flex items-center justify-center mx-auto mb-6"
              style={{ background: "#D4F0E2" }}
            >
              <svg width="28" height="28" fill="none" viewBox="0 0 24 24">
                <path
                  d="M5 13l4 4L19 7"
                  stroke="#4caf6e"
                  strokeWidth="2.5"
                  strokeLinecap="round"
                  strokeLinejoin="round"
                />
              </svg>
            </div>
            <h2 className="text-2xl font-bold text-charcoal mb-3">
              Request received
            </h2>
            <p className="text-sm text-neutral-500 leading-6">
              We have received your account deletion request. We will process it
              within 30 days and send a confirmation to <strong>{email}</strong>
              .
            </p>
          </div>
        ) : (
          <>
            <h1 className="text-3xl font-bold tracking-tight text-charcoal mb-2">
              Delete your account
            </h1>

            <form onSubmit={handleSubmit} className="space-y-5">
              <input
                type="email"
                required
                value={email}
                onChange={(e) => setEmail(e.target.value)}
                placeholder="the email on your Echoproof account"
                className="w-full px-4 py-3 text-sm rounded-xl border"
              />

              <select
                required
                value={reason}
                onChange={(e) => setReason(e.target.value)}
                className="w-full px-4 py-3 text-sm rounded-xl border"
              >
                <option value="">Select a reason</option>
                {reasons.map((r) => (
                  <option key={r} value={r}>
                    {r}
                  </option>
                ))}
              </select>

              <textarea
                value={description}
                onChange={(e) => setDescription(e.target.value)}
                rows={4}
                maxLength={500}
                className="w-full px-4 py-3 text-sm rounded-xl border"
              />

              <div ref={turnstileRef} />

              {error && <p className="text-red-500 text-sm">{error}</p>}

              <button
                type="submit"
                disabled={loading}
                className="w-full py-3 rounded-xl text-white bg-black"
              >
                {loading ? "Submitting..." : "Submit deletion request"}
              </button>
            </form>
          </>
        )}
      </main>
      <Footer />
    </>
  );
}
