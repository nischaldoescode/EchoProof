# trust engine

the trust engine is the core algorithmic system of echoproof.
it runs in supabase postgres and supabase edge functions.

## components

### scoring functions

recalculate_echo_scores(p_echo_id uuid)
  called after every interaction or report event.
  recalculates trust_score, confidence_score, controversy_score, report_score.
  determines new status from score thresholds.
  updates the echoes row atomically.

update_user_trust_tier(p_user_id uuid)
  called after identity verification or significant activity.
  reads identity_score from users_private.
  computes composite score from identity + echo + proof counts.
  sets trust_tier on users_public.

expire_zero_engagement_echoes()
  called hourly by trust-engine edge function.
  marks echoes with zero interactions older than 72h as low-priority.

settle_matured_bonds()
  called hourly by trust-engine edge function.
  settles truth bonds that have passed their 30-day window.
  gives +2 trust score to users whose bonds settle.

### edge functions

on-interaction — processes a support or challenge vote.
  validates caller, checks rate limit, inserts interaction row,
  calls recalculate_echo_scores, returns updated echo.

on-report — processes a community flag.
  validates caller, inserts report row,
  calls recalculate_echo_scores.

on-echo-created — ai spam check.
  calls hugging face or openai.
  sets status to hidden if spam_score >= 75.

on-echo-verified — creates permanent on-chain record.
  triggered when status changes to verified.
  writes echo content hash to solana via memo program.

trust-engine — hourly maintenance.
  expires zero-engagement echoes.
  recalculates stale echo scores.
  refreshes user trust tiers.
  settles matured truth bonds.

personalized-feed — per-user ranked feed.
  calls get_personalized_feed sql function.
  records passive category view signals.
  returns echo list pre-ranked for the user.

## score thresholds

trust_score >= 50 AND confidence >= 70%  → verified
controversy >= 0.6 AND interactions >= 10 → controversial
trust_score < 0                           → disputed
report_score >= 20                        → under_review
report_score >= 70                        → hidden

## feed algorithm

personalized_score = 
  (trust_score * 0.40)
  + (category_affinity * 0.30)
  + (recency_score * 0.20)
  + (confidence_score * 0.10)
  + (controversy_score * 0.05)
  + (user_selected_category_bonus: 15)
  - (already_interacted_penalty: 30)

category_affinity decays over 30 days.
signals are recorded for: view (0.1), support (2.0), challenge (1.0), bond (3.0).