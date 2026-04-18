import { createClient } from "@/lib/supabase/server";
import { Sidebar } from "@/components/layout/sidebar";
import { Topbar } from "@/components/layout/topbar";
import { notFound } from "next/navigation";

export default async function UserDetailPage({
  params,
}: {
  params: { id: string };
}) {
  const supabase = await createClient();

  const { data: publicProfile } = await supabase
    .from("users_public")
    .select("*")
    .eq("id", params.id)
    .single();

  if (!publicProfile) notFound();

  const { data: privateProfile } = await supabase
    .from("users_private")
    .select("email, identity_score, is_identity_verified, ip_risk_score, created_at")
    .eq("id", params.id)
    .single();

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

  const settled   = (bonds ?? []).filter(b => b.bond_status === "settled").length;
  const contested = (bonds ?? []).filter(b => b.bond_status === "contested").length;
  const active    = (bonds ?? []).filter(b => b.bond_status === "active").length;

  return (
    <div className="flex min-h-screen">
      <Sidebar />
      <main className="flex-1 flex flex-col">
        <Topbar
          title={`@${publicProfile.username}`}
          subtitle={`${publicProfile.trust_tier} · score ${publicProfile.trust_score}`}
        />
        <div className="p-6 space-y-6 max-w-3xl">
          <div className="grid grid-cols-2 gap-4">
            <div className="bg-white rounded-xl border border-border-subtle p-5 space-y-3">
              <p className="text-xs font-medium text-gray-400">Public profile</p>
              <Row label="Username"       value={`@${publicProfile.username}`} />
              <Row label="Trust tier"     value={publicProfile.trust_tier} />
              <Row label="Trust score"    value={publicProfile.trust_score} />
              <Row label="Echoes"         value={publicProfile.echo_count} />
              <Row label="Suspended"      value={publicProfile.is_suspended ? "yes" : "no"} />
              <Row label="Shadow banned"  value={publicProfile.is_shadow_banned ? "yes" : "no"} />
              {publicProfile.wallet_address && (
                <Row label="Wallet" value={`${publicProfile.wallet_address.slice(0, 8)}...`} />
              )}
            </div>

            {privateProfile && (
              <div className="bg-white rounded-xl border border-border-subtle p-5 space-y-3">
                <p className="text-xs font-medium text-gray-400">Private data</p>
                <Row label="Email"       value={privateProfile.email} />
                <Row label="ID verified" value={privateProfile.is_identity_verified ? "yes" : "no"} />
                <Row label="ID score"    value={privateProfile.identity_score} />
                <Row label="IP risk"     value={privateProfile.ip_risk_score} />
              </div>
            )}
          </div>

          <div className="bg-white rounded-xl border border-border-subtle p-5">
            <p className="text-xs font-medium text-gray-400 mb-3">Truth bonds</p>
            <div className="flex gap-4">
              <BondStat label="Settled"   value={settled}   color="text-fern-dark" />
              <BondStat label="Active"    value={active}    color="text-gray-500" />
              <BondStat label="Contested" value={contested} color="text-coral-dark" />
            </div>
          </div>

          {(echoes ?? []).length > 0 && (
            <div className="bg-white rounded-xl border border-border-subtle overflow-hidden">
              <p className="px-4 py-3 text-xs font-medium text-charcoal border-b border-border-subtle">
                Recent echoes
              </p>
              {echoes?.map(e => (
                
                  key={e.id}
                  href={`/echoes/${e.id}`}
                  className="flex items-center justify-between px-4 py-3 border-b border-border-subtle last:border-0 hover:bg-soft-sand transition-colors"
                >
                  <span className="text-xs text-charcoal truncate max-w-xs">
                    {e.title || "Untitled"}
                  </span>
                  <span className={`text-xs font-medium ${
                    e.status === "verified" ? "text-fern-dark" :
                    e.status === "hidden"   ? "text-coral-dark" : "text-gray-400"
                  }`}>
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

function Row({ label, value }: { label: string; value: string | number | boolean }) {
  return (
    <div className="flex items-center justify-between">
      <span className="text-xs text-gray-400">{label}</span>
      <span className="text-xs font-medium text-charcoal">{String(value)}</span>
    </div>
  );
}

function BondStat({ label, value, color }: { label: string; value: number; color: string }) {
  return (
    <div>
      <p className={`text-lg font-semibold ${color}`}>{value}</p>
      <p className="text-xs text-gray-400">{label}</p>
    </div>
  );
}