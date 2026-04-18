import { createClient } from "@/lib/supabase/server";
import { Sidebar } from "@/components/layout/sidebar";
import { Topbar } from "@/components/layout/topbar";
import { DashboardStats } from "@/components/dashboard/stats-card";
import { ActivityChart } from "@/components/dashboard/activity-chart";

export default async function DashboardPage() {
  const supabase = await createClient();

  const [
    { count: totalUsers },
    { count: verifiedUsers },
    { count: totalEchoes },
    { count: flaggedEchoes },
    { count: verifiedEchoes },
    { data: recentEchoes },
  ] = await Promise.all([
    supabase.from("users_public").select("*", { count: "exact", head: true }),
    supabase.from("users_public").select("*", { count: "exact", head: true })
      .eq("trust_tier", "high").or("trust_tier.eq.elite,trust_tier.eq.medium"),
    supabase.from("echoes").select("*", { count: "exact", head: true }),
    supabase.from("echoes").select("*", { count: "exact", head: true })
      .in("status", ["under_review", "hidden"]),
    supabase.from("echoes").select("*", { count: "exact", head: true })
      .eq("status", "verified"),
    supabase.from("echoes")
      .select("created_at, status")
      .order("created_at", { ascending: false })
      .limit(30),
  ]);

  return (
    <div className="flex min-h-screen">
      <Sidebar />
      <main className="flex-1 flex flex-col">
        <Topbar title="Dashboard" subtitle="Trust engine overview" />
        <div className="p-6 space-y-6">
          <DashboardStats
            totalUsers={totalUsers ?? 0}
            verifiedUsers={verifiedUsers ?? 0}
            totalEchoes={totalEchoes ?? 0}
            flaggedEchoes={flaggedEchoes ?? 0}
            verifiedEchoes={verifiedEchoes ?? 0}
          />
          <ActivityChart echoes={recentEchoes ?? []} />
        </div>
      </main>
    </div>
  );
}