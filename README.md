<div align="center">

<img src="apps/mobile/assets/images/logo.png" alt="Echoproof" width="96" height="96" style="border-radius: 22px;" />

# Echoproof

**Truth, verified by community.**

A trust-layer social platform where community members support or challenge claims.
High-signal echoes get verified on-chain. Built with Flutter + Supabase.

[![Android](https://img.shields.io/badge/Get%20it%20on-Google%20Play-3DDC84?style=flat-square&logo=google-play&logoColor=white)](https://play.google.com/store/apps/details?id=com.echoproof.app)
[![Flutter](https://img.shields.io/badge/Flutter-3.x-02569B?style=flat-square&logo=flutter&logoColor=white)](https://flutter.dev)
[![Solana](https://img.shields.io/badge/Solana-on--chain-9945FF?style=flat-square&logo=solana&logoColor=white)](https://solana.com)
[![License](https://img.shields.io/badge/license-private-gray?style=flat-square)](LICENSE)

</div>


## What makes this different

Most platforms show raw engagement counts. Echoproof shows weighted credibility.
A vote from an identity-verified user with a strong track record carries more
weight than an anonymous new account. The engine calculates this automatically.

## Solana integration

Echoproof uses Solana in three places. The integration is functional on devnet
and designed for mainnet deployment.

### 1. Proof staking

When a user attaches evidence to an echo, they can optionally stake a small
amount (0.001 SOL) to signal confidence in their proof. The stake is transferred
to a program-derived escrow account on Solana. If the echo is verified by the
community, the stake is returned with a small reward. If the echo is rejected,
the stake is forfeited. This makes submitting false evidence economically costly.

In the UI this appears as "stake to verify" — the word Solana never appears to
the end user.

### 2. Reputation anchoring

When a user reaches High or Elite trust tier, their reputation score is written
to the Solana blockchain via a memo transaction. This creates a timestamped,
immutable record of their trust level that is independent of Echoproof. They
can use this record to prove their credibility on any platform that reads the
Solana ledger.

In the UI this appears as "portable reputation" and "reputation anchored."

### 3. Verified echo records

When an echo reaches Verified status (trust score >= 50, confidence >= 70%),
the system creates a permanent on-chain record via the Solana memo program.
The record contains a SHA-256 hash of the echo content, the final confidence
score, and a timestamp. This record cannot be altered or deleted by anyone,
including Echoproof.

In the UI this appears as "permanent record created" with a link to Solana
Explorer so anyone can independently verify the record exists.

### Network

Development uses Solana devnet (free, test SOL from faucet.solana.com).
Production targets same Devnet (THE MAIN REQUIRES FUNDING).

## Architecture

> Flutter app iOS Android

- Supabase Auth  
  > login  
  > Google OAuth  
  > session management  

- Supabase DB  
  > echoes  
  > users  
  > interactions  
  > reports  

- Supabase Storage  
  > proof files  
  > avatars  

- Supabase Realtime  
  > live score updates  

- Supabase Edge Functions  
  > on interaction processes support and challenge votes  
  > on report processes community reports  
  > on echo created AI spam detection  
  > on echo verified creates Solana on chain record
  > trust engine periodic score maintenance  

- Third party  
  > DIDIT identity verification government ID and liveness  
  > Sight Engine AI spam detection  
  > DiceBear avatar generation called once per user cached in storage  
  > Solana proof staking reputation anchoring verified echo records  


## Feed Ranking Algorithm

The home feed is a server-ranked, user-specific feed with a safe recency
fallback. It is implemented by the `get_personalized_feed` PostgreSQL function,
the `personalized-feed` Supabase Edge Function, and the mobile
`EchoFeedService`. The defaults are an authenticated request, 20 echoes per
page, a maximum requested page size of 50, and a 30-day candidate window.

### 1. Candidate eligibility and safety gates

Before scoring, the SQL function excludes hidden and rejected echoes, authors
blocked by either party, and echoes that the viewer marked as not interested,
reported, or blocked by author. It admits public profiles, the viewer's own
echoes, and private authors the viewer follows. Echoes with a public verdict of
`not_supported` or `insufficient_context` are excluded for other viewers but
remain visible to their author. The Edge Function repeats the feedback, block,
and verdict checks when it fetches full echo records, so a stale ranked ID cannot
silently bypass those rules.

### 2. Personal relevance signals

The ranker uses selected onboarding categories and the viewer's recent
`user_feed_signals`. Category views, support/challenge activity, category
clicks, and hashtag views are considered for seven days with exponential time
decay. It also recognises authors the viewer follows, support activity from
followed accounts during the last 14 days, and replies from followed accounts
during the same window. The Edge Function records lightweight category-view
signals from the first five returned echoes without delaying the response.

### 3. Quality and context scoring

Each eligible echo receives a blended score. The score uses bounded trust,
confidence, category affinity, the viewer's selected categories, social
proximity, engagement, proof count, and context-response activity. Logarithmic
caps prevent large interaction or proof counts from growing without limit.
Public verdicts and context evidence can raise or lower reach: supported echoes
receive a boost, while contested, needs-context, insufficient-context, and
not-supported outcomes receive progressively stronger penalties. Additional
penalties apply to active context reach caps, very new third-party echoes,
one-sided context challenges, reports, and echoes the viewer has already
interacted with.

### 4. Freshness, author diversity, and exploration

The blended score is multiplied by a recency curve: full weight for the first
three hours, then decreasing through 12 hours, one day, three days, one week,
and older content. Followed authors receive a modest multiplier. Trust and Pro
status are soft multipliers only: medium is 1.05x, high/elite is 1.10x, Pro is
1.07x, and Pro with high or elite trust is 1.16x. Creator diversity then keeps
the first echo from an author at full weight, reduces their second to 0.68x, and
their later echoes to 0.36x.

Each fresh feed session receives a random opaque seed. The ranker uses that
seed to give roughly 10% of otherwise eligible candidates a small, stable
discovery bonus. The same echo therefore keeps the same exploratory treatment
for the whole session instead of changing position because of a new random
draw on every page request. The bonus is intentionally smaller than the trust,
context, social, and recency signals, so discovery cannot dominate the feed.

### 5. Serving, cache, and recovery behaviour

The Edge Function preserves the ranked ID order while fetching full records.
It returns an opaque next cursor based on `(personalized_score, created_at,
echo_id)` and reuses the session seed for every following page. This is keyset
pagination: new echoes and score changes cannot move an already seen echo back
into a later page of the same session. It caches each user's cursor page in
Upstash Redis for 120 seconds. The cache key includes user ID, session seed,
cursor, page limit, and a feedback-version count; a pull to refresh starts a
new session and bypasses the cache. If the SQL ranker returns no usable
candidates, the function falls back to recent safe public echoes.

A ranked page can also become short after privacy, feedback, block, or verdict
filters remove candidates. In that case the Edge Function tops it up from
recent safe public echoes, scanning up to 60 rows while preserving exclusions
and removing duplicates. The mobile client independently performs the same
guard, so an older deployment, a short cached response, or a transient Edge
Function failure does not make the feed appear to contain only a few echoes.
Load-more requests exclude IDs already rendered before appending results.

### 6. Important current limits

The feed no longer uses offset pagination or per-request randomness. The client
still deduplicates IDs as a defence against legacy/cache responses and safe
recency recovery. Cache entries expire quickly, but follow changes, score
changes, and moderation changes do not yet have targeted invalidation events;
they are visible after the TTL or a forced refresh. New qualifying echoes are
reported through Realtime as a deferred `New echoes` control and are only loaded
after the reader opts in, so the list never jumps under an active scroll.

## Content Moderation Pipeline

All user-generated content goes through a three-stage pipeline:

1. **Client pre-check** (TFLite heuristics) — runs locally before submission, warns user
2. **Server moderation** (SightEngine rule-based + ML) — text checked on every echo creation
3. **Media AI detection** (SightEngine genai) — images and videos checked for AI-generated content

Content that fails moderation is hidden automatically and the user receives an in-app
and push notification explaining why.

## Identity Verification

Identity verification via Didit includes:

- Document must be at least 2 months old (server-enforced via webhook)
- Max 2 attempts per account per 30-day window
- Max 3 attempts per IP per 30-day window (prevents account farming)
- 30-day cooldown after rejection

## Security Model

The client-side security (root detection, certificate pinning) is a deterrent layer.


## Trust scoring

Every echo has four computed scores updated by the trust engine:

| Score | Formula | Meaning |
|-------|---------|---------|
| trust_score | support_weight - challenge_weight | net approval |
| confidence_score | support_weight / total * 100 | % weighted support |
| controversy_score | min(s,c) / max(s,c) * 100 | how split the community is |
| report_score | sum of reporter weights | flagging intensity |

User trust tiers and their vote weights:

| Tier | Weight | How to reach it |
|------|--------|----------------|
| Unverified | 1x | Default |
| Low | 2x | Active participation |
| Medium | 3x | Consistent contributions |
| High | 4x | Identity verified |
| Elite | 5x | Top contributors |

### 4. Truth Bonds

When an echo reaches Verified status, any user can create a Truth Bond on it.
A Truth Bond is a compressed NFT minted on Solana (Metaplex Bubblegum, costs
fractions of a cent) that publicly ties your reputation to the truthfulness
of that echo.

Bonds have a 30-day settlement window. If the echo stays verified for 30 days
with no admin intervention, the bond settles and you receive a small reputation
boost (+2 trust score). If an admin downgrades the echo after new evidence
emerges, your bond is marked Contested — a permanent public record that your
judgment was wrong on this claim.

This creates a prediction-market-like accountability layer. Users can see on
any profile how many bonds are Settled vs Contested. Settling many bonds over
time is the highest signal of credibility on the platform.

In the UI this appears as "Bond this truth" on verified echoes and
"Your bonds" on the profile screen. The word Solana never appears to users.

## NOTE
> I myself Don't advise to run this app locally on a machine by cloning the project as I have not included some internal some config files, You need to write those on your own.

Regards,
Nischal
