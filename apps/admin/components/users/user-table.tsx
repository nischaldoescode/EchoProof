"use client";

import { useState } from "react";
import { useRouter } from "next/navigation";
import { createClient } from "@/lib/supabase/client";
import type { PublicUser, TrustTier } from "@/types/user";

const TIER_COLORS: Record<TrustTier, string> = {
  unverified: "bg-gray-100 text-gray-500",
  low:        "bg-gray-100 text-gray-600",
  medium:     "bg-yellow-50 text-yellow-700",
  high:       "bg-fern-light text-fern-dark",
  elite:      "bg-fern-light text-fern-dark font-bold",
};

interface UserTableProps {
  users: PublicUser[];
}

export function UserTable({ users }: UserTableProps) {
  const router  = useRouter();
  const [loading, setLoading] = useState<string | null>(null);

  async function toggleSuspend(user: PublicUser) {
    setLoading(user.id);
    const supabase = createClient();
    await supabase
      .from("users_public")
      .update({ is_suspended: !user.is_suspended })
      .eq("id", user.id);
    router.refresh();
    setLoading(null);
  }

  async function toggleShadowBan(user: PublicUser) {
    setLoading(user.id);
    const supabase = createClient();
    await supabase
      .from("users_public")
      .update({ is_shadow_banned: !user.is_shadow_banned })
      .eq("id", user.id);
    router.refresh();
    setLoading(null);
  }

  return (
    <div className="bg-white rounded-xl border border-border-subtle overflow-hidden">
      <table className="w-full text-sm">
        <thead>
          <tr className="border-b border-border-subtle">
            <th className="text-left px-4 py-3 text-xs font-medium text-gray-400">User</th>
            <th className="text-left px-4 py-3 text-xs font-medium text-gray-400">Tier</th>
            <th className="text-right px-4 py-3 text-xs font-medium text-gray-400">Score</th>
            <th className="text-right px-4 py-3 text-xs font-medium text-gray-400">Echoes</th>
            <th className="text-left px-4 py-3 text-xs font-medium text-gray-400">On-chain</th>
            <th className="text-right px-4 py-3 text-xs font-medium text-gray-400">Actions</th>
          </tr>
        </thead>
        <tbody className="divide-y divide-border-subtle">
          {users.map(user => (
            <tr key={user.id} className="hover:bg-soft-sand transition-colors">
              <td className="px-4 py-3">
                <p className="font-medium text-charcoal text-xs">@{user.username}</p>
                {user.is_suspended && (
                  <span className="text-xs text-coral-dark">suspended</span>
                )}
                {user.is_shadow_banned && (
                  <span className="text-xs text-gray-400">shadow banned</span>
                )}
              </td>
              <td className="px-4 py-3">
                <span className={`px-2 py-0.5 rounded-md text-xs ${TIER_COLORS[user.trust_tier]}`}>
                  {user.trust_tier}
                </span>
              </td>
              <td className="px-4 py-3 text-right text-xs text-charcoal font-semibold">
                {user.trust_score}
              </td>
              <td className="px-4 py-3 text-right text-xs text-gray-500">
                {user.echo_count}
              </td>
              <td className="px-4 py-3">
                {user.wallet_address ? (
                  <span className="text-xs text-fern-dark font-mono">
                    {user.wallet_address.slice(0, 6)}...
                  </span>
                ) : (
                  <span className="text-xs text-gray-300">none</span>
                )}
              </td>
              <td className="px-4 py-3 text-right">
                <div className="flex gap-2 justify-end">
                  <button
                    onClick={() => toggleSuspend(user)}
                    disabled={loading === user.id}
                    className={`text-xs px-2 py-1 rounded-md border transition-colors ${
                      user.is_suspended
                        ? "border-fern-green text-fern-dark hover:bg-fern-light"
                        : "border-coral-dark text-coral-dark hover:bg-coral-light"
                    }`}
                  >
                    {user.is_suspended ? "Unsuspend" : "Suspend"}
                  </button>
                  <button
                    onClick={() => toggleShadowBan(user)}
                    disabled={loading === user.id}
                    className="text-xs px-2 py-1 rounded-md border border-border-subtle text-gray-500 hover:bg-soft-sand transition-colors"
                  >
                    {user.is_shadow_banned ? "Unban" : "Shadow ban"}
                  </button>
                </div>
              </td>
            </tr>
          ))}
        </tbody>
      </table>
    </div>
  );
}