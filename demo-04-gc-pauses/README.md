# Demo 04 — GC Pauses as Trace Gaps

> "The JVM stalled for 50ms. The trace shows it. The metric shows it. The dashboard tells you both at once."

## What this demo shows

A Spring Boot service is pushed into heap allocation pressure via an `/allocate` endpoint. Garbage collection pauses ripple through the running HTTP requests as **gaps in trace spans** while simultaneously showing as `jvm.gc.pause` histogram spikes in Prometheus.

The core point: observability sees **across** the JVM/app boundary. The pause is in the runtime, the affected span is in your code, and the same dashboard shows both. Pre-OTel, you'd correlate this in your head from two different tools.

The demo is also the **GC comparison** that powers the Shenandoah bonus content. The same workload runs against three GC configurations:

| GC | Run via | Expected p99 pause |
|---|---|---|
| Shenandoah (UBI9 default) | `./demo.sh run shenandoah` | ~5–10 ms |
| G1GC | `./demo.sh run g1` | ~50–100 ms |
| ZGC (generational) | `./demo.sh run zgc` | < 1 ms |

The dashboard side-by-side is the bonus-slide story.

## Files

| File | Role |
|---|---|
| `demo.sh` | Color-coded orchestrator. `run <gc>` switches GC and re-runs the workload. |
| `compose.yaml` | otel-lgtm + service. `JAVA_TOOL_OPTIONS` is templated by `demo.sh`. |
| `service/` | Spring Boot 4.0.x — `/allocate` endpoint creates heap pressure |
| `grafana/provisioning/` | Datasources + GC dashboard correlating pauses with trace gaps |

## Ports

| Service | Port |
|---|---|
| Grafana | http://localhost:3004 |
| Service | http://localhost:8084 |
| OTLP gRPC | localhost:34317 |
| OTLP HTTP | localhost:34318 |

## Running

```bash
./demo.sh                    # full demo: all three GCs in sequence
./demo.sh run shenandoah     # UBI default — leaves -XX flags alone
./demo.sh run g1             # explicitly -XX:+UseG1GC
./demo.sh run zgc            # explicitly -XX:+UseZGC -XX:+ZGenerational
./demo.sh load               # generate workload at current GC config
./demo.sh down               # tear down
```

## Talking Points

1. **The JVM emits GC metrics for free.** Micrometer registers `jvm.gc.pause` and `jvm.memory.used` as histograms automatically — no instrumentation code.
2. **Trace gaps are GC pauses you can see.** When a 50ms G1 pause hits mid-request, the trace span has a 50ms unaccounted gap. Tempo's flame graph shows it as empty time.
3. **Same workload, different GCs, very different p99.** This is the empirical evidence behind the Shenandoah bonus slides.
4. **UBI9's default = Shenandoah.** No flag flipped. Every other major OpenJDK distribution defaults to G1.

## Caveats

- Real-world GC tuning is workload-dependent. These numbers are representative for typical Spring Boot HTTP serving — your throughput-bound batch job may reach different conclusions.
- ZGC uses ~15% more memory than Shenandoah for the same heap size. The pause-time win has a memory cost.
- Generational ZGC is opt-in (`-XX:+ZGenerational`) on JDK 21; standard on JDK 25.
- Generational Shenandoah is the default mode on JDK 21+ in UBI9 OpenJDK.
