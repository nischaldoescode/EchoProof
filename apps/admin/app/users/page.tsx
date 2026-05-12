import { createServer } from "@/lib/supabase/server";
import { Sidebar } from "@/components/layout/sidebar";
import { Topbar } from "@/components/layout/topbar";
import { UserTable } from "@/components/users/user-table";
import type { PublicUser } from "@/types/user";

export const dynamic = "force-dynamic";

export default async function UsersPage() {
  const supabase = await createServer();

  const { data: users } = await supabase
    .from("users_public")
    .select(
      "id, username, display_name, avatar_url, trust_tier, trust_score, echo_count, " +
        "proof_count, is_suspended, is_shadow_banned, wallet_address, created_at, " +
        "is_pro, pro_plan, pro_expires_at, age, gender, follower_count, following_count",
    )
    .order("trust_score", { ascending: false })
    .limit(200);

  return (
    <div className="flex min-h-screen">
      <Sidebar />
      <main className="flex-1 min-w-0 flex flex-col">
        <Topbar
          title="User management"
          subtitle="Trust scores, suspensions, identity"
        />
        <div className="p-4 pb-24 sm:p-6 sm:pb-24 md:pb-6">
          <UserTable users={(users as unknown as PublicUser[]) ?? []} />
        </div>
      </main>
    </div>
  );
}
