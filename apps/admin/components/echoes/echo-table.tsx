"use client";

import { useState } from "react";
import type { Echo, EchoStatus } from "@/types/echo";
import { ModerationActions } from "./moderation-actions";

const STATUS_COLORS: Record<EchoStatus, string> = {
  pending_verification: "bg-gray-100 text-gray-600",
  active:               "bg-blue-50 text-blue-700",
  under_review:         "bg-yellow-50 text-yellow-700",
  verified:             "bg-fern-light text-fern-dark",
  controversial:        "bg-orange-50 text-orange-700",
  disputed:             "bg-red-50 text-red-700",
  hidden:               "bg-gray-200 text-gray-500",
  rejected:             "bg-coral-light text-coral-dark",
};

interface EchoTableProps {
  echoes: Echo[];
}

export function EchoTable({ echoes }: EchoTableProps) {
  const [filter, setFilter] = useState<EchoStatus | "all">("all");
  const [selected, setSelected] = useState<Echo | null>(null);

  const filtered = filter === "all"
    ? echoes
    : echoes.filter(e => e.status === filter);

  return (
    <div className="space-y-4">
      {/* filter tabs */}
      <div className="flex gap-2 flex-wrap">
        {(["all", "under_review", "hidden", "verified", "controversial"] as const).map(f => (
          <button
            key={f}
            onClick={() => setFilter(f)}
            className={`px-3 py-1.5 rounded-lg text-xs font-medium border transition-colors ${
              filter === f
                ? "bg-charcoal text-white border-charcoal"
                : "bg-white text-gray-500 border-border-subtle hover:border-gray-300"
            }`}
          >
            {f === "all" ? "All echoes" : f.replace("_", " ")}
          </button>
        ))}
      </div>

      <div className="flex flex-col gap-4 xl:flex-row">
        {/* table */}
        <div className="admin-soft-card flex-1 overflow-hidden rounded-xl border border-border-subtle bg-white">
          <div className="overflow-x-auto">
          <table className="w-full min-w-[760px] text-sm">
            <thead>
              <tr className="border-b border-border-subtle">
                <th className="text-left px-4 py-3 text-xs font-medium text-gray-400">User</th>
                <th className="text-left px-4 py-3 text-xs font-medium text-gray-400">Echo</th>
                <th className="text-left px-4 py-3 text-xs font-medium text-gray-400">Status</th>
                <th className="text-right px-4 py-3 text-xs font-medium text-gray-400">Report score</th>
                <th className="text-right px-4 py-3 text-xs font-medium text-gray-400">Confidence</th>
              </tr>
            </thead>
            <tbody className="divide-y divide-border-subtle">
              {filtered.map((echo, index) => (
                <tr
                  key={echo.id}
                  onClick={() => setSelected(selected?.id === echo.id ? null : echo)}
                  className={`cursor-pointer hover:bg-soft-sand transition-colors ${
                    selected?.id === echo.id ? "bg-soft-sand" : ""
                  }`}
                  style={{
                    animation: "echoRowIn 180ms ease-out both",
                    animationDelay: `${Math.min(index * 18, 180)}ms`,
                  }}
                >
                  <td className="px-4 py-3">
                    <p className="font-medium text-charcoal text-xs">
                      @{echo.users_public.username}
                    </p>
                    <p className="text-gray-400 text-xs capitalize">
                      {echo.users_public.trust_tier}
                    </p>
                  </td>
                  <td className="px-4 py-3 max-w-xs">
                    <p className="font-medium text-charcoal text-xs line-clamp-1">
                      {echo.title || echo.content.slice(0, 60)}
                    </p>
                    <p className="text-gray-400 text-xs capitalize">{echo.category}</p>
                  </td>
                  <td className="px-4 py-3">
                    <span className={`px-2 py-0.5 rounded-md text-xs font-medium ${STATUS_COLORS[echo.status]}`}>
                      {echo.status.replace("_", " ")}
                    </span>
                    {echo.verified_record_tx && (
                      <span className="ml-1.5 text-xs text-fern-dark">● record</span>
                    )}
                  </td>
                  <td className="px-4 py-3 text-right">
                    <span className={`text-xs font-semibold ${
                      echo.report_score >= 40 ? "text-coral-dark" :
                      echo.report_score >= 20 ? "text-yellow-600" : "text-gray-400"
                    }`}>
                      {echo.report_score}
                    </span>
                  </td>
                  <td className="px-4 py-3 text-right text-xs text-gray-500">
                    {echo.confidence_score.toFixed(0)}%
                  </td>
                </tr>
              ))}

              {filtered.length === 0 && (
                <tr>
                  <td colSpan={5} className="px-4 py-8 text-center text-gray-400 text-sm">
                    No echoes match this filter
                  </td>
                </tr>
              )}
            </tbody>
          </table>
          </div>
        </div>

        {/* detail panel */}
        {selected && (
          <div className="w-full flex-shrink-0 xl:w-80">
            <ModerationActions echo={selected} onClose={() => setSelected(null)} />
          </div>
        )}
      </div>

      <style jsx global>{`
        @keyframes echoRowIn {
          from {
            opacity: 0;
            transform: translateY(4px);
          }
          to {
            opacity: 1;
            transform: translateY(0);
          }
        }
      `}</style>
    </div>
  );
}
