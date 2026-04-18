import { createClient } from "@/lib/supabase/server";
import { Sidebar } from "@/components/layout/sidebar";
import { Topbar } from "@/components/layout/topbar";
import { UserTable } from "@/components/users/user-table";
import type { PublicUser } from "@/types/user";

export default async function UsersPage() {
  const supabase = await createClient();

  const { data: users } = await supabase
    .from("users_public")
    .select("id, username, avatar_url, trust_tier, trust_score, echo_count, proof_count, is_suspended, is_shadow_banned, wallet_address, created_at")
    .order("trust_score", { ascending: false })
    .limit(100);

  return (
    <div className="flex min-h-screen">
      <Sidebar />
      <main className="flex-1 flex flex-col">
        <Topbar title="User management" subtitle="Trust scores, suspensions, identity" />
        <div className="p-6">
          <UserTable users={(users as PublicUser[]) ?? []} />
        </div>
      </main>
    </div>
  );
}