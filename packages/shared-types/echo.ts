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
  bond_count: number;
  admin_verified: boolean | null;
  admin_note: string | null;
  verified_record_tx: string | null;
  verified_record_at: string | null;
  ai_metadata: AiMetadata | null;
  created_at: string;
  updated_at: string;
}

export interface AiMetadata {
  spam_score: number;
  clarity_score: number;
  has_verifiable_claim: boolean;
  suggested_category: EchoCategory;
  summary: string;
  provider: string;
  analyzed_at: string;
}