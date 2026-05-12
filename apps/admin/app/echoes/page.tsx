import { createClient } from "@/lib/supabase/server";
import { Sidebar } from "@/components/layout/sidebar";
import { Topbar } from "@/components/layout/topbar";
import { EchoTable } from "@/components/echoes/echo-table";
import type { Echo } from "@/types/echo";

export const dynamic = "force-dynamic";

export default async function EchoesPage() {
  const supabase = await createClient();

  const { data: echoes } = await supabase
    .from("echoes")
    .select(`
      id, title, content, category, status,
      trust_score, confidence_score, report_score,
      support_count, challenge_count, admin_verified, admin_note,
      verified_record_tx, ai_metadata, created_at,
      users_public!inner(username, trust_tier)
    `)
    .order("report_score", { ascending: false })
    .limit(100);

  const normalizedEchoes = (echoes ?? []).map((echo: any) => ({
    ...echo,
    users_public: Array.isArray(echo.users_public)
      ? echo.users_public[0]
      : echo.users_public,
  })) as unknown as Echo[];

  return (
    <div className="flex min-h-screen">
      <Sidebar />
      <main className="flex-1 min-w-0 flex flex-col">
        <Topbar title="Echo moderation" subtitle="Review, verify, or remove echoes" />
        <div className="p-4 pb-24 sm:p-6 sm:pb-24 md:pb-6">
          <EchoTable echoes={normalizedEchoes} />
        </div>
      </main>
    </div>
  );
}
