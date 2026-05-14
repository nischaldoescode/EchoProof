import { createAdminClient } from "@/lib/supabase/admin";
import { Sidebar } from "@/components/layout/sidebar";
import { Topbar } from "@/components/layout/topbar";
import { UserTable } from "@/components/users/user-table";
import type { PublicUser } from "@/types/user";

export const dynamic = "force-dynamic";

export default async function UsersPage() {
  const supabase = createAdminClient();

  const [
    { data: users, error },
    { count: totalProfiles },
    { count: completedProfiles },
    { count: partialProfiles },
  ] = await Promise.all([
    supabase
    .from("users_public")
    .select(
      "id, username, display_name, avatar_url, trust_tier, trust_score, echo_count, " +
        "proof_count, is_suspended, is_shadow_banned, wallet_address, created_at, " +
        "is_pro, pro_plan, pro_expires_at, date_of_birth, gender, follower_count, " +
        "following_count, onboarding_complete",
    )
    .eq("onboarding_complete", true)
    .not("username", "is", null)
    .order("trust_score", { ascending: false })
      .limit(200),
    supabase.from("users_public").select("id", { count: "exact", head: true }),
    supabase
      .from("users_public")
      .select("id", { count: "exact", head: true })
      .eq("onboarding_complete", true)
      .not("username", "is", null),
    supabase
      .from("users_public")
      .select("id", { count: "exact", head: true })
      .or("onboarding_complete.is.false,username.is.null"),
  ]);
  const completeUsers = ((users as unknown as PublicUser[]) ?? []).filter(
    (user) => Boolean(user.username),
  );

  return (
    <div className="flex min-h-screen">
      <Sidebar />
      <main className="flex-1 min-w-0 flex flex-col">
        <Topbar
          title="User management"
          subtitle="Completed onboarding users, trust scores, suspensions"
        />
        <div className="admin-stagger p-4 pb-24 sm:p-6 sm:pb-24 md:pb-6">
          <div className="mb-4 grid gap-3 sm:grid-cols-3">
            <SummaryCard label="All profile rows" value={totalProfiles ?? 0} />
            <SummaryCard
              label="Completed users"
              value={completedProfiles ?? completeUsers.length}
            />
            <SummaryCard
              label="Partial onboarding"
              value={partialProfiles ?? 0}
            />
          </div>
          {completeUsers.length === 0 && (
            <div className="mb-4 rounded-xl border border-border-subtle bg-white p-4 text-sm leading-6 text-gray-500 shadow-sm">
              <p className="font-medium text-charcoal">
                No completed app users are ready to manage yet.
              </p>
              <p className="mt-1">
                This table intentionally shows users who have a
                `users_public` profile, a username, and
                `onboarding_complete=true`. The admin password login is only a
                control-panel session, so it does not create an app user row by
                itself.
              </p>
            </div>
          )}
          {error && (
            <div className="mb-4 rounded-xl border border-coral-dark/20 bg-coral-light p-4 text-sm text-coral-dark">
              {error.message}
            </div>
          )}
          <UserTable users={completeUsers} />
        </div>
      </main>
    </div>
  );
}

function SummaryCard({ label, value }: { label: string; value: number }) {
  return (
    <div className="admin-soft-card rounded-xl border border-border-subtle bg-white p-4">
      <p className="text-xs text-gray-400">{label}</p>
      <p className="mt-1 text-2xl font-semibold text-charcoal">{value}</p>
    </div>
  );
}
