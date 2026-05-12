import { createServer } from "@/lib/supabase/server";
import { Sidebar } from "@/components/layout/sidebar";
import { Topbar } from "@/components/layout/topbar";
import { notFound } from "next/navigation";

export const dynamic = "force-dynamic";

interface AdminPublicProfile {
  id: string;
  username: string;
  display_name: string | null;
  avatar_url: string | null;
  trust_tier: string;
  trust_score: number;
  echo_count: number;
  proof_count: number;
  is_suspended: boolean;
  is_shadow_banned: boolean;
  wallet_address: string | null;
  bio: string | null;
  is_pro: boolean;
  pro_plan: string | null;
  pro_expires_at: string | null;
  age: number | null;
  gender: string | null;
  date_of_birth: string | null;
  follower_count: number | null;
  following_count: number | null;
  is_public: boolean;
  categories: string[] | null;
  created_at: string;
}

interface AdminPrivateProfile {
  email: string | null;
  identity_score: number | null;
  is_identity_verified: boolean;
  ip_risk_score: number | null;
  created_at: string;
  verification_rejection_at: string | null;
  verification_attempt_count: number | null;
  last_verification_request_at: string | null;
}

export default async function UserDetailPage({
  params,
}: {
  params: { id: string };
}) {
  const supabase = await createServer();

  const { data: publicProfileData } = await supabase
    .from("users_public")
    .select(
      "id, username, display_name, avatar_url, trust_tier, trust_score, echo_count, " +
        "proof_count, is_suspended, is_shadow_banned, wallet_address, bio, is_pro, " +
        "pro_plan, pro_expires_at, age, gender, date_of_birth, follower_count, following_count, " +
        "is_public, categories, created_at",
    )
    .eq("id", params.id)
    .single();

  const publicProfile =
    publicProfileData as unknown as AdminPublicProfile | null;

  if (!publicProfile) notFound();

  const { data: privateProfileData } = await supabase
    .from("users_private")
    .select(
      "email, identity_score, is_identity_verified, ip_risk_score, created_at, " +
        "verification_rejection_at, verification_attempt_count, last_verification_request_at",
    )
    .eq("id", params.id)
    .single();

  const privateProfile =
    privateProfileData as unknown as AdminPrivateProfile | null;

  const { data: echoes } = await supabase
    .from("echoes")
    .select("id, title, status, trust_score, created_at")
    .eq("user_id", params.id)
    .order("created_at", { ascending: false })
    .limit(10);

  const { data: bonds } = await supabase
    .from("truth_bonds")
    .select("id, bond_status, created_at")
    .eq("user_id", params.id);

  const settled = (bonds ?? []).filter(
    (b) => b.bond_status === "settled",
  ).length;
  const contested = (bonds ?? []).filter(
    (b) => b.bond_status === "contested",
  ).length;
  const active = (bonds ?? []).filter((b) => b.bond_status === "active").length;

  return (
    <div className="flex min-h-screen">
      <Sidebar />
      <main className="flex-1 min-w-0 flex flex-col">
        <Topbar
          title={`@${publicProfile.username}`}
          subtitle={`${publicProfile.trust_tier} · score ${publicProfile.trust_score}`}
        />
        <div className="p-4 pb-24 sm:p-6 sm:pb-24 md:pb-6 space-y-6 max-w-3xl">
          <div className="grid gap-4 md:grid-cols-2">
            <div className="bg-white rounded-xl border border-border-subtle p-5 space-y-3">
              <p className="text-xs font-medium text-gray-400">
                Public profile
              </p>
              <Row label="Username" value={`@${publicProfile.username}`} />
              {publicProfile.display_name && (
                <Row label="Display name" value={publicProfile.display_name} />
              )}
              <Row label="Trust tier" value={publicProfile.trust_tier} />
              <Row label="Trust score" value={publicProfile.trust_score} />
              <Row label="Echoes" value={publicProfile.echo_count} />
              <Row
                label="Followers"
                value={publicProfile.follower_count ?? 0}
              />
              <Row
                label="Following"
                value={publicProfile.following_count ?? 0}
              />
              <Row
                label="Pro"
                value={
                  publicProfile.is_pro
                    ? `Yes — ${publicProfile.pro_plan ?? ""}`
                    : "No"
                }
              />
              {publicProfile.pro_expires_at && (
                <Row
                  label="Pro expires"
                  value={new Date(
                    publicProfile.pro_expires_at,
                  ).toLocaleDateString()}
                />
              )}
              <Row
                label="Age"
                value={
                  publicProfile.age != null ? `${publicProfile.age} yrs` : "—"
                }
              />
              <Row
                label="Gender"
                value={publicProfile.gender?.replace("_", " ") ?? "—"}
              />
              {publicProfile.date_of_birth && (
                <Row
                  label="Date of birth"
                  value={publicProfile.date_of_birth}
                />
              )}
              <Row
                label="Suspended"
                value={publicProfile.is_suspended ? "yes" : "no"}
              />
              <Row
                label="Shadow banned"
                value={publicProfile.is_shadow_banned ? "yes" : "no"}
              />
              {publicProfile.wallet_address && (
                <Row
                  label="Wallet"
                  value={`${publicProfile.wallet_address.slice(0, 8)}...`}
                />
              )}
              {publicProfile.bio && (
                <Row label="Bio" value={publicProfile.bio} />
              )}
            </div>

            {privateProfile && (
              <div className="bg-white rounded-xl border border-border-subtle p-5 space-y-3">
                <p className="text-xs font-medium text-gray-400">
                  Private data
                </p>
                <Row label="Email" value={privateProfile.email ?? "—"} />
                <Row
                  label="ID verified"
                  value={privateProfile.is_identity_verified ? "yes ✓" : "no"}
                />
                <Row label="ID score" value={privateProfile.identity_score} />
                <Row label="IP risk" value={privateProfile.ip_risk_score} />
                <Row
                  label="Verify attempts"
                  value={privateProfile.verification_attempt_count ?? 0}
                />
                {privateProfile.verification_rejection_at && (
                  <Row
                    label="Last rejected"
                    value={new Date(
                      privateProfile.verification_rejection_at,
                    ).toLocaleDateString()}
                  />
                )}
                {privateProfile.last_verification_request_at && (
                  <Row
                    label="Last verify request"
                    value={new Date(
                      privateProfile.last_verification_request_at,
                    ).toLocaleDateString()}
                  />
                )}
              </div>
            )}
          </div>

          <div className="bg-white rounded-xl border border-border-subtle p-5">
            <p className="text-xs font-medium text-gray-400 mb-3">
              Truth bonds
            </p>
            <div className="flex gap-4">
              <BondStat
                label="Settled"
                value={settled}
                color="text-fern-dark"
              />
              <BondStat label="Active" value={active} color="text-gray-500" />
              <BondStat
                label="Contested"
                value={contested}
                color="text-coral-dark"
              />
            </div>
          </div>

          {(echoes ?? []).length > 0 && (
            <div className="bg-white rounded-xl border border-border-subtle overflow-hidden">
              <p className="px-4 py-3 text-xs font-medium text-charcoal border-b border-border-subtle">
                Recent echoes
              </p>
              {echoes?.map((e) => (
                <a
                  key={e.id}
                  href={`/echoes/${e.id}`}
                  className="flex items-center justify-between px-4 py-3 border-b border-border-subtle last:border-0 hover:bg-soft-sand transition-colors"
                >
                  <span className="text-xs text-charcoal truncate max-w-xs">
                    {e.title || "Untitled"}
                  </span>
                  <span
                    className={`text-xs font-medium ${
                      e.status === "verified"
                        ? "text-fern-dark"
                        : e.status === "hidden"
                          ? "text-coral-dark"
                          : "text-gray-400"
                    }`}
                  >
                    {e.status.replace("_", " ")}
                  </span>
                </a>
              ))}
            </div>
          )}
        </div>
      </main>
    </div>
  );
}

function Row({
  label,
  value,
}: {
  label: string;
  value: string | number | boolean | null | undefined;
}) {
  return (
    <div className="flex items-center justify-between">
      <span className="text-xs text-gray-400">{label}</span>
      <span className="text-xs font-medium text-charcoal">
        {value == null ? "—" : String(value)}
      </span>
    </div>
  );
}

function BondStat({
  label,
  value,
  color,
}: {
  label: string;
  value: number;
  color: string;
}) {
  return (
    <div>
      <p className={`text-lg font-semibold ${color}`}>{value}</p>
      <p className="text-xs text-gray-400">{label}</p>
    </div>
  );
}
