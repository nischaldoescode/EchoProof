"use client";

// web delete account page
// @params none

import { useEffect, useMemo, useRef, useState } from "react";
import Nav from "@/components/Nav";
import Footer from "@/components/Footer";
import {
  normalizeEmail,
  validateDeletionEmail,
} from "@/lib/email-validation";

const reasons = [
  "I no longer use Echoproof",
  "I have privacy concerns",
  "The app is not working correctly",
  "I found a better alternative",
  "I created a duplicate account",
  "Other",
];

const submittedEmails = new Set<string>();
const turnstileSiteKey = process.env.NEXT_PUBLIC_TURNSTILE_SITE_KEY;

declare global {
  interface Window {
    turnstile?: {
      render: (
        element: HTMLElement,
        options: {
          sitekey: string;
          callback: (token: string) => void;
          "expired-callback": () => void;
          "error-callback": () => void;
        },
      ) => string;
      reset: (widgetId?: string) => void;
      remove?: (widgetId?: string) => void;
    };
  }
}

export default function DeleteAccountPage() {
  const [email, setEmail] = useState("");
  const [reason, setReason] = useState("");
  const [description, setDescription] = useState("");
  const [loading, setLoading] = useState(false);
  const [done, setDone] = useState(false);
  const [error, setError] = useState(() =>
    turnstileSiteKey
      ? ""
      : "Verification is not configured. Please contact support.",
  );
  const [captchaReady, setCaptchaReady] = useState(false);

  const turnstileRef = useRef<HTMLDivElement | null>(null);
  const tokenRef = useRef<string | null>(null);
  const widgetIdRef = useRef<string | null>(null);

  const normalizedEmail = useMemo(() => normalizeEmail(email), [email]);
  const emailError = email ? validateDeletionEmail(email) : null;
  const descriptionCount = description.trim().length;

  useEffect(() => {
    const siteKey = turnstileSiteKey;
    let mounted = true;
    if (!siteKey) return;

    const renderWidget = () => {
      if (
        !mounted ||
        !window.turnstile ||
        !turnstileRef.current ||
        widgetIdRef.current
      ) {
        return;
      }

      widgetIdRef.current = window.turnstile.render(turnstileRef.current, {
        sitekey: siteKey,
        callback: (token: string) => {
          tokenRef.current = token;
          setCaptchaReady(true);
          setError("");
        },
        "expired-callback": () => {
          tokenRef.current = null;
          setCaptchaReady(false);
        },
        "error-callback": () => {
          tokenRef.current = null;
          setCaptchaReady(false);
          setError("Verification could not load. Refresh and try again.");
        },
      });
    };

    if (window.turnstile) {
      renderWidget();
    } else {
      const existing = document.getElementById("cf-turnstile-script");
      const script =
        existing instanceof HTMLScriptElement
          ? existing
          : document.createElement("script");

      if (!existing) {
        script.id = "cf-turnstile-script";
        script.src = "https://challenges.cloudflare.com/turnstile/v0/api.js";
        script.async = true;
        script.defer = true;
        document.body.appendChild(script);
      }

      script.addEventListener("load", renderWidget);
      script.addEventListener("error", () => {
        if (mounted) {
          setError("Verification could not load. Check your connection.");
        }
      });
    }

    return () => {
      mounted = false;
      if (widgetIdRef.current && window.turnstile?.remove) {
        window.turnstile.remove(widgetIdRef.current);
      }
      widgetIdRef.current = null;
      tokenRef.current = null;
    };
  }, []);

  const handleSubmit = async (e: React.FormEvent) => {
    e.preventDefault();
    setError("");

    const validationMessage = validateDeletionEmail(email);
    if (validationMessage) {
      setError(validationMessage);
      return;
    }

    if (!reason) {
      setError("Choose the reason that best matches your request.");
      return;
    }

    if (reason === "Other" && description.trim().length < 8) {
      setError("For Other, add a short detail so support can process it.");
      return;
    }

    if (!tokenRef.current) {
      setError("Complete the verification before submitting.");
      return;
    }

    if (submittedEmails.has(normalizedEmail)) {
      setError(
        "A request for this email was already submitted in this browser session.",
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

      const data = await res.json().catch(() => ({}));

      if (!res.ok) {
        setError(data.error ?? "Something went wrong. Please try again.");
        window.turnstile?.reset(widgetIdRef.current ?? undefined);
        tokenRef.current = null;
        setCaptchaReady(false);
        return;
      }

      submittedEmails.add(normalizedEmail);
      window.turnstile?.reset(widgetIdRef.current ?? undefined);
      tokenRef.current = null;
      setDone(true);
    } catch {
      setError("Network error. Check your connection and try again.");
    } finally {
      setLoading(false);
    }
  };

  return (
    <>
      <Nav />
      <main className="ep-page-enter flex-1 bg-[#F8F7F5] px-5 pb-20 pt-24">
        <div className="mx-auto grid w-full max-w-5xl gap-8 md:grid-cols-[0.9fr_1.1fr] md:items-start">
          <section className="pt-2 md:sticky md:top-24">
            <p className="mb-3 text-xs font-semibold uppercase text-fern-dark">
              Account deletion
            </p>
            <h1 className="max-w-md text-3xl font-bold leading-tight text-charcoal sm:text-4xl">
              Request deletion without guessing where your data goes.
            </h1>
            <p className="mt-4 max-w-md text-sm leading-7 text-neutral-500">
              Use the email on your Echoproof account. If no account is linked
              to that email, we will tell you here so you can try the right
              address or know the account may already be gone.
            </p>
          </section>

          <section className="ep-card-in rounded-[22px] border border-border-subtle bg-white p-5 shadow-[0_18px_60px_rgba(26,26,26,0.08)] sm:p-7">
            {done ? (
              <div className="py-10 text-center">
                <div className="mx-auto mb-6 flex h-16 w-16 items-center justify-center rounded-2xl bg-fern-light">
                  <svg width="28" height="28" fill="none" viewBox="0 0 24 24">
                    <path
                      d="M5 13l4 4L19 7"
                      stroke="#4caf6e"
                      strokeLinecap="round"
                      strokeLinejoin="round"
                      strokeWidth="2.5"
                    />
                  </svg>
                </div>
                <h2 className="mb-3 text-2xl font-bold text-charcoal">
                  Request received
                </h2>
                <p className="mx-auto max-w-sm text-sm leading-6 text-neutral-500">
                  We saved the deletion request for{" "}
                  <strong>{normalizedEmail}</strong>. Support will process it
                  within 30 days and confirm by email.
                </p>
              </div>
            ) : (
              <form onSubmit={handleSubmit} className="space-y-5">
                <div>
                  <h2 className="text-xl font-bold text-charcoal">
                    Deletion request
                  </h2>
                  <p className="mt-1 text-sm text-neutral-500">
                    This form only creates the request. The actual deletion is
                    reviewed in the admin panel.
                  </p>
                </div>

                <label className="block">
                  <span className="mb-1.5 block text-xs font-semibold text-neutral-500">
                    Account email
                  </span>
                  <input
                    type="email"
                    required
                    value={email}
                    inputMode="email"
                    autoComplete="email"
                    onChange={(e) => setEmail(e.target.value)}
                    placeholder="you@example.com"
                    className="w-full rounded-xl border border-border-subtle bg-white px-4 py-3 text-sm text-charcoal outline-none transition focus:border-charcoal focus:ring-4 focus:ring-black/5"
                  />
                  {emailError && (
                    <span className="mt-1.5 block text-xs text-coral-dark">
                      {emailError}
                    </span>
                  )}
                </label>

                <label className="block">
                  <span className="mb-1.5 block text-xs font-semibold text-neutral-500">
                    Reason
                  </span>
                  <select
                    required
                    value={reason}
                    onChange={(e) => setReason(e.target.value)}
                    className="w-full rounded-xl border border-border-subtle bg-white px-4 py-3 text-sm text-charcoal outline-none transition focus:border-charcoal focus:ring-4 focus:ring-black/5"
                  >
                    <option value="">Select a reason</option>
                    {reasons.map((r) => (
                      <option key={r} value={r}>
                        {r}
                      </option>
                    ))}
                  </select>
                </label>

                <label className="block">
                  <div className="mb-1.5 flex items-center justify-between gap-3">
                    <span className="text-xs font-semibold text-neutral-500">
                      Details {reason === "Other" ? "" : "(optional)"}
                    </span>
                    <span className="text-xs text-neutral-400">
                      {descriptionCount}/500
                    </span>
                  </div>
                  <textarea
                    value={description}
                    onChange={(e) => setDescription(e.target.value)}
                    rows={4}
                    maxLength={500}
                    placeholder="Anything support should know before processing this."
                    className="w-full resize-none rounded-xl border border-border-subtle bg-white px-4 py-3 text-sm leading-6 text-charcoal outline-none transition focus:border-charcoal focus:ring-4 focus:ring-black/5"
                  />
                </label>

                <div className="rounded-xl border border-border-subtle bg-[#F8F7F5] p-3">
                  <div ref={turnstileRef} />
                  {!captchaReady && (
                    <p className="mt-2 text-xs text-neutral-500">
                      Waiting for verification.
                    </p>
                  )}
                </div>

                {error && (
                  <div className="rounded-xl border border-coral-dark/20 bg-coral-light px-4 py-3 text-sm text-coral-dark">
                    {error}
                  </div>
                )}

                <button
                  type="submit"
                  disabled={loading}
                  className="ep-hover-lift flex h-12 w-full items-center justify-center rounded-xl bg-charcoal text-sm font-bold text-white disabled:cursor-wait disabled:opacity-70"
                >
                  {loading ? (
                    <span className="ep-liquid-loader" aria-label="Submitting" />
                  ) : (
                    "Submit deletion request"
                  )}
                </button>
              </form>
            )}
          </section>
        </div>
      </main>
      <Footer />
    </>
  );
}
