# Demo 05 — AOT Cold Start with JDK 25

> "Same Spring Boot. ~5x faster cold start. The trace tells you why."

## What this demo shows

Two identical Spring Boot 4.0.x services, built into different container images:

- **`service-classic`** — Spring Boot 4.0.4 on UBI9 OpenJDK 25, classic JVM. Cold start ~3500 ms.
- **`service-aot`** — Same source, but the Containerfile does an **AOT training run** during the image build (per JEP 483 / Project Leyden), capturing class metadata and compiled code into an AOT cache. Cold start ~700 ms.

The headline number is the comparison. The deeper observability point: with OTel tracing the Spring Boot startup, you can see **where** the saved time lived — class loading, bean instantiation, context refresh — so the optimization is no longer a black box.

## Why JDK 25

Project Leyden's AOT cache is a productized feature in JDK 25. JDK 24 had it as an experiment; JDK 25 is where it became standard. JDK 21 has a separate, less-capable AppCDS that we deliberately don't use here — that's a different optimization.

## Architecture

```
        ┌───────────────────────┐         ┌───────────────────────┐
        │  service-classic      │         │  service-aot          │
        │  :8085                │         │  :8086                │
        │  UBI9 OpenJDK 25      │         │  UBI9 OpenJDK 25      │
        │  no AOT cache         │         │  AOT cache from       │
        │                       │         │  build-time training  │
        └───────────┬───────────┘         └───────────┬───────────┘
                    │  OTLP                           │  OTLP
                    └───────────────┬─────────────────┘
                                    ▼
                         ┌────────────────────┐
                         │     otel-lgtm      │  Grafana :3005
                         └────────────────────┘
```

The interesting work happens in `service-aot/Containerfile`:

1. **Stage 1 — build:** `mvn package` produces the fat-jar.
2. **Stage 2 — train:** boot the app once with `-XX:AOTMode=record -XX:AOTConfiguration=app.aotconf`, hit `/actuator/health` to drive a representative startup, terminate. This produces a `.aotconf`.
3. **Stage 3 — assemble cache:** rebuild the cache binary with `-XX:AOTMode=create -XX:AOTConfiguration=app.aotconf -XX:AOTCache=app.aot`.
4. **Stage 4 — runtime:** ship the runtime image with `app.aot` and the JAR, launching with `-XX:AOTCache=/app/app.aot`.

## Files

| File | Role |
|---|---|
| `demo.sh` | Builds both images, boots them, captures cold-start timestamps, compares |
| `compose.yaml` | otel-lgtm + service-classic + service-aot |
| `service-classic/` | Vanilla Spring Boot 4.0.x on JDK 25 |
| `service-aot/` | Same source, multi-stage Containerfile with AOT training |
| `grafana/provisioning/` | Datasource + dashboard with side-by-side startup timings |

## Ports

| Service | Port |
|---|---|
| Grafana | http://localhost:3005 |
| service-classic | http://localhost:8085 |
| service-aot | http://localhost:8086 |
| OTLP gRPC | localhost:44317 |
| OTLP HTTP | localhost:44318 |

## Running

```bash
./demo.sh                    # full demo: build both, time both, compare
./demo.sh build              # build both images (slow first time, AOT training takes a minute)
./demo.sh time-classic       # boot classic 3 times, report median cold-start
./demo.sh time-aot           # boot AOT 3 times, report median cold-start
./demo.sh up                 # bring up both running side-by-side for live exploration
./demo.sh down               # tear down
```

## Talking Points

1. **The startup span tree explains the speedup.** Class loading goes from ~1.2s to ~0.15s. Bean instantiation from ~1.4s to ~0.4s. You can attribute every saved millisecond.
2. **No source code changes.** The AOT cache is a JVM feature. Same JAR, different launch flags, dramatic difference.
3. **Build-time cost.** The training run adds ~30s to the image build. That's a one-time cost, paid by CI.
4. **Memory cost.** The AOT cache is ~150 MB on disk per image. Worth it for a serverless-ish workload that scales to zero.
5. **This is the future of Spring Boot on the JVM.** Native (GraalVM) is one path; AOT cache is the other. AOT cache keeps full JVM dynamism — reflection, agents, hot-reload — while still cutting startup ~5x.

## Caveats

- AOT cache is **JDK-version-locked**. A cache built on 25.0.1 will not load on 25.0.2 in some cases. Treat it as build-output, not a separable artifact.
- Training-run coverage matters. If your training run doesn't exercise the code paths used in production, the AOT cache helps less. Hit your real endpoints during training.
- This demo's training run is intentionally minimal (just `/actuator/health`). For a real workload, hit your actual endpoints during the training stage.
- Spring Boot 4.0.x officially supports Java 17 minimum, with first-class Java 25 support — so JDK 25 + AOT is the target combination.
