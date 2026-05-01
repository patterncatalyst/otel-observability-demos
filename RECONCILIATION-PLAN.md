# Reconciliation Plan — Three Signals, One Story

A step-by-step verification walkthrough for the talk's five demos. Each section has **acceptance criteria**, **what to do if it fails**, and a **time budget**. Work through in order — later steps depend on earlier ones.

**Total time: ~2 hours for first full pass. ~30 min for each subsequent re-verification.**

> **Status note:** This plan has been updated to reflect what's actually in the repository: renamed demos, the expanded Demo 05 (8-way comparison including Quarkus), the new pptx deck, and the real measured numbers from a Fedora 43 / podman 5.8.2 / JDK 25.0.3 environment.

---

## How to use this document

- Check off each step as you go. The check-mark is your "I saw this work with my own eyes" signal.
- If something fails, the **Fallback** notes get you unstuck without derailing the rest.
- Mark deviations from expected output in the margin — those become the talking points where reality differs from the plan.
- Don't skip the timing measurements at the end. The talk's headline numbers need to be *your* numbers, reproduced on *your* hardware.

### Checkbox legend

- **`[x]`** — verified during the April 2026 reconciliation work, with output evidence in transcripts
- **`[~]`** — completed in earlier sessions per conversation history; re-verify before talk day
- **`[ ]`** — not yet done; remaining work

---

## Phase 0 — Host prerequisites (15 min)

Run these on your Fedora 43 box.

### 0.1 — Install required tools

```bash
sudo dnf install -y podman podman-compose curl jq java-25-openjdk-devel maven git
# 'hey' isn't in Fedora repos; grab the binary
curl -L https://hey-release.s3.us-east-2.amazonaws.com/hey_linux_amd64 -o ~/.local/bin/hey
chmod +x ~/.local/bin/hey
```

JDK 25 is required for Demo 05's AOT cache work. JDK 21 still works for Demos 01-04.

**Acceptance criteria:**
- [x] `podman --version` ≥ 5.0 (5.8.2 verified working)
- [x] `podman-compose --version` works (any version)
- [~] `mvn --version` shows JDK 21+ (JDK 25 preferred)
- [~] `hey -h` shows usage
- [x] `jq --version` works
- [x] `git --version` works

**Fallback:** If `podman-compose` is missing, `pip install --user podman-compose` and add `~/.local/bin` to PATH.

---

### 0.2 — Verify the repo layout

```bash
cd otel-observability-demos
ls demo-*/
```

**Acceptance criteria:**
- [x] All five demo directories present:
  - `demo-01-three-signals/`
  - `demo-02-cardinality/`
  - `demo-03-tail-sampling/`
  - `demo-04-jvm-metrics-shenandoah/`
  - `demo-05-aot-coldstart/`
- [x] `ls diagrams/` shows nine `.excalidraw` files (08 through 16)
- [x] `ls presentation/` shows `slides.html`, `PRESENTER-GUIDE.md`, and `three-signals-one-story.pptx`

**Fallback:** If a demo directory is missing, `git status` will show what's missing. The repo is at `github.com/patterncatalyst/otel-observability-demos`.

---

### 0.3 — Make scripts executable (if git stripped the bit)

```bash
chmod +x demo-*/demo.sh
```

**Acceptance criteria:**
- [x] `ls -la demo-01-three-signals/demo.sh` shows `-rwxr-xr-x`

---

## Phase 1 — Image pre-pull (10 min, ~3 GB download)

The demos share a small set of base images. Pulling once up front avoids surprises on stage.

```bash
podman pull docker.io/grafana/otel-lgtm:0.8.1
podman pull docker.io/otel/opentelemetry-collector-contrib:0.114.0
podman pull registry.access.redhat.com/ubi9/openjdk-25:1.24
podman pull registry.access.redhat.com/ubi9/openjdk-25-runtime:1.24
podman pull registry.access.redhat.com/ubi9/openjdk-21:1.24
podman pull registry.access.redhat.com/ubi9/openjdk-21-runtime:1.24
podman pull docker.io/library/maven:3.9-eclipse-temurin-25
```

**Acceptance criteria:**
- [x] All seven images appear in `podman images`
  - UBI OpenJDK 25 (`:1.24` and `:latest`) verified directly in GC ergonomic probe
  - Other images confirmed via successful Demo 05 builds and runs

**Fallback — image tag has rolled forward:**
If a UBI9 OpenJDK tag is no longer pullable (Red Hat occasionally deprecates patch tags), check the current tag at the [Red Hat catalog](https://catalog.redhat.com/software/containers/search) and update the affected `Containerfile`(s).

**Fallback — collector-contrib version unavailable:**
The contrib image releases roughly weekly. If `0.114.0` has aged out, the GitHub releases page shows current options. Update both the pull command above and `demo-03-tail-sampling/compose.yaml`.

---

## Phase 2 — Demo 01 (Three Signals, One Story) (10 min)

The simplest demo — if this works, your podman + lgtm + Spring Boot baseline is healthy. The demo shows trace_id flowing through traces, metrics, and logs.

### 2.1 — Run the demo

```bash
cd demo-01-three-signals
./demo.sh
```

**Watch for:**
- "Grafana healthy" appears within ~30s
- "Service healthy" appears within ~90s

**Acceptance criteria:**
- [~] `curl http://localhost:8081/actuator/health` returns `{"status":"UP"...}`
- [~] `curl http://localhost:8081/api/hello` returns greeting JSON

**Fallback — `:Z` SELinux denial:**
Symptom: container exits, `podman logs` shows `Permission denied`. Fedora-specific. The `:Z` flag in `compose.yaml` should handle this; if not, `audit2why -a` will explain why.

---

### 2.2 — Verify all three signals correlate

Open Grafana at `http://localhost:3001` (anonymous login configured).

```bash
# Generate traffic
for i in 1 2 3 4 5; do
  curl -s "http://localhost:8081/api/hello?name=test$i" >/dev/null
done
```

In the Grafana UI:
1. Click **Explore** (compass icon)
2. Select **Tempo** datasource → run query → click any trace
3. Click "Logs for this trace" → Loki opens with correlated log lines
4. Click on a metric exemplar dot → jumps back to the trace

**Acceptance criteria:**
- [~] Tempo shows traces for `GET /api/hello`
- [~] Switch to Loki, query `{service_name=~"demo01.*"}` — log lines appear with `[traceId,spanId]` prefix
- [~] Click a `traceId` in a log line → opens in Tempo
- [~] Metric exemplar dots are clickable on the latency histogram

**Fallback — no traces in Tempo:**
1. Check the agent attached: `podman logs demo01-* 2>&1 | grep "otel.javaagent"` should show agent startup
2. Verify export endpoint: `podman exec demo01-* env | grep OTEL_EXPORTER` should be `http://lgtm:4318`

---

### 2.3 — Tear down

```bash
./demo.sh down
```

---

## Phase 3 — Demo 02 (The Cardinality Bomb) (15 min)

Demonstrates how a careless metric label can take down a TSDB, and how the OpenTelemetry Collector's `transform` processor defuses it.

### 3.1 — Run the demo

```bash
cd ../demo-02-cardinality
./demo.sh
```

**Acceptance criteria:**
- [~] All containers healthy (lgtm, service, collector)
- [~] Service responds at `http://localhost:8082`
- [~] Collector starts cleanly (no YAML errors in `podman logs demo02-collector`)

---

### 3.2 — Watch series count climb

The demo includes a feature flag that switches between bounded labels (~100 series) and `user_id` as label (10,000+ series).

```bash
# Generate traffic with bounded labels first
hey -z 30s -q 30 -c 4 http://localhost:8082/api/work >/dev/null

# Check series count in Mimir
curl -sf "http://localhost:3002/api/datasources/proxy/uid/prometheus/api/v1/query?query=count(http_server_requests_seconds_count)" | jq
```

**Acceptance criteria:**
- [~] Series count is bounded (~100s, not thousands)
- [~] After flipping the user_id flag, series count climbs to 10,000+
- [~] After applying the Collector's transform processor, series count plateaus

---

### 3.3 — Tear down

```bash
./demo.sh down
```

---

## Phase 4 — Demo 03 (Tail Sampling) (15 min)

First demo with a standalone Collector. Verifies the contrib image, the `tail_sampling` processor, and the head/tail config switching mechanic.

### 4.1 — Cold start (head mode)

```bash
cd ../demo-03-tail-sampling
./demo.sh up head
```

**Acceptance criteria:**
- [~] All three containers up: `demo03-lgtm`, `demo03-collector`, `demo03-service`
- [~] `curl http://localhost:8083/work` returns OK
- [~] `podman logs demo03-collector 2>&1 | head -20` shows `Everything is ready. Begin running and processing data.`

**Fallback — `tail_sampling` processor not found:**
Symptom: Collector logs `processor "tail_sampling" not available`. The contrib image should have it. Verify with `podman exec demo03-collector /otelcol-contrib components 2>&1 | grep tail_sampling`.

---

### 4.2 — Verify head sampling cuts traffic

```bash
hey -z 20s -q 30 -c 4 http://localhost:8083/work/random >/dev/null
sleep 5

curl -sf "http://localhost:3003/api/datasources/proxy/uid/prometheus/api/v1/query?query=otelcol_receiver_accepted_spans_total" | jq -r '.data.result[0].value[1]'
curl -sf "http://localhost:3003/api/datasources/proxy/uid/prometheus/api/v1/query?query=otelcol_exporter_sent_spans_total" | jq -r '.data.result[0].value[1]'
```

**Acceptance criteria:**
- [~] Both numbers positive
- [~] Received and exported are roughly equal (head sampling already cut traffic at the app)

---

### 4.3 — Switch to tail sampling

```bash
./demo.sh switch tail
sleep 10
hey -z 30s -q 30 -c 4 http://localhost:8083/work/random >/dev/null
sleep 15  # tail sampling buffer window

# Re-probe
curl -sf "http://localhost:3003/api/datasources/proxy/uid/prometheus/api/v1/query?query=otelcol_receiver_accepted_spans_total" | jq -r '.data.result[0].value[1]'
curl -sf "http://localhost:3003/api/datasources/proxy/uid/prometheus/api/v1/query?query=otelcol_exporter_sent_spans_total" | jq -r '.data.result[0].value[1]'
```

**Acceptance criteria:**
- [~] Received >> Exported (Collector dropping ~95% of healthy traces, keeping errors and slow traces)
- [~] In Tempo: filter by `status=error` finds essentially every `/work/error` generated
- [~] In Tempo: filter by latency > 1s finds essentially every `/work/slow`

---

### 4.4 — Tear down

```bash
./demo.sh down
```

---

## Phase 5 — Demo 04 (JVM Metrics & GC) (20 min)

The longest demo because of the three-GC sweep.

### 5.1 — Cold start with default GC (Shenandoah)

```bash
cd ../demo-04-jvm-metrics-shenandoah
./demo.sh up shenandoah
```

**Acceptance criteria:**
- [~] Service responds at `http://localhost:8084/work`
- [x] `podman exec demo04-service jcmd 1 VM.flags 2>&1 | grep -E "UseShenandoah|UseG1GC|UseZGC"` shows Shenandoah on, others off
  - **Note:** UBI9 OpenJDK ergonomic default is G1; verified across all five UBI variants (17, 21, 25; both builder and runtime) in the GC ergonomic probe during this session

**Important factual note:** UBI9 OpenJDK ergonomically picks **G1**, not Shenandoah, on every variant we tested (17, 21, 25; both builder and runtime). Shenandoah is *available* (Red Hat compiles it in) but has to be activated explicitly with `-XX:+UseShenandoahGC`. The talk's bonus slide reflects this.

---

### 5.2 — Generate allocation pressure

```bash
hey -z 30s -q 8 -c 4 'http://localhost:8084/allocate?sizeKb=64&objects=2000' >/dev/null
sleep 5
```

**Acceptance criteria:**
- [~] `http://localhost:3004/d/demo04-gc` shows GC pause percentile data
- [~] "GC events / sec by action and cause" panel shows recent GC activity

---

### 5.3 — Sweep G1 and ZGC

```bash
./demo.sh run g1
./demo.sh run zgc
```

**Acceptance criteria:**
- [~] Three distinct GC fingerprints visible on the dashboard
- [ ] Shenandoah p99: 5-15ms typical (capture during dress rehearsal)
- [ ] G1 p99: 30-100ms typical (capture during dress rehearsal)
- [ ] ZGC p99: < 5ms typical, often < 1ms (capture during dress rehearsal)

**Capture these numbers** for `BENCHMARKS.md` (currently has placeholder rows for Demo 04).

---

### 5.4 — Tear down

```bash
./demo.sh down
```

---

## Phase 6 — Demo 05 (Cold Start: Frameworks Compared) (25 min)

The headline demo. **The most ambitious phase** — measures cold-start time across 8 configurations: Spring Boot 4 with three telemetry modes (agent, SDK, none) × two AOT modes (classic, AOT cache), plus Quarkus 3.33 baseline and Quarkus + Project Leyden.

This demo evolved well beyond an early plan. The current state includes:
- Six Spring Boot variants using Piotr Minkowski's onRefresh AOT cache pipeline
- Spring Boot 4's new OpenTelemetry SDK starter (released Nov 2025)
- Two Quarkus variants demonstrating cross-framework comparison
- Log-line based timing methodology for apples-to-apples cross-framework measurement

### 6.1 — Build all images

```bash
cd ../demo-05-aot-coldstart
./demo.sh build
```

**First-time build is slow** (~5-7 minutes total): the Spring Boot AOT image takes ~2 min for the training run, the Quarkus Leyden image takes ~3 min for its training run.

**Acceptance criteria:**
- [x] `service-classic` builds (~1 min)
- [x] `service-classic-noagent` builds (~1 min, same image as classic)
- [x] `service-classic-sdk` builds (~1 min, includes spring-boot-starter-opentelemetry)
- [x] `service-aot` builds with `app.aot` ~120 MB present in image
- [x] `service-aot-noagent` builds (same image as aot)
- [x] `service-aot-sdk` builds with both AOT cache and SDK starter
- [x] `service-quarkus` builds (~1 min)
- [x] `service-quarkus-leyden` builds with `app.aot` ~50 MB present (~3 min for training run)

**Critical fallback — Quarkus AOT cache rejected at runtime:**
Symptom: Quarkus Leyden container starts but logs show `Loading static archive failed. Unable to map shared spaces.` and `UseCompressedOops disabled due to max heap > compressed oop heap`.

Cause: container has no memory limit, JVM sees full host RAM, `MaxRAMPercentage=75` blows past compressed-oop threshold (~32 GB), runtime disables compressed oops, AOT cache (built with compressed oops) can't map.

Fix: ensure `mem_limit: 512m` is set on Quarkus services in `compose.yaml`. Verify with `grep mem_limit compose.yaml` — should appear twice for the two Quarkus services.

**Fallback — Spring Boot 4 SDK telemetry doesn't engage:**
Spans don't appear in Tempo for `service-classic-sdk` / `service-aot-sdk`. This is a known limitation of Spring Boot 4.0.4 with the new opentelemetry starter — auto-config beans register correctly but Spring MVC's observation filter doesn't link to the new Tracer bean. Cold-start timing data remains valid (we measure time-to-startup, not telemetry quality). Documented in TALK-NOTES.md.

---

### 6.2 — Time the full 8-way comparison

```bash
# Cleanup any orphans first
podman ps -a --format '{{.Names}}' | grep '^demo05' | grep -v lgtm | xargs -r -I{} sh -c 'podman stop "{}" 2>/dev/null; podman rm -f "{}" 2>/dev/null'

./demo.sh time-all
```

This runs 24 cold starts (3 per variant × 8 variants), reports medians, and prints two comparison tables. **Takes ~10-12 minutes.**

**Expected results** (Fedora 43 / podman 5.8.2 / JDK 25.0.3 / log-line method):

Spring Boot 4 telemetry comparison:

| | + agent | + SDK | no telem |
|---|---|---|---|
| Classic JDK 25 | ~4700 ms | ~4000 ms | ~4000 ms |
| AOT cache | ~4300 ms | ~3300 ms | ~3300 ms |

Cross-framework (no-telemetry baseline):

| Configuration | Cold start | AOT savings |
|---|---|---|
| Spring Boot Classic | ~3950 ms | (baseline) |
| Spring Boot + AOT | ~3250 ms | ~700 ms (~18%) |
| Quarkus Classic | ~790 ms | (baseline) |
| Quarkus + Leyden | ~180 ms | ~610 ms (~77%) |

**Acceptance criteria:**
- [x] All 8 variants report a median (no `Could not parse startup time` errors)
- [x] Spring Boot AOT shows ~15-20% improvement over Spring Boot Classic (no telemetry)
- [x] Quarkus + Leyden shows ~70-80% improvement over Quarkus Classic
- [x] Quarkus baseline is faster than Spring Boot AOT (the talk's "framework, not vendor" thesis)

**See `BENCHMARKS.md` for the canonical numbers and methodology details.**

---

### 6.3 — Optional: visual walkthrough

```bash
./demo.sh up
```

Opens Grafana at `http://localhost:3005`. Useful for in-talk demonstration but not required for verification.

---

### 6.4 — Tear down

```bash
./demo.sh down
```

---

## Phase 7 — Slide deck verification (10 min)

Two decks live in `presentation/`:
- `slides.html` — older reveal.js deck (~32 sections)
- `three-signals-one-story.pptx` — current 29-slide deck with speaker notes and updated numbers

**The pptx is the canonical talk deck.** The reveal.js deck remains for reference / alternate formats.

### 7.1 — Open the pptx

```bash
xdg-open presentation/three-signals-one-story.pptx
# or use LibreOffice Impress / PowerPoint directly
```

**Acceptance criteria:**
- [x] All 29 slides render correctly (verified via PDF conversion + image rendering during deck QA)
- [x] Speaker notes visible on every slide (View → Notes Page in PowerPoint)
- [x] Slide 22 shows Spring Boot 4 telemetry comparison table
- [x] Slide 23 shows cross-framework comparison (Spring Boot vs Quarkus)
- [x] Slide 24 is the "agent tax doesn't amortize on cold scale" insight
- [x] Bonus slides 27-28 show Shenandoah-on-UBI and reproduction recipe

### 7.2 — Update placeholder text before talk day

Three placeholders to fill in:
- [ ] Slide 1: `[Speaker name] · WeAreDevelopers World Congress NA · [date]`
- [ ] Slide 26 (Q&A): `[Speaker] · [Twitter/X · GitHub · email]`

Edit directly in PowerPoint. No regeneration needed.

### 7.3 — Optional: replace inline diagrams with Excalidraw exports

The deck currently uses inline shapes for several diagrams. To upgrade with rendered Excalidraw diagrams:

1. Open each `.excalidraw` file from `diagrams/` in Excalidraw or the JetBrains plugin
2. Export as PNG (1200px wide, transparent background) into `diagrams/png/`
3. Suggested mapping:
   - `08-otel-signal-flow.png` → slide 5 (replaces inline pipeline)
   - `11-lgtm-architecture.png` → slide 6 (replaces text bullets)
   - `12-correlation-pivot.png` → slide 7 (Demo 01 setup)
   - `13-head-vs-tail-sampling.png` → slide 13 (Demo 03 setup)
   - `14-gc-trace-correlation.png` → slide 16 (Demo 04 setup)
   - `16-shenandoah-vs-g1-zgc.png` → slide 28 (Shenandoah bonus)
4. Skip `15-openshift-collector-patterns.excalidraw` — talk dropped OpenShift framing

**This is optional.** The talk works with the current inline diagrams.

---

## Phase 8 — Final dress rehearsal (45 min)

The single check that catches everything end-to-end. **This is the only critical-path remaining task.**

### 8.1 — Clean slate

```bash
podman ps -aq | xargs -r podman rm -f
podman volume prune -f
```

### 8.2 — Run-through with a timer

Pretend you're presenting. Open the deck. Click through, talking aloud, running each demo at the right slide.

**Time targets** (talk is 35 min content + 5 min Q&A = 40 min total):

| Section | Slides | Target | Cumulative |
|---|---|---|---|
| Open + why observability | 1-3 | 3 min | 0:03 |
| Three signals + OTel + stack | 4-6 | 4 min | 0:07 |
| Demo 01 (signals correlated) | 7-9 | 5 min | 0:12 |
| Demo 02 (cardinality) | 10-12 | 5 min | 0:17 |
| Demo 03 (tail sampling) | 13-15 | 4 min | 0:21 |
| Demo 04 (JVM/GC) | 16-18 | 4 min | 0:25 |
| Demo 05 (cold start headline) | 19-24 | 7 min | 0:32 |
| Close | 25-26 | 3 min | 0:35 |
| Q&A | — | 5 min | 0:40 |

If any segment runs long, candidates to compress:
- Three signals primer (slide 4) — cut to 90s
- Demo 04 sweep — show only Shenandoah live, mention G1/ZGC briefly
- Skip bonus slides (27-28) unless asked

**Acceptance criteria:**
- [ ] Full run completes in ≤ 40 minutes including Q&A
- [ ] No demo failures during rehearsal
- [ ] Speaker notes referenced for ≤ 3 slides total (rest known cold)
- [ ] Demo 05's `time-all` runs to completion

---

### 8.3 — Backup contingencies

For each demo, capture screenshots of the dashboard in working state. Save to `presentation/screenshots/`:

```bash
mkdir -p presentation/screenshots
# Capture during the dress rehearsal while everything is working
```

Suggested screenshots:
- [ ] `demo-01-trace-with-logs.png` — Tempo trace view with correlated logs panel
- [ ] `demo-02-cardinality-spike.png` — Series count climbing then plateauing
- [ ] `demo-03-tail-sampling-decisions.png` — Collector receive vs export counts
- [ ] `demo-04-three-gc-comparison.png` — Three-GC dashboard
- [ ] `demo-05-time-all-output.png` — Terminal showing the comparison table

If a demo fails live, switch to the screenshot, narrate what would have happened, move on. **Lost demo < lost momentum.**

---

## Talk-day morning checklist (10 min)

```bash
cd otel-observability-demos
git pull                              # latest code
podman pull <each base image>         # refresh
cd demo-05-aot-coldstart && ./demo.sh build  # warm cache for the headline
./demo.sh time-all                    # one quick run to confirm numbers
```

- [ ] All images present and recent
- [ ] Demo 05 builds clean and shows expected numbers
- [ ] Deck loads, speaker notes visible
- [ ] Browser bookmarks ready: dashboards for demos 01-05
- [ ] Terminal font size scaled for projector (18-22pt typical)
- [ ] Phone has hotspot ready in case venue Wi-Fi fails
- [ ] Speaker placeholders filled in on slides 1 and 26

---

## Common-issues quick reference

| Symptom | First thing to check |
|---|---|
| Container exits immediately | `podman logs <name>` — usually startup error |
| Container builds but won't start | Healthcheck timeout too short; bump `start_period` |
| `:Z` permission denied | `getenforce` — should be Enforcing; check `audit2why -a` |
| `localhost:` in container env | `OTEL_EXPORTER_OTLP_ENDPOINT` should use service-name, not localhost |
| Tempo empty | Agent not attached, or wrong endpoint |
| Loki has no logs | Logback pattern missing `%X{traceId}` |
| Quarkus Leyden cache rejected | `mem_limit: 512m` missing in compose.yaml (compressed oops issue) |
| Spring Boot 4 SDK spans missing | Known limitation — see TALK-NOTES.md |
| `tail_sampling` not found | Wrong Collector image — needs `-contrib`, not core |
| GC labels missing in dashboard | `OTEL_RESOURCE_ATTRIBUTES` not propagating to Prom labels |

---

## Sign-off

When everything above checks out:

```bash
git add BENCHMARKS.md presentation/screenshots/
git commit -m "chore: dress-rehearsal screenshots and reproduced benchmarks"
git push
```

Now you're ready to present.
