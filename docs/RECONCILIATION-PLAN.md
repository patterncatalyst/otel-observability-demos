# Reconciliation Plan — Three Signals, One Story

A step-by-step verification walkthrough. Each section has **acceptance criteria**, **what to do if it fails**, and a **time budget**. Work through in order — later steps depend on earlier ones.

**Total time: ~2 hours for first full pass. ~30 min for each subsequent re-verification.**

---

## How to use this document

- Check off each step as you go. The check-mark is your "I saw this work with my own eyes" signal.
- If something fails, the **Fallback** notes get you unstuck without derailing the rest.
- Mark deviations from expected output in the margin — those become the talking points where reality differs from the plan.
- Don't skip the timing measurements at the end. The talk's headline numbers need to be *your* numbers, not ones I made up.

---

## Phase 0 — Host prerequisites (15 min)

Run these on your Fedora 43 box.

### 0.1 — Install required tools

```bash
sudo dnf install -y podman podman-compose curl jq java-21-openjdk-devel maven git
# 'hey' isn't in Fedora repos; grab the binary
curl -L https://hey-release.s3.us-east-2.amazonaws.com/hey_linux_amd64 -o ~/.local/bin/hey
chmod +x ~/.local/bin/hey
```

For demo 05 (JDK 25 AOT) you'll also want JDK 25 on the host — useful but not required since the build happens in a container:

```bash
sudo dnf install -y java-25-openjdk-devel  # if available; else container build is fine
```

**Acceptance criteria:**
- [ ] `podman --version` ≥ 5.0
- [ ] `podman-compose --version` works (any version)
- [ ] `mvn --version` shows JDK 21 or higher
- [ ] `hey -h` shows usage
- [ ] `jq --version` works
- [ ] `git --version` works

**Fallback:** If `podman-compose` is missing, `pip install --user podman-compose` and add `~/.local/bin` to PATH.

---

### 0.2 — Verify the repo unpacked correctly

```bash
cd otel-observability-demos
find . -type f | wc -l
```

**Acceptance criteria:**
- [ ] Output is **87** files
- [ ] `ls demo-*/` shows all five demo directories
- [ ] `ls diagrams/` shows nine `.excalidraw` files
- [ ] `ls presentation/` shows `slides.html` and `PRESENTER-GUIDE.md`

**Fallback:** If file count differs, re-unzip the bundle. If the issue persists, `git status` will show what's missing.

---

### 0.3 — Make scripts executable (if git stripped the bit)

```bash
chmod +x pre-pull.sh verify-stacks.sh demo-*/demo.sh tools/build-diagrams.py
```

**Acceptance criteria:**
- [ ] `ls -la demo-01-auto-vs-manual/demo.sh` shows `-rwxr-xr-x`

---

## Phase 1 — Image pre-pull (10 min, ~3 GB download)

### 1.1 — Pull images

```bash
./pre-pull.sh
```

**Acceptance criteria:**
- [ ] `docker.io/grafana/otel-lgtm:0.8.1` pulled
- [ ] `docker.io/otel/opentelemetry-collector-contrib:0.114.0` pulled
- [ ] `registry.access.redhat.com/ubi9/openjdk-21:1.21-1` pulled
- [ ] `registry.access.redhat.com/ubi9/openjdk-21-runtime:1.21-1` pulled
- [ ] `registry.access.redhat.com/ubi9/openjdk-25:1.24` pulled
- [ ] `registry.access.redhat.com/ubi9/openjdk-25-runtime:1.24` pulled

**Fallback — image tag has rolled forward:**
If a UBI9 OpenJDK tag is no longer pullable (Red Hat sometimes deprecates patch tags), check the current tag at `https://catalog.redhat.com/software/containers/search?p=1&product_listings_names=Red%20Hat%20Universal%20Base%20Image%209` and update `pre-pull.sh` and the affected `Containerfile`(s).

**Fallback — collector-contrib version unavailable:**
The contrib image releases roughly weekly. If `0.114.0` has aged out, `podman search docker.io/otel/opentelemetry-collector-contrib --list-tags 2>/dev/null` (or the GitHub releases page) shows current options. Update both `pre-pull.sh` and `demo-03-sampling/compose.yaml`.

---

## Phase 2 — Demo 01 (auto vs manual instrumentation, 10 min)

The simplest demo — if this works, your podman + lgtm + Spring Boot baseline is healthy.

### 2.1 — Cold start the stack

```bash
cd demo-01-auto-vs-manual
./demo.sh up
```

**Watch for:**
- "Grafana healthy" appears within ~30s
- "Service healthy" appears within ~90s
- No SELinux denials in `journalctl -t setroubleshoot` (only relevant on Fedora)

**Acceptance criteria:**
- [ ] `curl http://localhost:8081/actuator/health` returns `{"status":"UP"...}`
- [ ] `curl http://localhost:3001/api/health` returns `{"database":"ok"...}`
- [ ] `curl http://localhost:8081/hello` returns the greeting JSON

**Fallback — `:Z` SELinux denial:**
Symptom: container exits, `podman logs demo01-service` shows `Permission denied` reading `/otel-lgtm/grafana/conf/...`. Fedora-specific. Check `getenforce` is `Enforcing`. The `:Z` flag in `compose.yaml` should handle this; if not, run `setenforce 0` to confirm SELinux is the cause, then put it back to `Enforcing` and inspect `audit2why -a`.

**Fallback — Maven build fails inside container:**
Symptom: `podman compose build` errors during the `mvn package` step. Most common cause: the Spring Boot 4.0.4 dependency couldn't resolve (network issue or repo redirect). Check `podman build --no-cache demo-01-auto-vs-manual/service` for the full error.

---

### 2.2 — Verify telemetry is flowing

Open Grafana at `http://localhost:3001` (anonymous login configured, no creds).

```bash
# Generate some traffic
curl -s 'http://localhost:8081/hello?name=test' >/dev/null
for i in 1 2 3 4 5; do
  curl -s "http://localhost:8081/work?sizeMs=100" >/dev/null
done
```

In the Grafana UI:
1. Click **Explore** (compass icon)
2. Select **Tempo** datasource
3. Hit **Run query** with default settings — recent traces should appear
4. Click any trace to expand the span tree

**Acceptance criteria:**
- [ ] Tempo shows traces for `GET /hello`, `GET /work`, `GET /actuator/health`
- [ ] `/work` traces have a child span called `compute.fibonacci` with attributes `workload=fibonacci` and `size_ms=N`
- [ ] Switch to **Loki** datasource, query `{service_name="demo01-service"}` — log lines appear with `[traceId,spanId]` prefix
- [ ] Click a `traceId` in a log line → it should open in Tempo

**Fallback — no traces in Tempo:**
1. Verify the agent attached: `podman exec demo01-service env | grep AGENT_ENABLED` should show `true` after `./demo.sh` flips it. If it shows `false`, the demo is in baseline mode. Run `./demo.sh` (the full run, not just `up`) to walk through the modes.
2. Check the agent's startup log: `podman logs demo01-service 2>&1 | head -50` — should mention `[otel.javaagent]` lines.
3. Verify the export endpoint: `podman exec demo01-service env | grep OTEL_EXPORTER` — should be `http://lgtm:4318`. If it's `localhost:...`, the env wasn't picked up; restart the container.

---

### 2.3 — Tear down

```bash
./demo.sh down
```

**Acceptance criteria:**
- [ ] `podman ps` shows nothing matching `demo01-*`
- [ ] Port 3001 / 8081 are free again

---

## Phase 3 — Demo 02 (the headline correlation demo, 15 min)

The most important demo of the talk. Over-rehearse the click path.

### 3.1 — Cold start

```bash
cd ../demo-02-correlation
./demo.sh up
```

**Acceptance criteria:**
- [ ] All three healthchecks pass (lgtm, inventory-service, order-service)
- [ ] `curl http://localhost:8082/orders/random` returns a JSON with a sku and stock
- [ ] `curl http://localhost:8092/admin/inject` returns `{"latencyMs":0,"errorRate":0.0,"active":false}`

**Fallback — `order-service` can't reach `inventory-service`:**
Symptom: `curl /orders/random` returns a 502 with "inventory unavailable". Check that both containers are on the same compose network: `podman network inspect otel-demo-02_default` should list both. If not, recreate: `./demo.sh down && ./demo.sh up`.

---

### 3.2 — Generate baseline traffic

```bash
hey -z 30s -q 15 -c 4 http://localhost:8082/orders/random >/dev/null
```

Open `http://localhost:3002/d/demo02-correlation` — the headline dashboard.

**Acceptance criteria:**
- [ ] Both services show on the **HTTP server p99 latency** chart
- [ ] **Request rate by service** shows ~15 RPS for `order-service` and matching for `inventory-service`
- [ ] **5xx error rate** is flat at zero
- [ ] **Service logs** panel shows interleaved log lines from both services with traceId prefixes

**Fallback — exemplar dots not appearing:**
Symptom: latency chart shows lines but no clickable dots. Check that the histogram panel has `exemplar: true` (it does in the provisioned dashboard). The exemplar needs the request to have happened in the last few seconds — wait 30s after traffic completes for older exemplars to age out, or refresh the dashboard. If you see *no* dots ever, verify `management.metrics.distribution.percentiles-histogram.http.server.requests=true` is in `application.yml` for both services (it is).

---

### 3.3 — The Pivot (THIS IS THE DEMO)

```bash
# Inject the fault
curl -sf -X POST 'http://localhost:8092/admin/inject?latencyMs=500&errorRate=0.05' | jq .

# Generate traffic with fault active
hey -z 30s -q 15 -c 4 http://localhost:8082/orders/random >/dev/null
```

Within ~10s the dashboard p99 should climb noticeably. Now do the **five-step pivot live**:

1. **Hover the histogram on the spike** — find a colored exemplar dot at the top of the curve
2. **Click the dot** — Tempo opens the trace
3. **Expand the trace tree** — find the `inventory.findStock` span (the slow one)
4. **Click "Logs for this span"** — Loki opens, filtered by traceId
5. **Read the error log line** — should say "downstream inventory database connection refused"

**Time yourself.** Practice until you can do this in 15-20 seconds with the audience watching.

**Acceptance criteria:**
- [ ] p99 visibly rises within 10s of fault injection
- [ ] At least one exemplar dot is clickable on the spike
- [ ] Clicking the dot opens Tempo and shows a trace
- [ ] The trace tree includes spans from both `order-service` and `inventory-service` (W3C context propagation works)
- [ ] "Logs for this span" produces filtered Loki results
- [ ] Log lines include the simulated error message

**Fallback — Tempo doesn't open from the exemplar click:**
Datasource correlation issue. In Grafana UI: Configuration → Data sources → Prometheus → "Exemplars" section should show `trace_id` mapped to Tempo. If it isn't, restart the lgtm container; provisioning runs at startup.

**Fallback — "Logs for this span" returns nothing:**
The Tempo→Loki linkage is by `service.name` resource attribute and time window. Check the datasource config: Configuration → Data sources → Tempo → "Trace to logs". The span time-shift defaults to ±1m. If the slow span is older than that, refresh the Tempo trace and try again. If still nothing, verify Loki has logs for that traceId: query `{service_name="inventory-service"} |= "<traceId>"` in Explore.

---

### 3.4 — Tear down

```bash
./demo.sh clear   # turn off fault
./demo.sh down
```

---

## Phase 4 — Demo 03 (sampling, 15 min)

First demo with the standalone Collector — verifies the contrib image, the tail_sampling processor, and the head/tail config switching mechanic.

### 4.1 — Cold start (head mode default)

```bash
cd ../demo-03-sampling
./demo.sh up head
```

**Acceptance criteria:**
- [ ] All three containers up: `demo03-lgtm`, `demo03-collector`, `demo03-service`
- [ ] `curl http://localhost:8083/work` returns `{"status":"ok","kind":"fast"}`
- [ ] `curl http://localhost:8083/work/slow` takes >1s and returns `kind:slow`
- [ ] `curl http://localhost:8083/work/error` returns 500
- [ ] `podman logs demo03-collector 2>&1 | head -20` shows `Everything is ready. Begin running and processing data.`

**Fallback — Collector exits at startup:**
Symptom: `demo03-collector` is in `Exited` state. Run `podman logs demo03-collector` — most common: bad YAML in `otelcol/config.yaml`. Verify by checking `cat otelcol/config.yaml` matches one of the templates. The first run of `./demo.sh up head` should have copied `config-head.yaml` to `config.yaml`.

**Fallback — `tail_sampling` processor not found:**
Symptom (when switching to tail mode later): Collector logs `processor "tail_sampling" not available`. The contrib image should have it; if it doesn't, the image tag may have changed. `podman exec demo03-collector /otelcol-contrib components 2>&1 | grep tail_sampling` confirms.

---

### 4.2 — Verify head sampling cuts traffic

```bash
hey -z 20s -q 30 -c 4 http://localhost:8083/work/random >/dev/null
sleep 5

# Probe Collector's own metrics
curl -sf "http://localhost:3003/api/datasources/proxy/uid/prometheus/api/v1/query?query=otelcol_receiver_accepted_spans_total" | jq -r '.data.result[0].value[1]'
curl -sf "http://localhost:3003/api/datasources/proxy/uid/prometheus/api/v1/query?query=otelcol_exporter_sent_spans_total" | jq -r '.data.result[0].value[1]'
```

**Acceptance criteria:**
- [ ] Both numbers are positive
- [ ] In head mode, **received and exported should be roughly equal** (both small — only ~5% of traces left the JVM thanks to app-side sampling)
- [ ] `podman exec demo03-service env | grep OTEL_TRACES_SAMPLER_ARG` shows `0.05`

---

### 4.3 — Switch to tail sampling, observe the change

```bash
./demo.sh switch tail
sleep 10  # let services restart
hey -z 30s -q 30 -c 4 http://localhost:8083/work/random >/dev/null
sleep 15  # wait for tail decision_wait window

# Re-probe
curl -sf "http://localhost:3003/api/datasources/proxy/uid/prometheus/api/v1/query?query=otelcol_receiver_accepted_spans_total" | jq -r '.data.result[0].value[1]'
curl -sf "http://localhost:3003/api/datasources/proxy/uid/prometheus/api/v1/query?query=otelcol_exporter_sent_spans_total" | jq -r '.data.result[0].value[1]'
```

**Acceptance criteria:**
- [ ] **Received >> Exported now** — the Collector is dropping ~95% of healthy traces but keeping every error and every slow trace
- [ ] In Tempo (Explore → Tempo): filter by `status=error` — you should find essentially every `/work/error` you generated
- [ ] In Tempo: filter by latency > 1s — you should find essentially every `/work/slow` you generated
- [ ] In Tempo: filter by latency < 100ms — you should find ~5% of `/work` calls

**Fallback — exported count stays equal to received in tail mode:**
Tail policies aren't matching. Check `otelcol/config.yaml` is the tail variant: `head -3 otelcol/config.yaml`. Should mention "tail sampling mode". If it shows the head template, `./demo.sh switch tail` failed silently — re-run.

---

### 4.4 — Tear down

```bash
./demo.sh down
```

---

## Phase 5 — Demo 04 (GC pauses, 20 min)

The longest demo to walk through because of the three-GC sweep.

### 5.1 — Cold start with default GC (Shenandoah)

```bash
cd ../demo-04-gc-pauses
./demo.sh up shenandoah
```

**Acceptance criteria:**
- [ ] Service responds at `http://localhost:8084/work`
- [ ] `podman exec demo04-service jcmd 1 VM.flags 2>&1 | grep -E "UseShenandoah|UseG1GC|UseZGC"` shows **Shenandoah on**, others off

**Fallback — service exits at startup:**
Symptom: container in `Exited` state, logs show JVM error. Most common: `-Xms256m -Xmx256m` is too small for Spring Boot 4.0 with the OTel agent — bump to 384m or 512m in `compose.yaml` and retry.

---

### 5.2 — Generate allocation pressure, verify GC metrics flow

```bash
hey -z 30s -q 8 -c 4 'http://localhost:8084/allocate?sizeKb=64&objects=2000' >/dev/null
sleep 5

# Probe a GC histogram
curl -sf "http://localhost:3004/api/datasources/proxy/uid/prometheus/api/v1/query?query=jvm_gc_pause_seconds_count" | jq -r '.data.result | length'
```

**Acceptance criteria:**
- [ ] Result count > 0 (GC events have been recorded)
- [ ] Open `http://localhost:3004/d/demo04-gc` — the JVM GC pause percentile chart shows data
- [ ] The "GC events / sec by action and cause" panel shows recent GC activity

**Fallback — `gc_mode` label missing on metrics:**
Symptom: legend shows just `p99` instead of `p99 — shenandoah`. The label has to come from `OTEL_RESOURCE_ATTRIBUTES`. Verify: `podman exec demo04-service env | grep OTEL_RESOURCE_ATTRIBUTES` should include `gc.mode=shenandoah`. If yes but the label still doesn't show on Prom queries, OTel resource attributes aren't being mapped to Prometheus labels by lgtm's internal converter — check `application.yml` and add an explicit Micrometer common tag:

```yaml
management:
  metrics:
    tags:
      gc_mode: ${GC_MODE:-shenandoah}
```

This needs the env var on the service side (already passed from compose).

---

### 5.3 — Sweep G1 and ZGC

```bash
./demo.sh run g1
# script will restart the service and run the workload
# (~1 minute)
```

When prompted, check the dashboard. The p99 GC pause series should now have a noticeably higher peak — typically 30-100ms vs Shenandoah's 5-10ms.

```bash
./demo.sh run zgc
```

This run should show p99 below 1ms.

**Acceptance criteria:**
- [ ] After all three runs, the dashboard's p99 chart shows three distinct series with three distinct typical pause ranges
- [ ] Shenandoah p99: 5-15ms typical
- [ ] G1 p99: 30-100ms typical
- [ ] ZGC p99: < 5ms typical (often < 1ms)

**Capture these numbers** — they go into `BENCHMARKS.md` and the bonus slides.

**Fallback — ZGC won't start:**
Symptom: container exits with "ZGC requires JDK..." error. JDK 21 is fine for ZGC, but generational ZGC requires `-XX:+ZGenerational` (it's not the default until JDK 25). The compose flags in `gc_flags_for "zgc"` already include this. If still failing, drop `+ZGenerational` and re-run; you'll just get non-generational ZGC, which still demonstrates the sub-millisecond-pause point.

---

### 5.4 — Update BENCHMARKS.md

```bash
# Edit BENCHMARKS.md and fill in the Demo 04 table with your real numbers
```

Open `BENCHMARKS.md`, find the "Demo 04 — GC Pause Distribution" section, and replace the `TBD` entries with the values you observed.

**Acceptance criteria:**
- [ ] BENCHMARKS.md committed to git with real numbers

---

### 5.5 — Tear down

```bash
./demo.sh down
```

---

## Phase 6 — Demo 05 (AOT cold start, 20 min)

The most complex build — AOT cache requires JDK 25 to behave correctly. **First-time build is slow** (~3 min for AOT image due to training run).

### 6.1 — Build both images

```bash
cd ../demo-05-aot-coldstart
./demo.sh build
```

**Acceptance criteria:**
- [ ] `service-classic` image builds (~1 min)
- [ ] `service-aot` image builds, including these log lines:
  - `AOT config recorded (NNNN bytes)` (training stage)
  - `AOT cache assembled (~150M)` (assemble stage)

**Fallback — AOT training stage fails:**
This is the highest-risk part. Symptoms and fixes:

- *"`-XX:AOTMode` not recognized"* — flag spelling has shifted in your JDK 25 build. Inside the builder image: `podman run --rm registry.access.redhat.com/ubi9/openjdk-25:1.24 java -XX:+PrintFlagsFinal 2>&1 | grep -i aot` to see what AOT flags exist. Common alternatives: `-XX:CacheMode=record`, `-XX:AOTConfiguration` may be `-XX:CDSConfiguration`. Update Containerfile flags to match.

- *Training run dies before recording finishes* — increase `sleep 8` to `sleep 15` in the Containerfile's training stage. Slow CI hardware needs more time for Spring Boot context to fully load.

- *AOT cache assembles but runtime fails to load it* — JDK version mismatch between assemble stage and runtime stage. They both use `:1.24` so should match; if Red Hat ships a `:1.24-2` while you're working, pin both stages to the same exact tag.

**Fallback — OTel agent conflicts with AOT cache:**
Symptom: `service-aot` container exits with classloader errors mentioning the agent. The agent does bytecode rewriting at startup, which can fight with AOT-cached class data. Workaround: drop the agent from `service-aot`, use the SDK-only OTLP path. Edit `compose.yaml` to remove the `-javaagent:` line from `service-aot`'s `JAVA_TOOL_OPTIONS`. The Spring Boot Micrometer + OTel exporter path will still work; you just lose the auto-instrumented HTTP client/server spans (Micrometer Observation provides equivalents).

---

### 6.2 — Time the cold starts

```bash
./demo.sh time-classic
# 3 boot cycles, reports median in ms
```

```bash
./demo.sh time-aot
# 3 boot cycles, reports median in ms
```

**Acceptance criteria:**
- [ ] Classic median: typically 2500-4000 ms
- [ ] AOT median: typically 500-1200 ms
- [ ] Speedup: 3x-5x

**Fallback — AOT cold start is barely faster than classic:**
The training run didn't capture enough to be useful. In the Containerfile training stage, add more endpoint hits:

```dockerfile
# inside the training stage, after curl /actuator/health
curl -sf http://localhost:8080/hello >/dev/null 2>&1 || true
sleep 2
curl -sf http://localhost:8080/actuator/metrics >/dev/null 2>&1 || true
```

Rebuild and retime.

**Capture these numbers** for `BENCHMARKS.md`.

---

### 6.3 — Bring both up for the live walkthrough

```bash
./demo.sh up
```

Open Grafana at `http://localhost:3005/d/demo05-aot`. Both services should appear in the legend.

**Acceptance criteria:**
- [ ] Tempo shows startup spans for both `service-classic` and `service-aot`
- [ ] Looking at a `service-aot` startup trace, the class-loading and bean-instantiation spans are visibly shorter than the same spans on `service-classic`

**Fallback — startup traces don't appear:**
Spring Boot's startup spans require either the actuator's startup endpoint enabled (we have it) or the OTel agent's `spring-boot-autoconfigure-2.0` instrumentation. Verify: `curl http://localhost:8085/actuator/startup | jq` should return startup steps. If it does, but Tempo doesn't show them as spans, the OTel agent may need `-Dotel.instrumentation.spring-boot-autoconfigure.enabled=true`. Add to `JAVA_TOOL_OPTIONS` and restart.

---

### 6.4 — Update BENCHMARKS.md and tear down

```bash
./demo.sh down
```

Edit `BENCHMARKS.md`'s "Demo 05 — AOT Cold Start" table with your numbers, commit, push.

---

## Phase 7 — Slide deck verification (10 min)

### 7.1 — Open the deck in a browser

```bash
xdg-open presentation/slides.html
```

**Acceptance criteria:**
- [ ] All 32 sections render — press `→` arrow to advance
- [ ] Press `S` — speaker notes window opens
- [ ] Each section's notes match what's in `PRESENTER-GUIDE.md`
- [ ] No broken links to fonts (Bricolage Grotesque, Manrope, JetBrains Mono should all load — check Network tab in browser DevTools if any aren't loading)
- [ ] Dark navy background, teal accents — visually matches the diagram palette

**Fallback — fonts don't load (offline venue):**
Download the font files locally and serve from a `presentation/fonts/` directory. Update the `<link>` tags to local paths. Or accept the fallback to system fonts; the deck still works.

**Fallback — Reveal.js plugin loading fails:**
The deck loads from cdn.jsdelivr.net. If your venue's network blocks that, download `reveal.js@5.1.0` to `presentation/reveal/` and update three `<link>`/`<script>` tags. ~5 minutes of work.

---

### 7.2 — Diagram placeholder slides (slides 6, 13, 15, 18, 22, 24, 28, B2)

These currently show text placeholders pointing at the `.excalidraw` filenames. To replace with actual rendered diagrams:

1. Open each `.excalidraw` file at https://excalidraw.com (drag-and-drop)
2. Refine layout, add visual polish, export as PNG with dark background (File → Export image)
3. Save into `presentation/img/` (create the dir)
4. In `slides.html`, find each `<div class="diagram-placeholder">...</div>` block and replace with `<img src="img/08-otel-signal-flow.png" alt="..." style="max-width:90%;max-height:75vh;" />`

**Acceptance criteria for full polish (optional, can defer):**
- [ ] Each of the 9 diagrams has been opened and refined in Excalidraw
- [ ] PNG exports exist in `presentation/img/`
- [ ] All 8 `diagram-placeholder` divs replaced with `<img>` tags

**This is the optional step.** The talk works with placeholders if you're tight on time — the placeholder text tells you what the diagram should show, and the speaker notes are still there.

---

## Phase 8 — Final dress rehearsal (30 min)

### 8.1 — Clean slate

```bash
podman ps -aq | xargs -r podman rm -f
podman volume prune -f
./verify-stacks.sh
```

**Acceptance criteria:**
- [ ] `verify-stacks.sh` reports **5/5 passed**

This is the single check that catches everything. Each demo's compose comes up cleanly, healthcheck passes, tears down cleanly.

---

### 8.2 — Run-through with a timer

Pretend you're presenting. Open the deck. Click through, talking aloud, running each demo at the right slide.

**Time targets:**

| Section | Target | Cumulative |
|---|---|---|
| Open | 3 min | 0:03 |
| §1 fundamentals | 4 min | 0:07 |
| §2 + Demo 01 | 7 min | 0:14 |
| §3 OTel vs Prom | 4 min | 0:18 |
| §4 LGTM stack | 5 min | 0:23 |
| §5 + Demo 02 (headline) | 9 min | 0:32 |
| §6 + Demo 03 | 7 min | 0:39 |
| §7 + Demo 04 + Demo 05 | 7 min | 0:46 |
| §8 OpenShift | 4 min | 0:50 |
| Close | 2 min | 0:52 |
| Q&A | 8 min | 1:00 |

If any segment runs long, candidates to compress: §3 (cut to 2 min), §8 (cut to 3 min), Demo 04 (run only Shenandoah live, mention the others).

**Acceptance criteria:**
- [ ] Full run completes in ≤ 60 minutes including Q&A
- [ ] Demo 02 pivot performed in ≤ 20s
- [ ] No demo failures during the rehearsal
- [ ] Speaker notes referenced for at most ~3 slides total (the rest you should know cold)

---

### 8.3 — Backup contingencies

For each demo, capture screenshots of the dashboard in working state. Save to `presentation/screenshots/`:

```bash
mkdir -p presentation/screenshots
# After each demo verification, while the dashboard is showing the right state,
# take a screenshot and save as e.g. demo-02-pivot.png
```

If a demo fails live, switch to the screenshot, narrate what would have happened, move on. Lost demo < lost momentum.

**Acceptance criteria:**
- [ ] One screenshot per demo dashboard, in working state
- [ ] Screenshots committed to the repo

---

## Talk-day morning checklist (5 min)

```bash
cd otel-observability-demos
./pre-pull.sh                          # refresh images
./verify-stacks.sh                     # smoke test all five demos
xdg-open presentation/slides.html      # open deck, press S for speaker view
```

- [ ] All images present and recent
- [ ] All five stacks verified
- [ ] Deck loads, speaker view works
- [ ] Browser bookmarks ready: dashboards for demos 01-05
- [ ] Terminal font-size scaled for projector (18-22pt typical)
- [ ] Phone has hotspot ready in case venue Wi-Fi fails (for CDN-loaded reveal.js)

---

## Common-issues quick reference

| Symptom | First thing to check |
|---|---|
| Container exits immediately | `podman logs <name>` — usually startup error in Spring Boot |
| Container builds but won't start | Healthcheck timeout too short; bump `start_period` |
| `:Z` permission denied | `getenforce` — should be Enforcing; check `audit2why -a` |
| `localhost:` in container env | `OTEL_EXPORTER_OTLP_ENDPOINT` should use service-name, not localhost |
| Tempo empty | Agent not attached, or wrong endpoint |
| Loki has no logs | Logback pattern missing `%X{traceId}` |
| Exemplars not clickable | Histogram not configured, or PromQL query missing `exemplar: true` |
| Span context broken across services | Check `traceparent` header on the inter-service call |
| `tail_sampling` not found | Wrong Collector image — needs `-contrib`, not core |
| `-XX:AOTMode` not recognized | JDK version check; flag names shifted in EA builds |
| GC labels missing in dashboard | `OTEL_RESOURCE_ATTRIBUTES` not propagating to Prom labels |

---

## Sign-off

When everything above checks out:

```bash
git add BENCHMARKS.md presentation/screenshots/
git commit -m "chore: real benchmarks + dashboard screenshots from dress rehearsal"
git push
```

Now you're ready to present.
