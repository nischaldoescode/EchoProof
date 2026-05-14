import { createAdminClient } from "@/lib/supabase/admin";
import { Sidebar } from "@/components/layout/sidebar";
import { Topbar } from "@/components/layout/topbar";
import { DeletionRequestQueue } from "@/components/deletion-requests/deletion-request-queue";

export const dynamic = "force-dynamic";

export default async function DeletionRequestsPage() {
  const supabase = createAdminClient();

  const { data: requests, error } = await supabase
    .from("deletion_requests")
    .select("id, email, reason, description, status, ip, created_at")
    .order("created_at", { ascending: false })
    .limit(100);

  return (
    <div className="flex min-h-screen">
      <Sidebar />
      <main className="flex-1 min-w-0 flex flex-col">
        <Topbar
          title="Deletion requests"
          subtitle="User account deletion requests — review and process"
        />
        <div className="p-4 pb-24 sm:p-6 sm:pb-24 md:pb-6">
          {error && (
            <div className="mb-4 rounded-xl border border-coral-dark/20 bg-coral-light p-4 text-sm text-coral-dark">
              {error.message}
            </div>
          )}
          <DeletionRequestQueue requests={requests ?? []} />
        </div>
      </main>
    </div>
  );
}
