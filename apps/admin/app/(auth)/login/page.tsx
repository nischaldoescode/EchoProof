"use client";

import { Suspense, useState, type FormEvent } from "react";
import { useRouter, useSearchParams } from "next/navigation";
import { createClient } from "@/lib/supabase/client";

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
  const [loading, setLoading]   = useState(false);
  const queryError =
    searchParams.get("error") === "unauthorized"
      ? "This account is signed in, but it is not on the admin allowlist."
      : "";

  async function handleLogin(e: FormEvent) {
    e.preventDefault();
    setLoading(true);
    setError("");

    const supabase = createClient();
    const { error } = await supabase.auth.signInWithPassword({ email, password });

    if (error) {
      setError(error.message);
      setLoading(false);
      return;
    }

    router.push("/");
  }

  async function handleSignOut() {
    const supabase = createClient();
    await supabase.auth.signOut();
    router.replace("/login");
    router.refresh();
  }

  return (
    <LoginFrame
      email={email}
      password={password}
      error={error || queryError}
      loading={loading}
      canSignOut={!!queryError}
      onEmailChange={setEmail}
      onPasswordChange={setPassword}
      onSubmit={handleLogin}
      onSignOut={handleSignOut}
    />
  );
}

function LoginFrame({
  email = "",
  password = "",
  error = "",
  loading = false,
  canSignOut = false,
  onEmailChange,
  onPasswordChange,
  onSubmit,
  onSignOut,
}: {
  email?: string;
  password?: string;
  error?: string;
  loading?: boolean;
  canSignOut?: boolean;
  onEmailChange?: (value: string) => void;
  onPasswordChange?: (value: string) => void;
  onSubmit?: (e: FormEvent) => void;
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
          <h1 className="text-charcoal font-semibold text-lg">Sign in</h1>

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
            <label className="text-xs font-medium text-gray-500">Password</label>
            <input
              type="password"
              value={password}
              onChange={e => onPasswordChange?.(e.target.value)}
              className="w-full border border-border-subtle rounded-lg px-3 py-2 text-sm focus:outline-none focus:border-charcoal"
              required
            />
          </div>

          <button
            type="submit"
            disabled={loading}
            className="w-full bg-charcoal text-white rounded-lg py-2.5 text-sm font-semibold disabled:opacity-50 hover:-translate-y-0.5 hover:shadow-lg"
          >
            {loading ? "Signing in..." : "Sign in"}
          </button>
        </form>
      </div>
    </div>
  );
}
