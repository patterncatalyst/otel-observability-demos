#!/usr/bin/env bash
# demo.sh — Demo 01: Auto vs Manual Instrumentation
#
# Runs the same Spring Boot service in three modes back-to-back so the audience
# sees how Tempo coverage changes without any code change.
#
#   ./demo.sh         # run the full demo (recommended)
#   ./demo.sh up      # start the stack only
#   ./demo.sh load    # generate traffic
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
readonly DEMO_NUM="01"
readonly DEMO_NAME="Auto vs Manual Instrumentation"
readonly GRAFANA_PORT=3001
readonly SERVICE_PORT=8081

# ---- Prereqs -------------------------------------------------------------
check_prereqs() {
  step "Prerequisite check"
  local missing=0
  for tool in podman podman-compose curl jq hey; do
    if command -v "$tool" >/dev/null 2>&1; then
      ok "$tool ($(command -v $tool))"
    else
      fail "$tool not found on PATH"
      missing=$((missing+1))
    fi
  done
  if [[ $missing -gt 0 ]]; then
    warn "Install missing tools (see ../PREREQUISITES.md) and re-run."
    exit 1
  fi
}

# ---- Stack lifecycle -----------------------------------------------------
wait_for_grafana() {
  info "Waiting for Grafana on :${GRAFANA_PORT}..."
  local attempts=0
  until curl -sf "http://localhost:${GRAFANA_PORT}/api/health" >/dev/null 2>&1; do
    attempts=$((attempts+1))
    if [[ $attempts -gt 60 ]]; then fail "Grafana never came up"; exit 1; fi
    printf "."
    sleep 2
  done
  echo
  ok "Grafana healthy"
}

wait_for_service() {
  info "Waiting for service on :${SERVICE_PORT}..."
  local attempts=0
  until curl -sf "http://localhost:${SERVICE_PORT}/actuator/health" >/dev/null 2>&1; do
    attempts=$((attempts+1))
    if [[ $attempts -gt 90 ]]; then fail "Service never came up"; exit 1; fi
    printf "."
    sleep 2
  done
  echo
  ok "Service healthy"
}

up() {
  local agent_enabled="${1:-false}"
  step "Starting stack (AGENT_ENABLED=${agent_enabled})"
  AGENT_ENABLED="$agent_enabled" podman compose -f compose.yaml up -d --build
  wait_for_grafana
  wait_for_service
}

restart_service_with_agent() {
  step "Restarting service with the OTel Java agent attached"
  AGENT_ENABLED=true podman compose -f compose.yaml up -d --no-deps --force-recreate service
  wait_for_service
  ok "Service running with -javaagent attached"
}

down() {
  step "Tearing down stack"
  podman compose -f compose.yaml down -v 2>/dev/null || true
  ok "Stack removed"
}

# ---- Traffic -------------------------------------------------------------
generate_traffic() {
  local label="$1"
  local duration="${2:-15s}"
  step "Generating traffic — ${label}"
  sub "  GET /hello, GET /work?sizeMs=80, mixed"
  hey -z "$duration" -q 15 -c 4 "http://localhost:${SERVICE_PORT}/hello?name=audience" \
      > "/tmp/demo01-${label// /-}-hello.txt" 2>&1 &
  hey -z "$duration" -q 5 -c 2  "http://localhost:${SERVICE_PORT}/work?sizeMs=80" \
      > "/tmp/demo01-${label// /-}-work.txt" 2>&1
  wait
  local p99
  p99=$(grep "99%" "/tmp/demo01-${label// /-}-work.txt" | awk '{print $2}' || echo "?")
  metric "Avg /work p99 latency" "${p99}s"
  ok "Traffic done"
}

# ---- Demo flow -----------------------------------------------------------
run_demo() {
  banner "Demo ${DEMO_NUM} — ${DEMO_NAME}"
  check_prereqs

  echo
  info "This demo runs the same Spring Boot service in three modes,"
  info "showing how trace coverage changes ${BLD}without any code change${RST}."
  echo
  hr

  # ---- Mode 1: No instrumentation ---------------------------------------
  step "MODE 1 — Baseline (no agent, no manual spans triggered)"
  up "false"
  url "Grafana:    http://localhost:${GRAFANA_PORT}/d/demo01-overview"
  url "Service:    http://localhost:${SERVICE_PORT}/hello"
  url "Tempo:      http://localhost:${GRAFANA_PORT}/explore?left=%7B%22datasource%22:%22tempo%22%7D"
  generate_traffic "mode-1-baseline" "10s"
  echo
  warn "Open Tempo and search — there are no traces yet."
  warn "The service responds, /actuator works, but nothing is being exported."
  prompt

  # ---- Mode 2: Auto-agent -----------------------------------------------
  step "MODE 2 — Auto-agent attached"
  sub "Same JAR. Same container. Single env var change: AGENT_ENABLED=true"
  restart_service_with_agent
  generate_traffic "mode-2-agent" "15s"
  echo
  ok "Traces should now be flowing into Tempo for /hello, /work, and /actuator/*"
  warn "Open Tempo, find a recent trace — note the HTTP server span."
  warn "Note also: log lines on the dashboard now carry [traceId,spanId]."
  prompt

  # ---- Mode 3: Manual instrumentation in addition -----------------------
  step "MODE 3 — Manual instrumentation (Observation API)"
  sub "GET /work creates a custom 'compute.fibonacci' span via micrometer Observation"
  sub "Hitting /work specifically — this gives us nested spans"
  for i in 1 2 3 4 5; do
    curl -sf "http://localhost:${SERVICE_PORT}/work?sizeMs=$((50 + i * 30))" >/dev/null
  done
  ok "5 requests sent"
  warn "Open the most recent /work trace — you'll see the HTTP server span"
  warn "with a child 'compute.fibonacci' span carrying workload + size_ms attributes."
  prompt

  # ---- Recap -------------------------------------------------------------
  banner "Demo 01 — Recap"
  hr
  echo "  ${BLD}Mode 1${RST}  no telemetry exported (no agent, no observation triggered)"
  echo "  ${BLD}Mode 2${RST}  auto-agent attached → spans for HTTP, JDBC, etc., zero code change"
  echo "  ${BLD}Mode 3${RST}  manual Observation adds ${CYN}business${RST} spans inside auto-traced HTTP"
  hr
  echo
  ok "Auto-instrument first; hand-instrument the seams."
  echo
  warn "Press ENTER to tear down the stack"
  read -r

  down
  banner "Demo ${DEMO_NUM} complete"
}

# ---- Entrypoint ----------------------------------------------------------
case "${1:-run}" in
  up)    check_prereqs; up "true" ;;
  down)  down ;;
  load)  generate_traffic "manual" "30s" ;;
  run|*) run_demo ;;
esac
