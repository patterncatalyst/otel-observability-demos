# BENCHMARKS

Canonical performance measurements from this repository's demos. Numbers reproduced on a
single laptop; methodology documented so anyone can verify on their own hardware.

> **Reproducibility commitment:** every number in this document corresponds to a command in
> the repository that produces it. If a number drifts from what the demo currently outputs,
> either the demo changed or the JDK/runtime changed — both are interesting findings worth
> investigating, not bugs in the document.

---

## Test environment

All measurements taken on:

| Component | Version |
|---|---|
| OS | Fedora 43 |
| Container runtime | podman 5.8.2 |
| JDK (host) | OpenJDK 25.0.3 (Temurin) |
| JDK (container) | UBI9 OpenJDK 25.0.3 (Red Hat build) |
| Spring Boot | 4.0.4 |
| Quarkus | 3.33.1 LTS |
| Hardware class | Modern laptop (8+ cores, 32+ GB RAM, NVMe SSD) |

**Why these specifics matter:** The Quarkus AOT cache fails to load if the runtime container
has unrestricted memory access (the JVM disables compressed oops above ~32 GB heap, which
invalidates the AOT cache). All Quarkus runs use `mem_limit: 512m` to stay below the
compressed-oop threshold. Spring Boot has no equivalent constraint and runs without a memory
limit — see methodology notes for why this asymmetry is itself a finding.

---

## Demo 05 — Cold-start cost matrix

The headline benchmark of the talk. Measures cold-start time across 8 configurations:
Spring Boot 4 with three telemetry modes × two AOT modes, plus Quarkus baseline and
Quarkus with Project Leyden's AOT cache.

### Methodology

**What we measure:** JVM-internal startup time, parsed from the framework's own log line:
- Spring Boot: `Started ColdStartApplication in X.X seconds`
- Quarkus: `started in X.XXXs`

**Why log-line parsing:** Earlier versions of this benchmark used HTTP-readiness polling
(curl `/actuator/health` until 200). That measures container-start through HTTP-ready and
includes container orchestration overhead unrelated to the framework. Log-line measurement
gives apples-to-apples comparison between Spring Boot and Quarkus, matching the methodology
of published cold-start headlines.

**Sample size:** 3 cold starts per variant. Median reported. The script discards no outliers
— if 3 runs produce wildly varying numbers, something is wrong with the environment.

**Cold start is enforced:** every measurement starts from `podman compose down` and a fresh
`podman compose up`. No container reuse, no JIT warmup carryover.

### Reproducing

```bash
cd demo-05-aot-coldstart
./demo.sh build      # ~5-7 min first run (Quarkus Leyden training takes ~3 min)
./demo.sh time-all   # ~10-12 min for 24 cold starts
```

### Results

#### Spring Boot 4 — telemetry comparison

| | + agent | + SDK | no telemetry |
|---|---|---|---|
| Classic JDK 25 | 4733 ms | 4013 ms | 3954 ms |
| AOT cache | 4306 ms | 3282 ms | 3252 ms |

Three insights from this table:

1. **Agent tax: ~750 ms** — consistent across both classic and AOT (`4733 - 3954 = 779`,
   `4306 - 3252 = 1054`; the slightly larger AOT delta is within run-to-run noise). This is
   the cost of the OpenTelemetry javaagent's bytecode rewriting at startup.

2. **SDK tax: ~30-60 ms** — within run-to-run noise of "no telemetry." Spring Boot 4's new
   `spring-boot-starter-opentelemetry` (Nov 2025) is essentially free at startup compared to
   the agent.

3. **AOT savings: ~700 ms (~18%)** regardless of telemetry mode. AOT cache speeds class
   loading; it doesn't accelerate the post-classloading work (bean discovery,
   autoconfiguration evaluation, JPA metamodel construction) that dominates Spring Boot's
   startup.

#### Cross-framework comparison (no telemetry, apples-to-apples)

| Configuration | Cold start | AOT savings |
|---|---|---|
| Spring Boot Classic | 3954 ms | (baseline) |
| Spring Boot + AOT | 3252 ms | -702 ms (~18%) |
| Quarkus Classic | 787 ms | (baseline) |
| Quarkus + Leyden | 181 ms | -606 ms (~77%) |

Three observations from this table:

1. **Quarkus baseline is faster than fully-optimized Spring Boot.** 787 ms vs 3252 ms.
   Quarkus with no flags beats Spring Boot with Spring AOT processing + JDK 25 AOT cache.

2. **Same Project Leyden flag, very different leverage.** AOT cache saves roughly the same
   *absolute* amount on both frameworks (~600-700 ms — roughly the classloading work). But
   Spring Boot has 3 seconds of additional runtime work AOT can't accelerate, while Quarkus
   has almost none. The percentage gap is dramatic.

3. **The framework, not the vendor, is the cold-start lever.** This is the talk's central
   thesis. Quarkus does framework wiring at *build* time (via the `@QuarkusIntegrationTest`
   training phase and Quarkus Maven plugin). Spring Boot does it at *runtime*. AOT cache
   amplifies an already-fast Quarkus startup; it cannot bypass Spring Boot's runtime
   framework decisions.

### Known limitations of the SDK measurement

In our test environment, Spring Boot 4.0.4's `spring-boot-starter-opentelemetry` registers
auto-configuration beans correctly but spans aren't actually created during request
processing. This means the "SDK" column measures the cold-start cost of an app *configured
for* SDK telemetry, not an app where SDK telemetry is actually emitting spans.

The starter is ~5 months old at the time of writing (Nov 2025 announcement, tested Apr 2026).
Cold-start timing remains valid; trace emission is a Spring Boot 4.0.4 maturity gap that
will likely close in subsequent releases. Documented in `demo-05-aot-coldstart/TALK-NOTES.md`.

### Why Spring Boot is so much slower than Quarkus

Spring Boot does at runtime what Quarkus does at build time:

- **Component scan:** Spring walks every `.class` file in your packages, reading annotations
  via reflection. Quarkus does this scan at build time and generates concrete bytecode for
  the result.
- **Auto-configuration evaluation:** Spring Boot 4 has ~150 auto-configuration classes, each
  with `@Conditional` checks. Each one runs at startup. Quarkus evaluates equivalent logic
  at build time.
- **Bean factory construction:** Spring instantiates beans via reflection at startup,
  resolving the dependency graph dynamically. Quarkus emits direct bean wiring code at build
  time.
- **JPA / Hibernate:** Spring Boot reads `@Entity` classes at startup, builds the persistence
  unit, generates proxies via ByteBuddy. Quarkus pre-builds the metamodel at build time.

AOT cache only handles *classloading* work — which is what those frameworks load up *from*
at startup. The cache cannot accelerate the post-classloading reflection-and-decision work
Spring Boot does on every cold start. Quarkus simply does less of that work at runtime.

### What about GraalVM native image?

Native image is an even more aggressive answer to the same problem: compile to a static
binary at build time, eliminate the JVM and classloading entirely. Spring Boot Native and
Quarkus Native both target ~50 ms cold starts.

Trade-offs: build time goes from seconds to minutes, dynamic class loading is restricted,
JFR support is limited, and reflection patterns require explicit configuration. Different
commitment level. Demo 05 deliberately stays on the JVM to isolate the AOT-cache variable.

---

## Demo 04 — GC pause distribution (placeholder)

Three garbage collectors under matching allocation pressure. Each leaves a distinct
operational fingerprint on the dashboard.

> **Status:** Numbers below are typical ranges, not measured-in-this-environment values.
> Capture real numbers during dress rehearsal and update this section.

### Methodology

```bash
cd demo-04-jvm-metrics-shenandoah
./demo.sh up shenandoah
hey -z 30s -q 8 -c 4 'http://localhost:8084/allocate?sizeKb=64&objects=2000' >/dev/null
# capture p99 GC pause from dashboard

./demo.sh run g1
# repeat capture

./demo.sh run zgc
# repeat capture
```

### Expected ranges (to be replaced with measured values)

| GC | p50 pause | p99 pause | Suitable for |
|---|---|---|---|
| Shenandoah | ~1 ms | 5-15 ms | Latency-sensitive workloads, multi-GB heaps |
| G1 | ~5 ms | 30-100 ms | General purpose, throughput-oriented |
| ZGC | < 1 ms | < 5 ms | Latency-critical, large heaps |

### Why this matters

GC choice is an operational shape decision, not a tuning afterthought. The dashboard makes
the trade-offs visible: Shenandoah and ZGC trade some throughput for low pause times. G1
optimizes for throughput at the cost of occasional 30-100 ms pauses. None is universally
"better" — fingerprint your service against your SLO budget.

**Note on UBI defaults:** UBI9 OpenJDK images (17, 21, 25; both builder and runtime variants)
ergonomically pick **G1** as the default GC. Shenandoah is *available* (Red Hat compiles it
in) but is not selected by JVM ergonomics. Activate with `-XX:+UseShenandoahGC`.

---

## Notes on hardware sensitivity

These benchmarks are reproducible across modern laptops with reasonable consistency, but
absolute numbers will vary:

- **CPU clock speed** affects classloading and JIT warmup — slower CPUs see proportionally
  slower startup across all variants.
- **NVMe vs SATA SSD** affects AOT cache load time — the Quarkus Leyden cache is 50 MB and
  the Spring Boot cache is 120 MB; SATA SSDs see noticeably slower load.
- **Container runtime** (podman vs docker) shows minor differences at startup. Both are
  fine; podman 5.x was used here for parity with rootless production deployments.
- **Memory limits matter for the Quarkus Leyden case.** The compressed-oops issue is real
  and reproducible; without `mem_limit`, the Leyden run regresses below baseline.

---

## When to update this document

- After any change to Demo 05's compose.yaml, demo.sh, or service Containerfiles
- After a JDK upgrade (especially within the LTS cycle — JDK 25 → 25.0.4, etc.)
- After Spring Boot or Quarkus version bumps
- After a dress rehearsal on the talk-day hardware (different laptop = different numbers)
- When the SDK telemetry maturity gap closes (Spring Boot 4.x.x release notes)
