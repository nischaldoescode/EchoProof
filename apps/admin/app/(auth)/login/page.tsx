"use client";

// admin auth login page
// @params none

import { Suspense, useState, type FormEvent } from "react";
import { useRouter, useSearchParams } from "next/navigation";
import { adminPath } from "@/lib/routes";

const DEFAULT_ADMIN_EMAIL = "support@echoproof.online";

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
  const [email, setEmail] = useState(DEFAULT_ADMIN_EMAIL);
  const [password, setPassword] = useState("");
  const [error, setError] = useState("");
  const [loading, setLoading] = useState(false);
  const queryError =
    searchParams.get("error") === "unauthorized"
      ? "This account is not allowed to use the admin panel."
      : searchParams.get("error") === "auth_callback"
        ? "The OAuth callback failed. Use the admin password instead."
        : "";

  async function handlePasswordLogin(e: FormEvent) {
    e.preventDefault();

    if (!email.trim() || !password) {
      setError("Enter the admin email and password.");
      return;
    }

    setLoading(true);
    setError("");

    const response = await fetch(adminPath("/api/auth/admin-access-login"), {
      method: "POST",
      headers: { "Content-Type": "application/json" },
      body: JSON.stringify({ email, password }),
    });
    const result = (await response.json().catch(() => ({}))) as {
      error?: string;
    };

    if (!response.ok) {
      setError(result.error || "Could not sign in with that password.");
      setLoading(false);
      return;
    }

    router.replace(adminPath("/"));
    router.refresh();
  }

  return (
    <LoginFrame
      email={email}
      password={password}
      error={error || queryError}
      loading={loading}
      onEmailChange={setEmail}
      onPasswordChange={setPassword}
      onSubmit={handlePasswordLogin}
    />
  );
}

function LoginFrame({
  email = DEFAULT_ADMIN_EMAIL,
  password = "",
  error = "",
  loading = false,
  onEmailChange,
  onPasswordChange,
  onSubmit,
}: {
  email?: string;
  password?: string;
  error?: string;
  loading?: boolean;
  onEmailChange?: (value: string) => void;
  onPasswordChange?: (value: string) => void;
  onSubmit?: (e: FormEvent) => void;
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
                Sign in with the private admin password configured on the
                server.
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
                  Admin sign in
                </h2>
                <p className="mt-1 text-xs leading-5 text-gray-500">
                  Use the support email and the password stored in Render env.
                </p>
              </div>

              {error && (
                <div className="rounded-lg border border-coral-dark/20 bg-coral-light p-3">
                  <p className="text-sm text-coral-dark">{error}</p>
                </div>
              )}

              <div className="space-y-1">
                <label className="text-xs font-medium text-gray-500">
                  Email
                </label>
                <input
                  type="email"
                  value={email}
                  onChange={(e) => onEmailChange?.(e.target.value)}
                  className="w-full rounded-lg border border-border-subtle px-3 py-2 text-sm focus:border-fern-green focus:outline-none"
                  autoComplete="username"
                  required
                />
              </div>

              <div className="space-y-1">
                <label className="text-xs font-medium text-gray-500">
                  Password
                </label>
                <input
                  type="password"
                  value={password}
                  onChange={(e) => onPasswordChange?.(e.target.value)}
                  className="w-full rounded-lg border border-border-subtle px-3 py-2 text-sm focus:border-fern-green focus:outline-none"
                  autoComplete="current-password"
                  autoFocus
                  required
                />
              </div>

              <button
                type="submit"
                disabled={loading}
                className="w-full rounded-lg bg-charcoal py-2.5 text-sm font-semibold text-white transition-colors hover:bg-charcoal/90 disabled:opacity-50"
              >
                {loading ? "Signing in..." : "Sign in"}
              </button>
            </form>
          </div>
        </div>
      </div>
    </div>
  );
}
