"use client";

import { useState } from "react";
import { useRouter } from "next/navigation";
import { adminPath } from "@/lib/routes";

interface TrustScoreEditorProps {
  userId: string;
  currentScore: number;
  currentTier: string;
}

export function TrustScoreEditor({ userId, currentScore, currentTier }: TrustScoreEditorProps) {
  const router = useRouter();
  const [score, setScore] = useState(currentScore);
  const [saving, setSaving] = useState(false);

  async function save() {
    setSaving(true);
    try {
      const response = await fetch(adminPath("/api/admin/users/trust-score"), {
        method: "POST",
        headers: { "Content-Type": "application/json" },
        body: JSON.stringify({ userId, score }),
      });
      if (!response.ok) {
        const body = (await response.json().catch(() => ({}))) as {
          error?: string;
        };
        alert(body.error || "Could not update trust score.");
        return;
      }
      router.refresh();
    } finally {
      setSaving(false);
    }
  }

  return (
    <div className="flex items-center gap-3">
      <input
        type="number"
        value={score}
        min={0}
        max={100}
        onChange={e => setScore(Number(e.target.value))}
        className="w-20 border border-border-subtle rounded-lg px-2 py-1 text-xs text-center focus:outline-none focus:border-charcoal"
      />
      <button
        onClick={save}
        disabled={saving || score === currentScore}
        className="text-xs px-3 py-1.5 bg-charcoal text-white rounded-lg disabled:opacity-40"
      >
        {saving ? "saving..." : "save"}
      </button>
    </div>
  );
}
