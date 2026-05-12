"use client";

import { Suspense, useEffect, useState, type FormEvent } from "react";
import type { Provider } from "@supabase/supabase-js";
import { useRouter, useSearchParams } from "next/navigation";
import { createClient } from "@/lib/supabase/client";
import { adminPath } from "@/lib/routes";

export default function LoginPage() {
  return (
    <Suspense fallback={<LoginFrame />}>
      <LoginForm />
    </Suspense>
  );
}

function LoginForm() {
  const router = useRouter();
  const searchParams = useSearchParams();
  const [email, setEmail] = useState("");
  const [error, setError] = useState("");
  const [notice, setNotice] = useState("");
  const [loading, setLoading] = useState(false);
  const queryError =
    searchParams.get("error") === "unauthorized"
      ? "This account is signed in, but it is not on the admin allowlist."
      : searchParams.get("error") === "auth_callback"
        ? "The login callback failed. Try signing in again."
        : "";

  useEffect(() => {
    const hash = new URLSearchParams(window.location.hash.replace(/^#/, ""));
    const accessToken = hash.get("access_token");
    const refreshToken = hash.get("refresh_token");

    if (!accessToken || !refreshToken) return;

    let cancelled = false;
    window.history.replaceState(null, "", window.location.pathname);

    async function finishHashLogin() {
      setLoading(true);
      setError("");
      setNotice("Finishing secure sign-in...");

      const supabase = createClient();
      const { error } = await supabase.auth.setSession({
        access_token: accessToken!,
        refresh_token: refreshToken!,
      });

      if (cancelled) return;

      if (error) {
        setError(authMessage(error.message));
        setNotice("");
        setLoading(false);
        return;
      }

      router.replace(adminPath("/"));
      router.refresh();
    }

    finishHashLogin();

    return () => {
      cancelled = true;
    };
  }, [router]);

  async function handleMagicLink(e?: FormEvent) {
    e?.preventDefault();

    if (!email.trim()) {
      setError("Enter your admin email first.");
      return;
    }

    setLoading(true);
    setError("");
    setNotice("");

    const response = await fetch(adminPath("/api/auth/admin-magic-link"), {
      method: "POST",
      headers: { "Content-Type": "application/json" },
      body: JSON.stringify({ email }),
    });
    const result = (await response.json().catch(() => ({}))) as {
      error?: string;
    };

    if (!response.ok) {
      setError(authMessage(result.error));
    } else {
      setNotice("Magic link sent. Open it from this admin email account.");
    }

    setLoading(false);
  }

  async function signInWithProvider(provider: Provider) {
    setLoading(true);
    setError("");
    setNotice("");

    try {
      const supabase = createClient();
      const redirectTo = `${window.location.origin}${adminPath("/auth/callback")}`;
      const { data, error } = await supabase.auth.signInWithOAuth({
        provider,
        options: { redirectTo, skipBrowserRedirect: true },
      });

      if (error) {
        setError(authMessage(error.message));
        setLoading(false);
        return;
      }

      if (!data?.url) {
        setError("Supabase did not return a redirect URL for this provider.");
        setLoading(false);
        return;
      }

      window.location.assign(data.url);
    } catch (error) {
      setError(authMessage(error instanceof Error ? error.message : undefined));
      setLoading(false);
    }
  }

  async function handleSignOut() {
    const supabase = createClient();
    await supabase.auth.signOut();
    router.replace(adminPath("/login"));
    router.refresh();
  }

  return (
    <LoginFrame
      email={email}
      error={error || queryError}
      notice={notice}
      loading={loading}
      canSignOut={!!queryError}
      onEmailChange={setEmail}
      onSubmit={handleMagicLink}
      onGoogle={() => signInWithProvider("google")}
      onGithub={() => signInWithProvider("github")}
      onSignOut={handleSignOut}
    />
  );
}

function LoginFrame({
  email = "",
  error = "",
  notice = "",
  loading = false,
  canSignOut = false,
  onEmailChange,
  onSubmit,
  onGoogle,
  onGithub,
  onSignOut,
}: {
  email?: string;
  error?: string;
  notice?: string;
  loading?: boolean;
  canSignOut?: boolean;
  onEmailChange?: (value: string) => void;
  onSubmit?: (e: FormEvent) => void;
  onGoogle?: () => void;
  onGithub?: () => void;
  onSignOut?: () => void;
}) {
  return (
    <div className="min-h-screen bg-soft-sand px-4 py-10 text-charcoal">
      <div className="mx-auto flex min-h-[calc(100vh-5rem)] w-full max-w-5xl items-center justify-center">
        <div className="grid w-full gap-8 lg:grid-cols-[0.9fr_1.1fr] lg:items-center">
          <div className="hidden lg:block">
            <div className="max-w-sm">
              <div className="mb-5 flex h-12 w-12 items-center justify-center rounded-xl border border-fern-green/20 bg-white shadow-sm">
                <img
                  src={adminPath("/favicon.ico")}
                  alt=""
                  className="h-6 w-6"
                />
              </div>
              <h1 className="text-3xl font-semibold tracking-tight text-charcoal">
                Echoproof Admin
              </h1>
              <p className="mt-3 text-sm leading-6 text-gray-600">
                A quiet control room for moderation, trust checks, and account
                operations.
              </p>
            </div>
          </div>

          <div className="mx-auto w-full max-w-sm animate-admin-enter">
            <div className="mb-6 flex items-center gap-3 lg:hidden">
              <div className="flex h-10 w-10 items-center justify-center rounded-xl border border-fern-green/20 bg-white">
                <img
                  src={adminPath("/favicon.ico")}
                  alt=""
                  className="h-5 w-5"
                />
              </div>
              <div>
                <p className="text-sm font-semibold text-charcoal">
                  Echoproof
                </p>
                <p className="text-xs text-gray-500">Admin panel</p>
              </div>
            </div>

            <form
              onSubmit={onSubmit}
              className="space-y-4 rounded-xl border border-white/80 bg-white p-6 shadow-xl shadow-black/5"
            >
              <div>
                <h2 className="text-lg font-semibold text-charcoal">
                  Sign in
                </h2>
                <p className="mt-1 text-xs leading-5 text-gray-500">
                  Use an allowlisted admin email with GitHub, Google, or a magic
                  link.
                </p>
              </div>

              {error && (
                <div className="rounded-lg border border-coral-dark/20 bg-coral-light p-3">
                  <p className="text-sm text-coral-dark">{error}</p>
                  {canSignOut && onSignOut && (
                    <button
                      type="button"
                      onClick={onSignOut}
                      className="mt-2 text-xs font-semibold text-coral-dark underline underline-offset-4"
                    >
                      Sign out and use another account
                    </button>
                  )}
                </div>
              )}

              {notice && (
                <div className="rounded-lg border border-fern-dark/20 bg-fern-light p-3">
                  <p className="text-sm text-fern-dark">{notice}</p>
                </div>
              )}

              <div className="grid gap-2">
                <button
                  type="button"
                  onClick={onGithub}
                  disabled={loading}
                  className="flex w-full items-center justify-center gap-2 rounded-lg border border-border-subtle bg-white py-2.5 text-sm font-semibold text-charcoal hover:-translate-y-0.5 hover:shadow-sm disabled:opacity-50"
                >
                  <GithubMark />
                  Continue with GitHub
                </button>
                <button
                  type="button"
                  onClick={onGoogle}
                  disabled={loading}
                  className="flex w-full items-center justify-center gap-2 rounded-lg border border-border-subtle bg-white py-2.5 text-sm font-semibold text-charcoal hover:-translate-y-0.5 hover:shadow-sm disabled:opacity-50"
                >
                  <GoogleMark />
                  Continue with Google
                </button>
              </div>

              <div className="flex items-center gap-3">
                <div className="h-px flex-1 bg-border-subtle" />
                <span className="text-[11px] uppercase tracking-wide text-gray-400">
                  or
                </span>
                <div className="h-px flex-1 bg-border-subtle" />
              </div>

              <div className="space-y-1">
                <label className="text-xs font-medium text-gray-500">
                  Email
                </label>
                <input
                  type="email"
                  value={email}
                  onChange={(e) => onEmailChange?.(e.target.value)}
                  className="w-full rounded-lg border border-border-subtle px-3 py-2 text-sm focus:border-fern-green focus:outline-none"
                  required
                />
              </div>

              <button
                type="submit"
                disabled={loading}
                className="w-full rounded-lg bg-fern-green py-2.5 text-sm font-semibold text-white hover:bg-fern-dark disabled:opacity-50"
              >
                {loading ? "Sending..." : "Send magic link"}
              </button>
            </form>
          </div>
        </div>
      </div>
    </div>
  );
}

function GoogleMark() {
  return (
    <svg width="16" height="16" viewBox="0 0 48 48" aria-hidden="true">
      <path
        fill="#FFC107"
        d="M43.6 20.5H42V20H24v8h11.3C33.7 32.7 29.3 36 24 36c-6.6 0-12-5.4-12-12s5.4-12 12-12c3.1 0 5.9 1.2 8 3.1l5.7-5.7C34.1 6.1 29.3 4 24 4 12.9 4 4 12.9 4 24s8.9 20 20 20 20-8.9 20-20c0-1.3-.1-2.4-.4-3.5z"
      />
      <path
        fill="#FF3D00"
        d="m6.3 14.7 6.6 4.8C14.7 15.1 19 12 24 12c3.1 0 5.9 1.2 8 3.1l5.7-5.7C34.1 6.1 29.3 4 24 4 16.3 4 9.6 8.3 6.3 14.7z"
      />
      <path
        fill="#4CAF50"
        d="M24 44c5.2 0 10-2 13.5-5.3l-6.2-5.2C29.3 35.1 26.8 36 24 36c-5.3 0-9.7-3.3-11.3-7.9l-6.6 5.1C9.4 39.6 16.1 44 24 44z"
      />
      <path
        fill="#1976D2"
        d="M43.6 20.5H42V20H24v8h11.3c-.8 2.4-2.3 4.2-4 5.5l6.2 5.2C36.9 39.2 44 34 44 24c0-1.3-.1-2.4-.4-3.5z"
      />
    </svg>
  );
}

function GithubMark() {
  return (
    <svg
      width="16"
      height="16"
      viewBox="0 0 24 24"
      fill="currentColor"
      aria-hidden="true"
    >
      <path d="M12 2C6.5 2 2 6.6 2 12.2c0 4.5 2.9 8.3 6.8 9.6.5.1.7-.2.7-.5v-1.8c-2.8.6-3.4-1.2-3.4-1.2-.5-1.2-1.1-1.5-1.1-1.5-.9-.6.1-.6.1-.6 1 .1 1.5 1 1.5 1 .9 1.5 2.3 1.1 2.9.8.1-.7.4-1.1.7-1.3-2.2-.3-4.6-1.1-4.6-5 0-1.1.4-2 1-2.8-.1-.3-.4-1.3.1-2.7 0 0 .8-.3 2.8 1.1.8-.2 1.6-.3 2.5-.3s1.7.1 2.5.3c1.9-1.4 2.8-1.1 2.8-1.1.5 1.4.2 2.4.1 2.7.6.7 1 1.7 1 2.8 0 3.9-2.4 4.7-4.6 5 .4.3.7 1 .7 2v2.9c0 .3.2.6.7.5 4-1.3 6.8-5.1 6.8-9.6C22 6.6 17.5 2 12 2z" />
    </svg>
  );
}

function authMessage(message?: string) {
  const normalized = message?.toLowerCase() ?? "";

  if (normalized.includes("signup") || normalized.includes("signups")) {
    return "This admin email is allowed, but Supabase Auth could not create or find the login user. Enable Email OTP signups or create this email in Authentication > Users.";
  }

  if (normalized.includes("provider")) {
    return "This OAuth provider is not enabled in Supabase Auth yet.";
  }

  return message || "Could not start admin sign-in. Try again.";
}
