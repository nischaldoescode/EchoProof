# solana integration

echoproof uses solana for four on-chain features.
the user never sees the word solana — all ui uses echoproof vocabulary.

## architecture

flutter app does not hold a funded keypair.
all transactions that require SOL fees are signed by a server keypair
stored in the supabase edge function environment.

this is intentional: mobile wallet private keys get compromised.
the server keypair is a hot wallet with a small SOL balance for fees.
for production, this should use a hardware security module (HSM).

## network

development: devnet (free, get test sol from faucet.solana.com)
production: mainnet-beta

configured via: SOLANA_RPC_URL environment variable

## feature 1 — proof staking

user attaches proof to an echo and optionally stakes 0.001 SOL.
stake is transferred to a program-derived escrow address.
if echo verified: stake returned + small reward.
if echo rejected: stake forfeited.

ui label: "stake to verify"
db column: echo_proofs.stake_tx (transaction signature)

## feature 2 — reputation anchoring

when user reaches high or elite trust tier, their tier is written
to solana as a memo transaction.
readable by any platform — portable reputation.

ui label: "reputation anchored" / "portable reputation"
db column: users_public.trust_anchor_tx

## feature 3 — verified echo record

when echo reaches verified status, content hash is written to solana.
immutable — cannot be altered or deleted by anyone including echoproof.

ui label: "permanent record created"
db column: echoes.verified_record_tx

## feature 4 — truth bonds

user bonds on a verified echo.
bond is recorded on-chain and settles after 30 days if echo stays verified.
settled bonds give +2 trust score.
contested bonds (echo downgraded) are a permanent public record.

ui label: "bond this truth" / "settled" / "contested"
db table: truth_bonds

## no api token needed

solana devnet rpc is public and free.
for high-traffic mainnet use, get an rpc endpoint from:
- helius.dev (free tier: 10M credits/month)
- alchemy.com (free tier available)
- quicknode.com (free tier available)

add the rpc url to .env as SOLANA_RPC_URL.
do not add the server keypair to .env.example — treat it like a database password.
add SOLANA_SERVER_KEYPAIR to .gitignore explicitly.