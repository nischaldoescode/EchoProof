import { createClient } from "@/lib/supabase/server";

export async function getUnresolvedReports() {
  const supabase = await createClient();
  const { data } = await supabase
    .from("echo_reports")
    .select(`
      id, reason, description, reporter_weight, resolved, created_at,
      echoes!inner(id, title, content, status),
      users_public!reporter_id(username, trust_tier)
    `)
    .eq("resolved", false)
    .order("reporter_weight", { ascending: false })
    .limit(200);
  return data ?? [];
}

export async function resolveReport(reportId: string): Promise<void> {
  const supabase = await createClient();
  await supabase.from("echo_reports").update({ resolved: true }).eq("id", reportId);
}