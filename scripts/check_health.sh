#!/usr/bin/env bash
# checks that all echoproof services are running and reachable
# usage: ./scripts/check_health.sh
# exit code 0 = all healthy, 1 = something is down

set -euo pipefail

GREEN='\033[0;32m'
RED='\033[0;31m'
YELLOW='\033[1;33m'
NC='\033[0m'

FAILED=0

ok()   { echo -e "${GREEN}[ok]${NC}   $1"; }
fail() { echo -e "${RED}[fail]${NC} $1"; FAILED=1; }
warn() { echo -e "${YELLOW}[warn]${NC} $1"; }

# -------------------------------------------------------
# supabase local
# -------------------------------------------------------

echo "checking supabase local services..."

if curl -sf http://127.0.0.1:54321/health > /dev/null 2>&1; then
  ok "supabase api is running at :54321"
else
  fail "supabase api is not running — run: supabase start"
fi

if curl -sf http://127.0.0.1:54323 > /dev/null 2>&1; then
  ok "supabase studio is running at :54323"
else
  warn "supabase studio is not reachable (non-critical)"
fi

# -------------------------------------------------------
# admin panel
# -------------------------------------------------------

echo ""
echo "checking admin panel..."

if curl -sf http://localhost:3000 > /dev/null 2>&1; then
  ok "admin panel is running at :3000"
else
  warn "admin panel is not running — run: cd apps/admin && npm run dev"
fi

# -------------------------------------------------------
# flutter app
# -------------------------------------------------------

echo ""
echo "checking flutter..."

if command -v flutter > /dev/null 2>&1; then
  FLUTTER_VERSION=$(flutter --version 2>&1 | head -1)
  ok "flutter found: $FLUTTER_VERSION"

  DEVICE_COUNT=$(flutter devices 2>/dev/null | grep -c "•" || echo "0")
  if [ "$DEVICE_COUNT" -gt 0 ]; then
    ok "$DEVICE_COUNT device(s) available for flutter run"
  else
    warn "no devices connected — start an emulator before running the app"
  fi
else
  fail "flutter not found in PATH"
fi

# -------------------------------------------------------
# result
# -------------------------------------------------------

echo ""
if [ "$FAILED" -eq 0 ]; then
  echo -e "${GREEN}all critical services healthy.${NC}"
  exit 0
else
  echo -e "${RED}some services are down. see above.${NC}"
  exit 1
fi