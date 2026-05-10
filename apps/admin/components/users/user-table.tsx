"use client";

import { useState } from "react";
import { useRouter } from "next/navigation";
import { createBrowserClient } from "@/lib/supabase/client";
import type { PublicUser } from "@/types/user";
import Link from "next/link";

const TIER_COLORS: Record<string, string> = {
  unverified: "bg-gray-100 text-gray-500",
  low: "bg-gray-100 text-gray-600",
  medium: "bg-yellow-50 text-yellow-700",
  high: "bg-green-50 text-green-700",
  elite: "bg-green-100 text-green-800 font-bold",
};

// Extended user type including new columns from migration 030+.
interface ExtendedUser extends PublicUser {
  display_name?: string | null;
  is_pro?: boolean;
  pro_plan?: string | null;
  pro_expires_at?: string | null;
  age?: number | null;
  gender?: string | null;
  follower_count?: number;
  following_count?: number;
}

interface UserTableProps {
  users: ExtendedUser[];
}

type FilterType =
  | "all"
  | "pro"
  | "suspended"
  | "shadow_banned"
  | "elite"
  | "high";

export function UserTable({ users }: UserTableProps) {
  const router = useRouter();
  const [loading, setLoading] = useState<string | null>(null);
  const [filter, setFilter] = useState<FilterType>("all");
  const [search, setSearch] = useState("");

  const filtered = users.filter((u) => {
    if (search) {
      const q = search.toLowerCase();
      if (
        !u.username?.toLowerCase().includes(q) &&
        !u.display_name?.toLowerCase().includes(q)
      )
        return false;
    }
    if (filter === "pro") return u.is_pro;
    if (filter === "suspended") return u.is_suspended;
    if (filter === "shadow_banned") return u.is_shadow_banned;
    if (filter === "elite") return u.trust_tier === "elite";
    if (filter === "high") return u.trust_tier === "high";
    return true;
  });

  async function toggleSuspend(user: ExtendedUser) {
    setLoading(user.id);
    const supabase = createBrowserClient();
    await supabase
      .from("users_public")
      .update({ is_suspended: !user.is_suspended })
      .eq("id", user.id);
    router.refresh();
    setLoading(null);
  }

  async function toggleShadowBan(user: ExtendedUser) {
    setLoading(user.id);
    const supabase = createBrowserClient();
    await supabase
      .from("users_public")
      .update({ is_shadow_banned: !user.is_shadow_banned })
      .eq("id", user.id);
    router.refresh();
    setLoading(null);
  }

  return (
    <div className="space-y-4">
      {/* search + filter bar */}
      <div className="flex flex-wrap gap-3 items-center">
        <input
          value={search}
          onChange={(e) => setSearch(e.target.value)}
          placeholder="Search by username or name..."
          className="border border-[#E6E6E6] rounded-lg px-3 py-2 text-xs w-56 focus:outline-none focus:border-[#1A1A1A] transition-colors"
        />
        <div className="flex gap-2 flex-wrap">
          {(
            [
              "all",
              "pro",
              "suspended",
              "shadow_banned",
              "elite",
              "high",
            ] as FilterType[]
          ).map((f) => (
            <button
              key={f}
              onClick={() => setFilter(f)}
              className={`px-3 py-1.5 rounded-lg text-xs font-medium border transition-all duration-200 cursor-pointer ${
                filter === f
                  ? "bg-[#1A1A1A] text-white border-[#1A1A1A] scale-95"
                  : "bg-white text-gray-500 border-[#E6E6E6] hover:border-gray-300 hover:scale-95"
              }`}
            >
              {f === "all" ? "All" : f.replace("_", " ")}
            </button>
          ))}
        </div>
        <span className="text-xs text-gray-400 ml-auto">
          {filtered.length} user{filtered.length !== 1 ? "s" : ""}
        </span>
      </div>

      <div className="bg-white rounded-xl border border-[#E6E6E6] overflow-hidden">
        <div className="overflow-x-auto">
          <table className="w-full text-sm min-w-[900px]">
            <thead>
              <tr className="border-b border-[#E6E6E6] bg-[#F8F7F5]">
                <th className="text-left px-4 py-3 text-xs font-medium text-gray-400">
                  User
                </th>
                <th className="text-left px-4 py-3 text-xs font-medium text-gray-400">
                  Tier
                </th>
                <th className="text-left px-4 py-3 text-xs font-medium text-gray-400">
                  Pro
                </th>
                <th className="text-left px-4 py-3 text-xs font-medium text-gray-400">
                  Age / Gender
                </th>
                <th className="text-right px-4 py-3 text-xs font-medium text-gray-400">
                  Score
                </th>
                <th className="text-right px-4 py-3 text-xs font-medium text-gray-400">
                  Echoes
                </th>
                <th className="text-right px-4 py-3 text-xs font-medium text-gray-400">
                  Followers
                </th>
                <th className="text-right px-4 py-3 text-xs font-medium text-gray-400">
                  Actions
                </th>
              </tr>
            </thead>
            <tbody className="divide-y divide-[#F0F0F0]">
              {filtered.map((user) => (
                <tr
                  key={user.id}
                  className="hover:bg-[#F8F7F5] transition-colors"
                >
                  <td className="px-4 py-3">
                    <div className="flex flex-col">
                      <Link
                        href={`/users/${user.id}`}
                        className="font-medium text-[#1A1A1A] text-xs hover:text-[#4CAF6E] transition-colors cursor-pointer"
                      >
                        @{user.username}
                      </Link>
                      {user.display_name && (
                        <span className="text-xs text-gray-400">
                          {user.display_name}
                        </span>
                      )}
                      {user.is_suspended && (
                        <span className="text-xs text-[#FF7759] font-medium">
                          suspended
                        </span>
                      )}
                      {user.is_shadow_banned && (
                        <span className="text-xs text-gray-400">
                          shadow banned
                        </span>
                      )}
                    </div>
                  </td>
                  <td className="px-4 py-3">
                    <span
                      className={`px-2 py-0.5 rounded-md text-xs ${TIER_COLORS[user.trust_tier] ?? "bg-gray-100 text-gray-500"}`}
                    >
                      {user.trust_tier}
                    </span>
                  </td>
                  <td className="px-4 py-3">
                    {user.is_pro ? (
                      <div className="flex flex-col">
                        <span className="text-xs font-semibold text-[#4CAF6E]">
                          Pro ★
                        </span>
                        {user.pro_plan && (
                          <span className="text-xs text-gray-400">
                            {user.pro_plan
                              .replace("pro_", "")
                              .replace("ly", "")}
                          </span>
                        )}
                        {user.pro_expires_at && (
                          <span className="text-xs text-gray-400">
                            exp{" "}
                            {new Date(user.pro_expires_at).toLocaleDateString(
                              "en-GB",
                              { day: "2-digit", month: "short" },
                            )}
                          </span>
                        )}
                      </div>
                    ) : (
                      <span className="text-xs text-gray-300">Free</span>
                    )}
                  </td>
                  <td className="px-4 py-3">
                    <div className="flex flex-col">
                      {user.age != null && (
                        <span className="text-xs text-gray-600">
                          {user.age} yrs
                        </span>
                      )}
                      {user.gender && (
                        <span className="text-xs text-gray-400 capitalize">
                          {user.gender.replace("_", " ")}
                        </span>
                      )}
                    </div>
                  </td>
                  <td className="px-4 py-3 text-right text-xs font-semibold text-[#1A1A1A]">
                    {user.trust_score}
                  </td>
                  <td className="px-4 py-3 text-right text-xs text-gray-500">
                    {user.echo_count}
                  </td>
                  <td className="px-4 py-3 text-right">
                    <div className="flex flex-col items-end">
                      <span className="text-xs text-gray-500">
                        {user.follower_count ?? 0} followers
                      </span>
                      <span className="text-xs text-gray-400">
                        {user.following_count ?? 0} following
                      </span>
                    </div>
                  </td>
                  <td className="px-4 py-3 text-right">
                    <div className="flex gap-2 justify-end">
                      <button
                        onClick={() => toggleSuspend(user)}
                        disabled={loading === user.id}
                        className={`text-xs px-2 py-1 rounded-md border transition-all duration-200 cursor-pointer hover:scale-95 ${
                          user.is_suspended
                            ? "border-[#4CAF6E] text-[#2D7A4A] hover:bg-[#E8F5EE]"
                            : "border-[#FF7759] text-[#B03E28] hover:bg-[#FFF0ED]"
                        } disabled:opacity-40`}
                      >
                        {user.is_suspended ? "Unsuspend" : "Suspend"}
                      </button>
                      <button
                        onClick={() => toggleShadowBan(user)}
                        disabled={loading === user.id}
                        className="text-xs px-2 py-1 rounded-md border border-[#E6E6E6] text-gray-500 hover:bg-[#F8F7F5] transition-all duration-200 cursor-pointer hover:scale-95 disabled:opacity-40"
                      >
                        {user.is_shadow_banned ? "Unban" : "Shadow ban"}
                      </button>
                    </div>
                  </td>
                </tr>
              ))}

              {filtered.length === 0 && (
                <tr>
                  <td
                    colSpan={8}
                    className="px-4 py-10 text-center text-gray-400 text-sm"
                  >
                    No users match this filter
                  </td>
                </tr>
              )}
            </tbody>
          </table>
        </div>
      </div>
    </div>
  );
}
