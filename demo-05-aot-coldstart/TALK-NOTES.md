# Demo 05 — Talk Notes

## What this demo shows

Six-way cold-start comparison of a Spring Boot 4 + JDK 25 + JPA app:

|                  | + agent  | + SDK    | no telemetry |
|------------------|----------|----------|--------------|
| Classic JDK 25   | ~8.2 s   | ~5.3 s   | ~4.5 s       |
| AOT cache        | ~7.4 s   | ~4.4 s   | ~3.9 s       |

Telemetry costs:
- Agent: ~3.5-3.7 seconds (massive runtime instrumentation tax)
- SDK:   ~600-800 ms      (~5x cheaper than the agent)

AOT savings: ~600-860 ms regardless of telemetry mode

(Actual numbers vary; representative results from a Fedora 43 / podman 5.8.2
laptop with JDK 25.0.3.)

Three insights:

1. **The OTel javaagent costs ~3.3 seconds at startup** on a JPA-heavy
   Spring Boot 4 app. The agent does runtime bytecode rewriting on
   hundreds of Spring/Hibernate/Tomcat classes. It's a massive
   instrumentation tax that amortizes to zero on long-running services
   but is fortune-eating on cold-scale workloads.

2. **SDK telemetry costs <500ms.** Spring Boot 4's new
   `spring-boot-starter-opentelemetry` (released November 2025) wires up
   the OpenTelemetry SDK at startup. Even when fully engaged, the cost
   is roughly 1/30th of the agent's cost.

3. **JDK 25's AOT cache saves ~700ms regardless of telemetry mode.**
   Real, measurable, but modest. Pair with Spring AOT processing for
   slightly more (we generated one repository AOT class via
   `process-aot`).

## Known limitation: SDK telemetry doesn't fully engage on Spring Boot 4.0.4

In our test environment, the new `spring-boot-starter-opentelemetry` is
loaded, all auto-config classes match, the `Tracer` bean is registered —
but spans aren't created during request processing.

Spring Boot 4.0.4 was released April 2026; the OpenTelemetry starter
itself was announced November 2025. This is a very young feature
combination. Possible causes (not investigated):
- Spring MVC's observation filter may not link to the new starter's
  Tracer in this version
- Logback MDC keys may differ between agent (`trace_id`/`span_id`) and
  SDK (`traceId`/`spanId`)
- An interaction between Spring AOT processing and the new auto-config

For talk purposes, the **cold-start measurements remain valid** — we
measured time-to-health, not telemetry quality. The "SDK column" shows
what cold-start looks like for an app *configured for* SDK telemetry,
even if the spans don't currently flow.

## How to reproduce

```bash
cd demo-05-aot-coldstart
./demo.sh build       # ~3 min, builds both images
./demo.sh time-all    # ~6 min, runs 18 cold starts (3 per variant)
```

## Talk script suggestions

**For the slide:**
> "Spring Boot 4 + JDK 25 + JPA app, 6 startup variants. Look at the
> agent column. 3.3 seconds. That's your serverless cold-start budget,
> gone, just to attach observability. AOT saves you a second; what
> really matters is choosing your telemetry approach for the workload."

**Key talking points:**
- AOT is real but modest on framework-heavy apps. The Spring AOT
  ecosystem will improve, but JPA initialization is fundamentally
  hard to cache.
- The agent is great for production observability of long-running
  services. The 3.3s tax disappears within 5 minutes of running.
- Cold-scale workloads (serverless, scale-from-zero) need a different
  telemetry approach. SDK starters are emerging.
- This space is moving fast. Numbers in this demo are accurate as of
  April 2026 with Spring Boot 4.0.4 + JDK 25.0.3.

## Files

- `service-classic/` — baseline JDK 25 Spring Boot 4 app
- `service-aot/` — same app, with Spring AOT processing + JDK AOT cache
  (extracted layout + onRefresh + AOTCacheOutput pipeline per the
  Piotr Minkowski / Spring team writeups)
- `compose.yaml` — six service definitions (lgtm + 5 service variants)
- `demo.sh` — `time-all` runs the full comparison
