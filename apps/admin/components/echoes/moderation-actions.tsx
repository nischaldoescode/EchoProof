"use client";

import { useState } from "react";
import { useRouter } from "next/navigation";
import type { Echo } from "@/types/echo";
import { adminPath } from "@/lib/routes";

interface ModerationActionsProps {
  echo: Echo;
  onClose: () => void;
}

export function ModerationActions({ echo, onClose }: ModerationActionsProps) {
  const router = useRouter();
  const [note, setNote]       = useState(echo.admin_note ?? "");
  const [loading, setLoading] = useState(false);

  async function applyAction(action: "verify" | "reject" | "hide" | "restore") {
    setLoading(true);

    const updates: Record<string, unknown> = {};

    if (action === "verify") {
      updates.admin_verified = true;
      updates.status         = "verified";
      updates.admin_note     = note;
    } else if (action === "reject") {
      updates.admin_verified = false;
      updates.status         = "rejected";
      updates.admin_note     = note;
    } else if (action === "hide") {
      updates.status     = "hidden";
      updates.admin_note = note;
    } else if (action === "restore") {
      updates.admin_verified = null;
      updates.status         = "active";
      updates.admin_note     = note;
    }

    const res = await fetch(adminPath(`/api/admin/echo/${echo.id}/status`), {
      method: "POST",
      headers: { "Content-Type": "application/json" },
      body: JSON.stringify({
        ...updates,
        resolve_reports: action === "reject",
        notify: true,
      }),
    });

    if (res.ok) {
      router.refresh();
      onClose();
    }

    setLoading(false);
  }

  return (
    <div className="bg-white rounded-xl border border-border-subtle p-4 space-y-4 sticky top-6">
      <div className="flex items-start justify-between">
        <p className="text-sm font-semibold text-charcoal">Moderation</p>
        <button
          onClick={onClose}
          className="text-gray-400 hover:text-charcoal text-lg leading-none"
        >
          ×
        </button>
      </div>

      <div className="space-y-1">
        <p className="text-xs font-medium text-gray-500">Echo content</p>
        <p className="text-xs text-charcoal leading-relaxed line-clamp-4">{echo.content}</p>
      </div>

      <div className="grid grid-cols-2 gap-2 text-xs">
        <div className="bg-soft-sand rounded-lg p-2">
          <p className="text-gray-400">Trust score</p>
          <p className="font-semibold text-charcoal">{echo.trust_score}</p>
        </div>
        <div className="bg-soft-sand rounded-lg p-2">
          <p className="text-gray-400">Report score</p>
          <p className={`font-semibold ${echo.report_score >= 40 ? "text-coral-dark" : "text-charcoal"}`}>
            {echo.report_score}
          </p>
        </div>
        <div className="bg-soft-sand rounded-lg p-2">
          <p className="text-gray-400">Confidence</p>
          <p className="font-semibold text-charcoal">{echo.confidence_score.toFixed(0)}%</p>
        </div>
        <div className="bg-soft-sand rounded-lg p-2">
          <p className="text-gray-400">AI spam score</p>
          <p className="font-semibold text-charcoal">
            {echo.ai_metadata?.spam_score ?? "—"}
          </p>
        </div>
      </div>

      {echo.verified_record_tx && (
        <div className="bg-fern-light rounded-lg p-2">
          <p className="text-xs text-fern-dark font-medium">Permanent record exists</p>
          <p className="text-xs text-fern-dark font-mono truncate">{echo.verified_record_tx}</p>
        </div>
      )}

      <div className="space-y-1">
        <p className="text-xs font-medium text-gray-500">Admin note</p>
        <textarea
          value={note}
          onChange={e => setNote(e.target.value)}
          placeholder="Optional note for audit log..."
          className="w-full border border-border-subtle rounded-lg px-3 py-2 text-xs resize-none h-16 focus:outline-none focus:border-charcoal"
        />
      </div>

      <div className="grid grid-cols-2 gap-2">
        <button
          onClick={() => applyAction("verify")}
          disabled={loading}
          className="bg-fern-light text-fern-dark text-xs font-semibold py-2 rounded-lg hover:bg-fern-green hover:text-white transition-colors disabled:opacity-50"
        >
          Verify
        </button>
        <button
          onClick={() => applyAction("reject")}
          disabled={loading}
          className="bg-coral-light text-coral-dark text-xs font-semibold py-2 rounded-lg hover:bg-sunset-coral hover:text-white transition-colors disabled:opacity-50"
        >
          Reject
        </button>
        <button
          onClick={() => applyAction("hide")}
          disabled={loading}
          className="bg-soft-sand text-gray-600 text-xs font-semibold py-2 rounded-lg hover:bg-gray-200 transition-colors disabled:opacity-50"
        >
          Hide
        </button>
        <button
          onClick={() => applyAction("restore")}
          disabled={loading}
          className="bg-soft-sand text-gray-600 text-xs font-semibold py-2 rounded-lg hover:bg-gray-200 transition-colors disabled:opacity-50"
        >
          Restore
        </button>
      </div>
    </div>
  );
}
