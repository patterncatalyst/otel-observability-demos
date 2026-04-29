# Demo 02 — Three-Signal Correlation

> "Fifteen seconds from anomaly to root cause."

## What this demo shows

The headline demo of the talk. Two Spring Boot services — `order-service` and `inventory-service` — are auto-instrumented and emit metrics, logs, and traces to a single LGTM stack. With a fault injected on `inventory-service`, the audience watches the operator pivot **metric → trace → log** in Grafana to find the root cause in well under a minute.

The five-step pivot:

1. p99 latency dashboard spikes
2. Click an **exemplar dot** on the histogram → Tempo opens on the slow trace
3. Drill into the trace, find the span where time was spent
4. Click "**Logs for this span**" → Loki query auto-runs filtered by `traceId`
5. Read the error log, identify the cause

## Architecture

```
              ┌──────────────────┐
              │  order-service   │  GET /orders/random
              │   :8082          │      │
              └─────────┬────────┘      │
                        │ HTTP          ▼
                        ▼          (audience hits this)
              ┌──────────────────┐
              │ inventory-service│  /admin/inject toggles latency + errors
              │   :8092          │
              └─────────┬────────┘
                        │
                        ▼  OTLP traces / metrics / logs
              ┌──────────────────┐
              │   otel-lgtm      │  Grafana :3002, Tempo, Loki, Prom
              └──────────────────┘
```

Both services are auto-instrumented via the OTel Java agent. Logs are emitted with `traceId` in the MDC so Loki can find them via the derived field.

## Files

| File | Role |
|---|---|
| `demo.sh` | Color-coded orchestrator. Generates traffic, injects fault, narrates pivot. |
| `compose.yaml` | otel-lgtm + order-service + inventory-service |
| `order-service/` | Spring Boot 4.0.x — calls inventory-service |
| `inventory-service/` | Spring Boot 4.0.x — accepts `/admin/inject` to toggle fault |
| `grafana/provisioning/` | Datasources (with trace↔log links), correlation dashboard |

## Ports

| Service | Port |
|---|---|
| Grafana | http://localhost:3002 |
| order-service | http://localhost:8082 |
| inventory-service | http://localhost:8092 |
| OTLP gRPC | localhost:14317 |
| OTLP HTTP | localhost:14318 |

## Running

```bash
./demo.sh           # full demo (recommended) — runs the fault injection sequence
./demo.sh up        # start stack only
./demo.sh load      # generate baseline traffic
./demo.sh inject    # turn fault on
./demo.sh clear     # turn fault off
./demo.sh down      # tear down
```

## Live Demo Choreography

The whole thing lives or dies on the dashboard pivot. Practice this sequence:

1. **Start `demo.sh`** — stack comes up, baseline traffic is generated, dashboard tab is opened.
2. **Show baseline** — flat p99, no errors, both services healthy in the trace map. ~30 seconds.
3. **Inject fault** — when prompted, `demo.sh` calls `/admin/inject`. p99 immediately starts climbing.
4. **The pivot** — once the spike is visible (~10 seconds after injection):
   - Hover the histogram, find an exemplar dot at the top
   - Click → Tempo opens
   - Trace shows order-service → inventory-service with a long `findStock` span
   - Click "Logs for this span" → Loki shows the error
5. **Recap and clear** — `demo.sh clear` stops injection; latency returns.

## Talking Points

1. **Three signals, one identifier.** The traceId is what makes the pivot work — it's on the metric exemplar, in the trace itself, and in every log line via the MDC.
2. **Exemplars are the bridge.** Histogram exemplars are the killer feature most teams forget to enable. One Spring Boot property: `management.metrics.distribution.percentiles-histogram.http.server.requests=true`.
3. **Auto-instrumentation gets you 90% there.** No custom code in either service exports the trace context across the HTTP call — the agent does it.
4. **The Collector is still optional here.** otel-lgtm has one built-in. Demo 03 is when we add an external Collector for sampling.

## Caveats

- Exemplars require the histogram to be configured server-side AND the dashboard's PromQL query to use `exemplar: true`. Both are pre-set in the provisioned dashboard.
- The `traceparent` header propagates over Spring Boot's `RestTemplate` / `RestClient` automatically thanks to Micrometer Observation. Old `RestTemplate` interceptors used to be required — they aren't anymore.
- Logback's `%X{traceId}` works because Spring Boot 4.0.x's auto-config installs the MDC-correlated tracing pattern when `micrometer-tracing-bridge-otel` is on the classpath.
