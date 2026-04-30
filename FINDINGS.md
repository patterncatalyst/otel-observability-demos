# Engineering Findings — JVM + OpenTelemetry + Containers

A working document of hard-won lessons from building five end-to-end observability demos on a single laptop. Each finding documents what we tried, what failed, what worked, and why — written so other projects can avoid the same potholes.

The findings here are mostly framework-agnostic, but examples cite the `otel-observability-demos` repository where concrete file paths help.

---

## How to use this document

This is organized by *where you'd be when you hit the problem*: building containers, running them, wiring up telemetry, debugging the JVM, measuring performance, or thinking architecturally. Each section is self-contained — you don't need to read in order.

If you're in active debugging mode, jump straight to **Quick reference** at the bottom for the five highest-leverage findings.

---

## Section 1: Container build patterns

### 1.1 Spring Boot's fat JAR breaks AOT cache

Spring Boot's default `spring-boot-maven-plugin` builds a fat JAR — your application classes plus all dependencies, all nested inside one archive, loaded by Spring Boot's custom `LaunchedClassLoader`. This worked beautifully for fifteen years. JDK 25's AOT cache (JEP 514) breaks the convention.

When we first tried building an AOT cache for a Spring Boot 4 app, we ran the recommended training command:

```bash
java -XX:AOTCacheOutput=app.aot -jar build/libs/app.jar
```

The cache wrote successfully — about 80 MB. At runtime:

```
[error][cds] An error has occurred while processing the AOT cache.
[error][cds] Class space verification failed
```

The JDK's AOT mechanism reads classes through the JVM's standard system classloader, but Spring Boot's nested classloader hides classes inside the fat JAR. The cache captured what the JDK could see; at runtime, the actual class loading went through Spring Boot's classloader, and the cache's class identities didn't match.

**The fix:** extract the fat JAR before building the cache. Spring Boot's `tools` jarmode does this:

```bash
java -Djarmode=tools -jar app.jar extract
# Produces a flat layout in extracted/:
#   extracted/app.jar           (your app, no nested deps)
#   extracted/lib/*.jar         (each dependency as a separate JAR)
#   extracted/META-INF/...
```

Now the JDK sees a normal classpath. The training run captures real class identities. The cache loads correctly at runtime.

This means Spring Boot AOT containerfiles need a four-stage build:

1. **Build** — `mvn package` produces the fat JAR
2. **Extract** — `java -Djarmode=tools extract` produces a flat layout
3. **Train** — boot the extracted app with `-XX:AOTCacheOutput=app.aot`, exit cleanly
4. **Runtime** — ship extracted layout + cache, launch with `-XX:AOTCache=app.aot`

The Containerfile in `demo-05-aot-coldstart/service-aot/Containerfile` shows this end-to-end.

### 1.2 The `spring.context.exit=onRefresh` trick

Once you have the extracted layout, you still need a *clean* exit during training. AOT cache writes happen at JVM shutdown — but Spring Boot apps don't typically shut down cleanly on their own; they wait for SIGTERM. Sending SIGTERM during training risks shutting down before the bean factory is fully populated, and you get a partially-trained cache that performs worse than no cache at all.

Piotr Minkowski's writeup (March 2026) documents the cleanest solution:

```bash
java -XX:AOTCacheOutput=app.aot \
     -Dspring.context.exit=onRefresh \
     -jar app.jar
```

The `spring.context.exit=onRefresh` property tells Spring to exit immediately after the application context is refreshed — that is, after every bean is instantiated and dependencies are resolved, but before any `ApplicationRunner` or web server start. The JVM exits cleanly. The cache captures a fully-populated bean factory.

We tried two earlier approaches before landing on this:

- **`curl /shutdown` against actuator** — works but requires actuator endpoint to be enabled and the order of operations is fragile (need to wait for ready, then call shutdown). Several extra seconds and several places to fail.
- **Sending SIGTERM after a fixed sleep** — works on fast machines, racy on slow ones. Slow CI runners gave us caches captured before JPA initialization completed.

`onRefresh` is fast (no need to wait for HTTP server to start), deterministic (always exits at the same lifecycle point), and produces the most useful cache content (the bean factory is fully populated, just not yet *running*).

### 1.3 Quarkus's training is built into Maven

Quarkus's approach to AOT cache training is fundamentally different and worth understanding even if you're not using Quarkus — it shows what "training as a first-class concept" looks like.

In Quarkus, you set one property in `application.properties`:

```properties
quarkus.package.jar.aot.enabled=true
```

Then `mvn verify` does the entire training pipeline:

1. Builds the application (the standard build phase)
2. Packages it into `target/quarkus-app/` (Quarkus's flat layout — no fat JAR, no extraction needed)
3. **Runs your `@QuarkusIntegrationTest` tests against the packaged application**, with `-XX:AOTCacheOutput` configured automatically
4. The integration tests serve as the AOT training workload — they exercise the application's real endpoints
5. Writes `target/quarkus-app/app.aot` on shutdown

The key insight: `@QuarkusIntegrationTest` runs against the *packaged* JAR, not the dev-mode classpath. It boots a real instance, hits real endpoints, then shuts down. That's exactly what an AOT training run should do. The Quarkus Maven plugin orchestrates the whole thing transparently.

The lesson: if you're designing a framework that wants to support AOT cache, build training into the test/package lifecycle. Don't make it a separate step the user has to learn and orchestrate.

### 1.4 The JVM build-ID matching trap (3-stage Containerfiles)

This one cost us most of an evening to diagnose. Here's the symptom:

You build a multi-stage Dockerfile. Stage 1 uses `maven:3.9-eclipse-temurin-25` to compile (Temurin OpenJDK 25). Stage 2 uses `registry.access.redhat.com/ubi9/openjdk-25` to run the application at runtime. Both are JDK 25. Same major and minor versions. Should be interchangeable.

You run `mvn verify` in the Maven stage to do the AOT training. The cache writes successfully. You build the runtime image. You boot it. You see:

```
[warning][aot] Unable to use AOT cache.
[error  ][aot] An error has occurred while processing the AOT cache.
[error  ][aot] Loading static archive failed.
[error  ][aot] Unable to map shared spaces
```

What's happening: the AOT cache embeds the JVM's *build identifier* — a fingerprint of the specific JVM binary that wrote it. This is stricter than version matching. Temurin's JDK 25 build and Red Hat's UBI OpenJDK 25 build have different build IDs even though they're both JDK 25.0.3. The cache rejects mismatches.

The reason this is strict: AOT cache contains memory layouts, addresses, and method dispatch tables that depend on the exact JVM build's internal data structures. Even patch-level differences can shift these. A "close enough" runtime would crash subtly during execution rather than visibly at load time. Strict rejection at load time is the right call.

**The fix: training JVM must equal runtime JVM.**

For Quarkus + Leyden, that means a 3-stage build:

```dockerfile
# Stage 1: Compile only (Temurin Maven for build tooling convenience)
FROM docker.io/library/maven:3.9-eclipse-temurin-25 AS compiler
WORKDIR /build
COPY pom.xml .
COPY src ./src
RUN mvn package -Dmaven.test.skip=true --no-transfer-progress

# Stage 2: Train with UBI JDK 25 (same JVM that will run at runtime)
FROM registry.access.redhat.com/ubi9/openjdk-25 AS trainer
USER root
WORKDIR /build
COPY --from=compiler /build /build
COPY --from=compiler /root/.m2 /root/.m2
RUN mvn verify --no-transfer-progress \
    -Dmaven.repo.local=/root/.m2 \
    -Dquarkus.package.jar.aot.enabled=true \
    -DskipITs=false

# Stage 3: Runtime (same JVM build as trainer)
FROM registry.access.redhat.com/ubi9/openjdk-25
COPY --from=trainer /build/target/quarkus-app/ /deployments/
```

Three observations:

1. The compile stage *can* use a different JVM, because compilation produces bytecode that's portable across JVM builds. Only the training and runtime JVMs need to match.
2. The `:1.24` and `:latest` tags on Red Hat UBI images may resolve to the same image ID, but you should pin specifically to avoid silent drift if Red Hat ships a `:1.24-2` mid-build.
3. If your build environment doesn't easily support multi-stage builds with two different base images, you can do everything in one stage with the runtime JVM. It's slower (need Maven installed in runtime image) but works.

### 1.5 Why training and runtime should match memory limits too

A subtler corollary of build-ID matching: AOT cache captures JVM internals that are sensitive to *runtime configuration*, not just JVM version. The most painful example is heap layout.

If you train with one heap size and run with another, the cache may fail to load even though the JVM build matches. This particularly bites with `-XX:MaxRAMPercentage`, which depends on detected memory at *that moment* — different in the trainer container than the runtime container.

For Spring Boot AOT cache work, we landed on training with the same memory configuration as runtime. For Quarkus, the issue is more dramatic and gets its own section below (compressed oops).

The general rule: **whatever JVM flags affect memory or pointer layout, set them identically in training and runtime.**

---

## Section 2: Container runtime configuration

### 2.1 The compressed-oops trap (and why Quarkus needed `mem_limit`)

This was the single hardest bug we hit, and it has a specific signature worth memorizing.

We built the Quarkus + Leyden image successfully. The training stage ran cleanly. The 53 MB `app.aot` file was present in the runtime image. We started the container:

```
[warning][aot] Unable to use AOT cache.
[warning][aot] The saved state of UseCompressedOops and UseCompressedClassPointers is different from runtime, CDS will be disabled.
[error  ][aot] Loading static archive failed.
[error  ][aot] Unable to map shared spaces
```

The diagnostic message is buried in `[info][aot]` output (only visible with `-Xlog:aot`):

```
[info][aot] UseCompressedOops and UseCompressedClassPointers have been disabled
            due to max heap 50111784960 > compressed oop heap 32178700288.
            Please check the setting of MaxRAMPercentage 75.00.
```

**What was happening:**

The HotSpot JVM uses *compressed object pointers* — 32-bit references instead of 64-bit — when the heap fits within ~32 GB. This saves significant memory and improves cache utilization. Above 32 GB, compressed oops can't address the entire heap, so the JVM falls back to 64-bit references.

When we built the AOT cache during training, the trainer container had access to the host's full memory (~64 GB). With `-XX:MaxRAMPercentage=75.0`, that's a 48 GB heap ceiling. *Above* the compressed-oop threshold. So the trainer JVM ran with compressed oops *disabled*.

When we ran the runtime container, also without memory limits, same situation: 75% of 64 GB is 48 GB max heap, compressed oops disabled.

Should have worked, right? Both training and runtime had the same configuration.

But here's the kicker: the AOT cache was actually built with compressed oops *enabled*, because Quarkus's Maven plugin runs the integration tests in a JVM with default heap settings (`-Xmx256m` or so), where compressed oops are absolutely active. So:

- Cache built with: compressed oops enabled (small heap from Maven test runner)
- Runtime: compressed oops disabled (large heap from MaxRAMPercentage=75 against host RAM)

Mismatch. Cache rejected.

**The fix: cap container memory.**

We added `mem_limit: 512m` to the Quarkus services in `compose.yaml`:

```yaml
service-quarkus-leyden:
  image: otel-demo-05-service-quarkus-leyden
  mem_limit: 512m
  # ...
```

With memory capped at 512 MB, MaxRAMPercentage=75 produces a 384 MB heap. Way below the compressed-oop threshold. The runtime JVM activates compressed oops. The cache loads correctly.

**Why the same fix isn't needed for Spring Boot:** Spring Boot's AOT cache is built differently. We do the training run inside the Containerfile with explicit JVM flags, so we control exactly what configuration the cache captures. Quarkus's training happens via `mvn verify` in the Maven plugin, where we don't directly control JVM flags — the test runner picks defaults. The fix is to align *runtime* with the test-runner defaults, not the other way around.

**Why we kept the asymmetry (no `mem_limit` on Spring Boot):** It's itself a finding. Spring Boot 4 with all its dependencies needs ~500 MB to start cleanly, sometimes more under load. Capping it at 512 MB causes occasional OOM. Quarkus boots and runs fine in 512 MB. That asymmetry — Quarkus runs in a fraction of the memory — is part of the talk's "framework, not vendor" thesis.

### 2.2 Healthcheck timing: `start_period` matters more than `interval`

The default Docker / Compose healthcheck behavior is to start polling immediately, fail fast, and report unhealthy after a few failed attempts. For typical short-lived services this is fine. For Spring Boot apps that take 4+ seconds to start, the default behavior reports the container unhealthy *while it's still booting normally*, which then breaks dependent service ordering.

The fix is `start_period`:

```yaml
healthcheck:
  test: ["CMD", "curl", "-sf", "http://localhost:8080/actuator/health"]
  interval: 2s
  timeout: 2s
  retries: 60
  start_period: 30s    # ← grace period before health failures count
```

`start_period` tells Docker: "during this initial window, failures don't count. After this window, normal health-check rules apply."

Numbers we landed on:

- `start_period: 30s` for Spring Boot apps (covers cold starts up to 30 seconds)
- `start_period: 5s` for Quarkus apps (boots well under 1 second)
- `interval: 2s` everywhere — fast enough to catch issues, not so fast it spams logs
- `retries: 60` — generous, since the cost of a false unhealthy is much worse than the cost of waiting

### 2.3 Healthcheck path conventions differ across frameworks

Trivially obvious but easy to forget when refactoring a timing harness:

- **Spring Boot Actuator**: `/actuator/health` (configurable, but conventional)
- **Quarkus SmallRye Health**: `/q/health/live` (configurable to `/health/live` if you set `quarkus.smallrye-health.root-path`)
- **Micronaut**: `/health` 
- **Quarkus Web Application Bundle**: depends on whether you have `smallrye-health` extension

If you write timing scripts that poll for HTTP readiness, parameterize the health path. Our `time_one_boot()` function takes the path as an argument. Don't hard-code `/actuator/health` — you'll forget about it the first time you add a non-Spring service.

### 2.4 OTLP endpoint configuration: service names, not localhost

When two containers in the same compose network need to communicate, the OTLP exporter URL on the application side should use the *service name* of the receiver, not `localhost`:

```yaml
# WRONG - app can't see the collector at localhost
environment:
  OTEL_EXPORTER_OTLP_ENDPOINT: "http://localhost:4318"

# RIGHT - app reaches the collector via Docker network DNS
environment:
  OTEL_EXPORTER_OTLP_ENDPOINT: "http://lgtm:4318"  # 'lgtm' is the service name in compose.yaml
```

This catches people coming from local-machine development where `localhost` works. In a compose network, `localhost` inside one container points to that container, not to the host or to other containers. Always use service names.

When the user *does* need to query the OTLP endpoint from the host (e.g., a script that runs from your laptop and shouldn't go through compose networking), use `localhost:4318` — that's fine because the compose port mapping forwards it.

### 2.5 SELinux and the `:Z` flag (Fedora-specific)

On Fedora and other SELinux-enforcing distributions, bind-mounting host directories into containers requires the `:Z` flag in the volume mount:

```yaml
volumes:
  - ./otelcol:/etc/otelcol-contrib:Z
```

Without it, the container can't read the mounted files even though the file permissions look correct. The symptom is `permission denied` errors at startup, often misleading.

What `:Z` does: relabels the host directory's SELinux context to one that the container can access. The "shared" alternative is `:z` (lowercase), which is appropriate for volumes used by multiple containers. We almost always want `:Z`.

This is a cross-cutting issue: every demo's compose.yaml has `:Z` on its config-file mounts. Forgetting it on Fedora produces immediate startup failures; on Ubuntu / macOS, the flag is a harmless no-op.

---

## Section 3: OpenTelemetry instrumentation

### 3.1 Agent vs SDK starter: a real choice now

Until Spring Boot 4.0 (November 2025), there was no real choice for OpenTelemetry on Spring Boot: you used the OTel Java agent. The agent attaches at JVM startup, rewrites bytecode of hundreds of classes (Tomcat connectors, Spring MVC handlers, Hibernate session factories), and instruments everything automatically. Massive coverage, minimal application code change.

Spring Boot 4 ships `spring-boot-starter-opentelemetry`, which uses the OpenTelemetry SDK directly. It hooks into Spring's existing observability infrastructure (Micrometer Tracing) and produces equivalent telemetry without bytecode rewriting.

The cold-start cost difference is real and significant. From our Demo 05 measurements:

| Configuration | Cold start | Cost vs no-telemetry |
|---|---|---|
| No telemetry | 3954 ms | (baseline) |
| + SDK starter | 4013 ms | +59 ms |
| + Java agent | 4733 ms | +779 ms |

The agent's runtime instrumentation costs ~750 ms at startup. The SDK starter costs ~50 ms — roughly 1/15th the cost.

**When to use which:**

- **Long-running services** (microservices, traditional web apps that boot once and serve for hours/days): the agent's startup cost is irrelevant. The agent's automatic instrumentation coverage is unmatched. Use the agent.

- **Cold-scale workloads** (serverless, scale-from-zero, edge, FaaS): 750 ms is your entire startup budget. Use the SDK starter, accept the smaller instrumentation surface.

- **You want vendor neutrality and explicit control over what's instrumented**: use the SDK. The agent's auto-instrumentation can be hard to selectively disable.

This is more nuance than "use the agent" or "use the SDK" — match the choice to the workload's startup sensitivity.

### 3.2 Spring Boot 4 SDK starter: still maturing (as of April 2026)

A finding worth its own section: in our environment, Spring Boot 4.0.4's `spring-boot-starter-opentelemetry` registers all the OpenTelemetry auto-configuration beans correctly, but spans aren't actually created during request processing.

We verified the auto-config:
- `OpenTelemetrySdkAutoConfiguration` matched
- `OpenTelemetryTracingAutoConfiguration` matched and created the `micrometerOtelTracer` bean
- `MicrometerTracingAutoConfiguration` matched

We confirmed the OTLP exporter endpoint was configured. We tested with `SPRING_AOT_ENABLED=false` to rule out Spring AOT processing. We checked Tempo for traces — zero. We checked logs for trace IDs — empty MDC.

The auto-configuration sets up the `Tracer` bean, but Spring MVC's request observation filter doesn't appear to use it for span creation. Possible causes (not investigated to root cause):

- The new starter and Spring MVC observation may have integration code that's not yet wired in 4.0.4
- Logback MDC integration may use different keys (`traceId` / `spanId` camelCase) than expected (`trace_id` / `span_id` snake_case)
- An edge case with the new OTel starter's bean lifecycle vs. Spring MVC's filter chain

The starter was announced November 2025; we tested April 2026 — about five months old. This kind of integration gap is normal for very young features.

**For the talk's purposes:** cold-start timing remained valid (we measure time-to-startup, not telemetry quality). We documented this as a "the SDK column shows cold start *configured for* SDK telemetry, even though traces don't currently flow." Honest framing.

**For your projects:** if you're considering migrating from the OTel agent to the SDK starter, test trace emission end-to-end before committing. Don't assume "auto-configuration matched" means "telemetry works." This will likely improve in subsequent Spring Boot 4.x releases.

### 3.3 Spring Boot 4 OpenTelemetry property paths shifted

A nasty gotcha when migrating: the property paths for OpenTelemetry configuration changed in Spring Boot 4.

**Spring Boot 3 (with `micrometer-tracing-bridge-otel`):**

```yaml
management:
  otlp:
    tracing:
      endpoint: http://localhost:4318/v1/traces
```

**Spring Boot 4 (with `spring-boot-starter-opentelemetry`):**

```yaml
management:
  opentelemetry:
    tracing:
      export:
        otlp:
          endpoint: http://localhost:4318/v1/traces
```

The corresponding environment variable also changed:

```bash
# Spring Boot 3
MANAGEMENT_OTLP_TRACING_ENDPOINT=http://lgtm:4318/v1/traces

# Spring Boot 4
MANAGEMENT_OPENTELEMETRY_TRACING_EXPORT_OTLP_ENDPOINT=http://lgtm:4318/v1/traces
```

If you set the Spring Boot 3 path on Spring Boot 4, nothing happens — no error, no warning, the config is silently ignored. The OTLP endpoint defaults to `localhost:4317` (gRPC) and the export silently fails.

We hit this on the first Spring Boot 4 SDK probe and spent 30 minutes wondering why no telemetry was reaching Tempo. Set the environment variable to the new path and traces appeared (at least, before we hit the deeper SDK maturity issue documented above).

### 3.4 Quarkus's native OTel approach

Worth knowing as a counterpoint. Quarkus has a `quarkus-opentelemetry` extension that provides similar functionality to Spring Boot 4's SDK starter, but built on Quarkus's build-time framework. Unlike Spring Boot, it's been mature for years.

To enable, add to `pom.xml`:

```xml
<dependency>
    <groupId>io.quarkus</groupId>
    <artifactId>quarkus-opentelemetry</artifactId>
</dependency>
```

And to `application.properties`:

```properties
quarkus.otel.exporter.otlp.endpoint=http://lgtm:4318
quarkus.otel.exporter.otlp.protocol=http/protobuf
```

That's it. No agent, no extra Containerfile complexity. Quarkus's build-time wiring inserts span creation around CDI beans, REST resources, and JDBC calls during compilation. The runtime cost is comparable to Spring Boot 4's SDK starter — under 100 ms — but the engagement is reliable.

The pattern: when a framework is designed around build-time wiring, OTel integration is typically more polished than retrofitted SDK starters. This is a moat that takes years to build, and Spring is in the early years of building it.

### 3.5 Logback MDC for trace-id correlation

For trace context to appear in logs, the application's logging needs to read it from the active span context. With OpenTelemetry on the JVM, this is the OTel agent's `LogbackMdcInstrumentation` (built in) or a manual MDC integration.

The minimum log pattern to see trace context:

```xml
<encoder>
    <pattern>%d{HH:mm:ss.SSS} %-5level [%thread] %logger - %msg [trace_id=%X{trace_id} span_id=%X{span_id}]%n</pattern>
</encoder>
```

The `%X{trace_id}` reads the MDC entry named `trace_id`. With the OTel agent attached, this is populated automatically for every log line emitted within an active span context. With the SDK starter, *you may need to add explicit configuration* — this is one of the integration gaps in Spring Boot 4.0.4.

A subtle gotcha: different instrumentations use different MDC keys. The OTel agent uses `trace_id` and `span_id` (snake_case). Some Micrometer Tracing integrations use `traceId` and `spanId` (camelCase). If your log lines have empty trace IDs, check which keys the active instrumentation populates and align your log pattern.

---

## Section 4: JVM and GC findings

### 4.1 UBI9 OpenJDK ergonomically picks G1, not Shenandoah

A common misconception: "Red Hat builds Shenandoah, so UBI OpenJDK images use Shenandoah by default."

Empirical reality (verified across UBI9 OpenJDK 17, 21, and 25, both builder and runtime variants):

```
$ podman run --rm registry.access.redhat.com/ubi9/openjdk-25:1.24 \
    java -XX:+PrintFlagsFinal -version 2>&1 \
    | grep -E "Use(G1|Shenandoah|ZGC|Parallel|Serial)GC " | grep -v "= false"

bool UseG1GC                                  = true                                      {product} {ergonomic}
```

The `{ergonomic}` annotation tells you the JVM auto-selected this based on detected hardware (server-class machines have ≥ 2 cores and > ~2 GB RAM, which JDK ergonomics sees as "use G1").

Shenandoah is *available* in these images — Red Hat compiles it in. It's just not selected ergonomically. To activate:

```bash
java -XX:+UseShenandoahGC -jar app.jar
```

Why this matters: if you're recommending GC choices on Red Hat infrastructure, the framing should be "Shenandoah is one flag away on UBI" — not "UBI defaults to Shenandoah." The latter is wrong, and someone reproducing your benchmarks will see G1 and wonder what they did differently.

We caught this finding during talk preparation. The original slides claimed UBI's default was Shenandoah; the correct framing is "Red Hat ships Shenandoah; the JVM chooses G1; one flag activates Shenandoah."

### 4.2 The compressed-oops threshold

JDK uses 32-bit object pointers (compressed oops) when the heap is small enough. The threshold is approximately 32 GB of *heap* — but the calculation is more nuanced than that. Variables include:

- The actual heap size (`-Xmx`, or `MaxRAMPercentage` of detected memory)
- The base address (typically near zero)
- The shift amount (3 by default — divides by 8 to compress)

Conservatively, set heap below 30 GB to ensure compressed oops are enabled.

This matters most for AOT cache work (Section 2.1). In production, exceeding the compressed-oop threshold can also affect:

- Memory footprint (4-byte vs 8-byte pointers across millions of objects = significant)
- Cache locality (smaller pointers = better CPU cache utilization)
- AOT cache compatibility (covered above)

For containerized JVM workloads, the practical recommendation: **set `mem_limit` on containers to keep heap below 30 GB**. If you genuinely need more than 30 GB of heap, you're outside the compressed-oop regime and AOT cache is not your biggest concern.

### 4.3 AOT cache failure diagnosis

When an AOT cache fails to load, the default error message is uninformative:

```
[error][cds] An error has occurred while processing the AOT cache.
[error][cds] Run with -Xlog:cds for details.
```

Always re-run with `-Xlog:aot` (or `-Xlog:cds` on older JDKs):

```bash
podman run -e JAVA_TOOL_OPTIONS="-Xlog:aot" your-image
```

You'll see one of these distinct failure patterns:

1. **"Unable to map shared spaces"** — usually the compressed-oops mismatch (Section 2.1) or other heap-layout differences. Look for `UseCompressedOops` warnings *before* the failure.

2. **"AOT cache was created with different JVM"** — the build-ID mismatch (Section 1.4). Different JVM build wrote the cache than is trying to read it.

3. **"Class space verification failed"** — usually classloader hierarchy differences (Section 1.1). Could also be that the classpath has changed between training and runtime.

4. **"No archive found"** — the AOT cache file wasn't found at the path specified. Check `ls` on the runtime container, verify the `-XX:AOTCache=` path matches the actual file.

5. **"Header verification failed"** — the cache file is corrupt or incomplete. Usually means the training run was killed before write completion. Re-train.

The diagnostic process: get verbose logs, identify the failure pattern, work backward to which stage of the build introduced the inconsistency.

---

## Section 5: Measurement methodology

### 5.1 HTTP-poll vs log-line: when to use which

Two ways to measure cold-start time on a JVM application, and they measure different things:

**HTTP-poll method:**

```bash
podman compose up -d service
start_ms=$(($(date +%s%N) / 1000000))
while ! curl -sf "http://localhost:8080/actuator/health" >/dev/null 2>&1; do
  sleep 0.05
done
end_ms=$(($(date +%s%N) / 1000000))
echo $((end_ms - start_ms))
```

This measures **container-up to HTTP-200**: includes container start, network setup, healthcheck poll interval. Closer to "user-perceived startup."

**Log-line method:**

```bash
podman compose up -d service
while true; do
  secs=$(podman logs $svc 2>&1 | grep -oP 'started in \K[\d.]+' | head -1)
  [[ -n "$secs" ]] && break
  sleep 0.05
done
echo $(awk -v s="$secs" 'BEGIN{print int(s*1000)}')
```

This parses the framework's own startup log line:
- Spring Boot: `Started ColdStartApplication in 3.881 seconds`
- Quarkus: `started in 0.181s`

Measures **JVM-internal startup**: from `main()` invocation to the framework declaring itself ready. Excludes container orchestration overhead.

**When to use which:**

- HTTP-poll for end-to-end user-perceived latency (production-like measurement)
- Log-line for cross-framework comparison (apples-to-apples regardless of orchestration)
- Both, side by side, when you want to see the gap

For Demo 05, we initially used HTTP-poll. It told us Quarkus baseline was ~1300 ms, which contradicted both Quarkus's published numbers and our other-project measurements (~480 ms). The discrepancy was the 2-second healthcheck interval — Quarkus boots in ~700 ms, but our healthcheck didn't poll until 2 seconds later.

We refactored to log-line parsing. Numbers aligned with industry conventions. Spring Boot dropped slightly too (less of a gap because Spring Boot's "Started" log line happens before some post-classloading framework warmup that HTTP-poll catches).

The lesson: **be explicit about what you're measuring**. Both methods are valid, but they answer different questions. Don't mix them in the same comparison.

### 5.2 Sample sizes and noise

For cold-start measurements, run *at least* 3 cold starts per configuration. Ideally 5-10. Take the median, not the mean.

Why median: cold starts have a long tail. Background processes, OS file caching, JIT compiler quirks all introduce occasional outliers. Mean is sensitive to outliers; median isn't.

We don't discard outliers. Three runs that differ by less than 10% are fine — take the median. Three runs that differ by more than 30% means something is wrong with the environment (background load, thermal throttling, swap pressure) — investigate before reporting.

### 5.3 Cold start means cold start

Make sure you're actually measuring cold start, not warm start. Each measurement should:

1. Stop any prior instance of the service (`podman stop`, `podman rm`)
2. Optionally drop the OS file cache (`echo 3 > /proc/sys/vm/drop_caches` — needs root)
3. Start fresh
4. Measure
5. Stop again

Don't reuse a running container, don't use container `restart`, don't time the second consecutive boot. The OS file cache from a prior run will have warmed JAR file pages, classloader paths, and library files — that's not what production sees.

For lab purposes, dropping the file cache between runs is excessive. Just make sure each run is a fresh container start, not a restart.

---

## Section 6: Architectural insights

### 6.1 Build-time vs runtime framework wiring: the cold-start lever

The talk's central thesis. AOT cache is a JVM feature. How much it accelerates startup depends on what your *framework* does at startup.

**Spring Boot wiring at runtime:**

- `@ComponentScan` walks every `.class` file in your packages, reading annotations via reflection
- `@EnableAutoConfiguration` loads ~150 auto-configuration classes' conditional logic (`@ConditionalOnClass`, `@ConditionalOnProperty`, etc.)
- The bean factory is constructed reflectively, dependency graph resolved at runtime
- Hibernate reads `@Entity` classes, builds the persistence unit metamodel, generates proxies via ByteBuddy

All of this is reflection-and-decision work. AOT cache only handles classloading. The rest happens at runtime no matter what.

**Quarkus wiring at build time:**

- The Maven plugin walks the classpath at build time and finds beans
- Conditional logic is evaluated at build time
- The bean dependency graph is resolved and emitted as concrete bytecode
- Hibernate's metamodel is pre-built; entity proxies are pre-generated

By the time `quarkus-run.jar` starts, almost all framework decisions are already baked. The runtime is essentially "load classes, register pre-wired handlers, listen on port 8080." AOT cache amplifies this dramatically because there's so little post-classloading work to slow startup.

The leverage difference is where the 18% (Spring Boot AOT savings) vs 77% (Quarkus Leyden savings) gap comes from. Same JVM. Same Project Leyden flag. Different framework architecture.

### 6.2 When to reach for native image instead

GraalVM native image is an even more aggressive answer to the same problem: ahead-of-time compile to a static binary at build time. Eliminates the JVM (in the conventional sense) entirely. Native binaries cold-start in 10-50 ms.

Trade-offs vs. AOT cache on JVM:

- **Build time**: 5-10 minutes for native, 1-2 minutes for AOT cache
- **Runtime flexibility**: native is closed-world (no dynamic class loading, restricted reflection); JVM remains fully dynamic
- **Tooling**: native has limited JFR support, no live JVM debugging, restricted instrumentation; JVM has the full ecosystem
- **Memory footprint**: native is much smaller (50 MB resident vs 300+ MB)
- **Throughput at peak**: native is sometimes lower than JIT-compiled JVM (no profile-guided optimization; static analysis is conservative)

Decision tree:

- **Long-running service, JVM ecosystem important**: stay on JVM. AOT cache as cherry on top.
- **Cold-scale workload, willing to invest in build time, framework supports it well**: native image. Quarkus and Micronaut have mature native paths; Spring Native is improving but more complex.
- **You want startup so fast you don't care about anything else**: native image. Don't use the JVM.

Demo 05 deliberately stays on the JVM to isolate the AOT-cache variable. Native image is a separate conversation.

### 6.3 Cardinality budgets: the operational cost of metrics

A finding from Demo 02. Time-series databases (Prometheus, Mimir, VictoriaMetrics, Cortex) store metrics keyed by their full label set. Every unique combination of label values is a separate time series. A metric with 1,000 unique values across one label is 1,000 series. Add a second label with 100 values: 100,000 series. Add a third with 50: 5,000,000 series.

TSDBs OOM, they don't slow down. There's no graceful degradation when you exceed the memory budget — the database falls over, alerting silently breaks, and the team finds out at 3 AM.

The critical ops practice: budget cardinality like compute. Common rules:

- **User IDs go in traces, not metrics.** Metrics aggregate; traces correlate. Trace storage is denormalized for query, not aggregation.
- **Bucket continuous values before exporting.** Latency in milliseconds → latency histogram bucket. URLs with query strings → URL template.
- **Filter at the Collector, not at the application.** The application can be wrong; the Collector is the architectural enforcement point.
- **Alert on series count growth.** Catch the cardinality bomb before it OOMs the storage layer.

The OpenTelemetry Collector's `transform` and `filter` processors are the right tool for this. Define them once, every service in the platform inherits the protection.

### 6.4 The Collector as architectural buffer

A general pattern that emerged across Demos 02, 03, and the discussion: the OpenTelemetry Collector is where you *make decisions* about your telemetry data. Not your application code, not your storage backend — the Collector.

What lives in the Collector:

- **Filtering**: drop noisy spans before they reach the trace store
- **Sampling**: head sampling, tail sampling, rate-based sampling
- **Transforming**: redact PII, normalize labels, derive metrics from spans
- **Routing**: send some signals to vendor X, others to vendor Y
- **Aggregating**: batch writes for efficiency, deduplicate, compute summaries
- **Cardinality enforcement**: strip high-cardinality labels at the edge

Why this matters architecturally: the Collector is the seam between your application and your observability platform. Application code shouldn't know which backend is current. Storage backends shouldn't have to enforce policy. Decisions live in the middle, where they can be changed without redeploying applications or migrating storage.

This is more important than it sounds. Most teams treat their observability stack as "vendor X for everything"; the Collector pattern lets you decompose that into "ingestion → policy → storage" with clear seams between them.

---

## Quick reference: the five things that bit us hardest

The five highest-leverage findings from this work, in priority order:

1. **Spring Boot's fat JAR breaks JDK 25 AOT cache** (Section 1.1)
   Extract the JAR before training. Use Spring Boot's `tools` jarmode.

2. **The JVM build-ID matching trap** (Section 1.4)
   Training JVM and runtime JVM must be *exactly* the same build, not just same version. Use the same base image for the trainer and runtime stages.

3. **The compressed-oops trap on Quarkus + Leyden** (Section 2.1)
   Without `mem_limit`, the JVM disables compressed oops on host-RAM-sized heaps and the AOT cache becomes incompatible. Set `mem_limit: 512m` on Quarkus services.

4. **Spring Boot 4 OpenTelemetry property paths shifted** (Section 3.3)
   The old `MANAGEMENT_OTLP_TRACING_*` paths are silently ignored on Spring Boot 4. Use `MANAGEMENT_OPENTELEMETRY_TRACING_EXPORT_OTLP_*` instead.

5. **HTTP-poll vs log-line measurement methodology** (Section 5.1)
   They measure different things. Choose deliberately. Don't mix in the same comparison.

---

## When to update this document

- After hitting a new build / runtime / instrumentation gotcha that takes more than an hour to diagnose
- After upgrading a major framework version (Spring Boot 4 → 5, Quarkus 3 → 4)
- After upgrading the JDK across an LTS boundary (25 → 31)
- After Project Leyden lands new JEPs (516 ZGC support, 514 successor work, etc.)
- When something in this document becomes wrong because the underlying tools changed

This doc is most valuable when it stays current. Stale findings are worse than no findings — they send people down debugging paths that no longer apply.
