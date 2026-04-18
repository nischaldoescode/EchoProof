"use client";

import { useState } from "react";
import { createClient } from "@/lib/supabase/client";

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
  const [result, setResult]   = useState<string | null>(null);

  async function triggerEngineRun() {
    setRunning(true);
    setResult(null);

    try {
      const supabase   = createClient();
      const session    = await supabase.auth.getSession();
      const accessToken = session.data.session?.access_token;

      const supabaseUrl = process.env.NEXT_PUBLIC_SUPABASE_URL;
      const res = await fetch(`${supabaseUrl}/functions/v1/trust-engine`, {
        method: "POST",
        headers: {
          "Authorization": `Bearer ${accessToken}`,
          "Content-Type": "application/json",
        },
      });

      const data = await res.json();
      setResult(JSON.stringify(data.results, null, 2));
    } catch (err) {
      setResult(`error: ${err}`);
    }

    setRunning(false);
  }

  return (
    <div className="space-y-6">
      <div className="bg-white rounded-xl border border-border-subtle p-5">
        <div className="flex items-center justify-between mb-4">
          <div>
            <p className="text-sm font-semibold text-charcoal">Manual engine run</p>
            <p className="text-xs text-gray-400 mt-0.5">
              Triggers trust score recalculation for all stale echoes
            </p>
          </div>
          <button
            onClick={triggerEngineRun}
            disabled={running}
            className="px-4 py-2 bg-charcoal text-white text-xs font-semibold rounded-lg disabled:opacity-50 hover:bg-charcoal/90 transition-colors"
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

      <div className="bg-white rounded-xl border border-border-subtle overflow-hidden">
        <div className="px-4 py-3 border-b border-border-subtle">
          <p className="text-sm font-medium text-charcoal">
            Pending echoes ({pendingEchoes.length})
          </p>
        </div>
        <table className="w-full text-xs">
          <thead>
            <tr className="border-b border-border-subtle">
              <th className="text-left px-4 py-2 text-gray-400 font-medium">Echo ID</th>
              <th className="text-right px-4 py-2 text-gray-400 font-medium">Trust score</th>
              <th className="text-right px-4 py-2 text-gray-400 font-medium">Confidence</th>
              <th className="text-right px-4 py-2 text-gray-400 font-medium">Last run</th>
            </tr>
          </thead>
          <tbody className="divide-y divide-border-subtle">
            {pendingEchoes.map(echo => (
              <tr key={echo.id} className="hover:bg-soft-sand">
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
  );
}