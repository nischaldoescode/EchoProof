#!/usr/bin/env bash
# =============================================================
# echoproof unified test runner
# runs flutter unit, widget, integration tests + admin checks
# usage: ./scripts/test_runner.sh
# exit code 0 = all passed, 1 = any failure
# =============================================================

set -euo pipefail

GREEN='\033[0;32m'
RED='\033[0;31m'
YELLOW='\033[1;33m'
NC='\033[0m'

FAILED=0

log()  { echo -e "${GREEN}[test]${NC} $1"; }
warn() { echo -e "${YELLOW}[warn]${NC} $1"; }
fail() { echo -e "${RED}[fail]${NC} $1"; FAILED=1; }

# -------------------------------------------------------
# flutter tests
# -------------------------------------------------------

log "running flutter unit tests..."
cd apps/mobile
flutter test test/unit/ --coverage || fail "flutter unit tests failed"

log "running flutter widget tests..."
flutter test test/widget/ || fail "flutter widget tests failed"

# -------------------------------------------------------
# integration tests (safe CI handling)
# -------------------------------------------------------

log "checking integration test environment..."

if [ "${SKIP_INTEGRATION:-0}" = "1" ]; then
  warn "integration tests skipped (SKIP_INTEGRATION=1)"
else
  # check if emulator/device exists
  DEVICE_COUNT=$(flutter devices | grep -c "device" || true)

  if [ "$DEVICE_COUNT" -eq 0 ]; then
    warn "no device/emulator found — skipping integration tests"
    warn "start emulator or connect device to enable them"
  else
    log "running flutter integration tests..."
    
    # optional: ensure supabase is running (local dev assumption)
    if [ "${SUPABASE_LOCAL:-0}" = "1" ]; then
      log "using local supabase instance"
    else
      warn "assuming remote supabase (SUPABASE_LOCAL not set)"
    fi

    flutter test test/integration/ || fail "flutter integration tests failed"
  fi
fi

cd ../../

# -------------------------------------------------------
# admin typescript checks
# -------------------------------------------------------

log "running admin typescript checks..."
cd apps/admin
npx tsc --noEmit || fail "typescript errors in admin panel"
cd ../../

# -------------------------------------------------------
# final result
# -------------------------------------------------------

if [ "$FAILED" -eq 0 ]; then
  echo -e "${GREEN}all tests passed.${NC}"
  exit 0
else
  echo -e "${RED}some tests failed. see above output.${NC}"
  exit 1
fi