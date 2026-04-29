#!/usr/bin/env bash
# verify-stacks.sh — smoke-test each demo's stack starts cleanly.
# Run before talk day to catch broken composes, missing images, port conflicts.

set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)" && cd "$SCRIPT_DIR"

readonly RED=$'\033[0;31m'  GRN=$'\033[0;32m'  YLW=$'\033[1;33m'
readonly BLU=$'\033[0;34m'  CYN=$'\033[0;36m'  BLD=$'\033[1m'  RST=$'\033[0m'

step()  { echo; echo "${BLU}${BLD}▶ $1${RST}"; }
ok()    { echo "${GRN}  ✓${RST} $1"; }
warn()  { echo "${YLW}  ⚠${RST} $1"; }
fail()  { echo "${RED}  ✗${RST} $1" >&2; }

DEMOS=(
  "demo-01-auto-vs-manual:3001"
  "demo-02-correlation:3002"
  "demo-03-sampling:3003"
  "demo-04-gc-pauses:3004"
  "demo-05-aot-coldstart:3005"
)

PASS=0
FAIL=0

for entry in "${DEMOS[@]}"; do
  IFS=':' read -r demo_dir grafana_port <<< "$entry"
  step "Verifying ${demo_dir}"

  if [[ ! -d "$demo_dir" ]]; then
    fail "directory not found"
    FAIL=$((FAIL+1))
    continue
  fi

  pushd "$demo_dir" >/dev/null

  # Special case: demo-03-sampling needs an active config.yaml (head or tail).
  # We use the head config for verify; the demo.sh manages the swap during real runs.
  if [[ "$demo_dir" == "demo-03-sampling" && -f otelcol/config-head.yaml && ! -f otelcol/config.yaml ]]; then
    cp otelcol/config-head.yaml otelcol/config.yaml
  fi

  if [[ ! -f compose.yaml ]]; then
    fail "compose.yaml missing"
    FAIL=$((FAIL+1))
    popd >/dev/null
    continue
  fi

  echo "   bringing up..."
  if podman compose -f compose.yaml up -d --build >/tmp/verify-${demo_dir}.log 2>&1; then
    ok "stack started"
  else
    fail "stack failed to start (see /tmp/verify-${demo_dir}.log)"
    FAIL=$((FAIL+1))
    podman compose -f compose.yaml down -v >/dev/null 2>&1 || true
    popd >/dev/null
    continue
  fi

  echo "   waiting for grafana on :${grafana_port}..."
  ATTEMPTS=0
  until curl -sf "http://localhost:${grafana_port}/api/health" >/dev/null 2>&1; do
    ATTEMPTS=$((ATTEMPTS+1))
    if [[ $ATTEMPTS -gt 60 ]]; then
      fail "grafana did not become healthy"
      FAIL=$((FAIL+1))
      break
    fi
    sleep 2
  done

  if [[ $ATTEMPTS -le 60 ]]; then
    ok "grafana healthy on :${grafana_port}"
    PASS=$((PASS+1))
  fi

  echo "   tearing down..."
  podman compose -f compose.yaml down -v >/dev/null 2>&1 || true
  ok "torn down"

  popd >/dev/null
done

step "Summary"
echo "  ${GRN}passed:${RST} $PASS"
echo "  ${RED}failed:${RST} $FAIL"

if [[ $FAIL -gt 0 ]]; then
  exit 1
fi
ok "All stacks verified"
