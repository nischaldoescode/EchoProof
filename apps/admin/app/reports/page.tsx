import { createClient } from "@/lib/supabase/server";
import { Sidebar } from "@/components/layout/sidebar";
import { Topbar } from "@/components/layout/topbar";
import { ReportQueue } from "@/components/reports/report-queue";

export default async function ReportsPage() {
  const supabase = await createClient();

  const { data: reports } = await supabase
    .from("echo_reports")
    .select(`
      id, reason, description, reporter_weight, resolved, created_at,
      echoes!inner(id, title, content, status),
      users_public!reporter_id(username, trust_tier)
    `)
    .eq("resolved", false)
    .order("reporter_weight", { ascending: false })
    .limit(100);

  const transformedReports = reports?.map(report => ({
    ...report,
    echoes: report.echoes[0],
    users_public: report.users_public[0],
  }));

  return (
    <div className="flex min-h-screen">
      <Sidebar />
      <main className="flex-1 flex flex-col">
        <Topbar title="Report queue" subtitle="Unresolved community reports" />
        <div className="p-6">
          <ReportQueue reports={reports ?? []} />
        </div>
      </main>
    </div>
  );
}