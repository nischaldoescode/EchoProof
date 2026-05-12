<div align="center">

<img src="apps/mobile/assets/images/logo.png" alt="Echoproof" width="96" height="96" style="border-radius: 22px;" />

# Echoproof

**Truth, verified by community.**

A trust-layer social platform where community members support or challenge claims.
High-signal echoes get verified on-chain. Built with Flutter + Supabase.

[![Android](https://img.shields.io/badge/Android-coming--soon-3DDC84?style=flat-square&logo=android&logoColor=white)]()
[![Flutter](https://img.shields.io/badge/Flutter-3.x-02569B?style=flat-square&logo=flutter&logoColor=white)](https://flutter.dev)
[![Supabase](https://img.shields.io/badge/Supabase-backend-3ECF8E?style=flat-square&logo=supabase&logoColor=white)](https://supabase.com)
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

Echoproof uses a six-layer blended ranking pipeline designed to balance quality,
fairness, and discovery.

### Layers (in order)

1. **Candidate Pull** — All eligible echoes from the last 30 days
2. **Base Score** — Tier-agnostic quality signal (40% trust + 30% affinity + 20% recency + 10% confidence)
3. **Engagement Decay** — Posts older than 24h decay to prevent stale viral content dominating
4. **Tier Soft Boost** — Pro/Verified authors get max 1.25x multiplier (not a head start, better shoes)
5. **Creator Diversity** — Second post from same creator gets 30% penalty; third+ gets 60%
6. **Exploration Injection** — 10% of each page is random, enabling discovery of new creators

### Fairness Constraints

- Free user posts are never excluded by design
- Pro posts capped at 40% of any given page
- A free user with better content always beats a Pro user with worse content

### Trust Tiers and Voting Weight

| Tier       | Vote Weight | Feed Boost |
|------------|-------------|------------|
| Unverified | 1x          | None       |
| Low        | 2x          | None       |
| Medium     | 3x          | 1.05x      |
| High       | 4x          | 1.10x      |
| Elite      | 5x          | 1.10x      |
| Pro        | —           | +1.15x     |
| Pro+High   | —           | +1.25x     |

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