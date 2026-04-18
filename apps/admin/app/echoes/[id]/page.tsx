import { createClient } from "@/lib/supabase/server";
import { Sidebar } from "@/components/layout/sidebar";
import { Topbar } from "@/components/layout/topbar";
import { notFound } from "next/navigation";

export default async function EchoDetailPage({
  params,
}: {
  params: { id: string };
}) {
  const supabase = await createClient();

  const { data: echo } = await supabase
    .from("echoes")
    .select(`
      id, title, content, category, status,
      trust_score, confidence_score, controversy_score, report_score,
      support_count, challenge_count, bond_count, response_count,
      admin_verified, admin_note, verified_record_tx, ai_metadata, created_at,
      users_public!inner(username, trust_tier, avatar_url)
    `)
    .eq("id", params.id)
    .single();

  if (!echo) notFound();

  const { data: reports } = await supabase
    .from("echo_reports")
    .select("id, reason, description, reporter_weight, resolved, created_at")
    .eq("echo_id", params.id)
    .order("reporter_weight", { ascending: false });

  const { data: proofs } = await supabase
    .from("echo_proofs")
    .select("id, proof_type, proof_url, description, created_at, users_public(username)")
    .eq("echo_id", params.id)
    .order("created_at");

  const { data: responses } = await supabase
    .from("signal_responses")
    .select("id, content, stance, author_weight, created_at, users_public(username, trust_tier)")
    .eq("echo_id", params.id)
    .order("created_at", { ascending: false })
    .limit(20);

  const { data: bonds } = await supabase
    .from("truth_bonds")
    .select("id, bond_status, created_at, users_public(username)")
    .eq("echo_id", params.id)
    .order("created_at", { ascending: false });

  return (
    <div className="flex min-h-screen">
      <Sidebar />
      <main className="flex-1 flex flex-col">
        <Topbar
          title={echo.title || "Untitled echo"}
          subtitle={`${echo.category} · ${echo.status.replace("_", " ")}`}
        />
        <div className="p-6 space-y-6 max-w-4xl">
          <div className="grid grid-cols-3 gap-4">
            <StatCard label="Trust score"    value={echo.trust_score} />
            <StatCard label="Report score"   value={echo.report_score} danger={echo.report_score >= 40} />
            <StatCard label="Confidence"     value={`${echo.confidence_score.toFixed(0)}%`} />
            <StatCard label="Support"        value={echo.support_count} />
            <StatCard label="Challenge"      value={echo.challenge_count} />
            <StatCard label="Bonds"          value={echo.bond_count} />
          </div>

          <div className="bg-white rounded-xl border border-border-subtle p-5">
            <p className="text-xs font-medium text-gray-400 mb-2">Content</p>
            <p className="text-sm text-charcoal leading-relaxed">{echo.content}</p>
          </div>

          {echo.ai_metadata && (
            <div className="bg-white rounded-xl border border-border-subtle p-5">
              <p className="text-xs font-medium text-gray-400 mb-3">AI analysis</p>
              <div className="grid grid-cols-3 gap-3 text-xs">
                <div><p className="text-gray-400">Spam score</p><p className="font-semibold">{echo.ai_metadata.spam_score ?? "—"}</p></div>
                <div><p className="text-gray-400">Clarity</p><p className="font-semibold">{echo.ai_metadata.clarity_score ?? "—"}</p></div>
                <div><p className="text-gray-400">Provider</p><p className="font-semibold truncate">{echo.ai_metadata.provider ?? "none"}</p></div>
              </div>
              {echo.ai_metadata.summary && (
                <p className="text-xs text-gray-500 mt-2 italic">{echo.ai_metadata.summary}</p>
              )}
            </div>
          )}

          {echo.verified_record_tx && (
            <div className="bg-fern-light rounded-xl border border-fern-green/20 p-4">
              <p className="text-xs font-semibold text-fern-dark mb-1">On-chain record</p>
              <p className="text-xs font-mono text-fern-dark break-all">{echo.verified_record_tx}</p>
              
                href={`https://explorer.solana.com/tx/${echo.verified_record_tx}?cluster=devnet`}
                target="_blank"
                rel="noopener noreferrer"
                className="text-xs text-fern-dark underline mt-1 inline-block"
              >
                View on explorer
              </a>
            </div>
          )}

          {(reports ?? []).length > 0 && (
            <div className="bg-white rounded-xl border border-border-subtle overflow-hidden">
              <p className="px-4 py-3 text-xs font-medium text-charcoal border-b border-border-subtle">
                Reports ({reports?.length})
              </p>
              {reports?.map(r => (
                <div key={r.id} className="px-4 py-3 border-b border-border-subtle last:border-0">
                  <div className="flex items-center gap-2">
                    <span className="text-xs font-semibold text-coral-dark capitalize">
                      {r.reason.replace("_", " ")}
                    </span>
                    <span className="text-xs text-gray-400">weight: {r.reporter_weight}</span>
                    {r.resolved && <span className="text-xs text-fern-dark">resolved</span>}
                  </div>
                  {r.description && <p className="text-xs text-gray-500 mt-0.5">{r.description}</p>}
                </div>
              ))}
            </div>
          )}

          {(proofs ?? []).length > 0 && (
            <div className="bg-white rounded-xl border border-border-subtle overflow-hidden">
              <p className="px-4 py-3 text-xs font-medium text-charcoal border-b border-border-subtle">
                Proofs ({proofs?.length})
              </p>
              {proofs?.map(p => (
                <div key={p.id} className="px-4 py-3 border-b border-border-subtle last:border-0">
                  <div className="flex items-center gap-2">
                    <span className="text-xs font-medium text-charcoal capitalize">{p.proof_type}</span>
                    {p.description && <span className="text-xs text-gray-500">{p.description}</span>}
                  </div>
                  <a href={p.proof_url} target="_blank" rel="noopener noreferrer"
                    className="text-xs text-gray-400 underline truncate block max-w-xs">
                    {p.proof_url}
                  </a>
                </div>
              ))}
            </div>
          )}

          {(bonds ?? []).length > 0 && (
            <div className="bg-white rounded-xl border border-border-subtle overflow-hidden">
              <p className="px-4 py-3 text-xs font-medium text-charcoal border-b border-border-subtle">
                Truth bonds ({bonds?.length})
              </p>
              {bonds?.map(b => (
                <div key={b.id} className="px-4 py-3 border-b border-border-subtle last:border-0 flex items-center justify-between">
                  <span className="text-xs text-charcoal">
                    @{(b.users_public as { username: string })?.username}
                  </span>
                  <span className={`text-xs font-semibold ${
                    b.bond_status === 'settled'   ? 'text-fern-dark' :
                    b.bond_status === 'contested' ? 'text-coral-dark' : 'text-gray-400'
                  }`}>
                    {b.bond_status}
                  </span>
                </div>
              ))}
            </div>
          )}
        </div>
      </main>
    </div>
  );
}

function StatCard({ label, value, danger = false }: {
  label: string;
  value: string | number;
  danger?: boolean;
}) {
  return (
    <div className="bg-white rounded-xl border border-border-subtle p-4">
      <p className="text-xs text-gray-400">{label}</p>
      <p className={`text-xl font-semibold mt-0.5 ${danger ? "text-coral-dark" : "text-charcoal"}`}>
        {value}
      </p>
    </div>
  );
}