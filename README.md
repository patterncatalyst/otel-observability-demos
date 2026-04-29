# Cloud-Native Observability with OpenTelemetry — Demo Repository

Companion repo for the talk *"Three Signals, One Story: Cloud-Native Observability with OpenTelemetry on OpenShift."*

## Stack

| Component | Version |
|---|---|
| Spring Boot | 4.0.x (4.0.4+ GA) |
| Java | 21 LTS (demos 01–04), 25 LTS (demo 05 — Leyden / AOT) |
| Container base | `registry.access.redhat.com/ubi9/openjdk-21-runtime` |
| Container runtime | Podman 5.x rootless |
| Observability backend | `grafana/otel-lgtm:0.8.1+` (Tempo + Loki + Prometheus + Grafana, all-in-one) |
| OTel Java agent | 2.x (latest) |

## Repository Layout

```
otel-observability-demos/
├── demo-01-auto-vs-manual/    # Auto vs manual instrumentation
├── demo-02-correlation/        # Three-signal pivot (the headline demo)
├── demo-03-sampling/           # Head vs tail sampling (standalone Collector)
├── demo-04-gc-pauses/          # GC pauses showing as trace gaps
├── demo-05-aot-coldstart/      # JDK 25 + AOTCache cold-start (~5x speedup)
├── diagrams/                   # Excalidraw source files (08–16)
├── docs/                       # Long-form docs (reconciliation plan, etc.)
├── presentation/               # reveal.js slide deck + speaker notes
└── tools/                      # build-diagrams.py and other helpers
```

Each demo runs **independently** with its own podman compose stack on its own port range. You can `cd demo-NN-name && ./demo.sh` and it will spin up everything it needs without depending on sibling demos.

## Port Allocation

| Demo | Grafana | OTLP gRPC | OTLP HTTP | Service(s) |
|---|---|---|---|---|
| 01 | 3001 | 4317 | 4318 | 8081 |
| 02 | 3002 | 14317 | 14318 | 8082 (order), 8092 (inventory) |
| 03 | 3003 | 24317 | 24318 | 8083 |
| 04 | 3004 | 34317 | 34318 | 8084 |
| 05 | 3005 | 44317 | 44318 | 8085 |

## Quick Start

```bash
# Pull all images ahead of time (do this before the talk)
./pre-pull.sh

# Verify each demo's stack starts cleanly
./verify-stacks.sh

# Run a specific demo
cd demo-02-correlation
./demo.sh
```

## Demo Contract

Every demo follows the same shape:

1. `demo.sh` — color-coded orchestrator. Subcommands: `up`, `down`, `load`, `run` (default).
2. `compose.yaml` — podman compose file with the service(s) + otel-lgtm.
3. `otelcol/config.yaml` — Collector pipeline configuration.
4. `grafana/provisioning/` — datasources and pre-built dashboards.
5. `service/` (or per-service directories) — Spring Boot 4.0.x app.
6. `README.md` — what the demo shows, what to look at, expected output.

## Hard-Won Conventions (carried over from the Quarkus project)

- **Always `cd` to `SCRIPT_DIR` first.** Every `demo.sh` begins with `SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)" && cd "$SCRIPT_DIR"`.
- **Bind mounts use `:Z`** for SELinux compatibility on Fedora/RHEL.
- **Image names are fully qualified** — `docker.io/grafana/otel-lgtm:0.8.1`, not `grafana/otel-lgtm`.
- **Named volumes are root-owned in rootless podman** — use `tmpfs` + `user: root` for Grafana's data dir.
- **Use `-Dmaven.test.skip=true`** inside containers, not `-DskipTests` (the latter still compiles tests).
- **UBI9 OpenJDK defaults to Shenandoah**, not G1GC. Override explicitly only if you need a different GC for comparison.
- **Pre-pull large images** before the talk — see `pre-pull.sh`.

## See Also

- `BENCHMARKS.md` — verified numbers used in slides
- `PREREQUISITES.md` — host-side setup (Fedora, macOS)
- `docs/RECONCILIATION-PLAN.md` — step-by-step verification walkthrough for talk-day prep
- `presentation/PRESENTER-GUIDE.md` — slide-by-slide notes

## Talk Title

*Three Signals, One Story: Cloud-Native Observability with OpenTelemetry on OpenShift*
