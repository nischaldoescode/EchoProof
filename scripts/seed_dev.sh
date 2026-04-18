#!/usr/bin/env bash
# seeds local supabase with development test data
# usage: ./scripts/seed_dev.sh
# requires: supabase cli running (supabase start)

set -euo pipefail

GREEN='\033[0;32m'
NC='\033[0m'

log() { echo -e "${GREEN}[seed]${NC} $1"; }

log "getting local db url..."
DB_URL=$(supabase status --output json 2>/dev/null | python3 -c "
import sys, json
data = json.load(sys.stdin)
print(data.get('DB URL', ''))
" 2>/dev/null || echo "")

if [ -z "$DB_URL" ]; then
  # fallback to default local supabase db url
  DB_URL="postgresql://postgres:postgres@127.0.0.1:54322/postgres"
fi

log "running seed.sql against $DB_URL..."
psql "$DB_URL" -f supabase/seed/seed.sql

log "seed complete. test users:"
log "  email: alice@test.com  password: TestPass123!"
log "  email: bob@test.com    password: TestPass123!"