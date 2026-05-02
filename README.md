# Echoproof

A trust-layer social platform where community validation determines what is true.
Users post opinions and claims, the community supports or challenges them, and a
weighted scoring engine evolves each post into a verified, disputed, or
controversial record.

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
Production targets mainnet-beta.

Configure via environment variable:
SOLANA_RPC_URL=https://api.devnet.solana.com

## Architecture
Flutter app (iOS + Android)
Supabase Auth — login, Google OAuth, session management
Supabase DB — echoes, users, interactions, reports
Supabase Storage — proof files, avatars
Supabase Realtime — live score updates
Supabase Edge Functions
on-interaction — processes support and challenge votes
on-report — processes community reports
on-echo-created — AI spam detection via Hugging Face
on-echo-verified — creates Solana on-chain record
on-persona-webhook — receives identity verification result
trust-engine — periodic score maintenance
Third-party
Persona — identity verification (government ID + liveness)
Hugging Face — free AI spam detection
DiceBear — avatar generation (called once per user, cached in storage)
Solana — proof staking, reputation anchoring, verified echo records

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
> I myself Don't advise to run this app locally it will be a piss of kinda headache for a developer. So just enjoy what i am building.

Regards,
I code therefore, I am.