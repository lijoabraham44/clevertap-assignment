#!/usr/bin/env bash
# =============================================================================
# Staging smoke tests — fast, black-box checks that the freshly deployed service
# is actually serving correctly before we offer it for production promotion.
#
# Why smoke tests (not the full suite): they answer "is this build fundamentally
# healthy in a real cluster?" in seconds — health, readiness, a real request
# path, and the downstream Kafka dependency. Failing here blocks promotion.
#
# Exit non-zero on any failure so the GitHub Actions job (and the gate) fail.
# =============================================================================
set -euo pipefail

BASE_URL="${BASE_URL:?BASE_URL must be set, e.g. https://event-ingestion.staging.clevertap.internal}"
TIMEOUT="${TIMEOUT:-5}"
RETRIES="${RETRIES:-10}"
SLEEP="${SLEEP:-6}"

log()  { printf '\033[1;34m[smoke]\033[0m %s\n' "$*"; }
fail() { printf '\033[1;31m[FAIL]\033[0m %s\n' "$*" >&2; exit 1; }

# Retry helper: wait for the deployment to become reachable/ready.
retry() {
  local desc="$1"; shift
  local i
  for i in $(seq 1 "$RETRIES"); do
    if "$@"; then log "ok: $desc"; return 0; fi
    log "retry $i/$RETRIES: $desc"; sleep "$SLEEP"
  done
  fail "$desc (after $RETRIES attempts)"
}

check_status() {
  local path="$1" want="$2"
  local code
  code=$(curl -sS -o /dev/null -w '%{http_code}' --max-time "$TIMEOUT" "${BASE_URL}${path}")
  [[ "$code" == "$want" ]]
}

# 1. Liveness/health endpoint returns 200.
retry "GET /healthz == 200" check_status "/healthz" "200"

# 2. Readiness endpoint returns 200 (dependencies wired).
retry "GET /readyz == 200" check_status "/readyz" "200"

# 3. Real request path: POST a synthetic event is accepted (202 Accepted).
log "POST /v1/events (synthetic event)"
resp_code=$(curl -sS -o /tmp/smoke_resp.json -w '%{http_code}' --max-time "$TIMEOUT" \
  -X POST "${BASE_URL}/v1/events" \
  -H 'Content-Type: application/json' \
  -d '{"event":"smoke_test","tenant":"synthetic","ts":"2026-01-01T00:00:00Z"}')
[[ "$resp_code" == "202" ]] || fail "POST /v1/events expected 202, got ${resp_code}"
log "ok: event accepted (202)"

# 4. Downstream wiring: the app reports Kafka producer healthy via its metrics.
log "checking Kafka producer health via /metrics"
if curl -sS --max-time "$TIMEOUT" "${BASE_URL}/metrics" | grep -q 'kafka_producer_connection_up 1'; then
  log "ok: kafka producer connection up"
else
  fail "kafka producer connection not healthy"
fi

log "all smoke tests passed ✅"
