import { createAdminClient } from "@/lib/supabase/admin";
import type { PublicUser } from "@/types/user";

export async function getUsers(): Promise<PublicUser[]> {
  const supabase = createAdminClient();
  const { data } = await supabase
    .from("users_public")
    .select("id, username, avatar_url, trust_tier, trust_score, echo_count, proof_count, is_suspended, is_shadow_banned, wallet_address, created_at")
    .order("trust_score", { ascending: false })
    .limit(200);
  return (data as PublicUser[]) ?? [];
}

export async function suspendUser(userId: string, suspend: boolean): Promise<void> {
  const supabase = createAdminClient();
  await supabase
    .from("users_public")
    .update({ is_suspended: suspend })
    .eq("id", userId);
}
