"use client";

import { Suspense, useState, type FormEvent } from "react";
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
  const [email, setEmail]       = useState("");
  const [password, setPassword] = useState("");
  const [error, setError]       = useState("");
  const [notice, setNotice]     = useState("");
  const [loading, setLoading]   = useState(false);
  const queryError =
    searchParams.get("error") === "unauthorized"
      ? "This account is signed in, but it is not on the admin allowlist."
      : searchParams.get("error") === "auth_callback"
        ? "The login callback failed. Try signing in again."
      : "";

  async function handleLogin(e: FormEvent) {
    e.preventDefault();
    setLoading(true);
    setError("");
    setNotice("");

    if (!password.trim()) {
      await sendMagicLink();
      return;
    }

    const supabase = createClient();
    const { error } = await supabase.auth.signInWithPassword({ email, password });

    if (error) {
      setError(error.message);
      setLoading(false);
      return;
    }

    router.push(adminPath("/"));
  }

  async function sendMagicLink() {
    if (!email.trim()) {
      setError("Enter your admin email first.");
      setLoading(false);
      return;
    }

    setLoading(true);
    setError("");
    setNotice("");

    const supabase = createClient();
    const redirectTo = `${window.location.origin}${adminPath("/auth/callback")}`;
    const { error } = await supabase.auth.signInWithOtp({
      email: email.trim(),
      options: {
        emailRedirectTo: redirectTo,
        shouldCreateUser: false,
      },
    });

    if (error) {
      setError(error.message);
    } else {
      setNotice("Magic link sent. Open it from this admin email account.");
    }

    setLoading(false);
  }

  async function signInWithGoogle() {
    setLoading(true);
    setError("");
    setNotice("");

    const supabase = createClient();
    const redirectTo = `${window.location.origin}${adminPath("/auth/callback")}`;
    const { error } = await supabase.auth.signInWithOAuth({
      provider: "google",
      options: { redirectTo },
    });

    if (error) {
      setError(error.message);
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
      password={password}
      error={error || queryError}
      notice={notice}
      loading={loading}
      canSignOut={!!queryError}
      onEmailChange={setEmail}
      onPasswordChange={setPassword}
      onSubmit={handleLogin}
      onMagicLink={sendMagicLink}
      onGoogle={signInWithGoogle}
      onSignOut={handleSignOut}
    />
  );
}

function LoginFrame({
  email = "",
  password = "",
  error = "",
  notice = "",
  loading = false,
  canSignOut = false,
  onEmailChange,
  onPasswordChange,
  onSubmit,
  onMagicLink,
  onGoogle,
  onSignOut,
}: {
  email?: string;
  password?: string;
  error?: string;
  notice?: string;
  loading?: boolean;
  canSignOut?: boolean;
  onEmailChange?: (value: string) => void;
  onPasswordChange?: (value: string) => void;
  onSubmit?: (e: FormEvent) => void;
  onMagicLink?: () => void;
  onGoogle?: () => void;
  onSignOut?: () => void;
}) {
  return (
    <div className="min-h-screen bg-charcoal flex items-center justify-center px-4 py-10">
      <div className="w-full max-w-sm animate-admin-enter">
        <div className="flex items-center gap-3 mb-8">
          <div className="w-10 h-10 rounded-xl bg-fern-light flex items-center justify-center">
            <svg width="20" height="20" viewBox="0 0 20 20" fill="none">
              <circle cx="10" cy="10" r="2" fill="#4CAF6E"/>
              <circle cx="10" cy="10" r="5" stroke="#4CAF6E" strokeWidth="1.2" fill="none"/>
              <circle cx="10" cy="10" r="8" stroke="#4CAF6E" strokeWidth="0.8" fill="none" opacity="0.5"/>
            </svg>
          </div>
          <div>
            <p className="text-white font-semibold text-sm">Echoproof</p>
            <p className="text-gray-400 text-xs">Admin panel</p>
          </div>
        </div>

        <form onSubmit={onSubmit} className="bg-white rounded-2xl p-6 space-y-4 shadow-2xl shadow-black/20">
          <div>
            <h1 className="text-charcoal font-semibold text-lg">Sign in</h1>
            <p className="mt-1 text-xs leading-5 text-gray-500">
              Use Google, a magic link, or your Supabase admin password.
            </p>
          </div>

          {error && (
            <div className="bg-coral-light border border-coral-dark/20 rounded-lg p-3">
              <p className="text-coral-dark text-sm">{error}</p>
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

          <button
            type="button"
            onClick={onGoogle}
            disabled={loading}
            className="flex w-full items-center justify-center gap-2 rounded-lg border border-border-subtle bg-white py-2.5 text-sm font-semibold text-charcoal hover:-translate-y-0.5 hover:shadow-sm disabled:opacity-50"
          >
            <span className="h-2.5 w-2.5 rounded-full bg-[#4285F4]" />
            Continue with Google
          </button>

          <div className="flex items-center gap-3">
            <div className="h-px flex-1 bg-border-subtle" />
            <span className="text-[11px] uppercase tracking-wide text-gray-400">
              or
            </span>
            <div className="h-px flex-1 bg-border-subtle" />
          </div>

          <div className="space-y-1">
            <label className="text-xs font-medium text-gray-500">Email</label>
            <input
              type="email"
              value={email}
              onChange={e => onEmailChange?.(e.target.value)}
              className="w-full border border-border-subtle rounded-lg px-3 py-2 text-sm focus:outline-none focus:border-charcoal"
              required
            />
          </div>

          <div className="space-y-1">
            <label className="text-xs font-medium text-gray-500">
              Password, optional
            </label>
            <input
              type="password"
              value={password}
              onChange={e => onPasswordChange?.(e.target.value)}
              className="w-full border border-border-subtle rounded-lg px-3 py-2 text-sm focus:outline-none focus:border-charcoal"
              placeholder="Leave empty to send a magic link"
            />
          </div>

          <button
            type="submit"
            disabled={loading}
            className="w-full bg-charcoal text-white rounded-lg py-2.5 text-sm font-semibold disabled:opacity-50 hover:-translate-y-0.5 hover:shadow-lg"
          >
            {loading ? "Working..." : password ? "Sign in with password" : "Send magic link"}
          </button>

          <button
            type="button"
            onClick={onMagicLink}
            disabled={loading}
            className="w-full rounded-lg bg-soft-sand py-2.5 text-sm font-semibold text-charcoal hover:bg-[#dedad0] disabled:opacity-50"
          >
            Send magic link instead
          </button>
        </form>
      </div>
    </div>
  );
}
