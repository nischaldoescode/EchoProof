// admin echoes api
// @params none

import { createAdminClient } from "@/lib/supabase/admin";
import type { Echo } from "@/types/echo";

export async function getEchoes(status?: string): Promise<Echo[]> {
  const supabase = createAdminClient();

  let query = supabase
    .from("echoes")
    .select(`
      id, title, content, category, status,
      trust_score, confidence_score, report_score,
      support_count, challenge_count, context_support_count,
      context_challenge_count, context_score, public_verdict,
      public_verdict_at, public_context_closes_at,
      public_context_min_count, public_context_decision_reason,
      admin_override_used, bond_count,
      admin_verified, admin_note, verified_record_tx, created_at,
      users_public!inner(username, trust_tier)
    `)
    .order("report_score", { ascending: false })
    .limit(200);

  if (status && status !== "all") {
    query = query.eq("status", status);
  }

  const { data } = await query;
  return ((data ?? []).map((echo: any) => ({
    ...echo,
    ai_metadata: null,
    users_public: Array.isArray(echo.users_public)
      ? echo.users_public[0]
      : echo.users_public,
  })) as unknown as Echo[]) ?? [];
}

export async function updateEchoStatus(
  echoId: string,
  status: string,
  adminNote?: string,
  adminVerified?: boolean | null
): Promise<void> {
  const supabase = createAdminClient();
  await supabase
    .from("echoes")
    .update({
      status,
      admin_note: adminNote,
      admin_verified: adminVerified ?? null,
      admin_override_used: true,
    })
    .eq("id", echoId);
}
