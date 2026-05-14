"use client";

import { useState } from "react";
import { adminPath } from "@/lib/routes";

interface PendingEcho {
  id: string;
  status: string;
  trust_score: number;
  confidence_score: number;
  last_engine_run_at: string | null;
}

interface TrustEnginePanelProps {
  pendingEchoes: PendingEcho[];
}

export function TrustEnginePanel({ pendingEchoes }: TrustEnginePanelProps) {
  const [running, setRunning] = useState(false);
  const [result, setResult] = useState<string | null>(null);

  async function triggerEngineRun() {
    setRunning(true);
    setResult(null);

    try {
      const res = await fetch(adminPath("/api/admin/trust-engine/run"), {
        method: "POST",
      });

      const data = await res.json();
      if (!res.ok) {
        setResult(`error: ${JSON.stringify(data, null, 2)}`);
        return;
      }
      setResult(JSON.stringify(data.results ?? data, null, 2));
    } catch (err) {
      setResult(`error: ${err}`);
    } finally {
      setRunning(false);
    }
  }

  return (
    <div className="space-y-6">
      <div className="admin-soft-card rounded-xl border border-border-subtle bg-white p-5">
        <div className="mb-4 flex flex-col gap-3 sm:flex-row sm:items-center sm:justify-between">
          <div>
            <p className="text-sm font-semibold text-charcoal">Manual engine run</p>
            <p className="text-xs text-gray-400 mt-0.5">
              Triggers trust score recalculation for all stale echoes
            </p>
          </div>
          <button
            onClick={triggerEngineRun}
            disabled={running}
            className="w-full rounded-lg bg-charcoal px-4 py-2 text-xs font-semibold text-white shadow-sm transition-all hover:-translate-y-0.5 hover:bg-charcoal/90 disabled:translate-y-0 disabled:opacity-50 sm:w-auto"
          >
            {running ? "Running..." : "Run now"}
          </button>
        </div>

        {result && (
          <pre className="bg-soft-sand rounded-lg p-3 text-xs font-mono text-charcoal overflow-auto max-h-48">
            {result}
          </pre>
        )}
      </div>

      <div className="admin-soft-card overflow-hidden rounded-xl border border-border-subtle bg-white">
        <div className="px-4 py-3 border-b border-border-subtle">
          <p className="text-sm font-medium text-charcoal">
            Pending echoes ({pendingEchoes.length})
          </p>
        </div>
        <div className="overflow-x-auto">
          <table className="w-full min-w-[560px] text-xs">
            <thead>
              <tr className="border-b border-border-subtle">
                <th className="px-4 py-2 text-left font-medium text-gray-400">Echo ID</th>
                <th className="px-4 py-2 text-right font-medium text-gray-400">Trust score</th>
                <th className="px-4 py-2 text-right font-medium text-gray-400">Confidence</th>
                <th className="px-4 py-2 text-right font-medium text-gray-400">Last run</th>
              </tr>
            </thead>
            <tbody className="divide-y divide-border-subtle">
              {pendingEchoes.map((echo) => (
                <tr
                  key={echo.id}
                  className="admin-table-row hover:bg-soft-sand"
                >
                  <td className="px-4 py-2 font-mono text-charcoal">
                    {echo.id.slice(0, 12)}...
                  </td>
                  <td className="px-4 py-2 text-right">{echo.trust_score}</td>
                  <td className="px-4 py-2 text-right">{echo.confidence_score.toFixed(0)}%</td>
                  <td className="px-4 py-2 text-right text-gray-400">
                    {echo.last_engine_run_at
                      ? new Date(echo.last_engine_run_at).toLocaleTimeString()
                      : "never"}
                  </td>
                </tr>
              ))}
              {pendingEchoes.length === 0 && (
                <tr>
                  <td colSpan={4} className="px-4 py-6 text-center text-gray-400">
                    No pending echoes
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
