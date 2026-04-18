# api reference

all endpoints are supabase edge functions.
base url: {SUPABASE_URL}/functions/v1

## authentication

all endpoints require: Authorization: Bearer {access_token}
the access token comes from supabase.auth.currentSession.accessToken

## endpoints

### POST /on-interaction

request body:
  echo_id: string (uuid)
  type: "support" | "challenge"

response:
  success: boolean
  echo: { trust_score, confidence_score, status, support_count, challenge_count }

errors:
  401 — unauthenticated
  403 — suspended, own echo, or non-interactable status
  429 — rate limit (50 interactions/hour)

### POST /on-report

request body:
  echo_id: string (uuid)
  reason: "spam" | "misinformation" | "harassment" | "fake_proof" | "other"
  description?: string (max 500 chars)

response:
  success: boolean
  new_status: string
  report_score: number

errors:
  401 — unauthenticated
  403 — suspended or own echo
  409 — already reported

### GET /personalized-feed

query params:
  offset: number (default 0)
  limit: number (default 20, max 50)

response:
  echoes: Echo[]
  has_more: boolean

### POST /trust-engine

no body required.
service role key only.

response:
  success: boolean
  ran_at: string
  results: { expire_zero_engagement, recalculate_stale, trust_tier_refresh }