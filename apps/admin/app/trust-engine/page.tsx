// admin trust engine page
// @params none

import { createAdminClient } from "@/lib/supabase/admin";
import { Sidebar } from "@/components/layout/sidebar";
import { Topbar } from "@/components/layout/topbar";
import { TrustEnginePanel } from "@/components/trust-engine/trust-engine-panel";

export const dynamic = "force-dynamic";

export default async function TrustEnginePage() {
  const supabase = createAdminClient();

  const { data: pendingEchoes, error } = await supabase
    .from("echoes")
    .select("id, status, trust_score, confidence_score, last_engine_run_at")
    .eq("status", "pending_verification")
    .order("created_at", { ascending: false })
    .limit(20);

  return (
    <div className="flex min-h-screen">
      <Sidebar />
      <main className="flex-1 min-w-0 flex flex-col">
        <Topbar title="Trust engine" subtitle="Trigger runs and monitor scoring" />
        <div className="admin-stagger p-4 pb-24 sm:p-6 sm:pb-24 md:pb-6 space-y-6">
          <div className="admin-soft-card rounded-xl border border-border-subtle bg-white p-5">
            <p className="text-sm font-semibold text-charcoal">
              What this page is for
            </p>
            <div className="mt-4 grid gap-3 md:grid-cols-3">
              <TrustNote
                title="Re-score echoes"
                body="Runs the backend trust engine for stale pending echoes and refreshes trust/confidence values."
              />
              <TrustNote
                title="Watch the queue"
                body="Shows pending verification items so admins can see whether scoring is moving or stuck."
              />
              <TrustNote
                title="Keep tiers aligned"
                body="The engine path also supports keeping user trust tiers aligned with the latest echo activity."
              />
            </div>
          </div>
          {error && (
            <div className="rounded-xl border border-coral-dark/20 bg-coral-light p-4 text-sm text-coral-dark">
              {error.message}
            </div>
          )}
          <TrustEnginePanel pendingEchoes={pendingEchoes ?? []} />
        </div>
      </main>
    </div>
  );
}

function TrustNote({ title, body }: { title: string; body: string }) {
  return (
    <div className="rounded-lg border border-border-subtle bg-soft-sand/40 p-4">
      <p className="text-xs font-semibold text-charcoal">{title}</p>
      <p className="mt-2 text-xs leading-5 text-gray-500">{body}</p>
    </div>
  );
}
