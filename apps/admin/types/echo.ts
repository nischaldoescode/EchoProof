// shared echo types — used by admin panel and edge functions
// flutter uses its own echo_entity.dart — keep these in sync manually

export type EchoStatus =
  | "pending_verification"
  | "active"
  | "under_review"
  | "verified"
  | "controversial"
  | "disputed"
  | "hidden"
  | "rejected";

export type EchoCategory =
  | "tech" | "finance" | "startups" | "social_issues"
  | "web3" | "ai" | "gaming" | "education" | "other";

export interface EchoRecord {
  id: string;
  user_id: string;
  title: string;
  content: string;
  category: EchoCategory;
  status: EchoStatus;
  trust_score: number;
  confidence_score: number;
  controversy_score: number;
  report_score: number;
  support_count: number;
  challenge_count: number;
  context_support_count: number;
  context_challenge_count: number;
  context_score: number;
  public_verdict: "open" | "supported" | "not_supported" | "contested";
  public_verdict_at: string | null;
  public_context_closes_at: string | null;
  public_context_min_count: number;
  public_context_decision_reason: string | null;
  admin_override_used: boolean;
  bond_count: number;
  admin_verified: boolean | null;
  admin_note: string | null;
  verified_record_tx: string | null;
  verified_record_at: string | null;
  ai_metadata: AiMetadata | null;
  created_at: string;
  updated_at: string;
}

export type Echo = EchoRecord & {
  users_public: {
    username: string;
    trust_tier: string;
    avatar_url?: string | null;
  };
  echo_reports?: Array<{
    id: string;
    reason: string;
    reporter_id: string;
    created_at: string;
  }>;
  echo_proofs?: Array<{
    id: string;
    proof_type: string;
    proof_url: string;
    description: string | null;
  }>;
};

export interface AiMetadata {
  spam_score: number;
  clarity_score: number;
  has_verifiable_claim: boolean;
  suggested_category: EchoCategory;
  summary: string;
  provider: string;
  analyzed_at: string;
}
