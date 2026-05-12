import { createServer } from "@/lib/supabase/server";
import { Sidebar } from "@/components/layout/sidebar";
import { Topbar } from "@/components/layout/topbar";
import { DashboardStats } from "@/components/dashboard/stats-card";
import { ActivityChart } from "@/components/dashboard/activity-chart";

export const dynamic = "force-dynamic";

export default async function DashboardPage() {
  const supabase = await createServer();

  const [
    { count: totalUsers },
    { count: verifiedUsers },
    { count: totalEchoes },
    { count: flaggedEchoes },
    { count: verifiedEchoes },
    { count: pendingDeletions },
    { count: proUsers },
    { data: recentEchoes },
  ] = await Promise.all([
    supabase.from("users_public").select("*", { count: "exact", head: true }),
    supabase
      .from("users_public")
      .select("*", { count: "exact", head: true })
      .in("trust_tier", ["high", "elite", "medium"]),
    supabase.from("echoes").select("*", { count: "exact", head: true }),
    supabase
      .from("echoes")
      .select("*", { count: "exact", head: true })
      .in("status", ["under_review", "hidden"]),
    supabase
      .from("echoes")
      .select("*", { count: "exact", head: true })
      .eq("status", "verified"),
    supabase
      .from("deletion_requests")
      .select("*", { count: "exact", head: true })
      .eq("status", "pending"),
    supabase
      .from("users_public")
      .select("*", { count: "exact", head: true })
      .eq("is_pro", true),
    supabase
      .from("echoes")
      .select("created_at, status")
      .order("created_at", { ascending: false })
      .limit(30),
  ]);

  return (
    <div className="flex min-h-screen">
      <Sidebar />
      <main className="flex-1 min-w-0 flex flex-col">
        <Topbar title="Dashboard" subtitle="Trust engine overview" />
        <div className="p-4 pb-24 sm:p-6 sm:pb-24 md:pb-6 space-y-6">
          <DashboardStats
            totalUsers={totalUsers ?? 0}
            verifiedUsers={verifiedUsers ?? 0}
            totalEchoes={totalEchoes ?? 0}
            flaggedEchoes={flaggedEchoes ?? 0}
            verifiedEchoes={verifiedEchoes ?? 0}
            pendingDeletions={pendingDeletions ?? 0}
            proUsers={proUsers ?? 0}
          />
          <ActivityChart echoes={recentEchoes ?? []} />
        </div>
      </main>
    </div>
  );
}
