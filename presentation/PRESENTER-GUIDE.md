# Presenter Guide — Three Signals, One Story

A printable, paper-friendly reference for the speaker. Mirrors the speaker notes in `slides.html` but flat enough to mark up with a pen.

## Talk Outline

| Time | Section | Slides | Demo |
|---|---|---|---|
| 0:00 | Open | 1–3 | — |
| 0:04 | §1 OTel fundamentals | 4–7 | — |
| 0:11 | §2 Instrumentation | 8–11 | **Demo 01** (3 min) |
| 0:18 | §3 OTel vs Prometheus | 12–14 | — |
| 0:23 | §4 LGTM stack | 15–17 | — |
| 0:28 | §5 Correlation | 18–20 | **Demo 02** (8 min) — headline |
| 0:38 | §6 Sampling | 21–23 | **Demo 03** (6 min) |
| 0:46 | §7 Debug + perf | 24–26 | **Demo 04** + **Demo 05** (6 min) |
| 0:52 | §8 OpenShift | 27–29 | — |
| 0:55 | Close + Q&A | 30 | — |
| (extra) | Bonus: Shenandoah | B1–B2 | optional re-use of demo 04 |

---

## Slide-by-Slide

### 1 — Title
*"Three Signals, One Story."* Verbal title. Pause. Eye contact.

### 2 — Agenda
Walk each section in 10s. Highlight five demo markers.

### 3 — Why this is hard
**Headline:** "The problem isn't lack of data. The data is in three silos that don't pivot."

### 4 — What OTel is
- Vendor-neutral standard, CNCF graduated.
- API + SDK + Collector + OTLP wire format.
- **Line:** "Instrument once. Decide who you pay later."

### 5 — Three signals
- Metrics, logs, traces — each useful alone.
- **Multiplicative when sharing a `traceId`**, not additive.

### 6 — Diagram 08 (signal flow)
- Walk left to right: app → SDK → OTLP → Collector → Prom/Loki/Tempo.
- Highlight the dotted traceId line crossing all three lanes.

### 7 — Why it matters
- Before/after split: vendor lock-in vs swap-without-reinstrumenting.

### 8 — Three approaches (diagram 09)
- Auto / Manual / Hybrid.
- **Hybrid is what production looks like.**

### 9 — Auto-instrumentation deep dive
- `-javaagent:opentelemetry-javaagent.jar` + env vars.
- ~120 instrumentations.
- Costs: 5–10% startup, 1–3% steady-state CPU.

### 10 — Spring Boot 4.0.x reality
- `micrometer-tracing-bridge-otel` + `opentelemetry-exporter-otlp` = two-line dep change.
- **Heads up:** Zipkin exporter deprecated in 4.0, gone in 4.2.

### 11 — DEMO 01 (3 min)
- Same JAR. One env var. Three modes.
- The empty-Tempo / full-Tempo flip is the slide.

### 12 — Pull vs push
- Prom = pull, single-signal, stable.
- OTel = push, multi-signal, vendor-neutral.

### 13 — Diagram 10 (the bridge)
- Collector with bidirectional arrows.
- AND, not OR.

### 14 — Decision matrix
- Use Prom for K8s infra metrics.
- Use OTel for app traces, logs, business metrics.
- Most production runs both.

### 15 — Diagram 11 (LGTM)
- All-in-one image: `docker.io/grafana/otel-lgtm:0.8.1`.
- Tempo + Loki + Mimir + Grafana + embedded Collector.

### 16 — Compose, in practice
- `:Z` for SELinux, fully-qualified image names, tmpfs trick.
- These three lessons cost real time.

### 17 — One stack per demo
- Port allocation table (3001–3005).
- Talk-day reliability >> elegance.

### 18 — Diagram 12 (the pivot) — HEADLINE
- Five steps: spike → exemplar → trace → span logs → root cause.
- **Headline:** "≈ 15 seconds, end to end."

### 19 — How it works
- App side: `percentiles-histogram: true` + Logback `%X{traceId}`.
- Grafana side: `derivedFields` regex on Loki, `exemplarTraceIdDestinations` on Prom.
- **Line:** "Three lines of YAML each."

### 20 — DEMO 02 (8 min) — HEADLINE
- Two services, fault injection, three-store pivot.
- OVER-REHEARSE THIS. Bookmark the dashboard URL.
- Click-path: dashboard → exemplar dot → Tempo → "logs for span" → Loki.

### 21 — Why sample
- 1k RPS × 100% × 30d = ~13 TB.
- Sampling is the cost lever.

### 22 — Diagram 13 (head vs tail)
- Head: cheap, blind to outcome.
- Tail: smart, expensive (Collector RAM).
- Production: both.

### 23 — DEMO 03 (6 min)
- Two configs side by side: `parentbased_traceidratio` vs `tail_sampling`.
- Show Tempo trace counts.

### 24 — Use case 1 · GC pauses (diagram 14, demo 04)
- Three lanes align: spans, GC, p99.
- **Line:** "Observability sees ACROSS the JVM/app boundary."

### 25 — Use case 2 · Cold-start (demo 05, JDK 25)
- ~3500 ms classic → ~700 ms AOTCache.
- Trace span tree shows WHERE the time was saved.

### 26 — Use case 3 · Cross-service errors
- The customer/frontend/database story.
- **Line:** "The traceId is the only thing that connects them."

### 27 — Red Hat OTel
- Operator + `OpenTelemetryCollector` CRD.
- Cluster-supported.

### 28 — Diagram 15 (deployment patterns)
- Sidecar / DaemonSet / Deployment.
- Most teams: DaemonSet → centralized Deployment gateway.

### 29 — OpenShift gotchas
- Service mesh emits proxy spans only.
- Routes preserve traceparent.
- SCCs and network policies for the Collector.

### 30 — Five takeaways
1. Three signals, one identifier.
2. Auto-instrument first; hand-instrument the seams.
3. OTel and Prom compose.
4. Sample at head in dev, tail in prod.
5. The Collector is the most important thing you'll deploy.

### B1 — Shenandoah default in UBI9
- "The default GC nobody talks about."
- Spring Boot devs on UBI9 already have sub-10ms pauses.
- Generational since JDK 21, ~5% memory overhead.

### B2 — G1 vs Shenandoah vs ZGC (diagram 16)
- Comparison table.
- **The Red Hat dividend:** Shenandoah free in UBI9.

---

## Demo Cheatsheet

### Demo 01 — Auto vs Manual (3 min)
```bash
cd demo-01-auto-vs-manual && ./demo.sh
```
- Watch the empty-Tempo → full-Tempo flip when AGENT_ENABLED toggles.
- Hit `/work` to see the manual Observation span nest under HTTP.

### Demo 02 — Correlation (8 min) — HEADLINE
```bash
cd demo-02-correlation && ./demo.sh
```
- Baseline traffic → inject fault → pivot in Grafana.
- Bookmark `http://localhost:3002/d/demo02-correlation`.
- Practice: dashboard → exemplar → Tempo → Logs → done.

### Demo 03 — Sampling (6 min)
```bash
cd demo-03-sampling && ./demo.sh
```
- Compare head sampling at app vs tail sampling at Collector.
- Show Tempo trace counts.

### Demo 04 — GC pauses (3 min)
```bash
cd demo-04-gc-pauses && ./demo.sh
```
- `/allocate` endpoint → JVM pauses align with span gaps.

### Demo 05 — AOT cold-start (3 min, JDK 25)
```bash
cd demo-05-aot-coldstart && ./demo.sh
```
- Classic vs AOTCache containers boot side-by-side.
- ~3500ms → ~700ms.

---

## Pre-Talk Checklist (the morning of)

- [ ] `./pre-pull.sh` ran, all images present.
- [ ] `./verify-stacks.sh` passed for all five demos.
- [ ] All five demo scripts have execute bits (`chmod +x demo-*/demo.sh`).
- [ ] Browser bookmarks: dashboards for demos 01–05.
- [ ] Terminal font scaled up to projector size.
- [ ] BENCHMARKS.md numbers are current (re-ran in last 60 days).
- [ ] Slide deck loads cleanly in `slides.html` (Reveal.js controls work).
- [ ] Speaker notes pop up on press 'S'.

## Mid-Talk Recovery

If a demo hangs or fails:
1. Don't apologize at length. "Let me show you what would have happened" — switch to the dashboard screenshot.
2. Move on. Lost demo &lt; lost momentum.
3. Note it in the recap, offer to demo it after the talk.
