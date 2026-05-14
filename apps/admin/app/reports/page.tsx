import { createAdminClient } from "@/lib/supabase/admin";
import { Sidebar } from "@/components/layout/sidebar";
import { Topbar } from "@/components/layout/topbar";
import { ReportQueue } from "@/components/reports/report-queue";

export const dynamic = "force-dynamic";

export default async function ReportsPage() {
  const supabase = createAdminClient();

  const { data: reports, error } = await supabase
    .from("echo_reports")
    .select(`
      id, echo_id, reporter_id, reason, description, reporter_weight, resolved, created_at,
      echoes!inner(id, title, content, status, report_score, trust_score, user_id),
      users_public!reporter_id(username, trust_tier)
    `)
    .eq("resolved", false)
    .order("created_at", { ascending: false })
    .limit(100);

  const firstRelation = <T,>(value: T | T[] | null): T | null => {
    if (Array.isArray(value)) return value[0] ?? null;
    return value ?? null;
  };

  const transformedReports = (reports ?? []).map((report: any) => ({
    ...report,
    echoes: firstRelation(report.echoes),
    users_public: firstRelation(report.users_public),
  }));

  return (
    <div className="flex min-h-screen">
      <Sidebar />
      <main className="flex-1 min-w-0 flex flex-col">
        <Topbar
          title="Report queue"
          subtitle="Grouped by echo so moderation decisions use multiple signals, not one loud report"
        />
        <div className="p-4 pb-24 sm:p-6 sm:pb-24 md:pb-6">
          {error && (
            <div className="mb-4 rounded-xl border border-coral-dark/20 bg-coral-light p-4 text-sm text-coral-dark">
              {error.message}
            </div>
          )}
          <ReportQueue reports={transformedReports} />
        </div>
      </main>
    </div>
  );
}
