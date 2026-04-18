"use client";

import { useState } from "react";
import { useRouter } from "next/navigation";
import { createClient } from "@/lib/supabase/client";

export default function LoginPage() {
  const router = useRouter();
  const [email, setEmail]       = useState("");
  const [password, setPassword] = useState("");
  const [error, setError]       = useState("");
  const [loading, setLoading]   = useState(false);

  async function handleLogin(e: React.FormEvent) {
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

  return (
    <div className="min-h-screen bg-charcoal flex items-center justify-center px-4">
      <div className="w-full max-w-sm">
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

        <form onSubmit={handleLogin} className="bg-white rounded-2xl p-6 space-y-4">
          <h1 className="text-charcoal font-semibold text-lg">Sign in</h1>

          {error && (
            <div className="bg-coral-light border border-coral-dark/20 rounded-lg p-3">
              <p className="text-coral-dark text-sm">{error}</p>
            </div>
          )}

          <div className="space-y-1">
            <label className="text-xs font-medium text-gray-500">Email</label>
            <input
              type="email"
              value={email}
              onChange={e => setEmail(e.target.value)}
              className="w-full border border-border-subtle rounded-lg px-3 py-2 text-sm focus:outline-none focus:border-charcoal"
              required
            />
          </div>

          <div className="space-y-1">
            <label className="text-xs font-medium text-gray-500">Password</label>
            <input
              type="password"
              value={password}
              onChange={e => setPassword(e.target.value)}
              className="w-full border border-border-subtle rounded-lg px-3 py-2 text-sm focus:outline-none focus:border-charcoal"
              required
            />
          </div>

          <button
            type="submit"
            disabled={loading}
            className="w-full bg-charcoal text-white rounded-lg py-2.5 text-sm font-semibold disabled:opacity-50"
          >
            {loading ? "Signing in..." : "Sign in"}
          </button>
        </form>
      </div>
    </div>
  );
}