# Demo 01 — Auto vs Manual Instrumentation

> "Auto-agent in 60 seconds."

## What this demo shows

A single Spring Boot 4.0.x service runs in three modes back-to-back. The audience sees how each mode produces traces in Tempo with **zero, identical, or extended** coverage:

1. **Baseline** — no instrumentation at all. App responds, but Tempo is empty.
2. **Auto-agent** — same JAR, same container, but launched with `-javaagent:opentelemetry-javaagent.jar`. Traces appear immediately for `/actuator/health`, JDBC if present, HTTP server, etc. **Zero code change.**
3. **Manual** — adds a custom span via the Micrometer Observation API for a business operation. Shows up as a child span with custom attributes.

## What you'll see in Grafana

- **Tempo (`Explore` → datasource `Tempo`)** — span-tree view changing as you switch modes.
- **Loki** — log lines emitted by the service, filtered by `service.name`. After mode 2, log lines carry `traceId` and `spanId`.
- **Prometheus (Metrics)** — `http_server_requests_seconds` histogram produced by the actuator endpoint.

## Files

| File | Role |
|---|---|
| `demo.sh` | Color-coded orchestrator. Runs all three modes in sequence with pauses. |
| `compose.yaml` | otel-lgtm + service container |
| `service/` | Spring Boot 4.0.x app — single endpoint `/hello`, `/work`, `/admin/inject` |
| `agent/` | Where the OTel Java agent JAR is downloaded to (gitignored) |
| `grafana/provisioning/` | Pre-loaded datasources and dashboard |

## Ports

| Service | Port |
|---|---|
| Grafana | http://localhost:3001 |
| Service | http://localhost:8081 |
| OTLP gRPC | localhost:4317 |
| OTLP HTTP | localhost:4318 |

## Running

```bash
./demo.sh           # full demo (recommended)
./demo.sh up        # start stack only
./demo.sh load      # generate traffic
./demo.sh down      # tear down
```

## Talking Points

1. **Same JAR, three behaviors.** The only difference between mode 1 and mode 2 is the `-javaagent` flag. No rebuild.
2. **Auto-instrumentation covers the seams.** HTTP, JDBC, Kafka, Redis, gRPC — about 120 instrumentations ship with the agent.
3. **Manual instrumentation is for your domain.** Use the Observation API (Spring 6+/Boot 3+) or the OTel API directly when you want spans around business logic.
4. **The hybrid model is reality.** Most production Spring Boot apps run with the agent attached *and* a few hand-instrumented spans for hot paths. That's the right shape.

## Caveats

- The OTel Java agent version is pinned in `agent/VERSION`. Bump it when there's a release worth picking up.
- Spring Boot 4.0's `ZipkinSpanExporter` is deprecated and will be removed in 4.2. We use OTLP throughout.
- On UBI9 OpenJDK 21, the default GC is **Shenandoah**, not G1GC. This is fine for this demo but worth knowing.
