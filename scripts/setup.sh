#!/usr/bin/env bash
# =============================================================
# echoproof full project setup script
# run once after cloning the repo on a fresh machine
# requires: flutter, node 20+, supabase cli, dart
# usage: chmod +x scripts/setup.sh && ./scripts/setup.sh
# =============================================================

set -euo pipefail
cd "$(dirname "$0")/.."

GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m'

log()  { echo -e "${GREEN}[setup]${NC} $1"; }
warn() { echo -e "${YELLOW}[warn]${NC} $1"; }
fail() { echo -e "${RED}[error]${NC} $1"; exit 1; }

# -------------------------------------------------------
# 0. check required tools
# -------------------------------------------------------

log "checking required tools..."

command -v flutter >/dev/null 2>&1 || fail "flutter not found. install from https://flutter.dev"
command -v node >/dev/null 2>&1    || fail "node not found. install from https://nodejs.org"
command -v supabase >/dev/null 2>&1 || fail "supabase cli not found. install: brew install supabase/tap/supabase"
command -v dart >/dev/null 2>&1    || fail "dart not found (should come with flutter)"

log "all tools found."

# -------------------------------------------------------
# 1. copy environment files
# -------------------------------------------------------

if [ ! -f .env ]; then
  cp .env.example .env
  warn ".env created from .env.example — fill in your supabase credentials before running the app"
else
  log ".env already exists, skipping."
fi

# -------------------------------------------------------
# 2. flutter app setup
# -------------------------------------------------------

log "setting up flutter app..."
cd apps/mobile
flutter pub get
cd ../../

# -------------------------------------------------------
# 3. admin panel setup
# -------------------------------------------------------

log "setting up admin panel..."
cd apps/admin
npm install
cd ../../

# -------------------------------------------------------
# 4. start supabase local dev
# -------------------------------------------------------

log "starting supabase local dev instance..."
supabase start

# -------------------------------------------------------
# 5. run migrations
# -------------------------------------------------------

log "running database migrations..."
supabase db push

# -------------------------------------------------------
# 6. seed development data
# -------------------------------------------------------

log "seeding development data..."
supabase db reset --db-url "$(supabase status | grep 'DB URL' | awk '{print $3}')" < supabase/seed/seed.sql || warn "seed failed — run scripts/seed_dev.sh manually"

log "========================================="
log "setup complete."
log "run the flutter app:  cd apps/mobile && flutter run"
log "run the admin panel:  cd apps/admin && npm run dev"
log "supabase studio:      http://127.0.0.1:54323"
log "========================================="s