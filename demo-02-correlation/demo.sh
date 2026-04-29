#!/usr/bin/env bash
# demo.sh — Demo 02: Three-Signal Correlation
#
# The headline demo. Drives traffic, injects a fault on inventory-service,
# and prompts the operator to walk through the metric → trace → log pivot.
#
#   ./demo.sh         # full demo (recommended)
#   ./demo.sh up      # start stack only
#   ./demo.sh load    # generate baseline traffic
#   ./demo.sh inject  # turn fault on (500ms latency, 5% errors)
#   ./demo.sh clear   # turn fault off
#   ./demo.sh down    # tear down

set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)" && cd "$SCRIPT_DIR"

# ---- Colors --------------------------------------------------------------
readonly RED=$'\033[0;31m'  GRN=$'\033[0;32m'  YLW=$'\033[1;33m'
readonly BLU=$'\033[0;34m'  CYN=$'\033[0;36m'  MAG=$'\033[0;35m'
readonly DIM=$'\033[2m'     BLD=$'\033[1m'     RST=$'\033[0m'

banner() {
  echo
  echo "${CYN}${BLD}╔═══════════════════════════════════════════════════════════╗${RST}"
  printf  "${CYN}${BLD}║  %-57s║${RST}\n" "$1"
  echo "${CYN}${BLD}╚═══════════════════════════════════════════════════════════╝${RST}"
}
step()    { echo; echo "${BLU}${BLD}▶ $1${RST}"; }
sub()     { echo "${DIM}    $1${RST}"; }
info()    { echo "${CYN}  •${RST} $1"; }
ok()      { echo "${GRN}  ✓${RST} $1"; }
warn()    { echo "${YLW}  ⚠${RST} $1"; }
fail()    { echo "${RED}  ✗${RST} $1" >&2; }
metric()  { printf "  ${DIM}%-32s${RST} ${BLD}%s${RST}\n" "$1" "$2"; }
url()     { echo "  ${MAG}↗${RST} ${DIM}$1${RST}"; }
hr()      { echo "${DIM}--------------------------------------------------------------${RST}"; }
prompt()  { echo; echo "${YLW}${BLD}⏸  Press ENTER to continue...${RST}"; read -r; }

trap 'fail "Failed at line $LINENO"' ERR

# ---- Config --------------------------------------------------------------
readonly DEMO_NUM="02"
readonly DEMO_NAME="Three-Signal Correlation"
readonly GRAFANA_PORT=3002
readonly ORDER_PORT=8082
readonly INVENTORY_PORT=8092
readonly DASHBOARD_UID="demo02-correlation"

# ---- Prereqs -------------------------------------------------------------
check_prereqs() {
  step "Prerequisite check"
  local missing=0
  for tool in podman podman-compose curl jq hey; do
    if command -v "$tool" >/dev/null 2>&1; then
      ok "$tool"
    else
      fail "$tool not found"
      missing=$((missing+1))
    fi
  done
  if [[ $missing -gt 0 ]]; then
    warn "Install missing tools (../PREREQUISITES.md) and re-run."
    exit 1
  fi
}

# ---- Health waits --------------------------------------------------------
wait_for_grafana() {
  info "Waiting for Grafana on :${GRAFANA_PORT}..."
  local n=0
  until curl -sf "http://localhost:${GRAFANA_PORT}/api/health" >/dev/null 2>&1; do
    n=$((n+1))
    [[ $n -gt 60 ]] && { fail "Grafana never came up"; exit 1; }
    printf "."; sleep 2
  done
  echo; ok "Grafana healthy"
}

wait_for_service() {
  local name="$1" port="$2"
  info "Waiting for ${name} on :${port}..."
  local n=0
  until curl -sf "http://localhost:${port}/actuator/health" >/dev/null 2>&1; do
    n=$((n+1))
    [[ $n -gt 90 ]] && { fail "${name} never came up"; exit 1; }
    printf "."; sleep 2
  done
  echo; ok "${name} healthy"
}

# ---- Stack lifecycle -----------------------------------------------------
up() {
  step "Starting LGTM stack + services"
  podman compose -f compose.yaml up -d --build
  wait_for_grafana
  wait_for_service "inventory-service" "${INVENTORY_PORT}"
  wait_for_service "order-service" "${ORDER_PORT}"
}

down() {
  step "Tearing down stack"
  podman compose -f compose.yaml down -v 2>/dev/null || true
  ok "Stack removed"
}

# ---- Fault injection -----------------------------------------------------
inject() {
  local latency="${1:-500}" rate="${2:-0.05}"
  step "Injecting fault on inventory-service"
  sub "  latencyMs=${latency}, errorRate=${rate}"
  curl -sf -X POST "http://localhost:${INVENTORY_PORT}/admin/inject?latencyMs=${latency}&errorRate=${rate}" \
    | jq -C . || true
  ok "Fault injected — watch the dashboard"
}

clear_fault() {
  step "Clearing fault on inventory-service"
  curl -sf -X POST "http://localhost:${INVENTORY_PORT}/admin/inject?latencyMs=0&errorRate=0.0" \
    | jq -C . || true
  ok "Fault cleared"
}

# ---- Traffic -------------------------------------------------------------
generate_traffic() {
  local label="$1" duration="${2:-30s}" rps="${3:-15}"
  step "Generating traffic — ${label} (${duration} @ ${rps} RPS)"
  hey -z "$duration" -q "$rps" -c 4 "http://localhost:${ORDER_PORT}/orders/random" \
    > "/tmp/demo02-${label// /-}.txt" 2>&1
  local p99 errors
  p99=$(grep "99%" "/tmp/demo02-${label// /-}.txt" | awk '{print $2}' || echo "?")
  errors=$(grep "Status code distribution" -A 5 "/tmp/demo02-${label// /-}.txt" | grep -E '\[5[0-9]{2}\]' | awk '{sum+=$2} END {print sum+0}' || echo "0")
  metric "p99 latency" "${p99}s"
  metric "5xx responses" "${errors}"
}

# ---- Demo flow -----------------------------------------------------------
run_demo() {
  banner "Demo ${DEMO_NUM} — ${DEMO_NAME}"
  check_prereqs
  up

  echo
  url "Dashboard:      http://localhost:${GRAFANA_PORT}/d/${DASHBOARD_UID}"
  url "Order service:  http://localhost:${ORDER_PORT}/orders/random"
  url "Tempo Explore:  http://localhost:${GRAFANA_PORT}/explore?left=%7B%22datasource%22:%22tempo%22%7D"
  echo
  hr

  # ---- Phase 1: baseline ------------------------------------------------
  step "Phase 1 — Healthy baseline"
  sub "Both services responding cleanly. Latency should be flat, no errors."
  generate_traffic "baseline" "20s" "15"
  warn "Open the dashboard. p99 should be flat. No 5xx. This is what 'healthy' looks like."
  prompt

  # ---- Phase 2: inject fault --------------------------------------------
  step "Phase 2 — Inject the fault"
  sub "Adding 500ms latency and 5% error rate on inventory-service."
  sub "The order-service has no idea anything's wrong upstream — it just gets slow + errors."
  inject 500 0.05
  echo
  info "Generating traffic for 30s with the fault active..."
  generate_traffic "fault-injected" "30s" "15"

  # ---- Phase 3: pivot in Grafana ----------------------------------------
  banner "Phase 3 — The 15-second pivot"
  echo
  echo "  ${BLD}Steps to do live in Grafana:${RST}"
  echo
  echo "  ${BLU}1.${RST} Look at the dashboard p99 chart — see the spike on inventory-service."
  echo "  ${BLU}2.${RST} Hover the histogram, find an ${MAG}exemplar dot${RST} at the top of the spike."
  echo "  ${BLU}3.${RST} Click the dot — Tempo opens with the slow trace."
  echo "  ${BLU}4.${RST} Expand the trace. The long span is ${CYN}inventory.findStock${RST}."
  echo "  ${BLU}5.${RST} Click ${BLD}'Logs for this span'${RST} — Loki shows the error log line."
  echo "  ${BLU}6.${RST} Read the error message — that's your root cause."
  echo
  echo "  ${BLD}Total time from 'something is wrong' to 'I'm reading the stack trace':${RST}"
  echo "  ${GRN}${BLD}~15 seconds.${RST}"
  echo
  prompt

  # ---- Phase 4: clear ----------------------------------------------------
  step "Phase 4 — Clear the fault and confirm recovery"
  clear_fault
  generate_traffic "recovered" "15s" "15"
  ok "Latency back to baseline. The story is repeatable."

  # ---- Recap -------------------------------------------------------------
  banner "Demo 02 — Recap"
  hr
  echo "  ${BLD}Three signals:${RST}    metrics, logs, traces"
  echo "  ${BLD}One identifier:${RST}   traceId — on metric exemplars, in spans, and in log MDC"
  echo "  ${BLD}Auto-instrumented:${RST} HTTP server + client traced by the OTel agent, no code"
  echo "  ${BLD}The pivot:${RST}        15 seconds from anomaly to root cause"
  hr

  echo
  warn "Press ENTER to tear down the stack"
  read -r

  down
  banner "Demo ${DEMO_NUM} complete"
}

# ---- Entrypoint ----------------------------------------------------------
case "${1:-run}" in
  up)        check_prereqs; up ;;
  down)      down ;;
  load)      generate_traffic "manual" "60s" "15" ;;
  inject)    inject "${2:-500}" "${3:-0.05}" ;;
  clear)     clear_fault ;;
  run|*)     run_demo ;;
esac
