#!/usr/bin/env bash
# demo.sh — Demo 03: Head vs Tail Sampling
#
#   ./demo.sh              # full demo (head -> tail comparison)
#   ./demo.sh up [head|tail]  # start stack with given config (default: head)
#   ./demo.sh switch head  # swap to head sampling (5% at app)
#   ./demo.sh switch tail  # swap to tail sampling (in Collector)
#   ./demo.sh load         # generate traffic mix
#   ./demo.sh down         # tear down

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
readonly DEMO_NUM="03"
readonly DEMO_NAME="Head vs Tail Sampling"
readonly GRAFANA_PORT=3003
readonly SERVICE_PORT=8083

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

# ---- Mode switching ------------------------------------------------------
# Active config is at otelcol/config.yaml. We rewrite it from the head/tail
# templates and either (re)create or just restart the Collector.
write_config() {
  local mode="$1"
  case "$mode" in
    head)
      cp otelcol/config-head.yaml otelcol/config.yaml
      ok "Wrote head-sampling Collector config"
      ;;
    tail)
      cp otelcol/config-tail.yaml otelcol/config.yaml
      ok "Wrote tail-sampling Collector config"
      ;;
    *)
      fail "Unknown mode '$mode'. Use 'head' or 'tail'."; exit 1
      ;;
  esac
}

write_env() {
  local mode="$1"
  # Head mode: app samples at 5%
  # Tail mode: app samples at 100% (Collector does the work)
  case "$mode" in
    head)
      export OTEL_TRACES_SAMPLER="parentbased_traceidratio"
      export OTEL_TRACES_SAMPLER_ARG="0.05"
      info "App-side sampler: parentbased_traceidratio (5%)"
      ;;
    tail)
      export OTEL_TRACES_SAMPLER="parentbased_traceidratio"
      export OTEL_TRACES_SAMPLER_ARG="1.0"
      info "App-side sampler: parentbased_traceidratio (100%) — Collector decides"
      ;;
  esac
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
  local mode="${1:-head}"
  step "Starting stack in ${BLD}${mode}${RST} mode"
  write_config "$mode"
  write_env "$mode"
  podman compose -f compose.yaml up -d --build
  wait_for_grafana
  wait_for_service
}

restart_for_mode() {
  local mode="$1"
  step "Switching to ${BLD}${mode}${RST} sampling"
  write_config "$mode"
  write_env "$mode"
  # Restart the Collector to pick up new config; restart service to pick up new env.
  podman compose -f compose.yaml up -d --no-deps --force-recreate collector service
  wait_for_service
  ok "Stack reconfigured for ${mode} sampling"
}

down() {
  step "Tearing down stack"
  podman compose -f compose.yaml down -v 2>/dev/null || true
  rm -f otelcol/config.yaml
  ok "Stack removed"
}

# ---- Traffic -------------------------------------------------------------
generate_traffic() {
  local label="$1" duration="${2:-30s}" rps="${3:-30}"
  step "Generating mixed traffic — ${label}  (${duration} @ ${rps} RPS)"
  sub "  90% fast, 5% slow, 5% error  (via /work/random)"
  hey -z "$duration" -q "$rps" -c 4 "http://localhost:${SERVICE_PORT}/work/random" \
    > "/tmp/demo03-${label// /-}.txt" 2>&1
  ok "Traffic done (${duration})"
}

# ---- Tempo trace counts --------------------------------------------------
report_kept() {
  local label="$1"
  step "Span counts in Tempo for ${label}"
  # Probe Collector's own counters via Prom on the lgtm side
  local in_count out_count
  in_count=$(curl -sf "http://localhost:${GRAFANA_PORT}/api/datasources/proxy/uid/prometheus/api/v1/query?query=otelcol_receiver_accepted_spans_total" \
    | jq -r '.data.result[0].value[1] // "?"')
  out_count=$(curl -sf "http://localhost:${GRAFANA_PORT}/api/datasources/proxy/uid/prometheus/api/v1/query?query=otelcol_exporter_sent_spans_total" \
    | jq -r '.data.result[0].value[1] // "?"')
  metric "Collector spans received" "${in_count}"
  metric "Collector spans exported" "${out_count}"
  if [[ "$in_count" != "?" && "$out_count" != "?" ]]; then
    if [[ "$in_count" -gt 0 ]]; then
      local pct=$(awk -v in_count="$in_count" -v out_count="$out_count" 'BEGIN { printf "%.1f", (out_count/in_count)*100 }')
      metric "Kept fraction" "${pct}%"
    fi
  fi
}

# ---- Demo flow -----------------------------------------------------------
run_demo() {
  banner "Demo ${DEMO_NUM} — ${DEMO_NAME}"
  check_prereqs

  # ---- Phase 1: head sampling -------------------------------------------
  banner "Phase 1 — Head sampling at the app"
  up "head"
  url "Dashboard:  http://localhost:${GRAFANA_PORT}/d/demo03-sampling"
  url "Tempo:      http://localhost:${GRAFANA_PORT}/explore?left=%7B%22datasource%22:%22tempo%22%7D"
  echo
  info "App is configured with parentbased_traceidratio=0.05"
  info "→ ~5% of traces survive. Decision is random, blind to error/latency."
  generate_traffic "head" "30s" "30"
  report_kept "Head sampling (5% probabilistic)"
  warn "Open Tempo. Search for traces. Most are /work (fast). Errors are RARE."
  warn "You probably won't find the error traces — head sampling threw most of them out."
  prompt

  # ---- Phase 2: tail sampling -------------------------------------------
  banner "Phase 2 — Tail sampling at the Collector"
  restart_for_mode "tail"
  echo
  info "Collector now buffers each trace, applies policies after completion:"
  info "  - status=ERROR     → keep 100%"
  info "  - latency >  1s    → keep 100%"
  info "  - else             → keep 5%"
  generate_traffic "tail" "30s" "30"
  echo
  info "Wait 15s for Collector decision_wait window to elapse..."
  sleep 15
  report_kept "Tail sampling"
  warn "Open Tempo again. Filter by status=error — every error is preserved."
  warn "Filter by latency >1s — every slow trace is preserved."
  warn "Filter by status=ok and latency<100ms — only ~5% of those, by design."
  prompt

  # ---- Recap -------------------------------------------------------------
  banner "Demo 03 — Recap"
  hr
  echo "  ${BLD}Head sampling:${RST}  cheap, predictable cost, ${RED}blind to outcome${RST}"
  echo "  ${BLD}Tail sampling:${RST}  smart, keeps interesting traces, costs Collector RAM"
  echo "  ${BLD}Production:${RST}     usually both — head at app to throttle output,"
  echo "                  tail at gateway to preserve what matters."
  hr
  echo
  warn "Press ENTER to tear down the stack"
  read -r
  down
  banner "Demo ${DEMO_NUM} complete"
}

# ---- Entrypoint ----------------------------------------------------------
case "${1:-run}" in
  up)      check_prereqs; up "${2:-head}" ;;
  switch)  restart_for_mode "${2:?need 'head' or 'tail'}" ;;
  load)    generate_traffic "manual" "60s" "30" ;;
  down)    down ;;
  run|*)   run_demo ;;
esac
