#!/usr/bin/env bash
# pre-pull.sh — pull all container images used by the demos before talk day.
# Run once on the host you'll present from; re-run periodically to refresh.

set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)" && cd "$SCRIPT_DIR"

readonly RED=$'\033[0;31m'  GRN=$'\033[0;32m'  YLW=$'\033[1;33m'
readonly BLU=$'\033[0;34m'  CYN=$'\033[0;36m'  BLD=$'\033[1m'  RST=$'\033[0m'

step() { echo; echo "${BLU}${BLD}▶ $1${RST}"; }
ok()   { echo "${GRN}  ✓${RST} $1"; }
warn() { echo "${YLW}  ⚠${RST} $1"; }
fail() { echo "${RED}  ✗${RST} $1" >&2; }

IMAGES=(
  "docker.io/grafana/otel-lgtm:0.8.1"
  "docker.io/otel/opentelemetry-collector-contrib:0.114.0"
  "registry.access.redhat.com/ubi9/openjdk-21-runtime:1.21-1"
  "registry.access.redhat.com/ubi9/openjdk-21:1.24"
  "registry.access.redhat.com/ubi9/openjdk-25-runtime:1.24"
  "registry.access.redhat.com/ubi9/openjdk-25:1.24"
)

step "Pulling demo images (${#IMAGES[@]} total)"
for img in "${IMAGES[@]}"; do
  echo "   pulling ${CYN}${img}${RST}"
  if podman pull "$img" >/dev/null 2>&1; then
    ok "$img"
  else
    fail "Failed to pull $img"
    warn "Check that you're online and the registry is reachable"
  fi
done

step "Image inventory"
podman images --format "table {{.Repository}}:{{.Tag}}\t{{.Size}}" \
  | grep -E "(otel-lgtm|opentelemetry-collector|openjdk-21|openjdk-25)" || true

step "Done"
ok "All images pulled. You're ready to demo."
