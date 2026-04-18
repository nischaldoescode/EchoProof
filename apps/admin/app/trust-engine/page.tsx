import { createClient } from "@/lib/supabase/server";
import { Sidebar } from "@/components/layout/sidebar";
import { Topbar } from "@/components/layout/topbar";
import { TrustEnginePanel } from "@/components/trust-engine/trust-engine-panel";

export default async function TrustEnginePage() {
  const supabase = await createClient();

  const { data: pendingEchoes } = await supabase
    .from("echoes")
    .select("id, status, trust_score, confidence_score, last_engine_run_at")
    .eq("status", "pending_verification")
    .order("created_at", { ascending: false })
    .limit(20);

  return (
    <div className="flex min-h-screen">
      <Sidebar />
      <main className="flex-1 flex flex-col">
        <Topbar title="Trust engine" subtitle="Trigger runs and monitor scoring" />
        <div className="p-6">
          <TrustEnginePanel pendingEchoes={pendingEchoes ?? []} />
        </div>
      </main>
    </div>
  );
}