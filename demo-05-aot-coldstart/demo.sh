#!/usr/bin/env bash
# demo.sh — Demo 05: AOT cold-start comparison (JDK 25)
#
#   ./demo.sh                # full demo: build both, time both, compare
#   ./demo.sh build          # build both images (slow first time, AOT training takes ~30s)
#   ./demo.sh time-classic   # boot classic 3 times, report median cold-start
#   ./demo.sh time-aot       # boot AOT 3 times, report median cold-start
#   ./demo.sh up             # bring both up running side-by-side
#   ./demo.sh down           # tear down

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
readonly DEMO_NUM="05"
readonly DEMO_NAME="AOT Cold Start (JDK 25)"
readonly GRAFANA_PORT=3005
readonly CLASSIC_PORT=8085
readonly AOT_PORT=8086

# ---- Prereqs -------------------------------------------------------------
check_prereqs() {
  step "Prerequisite check"
  local missing=0
  for tool in podman podman-compose curl jq; do
    if command -v "$tool" >/dev/null 2>&1; then
      ok "$tool"
    else
      fail "$tool not found"
      missing=$((missing+1))
    fi
  done
  [[ $missing -gt 0 ]] && { warn "Install missing tools and re-run."; exit 1; }
}

# ---- Build ---------------------------------------------------------------
build_images() {
  step "Building both images"
  sub "  classic: ~1 min"
  sub "  aot: ~1 min build + ~30s training run"
  podman compose -f compose.yaml build
  ok "Both images built"
  step "Image sizes"
  podman images --format "table {{.Repository}}:{{.Tag}}\t{{.Size}}" | grep -E "demo05" || true
}

# ---- LGTM lifecycle ------------------------------------------------------
up_lgtm() {
  step "Bringing up otel-lgtm"
  podman compose -f compose.yaml up -d lgtm
  info "Waiting for Grafana on :${GRAFANA_PORT}..."
  local n=0
  until curl -sf "http://localhost:${GRAFANA_PORT}/api/health" >/dev/null 2>&1; do
    n=$((n+1)); [[ $n -gt 60 ]] && { fail "Grafana never came up"; exit 1; }
    printf "."; sleep 2
  done
  echo; ok "Grafana healthy"
}

# ---- Cold-start timing ---------------------------------------------------
# Boot a service from scratch, measure the time from container start to /actuator/health 200.
time_one_boot() {
  local svc="$1" port="$2"
  # Make sure it's down
  podman stop "demo05-${svc}" >/dev/null 2>&1 || true
  podman rm   "demo05-${svc}" >/dev/null 2>&1 || true

  local start_ms=$(($(date +%s%N) / 1000000))
  podman compose -f compose.yaml up -d "${svc}" >/dev/null 2>&1

  # Poll until healthy, with millisecond precision
  while ! curl -sf "http://localhost:${port}/actuator/health" >/dev/null 2>&1; do
    # If the container died, bail
    if ! podman ps --format "{{.Names}}" | grep -q "demo05-${svc}"; then
      fail "Container demo05-${svc} died during boot"
      podman logs "demo05-${svc}" 2>&1 | tail -20
      return 1
    fi
    sleep 0.05
  done
  local end_ms=$(($(date +%s%N) / 1000000))
  echo $((end_ms - start_ms))
}

time_three_boots() {
  local svc="$1" port="$2" label="$3"
  step "Timing ${BLD}${label}${RST} cold-start (3 runs)"
  local results=()
  for i in 1 2 3; do
    local ms
    ms=$(time_one_boot "$svc" "$port")
    results+=("$ms")
    metric "  run $i" "${ms} ms"
  done
  # Median (middle of 3)
  local sorted=( $(printf "%s\n" "${results[@]}" | sort -n) )
  local median="${sorted[1]}"
  metric "  ${BLD}median${RST}" "${median} ms"
  echo "$median"
}

# ---- Demo flow -----------------------------------------------------------
run_demo() {
  banner "Demo ${DEMO_NUM} — ${DEMO_NAME}"
  check_prereqs

  build_images
  up_lgtm

  url "Dashboard:  http://localhost:${GRAFANA_PORT}/d/demo05-aot"

  local classic_median aot_median
  classic_median=$(time_three_boots "service-classic" "$CLASSIC_PORT" "service-classic (no AOT)")
  prompt
  aot_median=$(time_three_boots "service-aot" "$AOT_PORT" "service-aot (JDK 25 AOT cache)")

  banner "Demo 05 — Comparison"
  hr
  metric "service-classic median cold start" "${classic_median} ms"
  metric "service-aot median cold start"     "${aot_median} ms"
  if [[ -n "$classic_median" && -n "$aot_median" && "$aot_median" -gt 0 ]]; then
    local ratio
    ratio=$(awk -v c="$classic_median" -v a="$aot_median" 'BEGIN { printf "%.1fx", c/a }')
    local saved
    saved=$((classic_median - aot_median))
    metric "speedup" "${ratio}"
    metric "absolute savings" "${saved} ms"
  fi
  hr
  echo
  warn "Open the dashboard. Look at the startup span tree in Tempo for both."
  warn "AOT cache savings concentrate in the class-loading and bean-instantiation phases."
  prompt

  step "Bringing both services up side-by-side for live exploration"
  podman compose -f compose.yaml up -d service-classic service-aot
  url "service-classic: http://localhost:${CLASSIC_PORT}"
  url "service-aot:     http://localhost:${AOT_PORT}"
  echo
  warn "Press ENTER to tear down the stack"
  read -r

  podman compose -f compose.yaml down -v 2>/dev/null || true
  banner "Demo ${DEMO_NUM} complete"
}

# ---- Entrypoint ----------------------------------------------------------
case "${1:-run}" in
  build)
    check_prereqs; build_images ;;
  up)
    check_prereqs; build_images
    podman compose -f compose.yaml up -d
    ;;
  time-classic)
    check_prereqs; up_lgtm
    time_three_boots "service-classic" "$CLASSIC_PORT" "service-classic"
    ;;
  time-aot)
    check_prereqs; up_lgtm
    time_three_boots "service-aot" "$AOT_PORT" "service-aot"
    ;;
  down)
    podman compose -f compose.yaml down -v 2>/dev/null || true
    ok "Stack removed"
    ;;
  run|*)
    run_demo
    ;;
esac
