# echoproof — architecture

## overview

echoproof is a trust-layer social platform. users post opinions (echoes),
the community validates them, and a weighted scoring engine determines
whether each echo is verified, disputed, or controversial.

## system diagram
flutter app (ios + android)
│
├── supabase auth        login, signup, google oauth, session management
├── supabase db (pg)     all data — echoes, users, interactions, reports
├── supabase storage     proof files, user avatars (dicebear generated)
├── supabase realtime    live score updates on echo detail screen
└── supabase edge functions
├── on-interaction      called when user supports/challenges an echo
├── on-report           called when user reports an echo
├── on-echo-created     runs ai spam check via hugging face
├── on-persona-webhook  receives identity verification result from persona
└── trust-engine        periodic maintenance — runs every hour via pg_cron
third-party services
├── persona.com          identity verification (gov id + liveness)
├── hugging face         ai spam detection (free inference api)
└── dicebear.com         avatar generation (called once per user, cached in storage)

## trust scoring

every echo has four computed scores, all calculated in sql by recalculate_echo_scores():

| score | formula | meaning |
|-------|---------|---------|
| trust_score | support_weight - challenge_weight | net community approval |
| confidence_score | support_weight / total_weight * 100 | % of weighted support |
| controversy_score | min(s,c) / max(s,c) * 100 | how split the community is |
| report_score | sum of reporter weights | community flagging intensity |

## echo status transitions
created → pending_verification
↓
trust_score >= 10 → active
↓
trust_score >= 50 AND confidence >= 70% → verified
↓ (if challenged)
controversy >= 60% AND interactions >= 10 → controversial
↓ (if reported)
report_score >= 20 → under_review
report_score >= 70 → hidden

## identity verification

persona handles all real id verification.
the flow: flutter opens persona webview → user submits gov id + selfie →
persona runs liveness + deepfake detection → persona calls our webhook →
webhook updates users_private.is_identity_verified = true →
trust tier recalculated → user's votes carry more weight.

the user's real identity is never exposed publicly.
only their trust tier (unverified/low/medium/high/elite) is visible.

## data privacy model

| data | stored in | accessible by |
|------|----------|--------------|
| real name, gov id hash | users_private (rls locked) | service role only |
| email | users_private (rls locked) | service role only |
| username, trust tier | users_public | all authenticated users |
| echo content | echoes | all authenticated users |
| verification status | users_public.is_identity_verified | all authenticated users |