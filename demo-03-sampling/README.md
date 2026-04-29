# Demo 03 — Head vs Tail Sampling

> "Keep what matters. Drop the rest."

## What this demo shows

Sampling is the cost lever in observability. This demo introduces the **standalone OTel Collector** as a separate container in the pipeline (vs demos 01 and 02 which sent directly to otel-lgtm's built-in Collector) and shows two policies side-by-side:

1. **Head sampling at the app** — `parentbased_traceidratio=0.05` (keep 5% deterministically). 95% of traces are dropped before they ever leave the JVM.
2. **Tail sampling at the Collector** — app sends 100%, the Collector buffers full traces and applies smart policies: keep all errors, keep all slow traces, keep 5% of healthy ones.

The audience sees the difference in Tempo's trace counts and in *which* traces survived.

## Architecture

```
                            ┌────────────────┐
                            │    service     │  /work, /work/error, /work/slow
                            │     :8083      │
                            └────────┬───────┘
                                     │ OTLP 100%
                                     ▼
                            ┌────────────────────────┐
                            │  OTel Collector        │  ← config-head.yaml
                            │  (standalone)          │  ← config-tail.yaml  ← swap to compare
                            │  :4317 / :4318         │
                            └────────┬───────────────┘
                                     │ OTLP forward
                                     ▼
                            ┌────────────────┐
                            │   otel-lgtm    │  Grafana :3003
                            └────────────────┘
```

The Collector is configured via a bind-mounted YAML. The `demo.sh` driver swaps between `config-head.yaml` and `config-tail.yaml` and restarts the Collector container — the service stays running.

## Files

| File | Role |
|---|---|
| `demo.sh` | Color-coded orchestrator. Swaps Collector config, generates traffic, compares Tempo counts. |
| `compose.yaml` | otel-lgtm + standalone Collector + service |
| `service/` | Spring Boot 4.0.x — endpoints producing fast / slow / errored traces |
| `otelcol/config-head.yaml` | App-side head sampling: `parentbased_traceidratio=0.05` |
| `otelcol/config-tail.yaml` | Collector-side `tail_sampling` processor |
| `grafana/provisioning/` | Datasources + dashboard showing trace counts by status |

## Ports

| Service | Port |
|---|---|
| Grafana | http://localhost:3003 |
| Service | http://localhost:8083 |
| Collector OTLP gRPC | localhost:24317 |
| Collector OTLP HTTP | localhost:24318 |

## Running

```bash
./demo.sh                # full demo (recommended) — runs both modes back-to-back
./demo.sh up             # start stack only (defaults to head config)
./demo.sh switch head    # swap to head sampling
./demo.sh switch tail    # swap to tail sampling
./demo.sh load           # generate traffic mix
./demo.sh down           # tear down
```

## Talking Points

1. **Where you sample matters more than how much.** Head sampling at the app is cheap but blind. Tail sampling at the Collector is smart but costs RAM proportional to your trace duration × span rate.
2. **The combo is what production looks like.** Head sample at the app to control traffic to the Collector; tail sample at the gateway to keep the interesting traces.
3. **`parentbased`** — both policies respect the upstream sampling decision, which is why distributed traces stay coherent (no half-traces across services).
4. **Cost discipline.** A 1k RPS service with 100% trace volume × 5KB/trace × 30 days = ~13TB. Tail sampling at 5% with full retention of errors typically cuts that by 90%+ while preserving exactly the traces you'll actually look at.

## Caveats

- Tail sampling requires the Collector to wait for all spans of a trace to arrive. The default `decision_wait` is 30s. Spans arriving after the decision are dropped silently.
- The `tail_sampling` processor lives in the **contrib** distribution of the Collector, not core. We use the `otel/opentelemetry-collector-contrib` image.
- Buffering full traces means the Collector is no longer stateless. Plan for restart-induced trace loss; a deployment with replicas needs a load balancer with traceID-based routing (`loadbalancing` exporter).
