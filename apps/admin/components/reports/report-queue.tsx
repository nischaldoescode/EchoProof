"use client";

import { useState } from "react";
import { useRouter } from "next/navigation";
import { createClient } from "@/lib/supabase/client";

interface Report {
  id: string;
  reason: string;
  description: string | null;
  reporter_weight: number;
  resolved: boolean;
  created_at: string;
  echoes: { id: string; title: string; content: string; status: string };
  users_public: { username: string; trust_tier: string };
}

interface ReportQueueProps {
  reports: Report[];
}

export function ReportQueue({ reports }: ReportQueueProps) {
  const router = useRouter();
  const [loading, setLoading] = useState<string | null>(null);

  async function resolve(reportId: string) {
    setLoading(reportId);
    const supabase = createClient();
    await supabase.from("echo_reports").update({ resolved: true }).eq("id", reportId);
    router.refresh();
    setLoading(null);
  }

  if (reports.length === 0) {
    return (
      <div className="bg-white rounded-xl border border-border-subtle p-8 text-center">
        <p className="text-gray-400 text-sm">No unresolved reports</p>
      </div>
    );
  }

  return (
    <div className="space-y-3">
      {reports.map(report => (
        <div key={report.id} className="bg-white rounded-xl border border-border-subtle p-4">
          <div className="flex items-start justify-between gap-4">
            <div className="flex-1 min-w-0">
              <div className="flex items-center gap-2 mb-1">
                <span className="text-xs font-semibold text-coral-dark uppercase tracking-wide">
                  {report.reason.replace("_", " ")}
                </span>
                <span className="text-xs text-gray-400">
                  weight: {report.reporter_weight}
                </span>
                <span className="text-xs text-gray-400">
                  by @{report.users_public.username}
                </span>
              </div>

              <p className="text-xs text-charcoal line-clamp-2 mb-1">
                Echo: {report.echoes.title || report.echoes.content.slice(0, 80)}
              </p>

              {report.description && (
                <p className="text-xs text-gray-500 italic">{report.description}</p>
              )}
            </div>

            <button
              onClick={() => resolve(report.id)}
              disabled={loading === report.id}
              className="flex-shrink-0 text-xs px-3 py-1.5 bg-soft-sand text-gray-600 rounded-lg hover:bg-gray-200 transition-colors disabled:opacity-50"
            >
              Resolve
            </button>
          </div>
        </div>
      ))}
    </div>
  );
}