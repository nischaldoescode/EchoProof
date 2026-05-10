// trust engine thresholds — keep in sync with 003_trust_engine.sql

export const TrustThresholds = {
  verified_trust:        50,
  verified_confidence:   70,
  controversy_ratio:     0.6,
  controversy_min:       10,
  under_review_reports:  20,
  hidden_reports:        70,
} as const;

export const TierWeights: Record<string, number> = {
  elite:      5,
  high:       4,
  medium:     3,
  low:        2,
  unverified: 1,
};

export type BondStatus = "active" | "settled" | "contested";