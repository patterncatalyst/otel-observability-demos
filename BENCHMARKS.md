# Benchmarks — Single Source of Truth

All numbers used in slides, speaker notes, and READMEs should be sourced from this file. Update here, then propagate.

## Convention

- Run on the speaker's laptop (Fedora 40 / Apple Silicon — note which).
- Each benchmark has a date, host, and method.
- Pre-warm: 30 seconds of traffic at low rate before measurement window.
- Measurement window: 60 seconds at sustained rate unless stated.
- Tools: `hey` for REST, `ghz` for gRPC.

## Demo 02 — Correlation Pivot Latency

The headline number for the talk is **time from "metric spike" to "root cause" via the three-signal pivot**.

| Step | Approx. seconds |
|---|---|
| Notice spike on dashboard | 0–3 |
| Click exemplar dot, land in Tempo | 3–6 |
| Identify slow span | 6–10 |
| Click "logs for span", land in Loki | 10–13 |
| Read error message | 13–15 |

**Headline:** *"Fifteen seconds from anomaly to root cause."*

## Demo 04 — GC Pause Distribution (Spring Boot on UBI9)

| GC | p50 pause | p99 pause | p99.9 pause | Heap | Notes |
|---|---|---|---|---|---|
| G1GC | TBD | TBD | TBD | 512m | `-XX:+UseG1GC` |
| Shenandoah (gen) | TBD | TBD | TBD | 512m | UBI9 default, JDK 21+ |
| ZGC (gen) | TBD | TBD | TBD | 512m | `-XX:+UseZGC -XX:+ZGenerational` |

> Fill in after Demo 04 is built. Use the `jvm.gc.pause` Micrometer histogram pulled from the LGTM Prom-compatible store.

## Demo 05 — AOT Cold Start (Spring Boot on JDK 25)

| Configuration | Cold start (ms) | Time to first request (ms) |
|---|---|---|
| Classic JVM (JIT, no cache) | TBD | TBD |
| AppCDS (`-XX:SharedArchiveFile`) | TBD | TBD |
| AOTCache (JDK 25, training run) | TBD | TBD |

> Anticipated: ~3500ms classic → ~700ms AOTCache (per Spring blog references). Verify locally.

## Demo 01 — Auto-Agent Overhead

| Configuration | Startup (ms) | RPS @ 4 cores | p99 latency (ms) |
|---|---|---|---|
| No agent | TBD | TBD | TBD |
| Auto agent (default) | TBD | TBD | TBD |
| Manual instrumentation | TBD | TBD | TBD |

> Auto agent typically adds 5–10% startup time and 1–3% steady-state CPU.

## Notes for the Talk

- Always cite the date and host of the benchmark.
- Round numbers; do not over-specify ("about 700ms" not "703.2ms").
- If numbers haven't been re-verified in 60 days, re-run before a major presentation.
