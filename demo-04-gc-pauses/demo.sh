#!/usr/bin/env bash
# demo.sh — Demo 04: GC pauses as trace gaps
#
#   ./demo.sh                  # full demo: shenandoah → g1 → zgc, in sequence
#   ./demo.sh up [gc]          # start stack with given GC (default: shenandoah)
#   ./demo.sh run <gc>         # tear down, restart with this GC, run workload
#   ./demo.sh load             # generate workload at current GC config
#   ./demo.sh down             # tear down

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
readonly DEMO_NUM="04"
readonly DEMO_NAME="GC Pauses as Trace Gaps"
readonly GRAFANA_PORT=3004
readonly SERVICE_PORT=8084

# ---- GC config picker ----------------------------------------------------
gc_flags_for() {
  case "$1" in
    shenandoah)
      # Force Shenandoah explicitly (UBI9 default is actually G1)
      echo "-XX:+UseShenandoahGC"
      ;;
    g1)
      echo "-XX:+UseG1GC -XX:MaxGCPauseMillis=200"
      ;;
    zgc)
      # Generational ZGC explicit (it's standard on JDK 25, opt-in on 21)
      echo "-XX:+UseZGC -XX:+ZGenerational"
      ;;
    *)
      fail "Unknown GC '$1'. Use shenandoah, g1, or zgc."
      exit 1
      ;;
  esac
}

gc_label_for() {
  case "$1" in
    shenandoah) echo "Shenandoah (UBI9 default, generational since 21)" ;;
    g1)         echo "G1GC (most distros' default)" ;;
    zgc)        echo "ZGC generational" ;;
  esac
}

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
  if [[ $missing -gt 0 ]]; then warn "Install missing tools and re-run."; exit 1; fi
}

# ---- Health waits --------------------------------------------------------
wait_for_grafana() {
  info "Waiting for Grafana on :${GRAFANA_PORT}..."
  local n=0
  until curl -sf "http://localhost:${GRAFANA_PORT}/api/health" >/dev/null 2>&1; do
    n=$((n+1)); [[ $n -gt 60 ]] && { fail "Grafana never came up"; exit 1; }
    printf "."; sleep 2
  done
  echo; ok "Grafana healthy"
}

wait_for_service() {
  info "Waiting for service on :${SERVICE_PORT}..."
  local n=0
  until curl -sf "http://localhost:${SERVICE_PORT}/actuator/health" >/dev/null 2>&1; do
    n=$((n+1)); [[ $n -gt 90 ]] && { fail "Service never came up"; exit 1; }
    printf "."; sleep 2
  done
  echo; ok "Service healthy"
}

# ---- Stack lifecycle -----------------------------------------------------
up() {
  local gc="${1:-shenandoah}"
  local flags
  flags="$(gc_flags_for "$gc")"
  step "Starting stack with GC = ${BLD}${gc}${RST}"
  sub "  flags: ${flags:-(default — UBI9 Shenandoah)}"
  GC_MODE="$gc" GC_FLAGS="$flags" podman compose -f compose.yaml up -d --build
  wait_for_grafana
  wait_for_service
}

restart_with_gc() {
  local gc="$1"
  local flags
  flags="$(gc_flags_for "$gc")"
  step "Restarting service with GC = ${BLD}${gc}${RST}"
  sub "  flags: ${flags:-(default — UBI9 Shenandoah)}"
  GC_MODE="$gc" GC_FLAGS="$flags" podman compose -f compose.yaml up -d --no-deps --force-recreate service
  wait_for_service
  ok "Service running with $(gc_label_for "$gc")"
}

down() {
  step "Tearing down stack"
  podman compose -f compose.yaml down -v 2>/dev/null || true
  ok "Stack removed"
}

# ---- Workload ------------------------------------------------------------
generate_workload() {
  local label="$1" duration="${2:-45s}"
  step "Generating allocation pressure — ${label}"
  sub "  /allocate?sizeKb=64&objects=2000  (~125 MB allocated per request)"
  hey -z "$duration" -q 8 -c 4 "http://localhost:${SERVICE_PORT}/allocate?sizeKb=64&objects=2000" \
    > "/tmp/demo04-${label// /-}.txt" 2>&1 &
  # Light /work traffic alongside, so we have non-allocation spans to compare
  hey -z "$duration" -q 20 -c 2 "http://localhost:${SERVICE_PORT}/work" \
    > "/tmp/demo04-${label// /-}-work.txt" 2>&1
  wait
  local p99
  p99=$(grep "99%" "/tmp/demo04-${label// /-}.txt" | awk '{print $2}' || echo "?")
  metric "Allocate p99 latency" "${p99}s"
  ok "Workload done"
}

# ---- Demo flow -----------------------------------------------------------
run_demo() {
  banner "Demo ${DEMO_NUM} — ${DEMO_NAME}"
  check_prereqs
  up "shenandoah"
  url "Dashboard:  http://localhost:${GRAFANA_PORT}/d/demo04-gc"
  url "Service:    http://localhost:${SERVICE_PORT}"
  echo
  hr

  for gc in shenandoah g1 zgc; do
    banner "GC mode: ${gc}"
    info "$(gc_label_for "$gc")"
    if [[ "$gc" != "shenandoah" ]]; then
      restart_with_gc "$gc"
    fi
    generate_workload "$gc" "45s"
    warn "Look at the dashboard — note the p99 GC pause for this run."
    warn "Open Tempo, find an /allocate trace from the last 30s — note any gaps."
    prompt
  done

  banner "Demo 04 — Recap"
  hr
  echo "  ${BLD}Shenandoah${RST}  ~5–10ms p99 pauses, low memory overhead, UBI9 default"
  echo "  ${BLD}G1GC${RST}        ~50–100ms p99 pauses, throughput-optimized, broad default"
  echo "  ${BLD}ZGC${RST}         <1ms p99 pauses, ~15% memory overhead, big-heap optimized"
  hr
  echo
  ok "The dashboard tells you GC pauses and trace gaps in one place — that's the OTel point."
  ok "If you're on UBI9, you're already on Shenandoah. No flag flipped."
  echo
  warn "Press ENTER to tear down the stack"
  read -r
  down
  banner "Demo ${DEMO_NUM} complete"
}

# ---- Entrypoint ----------------------------------------------------------
case "${1:-run}" in
  up)      check_prereqs; up "${2:-shenandoah}" ;;
  run)
    if [[ -z "${2:-}" ]]; then
      run_demo
    else
      check_prereqs
      restart_with_gc "$2"
      generate_workload "$2"
    fi
    ;;
  load)    generate_workload "manual" "60s" ;;
  down)    down ;;
  *)       run_demo ;;
esac
