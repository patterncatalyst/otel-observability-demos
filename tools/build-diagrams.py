#!/usr/bin/env python3
"""
Generate skeleton .excalidraw JSON files for the talk's 9 diagrams.

These are intentionally MINIMAL — boxes, labels, arrows in roughly the right
positions, in the project color palette. Open in Excalidraw and refine.

Palette (matches presentation theme):
  bg     = #0A1628 dark navy
  card   = #122040
  teal   = #00BCD4 accent (headings, primary callouts)
  blue   = #1E6FC8 (section tags, info)
  coral  = #E84855 (anti-patterns, warnings)
  green  = #27AE60 (success, fixes)
  orange = #F5A623 (caution)
  purple = #9B59B6 (bonus content, JDK 25)
  text   = #ECF0F1
"""

import json
import os
import random
import time

OUT_DIR = "/home/claude/otel-observability-demos/diagrams"
os.makedirs(OUT_DIR, exist_ok=True)

PALETTE = {
    "bg":     "#0A1628",
    "card":   "#122040",
    "teal":   "#00BCD4",
    "blue":   "#1E6FC8",
    "coral":  "#E84855",
    "green":  "#27AE60",
    "orange": "#F5A623",
    "purple": "#9B59B6",
    "text":   "#ECF0F1",
    "muted":  "#90A4AE",
}

NOW_MS = int(time.time() * 1000)
_id_counter = [0]
_seed = [42]


def gen_id():
    _id_counter[0] += 1
    return f"el_{_id_counter[0]:06d}"


def gen_seed():
    _seed[0] = (_seed[0] * 1103515245 + 12345) & 0x7FFFFFFF
    return _seed[0]


def base_props():
    return {
        "version": 1,
        "versionNonce": gen_seed(),
        "isDeleted": False,
        "fillStyle": "solid",
        "strokeWidth": 2,
        "strokeStyle": "solid",
        "roughness": 1,
        "opacity": 100,
        "angle": 0,
        "groupIds": [],
        "frameId": None,
        "roundness": None,
        "boundElements": [],
        "updated": NOW_MS,
        "link": None,
        "locked": False,
    }


def rect(x, y, w, h, stroke=PALETTE["teal"], bg="transparent", round_radius=8):
    el = base_props()
    el.update({
        "type": "rectangle",
        "id": gen_id(),
        "x": x, "y": y,
        "width": w, "height": h,
        "strokeColor": stroke,
        "backgroundColor": bg,
        "seed": gen_seed(),
        "roundness": {"type": 3, "value": round_radius} if round_radius else None,
    })
    return el


def diamond(x, y, w, h, stroke=PALETTE["orange"]):
    el = base_props()
    el.update({
        "type": "diamond",
        "id": gen_id(),
        "x": x, "y": y,
        "width": w, "height": h,
        "strokeColor": stroke,
        "backgroundColor": "transparent",
        "seed": gen_seed(),
    })
    return el


def ellipse(x, y, w, h, stroke=PALETTE["teal"], bg="transparent"):
    el = base_props()
    el.update({
        "type": "ellipse",
        "id": gen_id(),
        "x": x, "y": y,
        "width": w, "height": h,
        "strokeColor": stroke,
        "backgroundColor": bg,
        "seed": gen_seed(),
    })
    return el


def text(x, y, content, size=18, color=PALETTE["text"], align="center", w=None, h=None):
    # Excalidraw is forgiving about text dimensions; we estimate then let it re-layout
    if w is None:
        # rough heuristic
        w = max(120, int(len(max(content.split("\n"), key=len)) * size * 0.55))
    if h is None:
        h = int(content.count("\n") + 1) * (size + 8)
    el = base_props()
    el.update({
        "type": "text",
        "id": gen_id(),
        "x": x, "y": y,
        "width": w, "height": h,
        "strokeColor": color,
        "backgroundColor": "transparent",
        "seed": gen_seed(),
        "text": content,
        "fontSize": size,
        "fontFamily": 1,        # 1 = handwritten (Virgil), 2 = normal, 3 = code
        "textAlign": align,
        "verticalAlign": "middle",
        "containerId": None,
        "originalText": content,
        "lineHeight": 1.25,
        "autoResize": True,
    })
    return el


def arrow(x1, y1, x2, y2, stroke=PALETTE["text"], style="solid", thick=2):
    el = base_props()
    el.update({
        "type": "arrow",
        "id": gen_id(),
        "x": x1, "y": y1,
        "width": x2 - x1, "height": y2 - y1,
        "strokeColor": stroke,
        "backgroundColor": "transparent",
        "strokeStyle": style,
        "strokeWidth": thick,
        "seed": gen_seed(),
        "points": [[0, 0], [x2 - x1, y2 - y1]],
        "lastCommittedPoint": None,
        "startBinding": None,
        "endBinding": None,
        "startArrowhead": None,
        "endArrowhead": "arrow",
        "elbowed": False,
    })
    return el


def line(x1, y1, x2, y2, stroke=PALETTE["muted"], style="dashed"):
    el = base_props()
    el.update({
        "type": "line",
        "id": gen_id(),
        "x": x1, "y": y1,
        "width": x2 - x1, "height": y2 - y1,
        "strokeColor": stroke,
        "backgroundColor": "transparent",
        "strokeStyle": style,
        "seed": gen_seed(),
        "points": [[0, 0], [x2 - x1, y2 - y1]],
        "lastCommittedPoint": None,
    })
    return el


def write_diagram(filename, elements, title):
    """Write a diagram with a title in the top-left."""
    title_el = text(40, 30, title, size=28, color=PALETTE["teal"], align="left", w=900, h=40)
    doc = {
        "type": "excalidraw",
        "version": 2,
        "source": "https://excalidraw.com",
        "elements": [title_el] + elements,
        "appState": {
            "viewBackgroundColor": PALETTE["bg"],
            "currentItemFontFamily": 1,
            "currentItemStrokeColor": PALETTE["text"],
            "currentItemBackgroundColor": "transparent",
            "gridSize": 20,
            "gridStep": 5,
        },
        "files": {},
    }
    path = os.path.join(OUT_DIR, filename)
    with open(path, "w") as f:
        json.dump(doc, f, indent=2)
    print(f"  wrote {path} ({len(elements) + 1} elements)")


# =============================================================================
# Diagram 08 — OTel Signal Flow
# =============================================================================
def diagram_08():
    """Three swim lanes (metrics/logs/traces) flowing app -> SDK -> OTLP -> Collector -> backends.
    Highlight the shared traceId line crossing all three lanes."""
    els = []

    # App box (left)
    els.append(rect(60, 120, 160, 360, stroke=PALETTE["teal"], bg=PALETTE["card"]))
    els.append(text(60, 130, "Spring Boot\nApp", size=20, color=PALETTE["teal"], w=160))

    # Three swim lanes
    lanes = [
        ("Metrics", PALETTE["green"], 180),
        ("Logs",    PALETTE["orange"], 280),
        ("Traces",  PALETTE["purple"], 380),
    ]
    for label, color, y in lanes:
        # Lane box for the SDK side
        els.append(rect(260, y, 120, 60, stroke=color))
        els.append(text(260, y + 10, label + " SDK", size=14, color=color, w=120))
        # Arrow into Collector
        els.append(arrow(385, y + 30, 555, 280, stroke=color))

    # Collector (middle)
    els.append(rect(560, 220, 200, 120, stroke=PALETTE["teal"], bg=PALETTE["card"]))
    els.append(text(560, 240, "OTel\nCollector", size=22, color=PALETTE["teal"], w=200))
    els.append(text(560, 295, "(OTLP receiver,\nbatching, processors)", size=12, color=PALETTE["muted"], w=200))

    # Backends (right)
    backends = [
        ("Prometheus / Mimir", PALETTE["green"],  140),
        ("Loki",                PALETTE["orange"], 270),
        ("Tempo",               PALETTE["purple"], 400),
    ]
    for label, color, y in backends:
        els.append(rect(820, y, 180, 80, stroke=color, bg=PALETTE["card"]))
        els.append(text(820, y + 25, label, size=18, color=color, w=180))
        els.append(arrow(770, 280, 815, y + 40, stroke=color))

    # Shared traceId line (the takeaway)
    els.append(line(60, 540, 1000, 540, stroke=PALETTE["coral"], style="dashed"))
    els.append(text(60, 550, "traceId  ━━━━━ shared across all three signals  (this is what makes correlation work)",
                    size=16, color=PALETTE["coral"], align="left", w=940))

    write_diagram("08-otel-signal-flow.excalidraw", els,
                  "08 — OTel Signal Flow")


# =============================================================================
# Diagram 09 — Instrumentation Modes
# =============================================================================
def diagram_09():
    """Three columns: auto / manual / hybrid. Tradeoffs row at bottom."""
    els = []
    cols = [
        ("Auto-Instrumentation",    "-javaagent:opentelemetry-\njavaagent.jar",         PALETTE["green"],  60),
        ("Manual Instrumentation",  "Span span = tracer\n  .spanBuilder(\"work\")\n  .startSpan();", PALETTE["orange"], 420),
        ("Hybrid (recommended)",    "Micrometer Observation\n  + auto-agent\n  + custom spans", PALETTE["teal"],   780),
    ]

    for title, code, color, x in cols:
        els.append(rect(x, 100, 320, 360, stroke=color, bg=PALETTE["card"]))
        els.append(text(x, 115, title, size=20, color=color, w=320))
        # Code box
        els.append(rect(x + 20, 165, 280, 110, stroke=PALETTE["muted"]))
        els.append(text(x + 20, 175, code, size=12, color=PALETTE["text"], w=280))
        # Tradeoffs
        els.append(text(x, 295, "Pros:", size=14, color=PALETTE["green"], align="left", w=320))
        els.append(text(x, 380, "Cons:", size=14, color=PALETTE["coral"], align="left", w=320))

    # Tradeoff captions (placeholders — fill in)
    pros = [
        "no code changes\n~120 libs covered\nfast to enable",
        "full control\nbusiness spans\nsurgical precision",
        "auto for seams\nmanual for domain\nbest of both"
    ]
    cons = [
        "5-10% startup hit\noccasional surprises\ncoarse semantic conv.",
        "you own maintenance\nslow to adopt new\nrisk of gaps",
        "two systems\nteach the team\nmore configuration"
    ]
    for (text_pros, text_cons), (_, _, color, x) in zip(zip(pros, cons), cols):
        els.append(text(x + 10, 320, text_pros, size=11, color=PALETTE["text"], align="left", w=300))
        els.append(text(x + 10, 405, text_cons, size=11, color=PALETTE["text"], align="left", w=300))

    write_diagram("09-instrumentation-modes.excalidraw", els,
                  "09 — Instrumentation Modes")


# =============================================================================
# Diagram 10 — OpenTelemetry vs Prometheus
# =============================================================================
def diagram_10():
    """Two boxes (Prom / OTel) with a Collector bridge between them."""
    els = []

    # Prom box (left)
    els.append(rect(60, 140, 320, 320, stroke=PALETTE["orange"], bg=PALETTE["card"]))
    els.append(text(60, 155, "Prometheus", size=24, color=PALETTE["orange"], w=320))
    prom_facts = [
        "• PULL-based",
        "• /actuator/prometheus",
        "• PromQL",
        "• Time-series only",
        "• Cardinality-bounded",
        "• Single-zone friendly"
    ]
    for i, f in enumerate(prom_facts):
        els.append(text(80, 200 + i * 35, f, size=15, color=PALETTE["text"], align="left", w=300))

    # OTel box (right)
    els.append(rect(720, 140, 320, 320, stroke=PALETTE["teal"], bg=PALETTE["card"]))
    els.append(text(720, 155, "OpenTelemetry", size=24, color=PALETTE["teal"], w=320))
    otel_facts = [
        "• PUSH-based (OTLP)",
        "• Multi-signal: M / L / T",
        "• Vendor-neutral",
        "• Semantic conventions",
        "• Exemplars built-in",
        "• Backend-agnostic"
    ]
    for i, f in enumerate(otel_facts):
        els.append(text(740, 200 + i * 35, f, size=15, color=PALETTE["text"], align="left", w=300))

    # Bridge: OTel Collector
    els.append(rect(420, 240, 260, 120, stroke=PALETTE["green"], bg=PALETTE["card"]))
    els.append(text(420, 255, "OTel Collector", size=20, color=PALETTE["green"], w=260))
    els.append(text(420, 295, "the bridge", size=14, color=PALETTE["muted"], w=260))
    els.append(text(420, 320, "scrape Prom → OTLP\nor remote_write OTLP → Prom", size=12, color=PALETTE["text"], w=260))

    # Bidirectional arrows
    els.append(arrow(380, 280, 415, 280, stroke=PALETTE["text"]))
    els.append(arrow(415, 320, 380, 320, stroke=PALETTE["text"]))
    els.append(arrow(685, 280, 720, 280, stroke=PALETTE["text"]))
    els.append(arrow(720, 320, 685, 320, stroke=PALETTE["text"]))

    # Bottom takeaway
    els.append(text(60, 510, "→ AND, not OR.  Most production deployments run both.", size=18, color=PALETTE["coral"], align="left", w=980))

    write_diagram("10-otel-vs-prometheus.excalidraw", els,
                  "10 — OTel vs Prometheus (Together)")


# =============================================================================
# Diagram 11 — LGTM Architecture
# =============================================================================
def diagram_11():
    """otel-lgtm internals: app -> embedded Collector -> Tempo/Loki/Prom -> Grafana."""
    els = []

    # Outer dashed box = podman boundary
    els.append(rect(220, 90, 760, 460, stroke=PALETTE["muted"], round_radius=12))
    els.append(text(232, 100, "podman", size=12, color=PALETTE["muted"], align="left", w=80))

    # App on the left, OUTSIDE the lgtm box
    els.append(rect(60, 230, 120, 100, stroke=PALETTE["teal"], bg=PALETTE["card"]))
    els.append(text(60, 250, "Spring Boot\n+ OTel agent", size=14, color=PALETTE["teal"], w=120))

    # Collector inside
    els.append(rect(260, 230, 160, 100, stroke=PALETTE["green"], bg=PALETTE["card"]))
    els.append(text(260, 245, "Collector", size=16, color=PALETTE["green"], w=160))
    els.append(text(260, 280, "(receivers,\nprocessors,\nexporters)", size=11, color=PALETTE["muted"], w=160))

    # Three stores
    els.append(rect(480, 130, 180, 80, stroke=PALETTE["green"], bg=PALETTE["card"]))
    els.append(text(480, 150, "Prometheus\n(Mimir)", size=14, color=PALETTE["green"], w=180))

    els.append(rect(480, 240, 180, 80, stroke=PALETTE["orange"], bg=PALETTE["card"]))
    els.append(text(480, 260, "Loki", size=16, color=PALETTE["orange"], w=180))

    els.append(rect(480, 350, 180, 80, stroke=PALETTE["purple"], bg=PALETTE["card"]))
    els.append(text(480, 370, "Tempo", size=16, color=PALETTE["purple"], w=180))

    # Grafana on the right
    els.append(rect(740, 230, 200, 120, stroke=PALETTE["teal"], bg=PALETTE["card"]))
    els.append(text(740, 250, "Grafana", size=22, color=PALETTE["teal"], w=200))
    els.append(text(740, 290, "datasources + dashboards\ntrace ↔ logs links\nexemplar pivots", size=11, color=PALETTE["muted"], w=200))

    # Arrows
    els.append(arrow(180, 280, 255, 280, stroke=PALETTE["text"]))
    els.append(text(180, 285, "OTLP", size=11, color=PALETTE["muted"], w=80))

    els.append(arrow(425, 270, 475, 170, stroke=PALETTE["green"]))
    els.append(arrow(425, 280, 475, 280, stroke=PALETTE["orange"]))
    els.append(arrow(425, 290, 475, 390, stroke=PALETTE["purple"]))

    els.append(arrow(665, 170, 735, 270, stroke=PALETTE["green"]))
    els.append(arrow(665, 280, 735, 290, stroke=PALETTE["orange"]))
    els.append(arrow(665, 390, 735, 310, stroke=PALETTE["purple"]))

    els.append(text(220, 565, "all-in-one image:  docker.io/grafana/otel-lgtm:0.8.1", size=14, color=PALETTE["muted"], align="left", w=600))

    write_diagram("11-lgtm-architecture.excalidraw", els,
                  "11 — Grafana LGTM Stack (otel-lgtm image)")


# =============================================================================
# Diagram 12 — Correlation Pivot (the headline)
# =============================================================================
def diagram_12():
    """Five numbered steps showing metric → trace → logs pivot. Clock at 15s."""
    els = []

    # Big clock circle on the right
    els.append(ellipse(820, 130, 180, 180, stroke=PALETTE["coral"], bg=PALETTE["card"]))
    els.append(text(820, 200, "15s", size=42, color=PALETTE["coral"], w=180))
    els.append(text(820, 250, "anomaly →\nroot cause", size=12, color=PALETTE["muted"], w=180))

    # Five steps along the left
    steps = [
        ("1", "Metric spike",     "p99 latency dashboard",                          PALETTE["green"],  130),
        ("2", "Click exemplar",   "histogram dot carries traceId",                  PALETTE["teal"],   215),
        ("3", "Tempo trace",      "find the long span",                             PALETTE["purple"], 300),
        ("4", "Span → logs",      "Loki query by traceId",                          PALETTE["orange"], 385),
        ("5", "Read error",       "stack trace in the log line",                    PALETTE["coral"],  470),
    ]
    for num, title, sub, color, y in steps:
        # Number circle
        els.append(ellipse(60, y, 60, 60, stroke=color, bg=PALETTE["card"]))
        els.append(text(60, y + 12, num, size=28, color=color, w=60))
        # Step box
        els.append(rect(150, y - 5, 600, 70, stroke=color))
        els.append(text(170, y, title, size=20, color=color, align="left", w=580))
        els.append(text(170, y + 32, sub, size=13, color=PALETTE["muted"], align="left", w=580))

    # Vertical connector line
    els.append(line(90, 195, 90, 470, stroke=PALETTE["muted"], style="dotted"))

    # Bottom callout
    els.append(text(60, 580, "the magic:  one identifier (traceId), three signal stores, fluid pivot in Grafana",
                    size=15, color=PALETTE["coral"], align="left", w=940))

    write_diagram("12-correlation-pivot.excalidraw", els,
                  "12 — The 15-Second Pivot")


# =============================================================================
# Diagram 13 — Head vs Tail Sampling
# =============================================================================
def diagram_13():
    """Two flows: head (decide at start) vs tail (decide at end after seeing whole trace)."""
    els = []

    # Top half: Head sampling
    els.append(text(40, 80, "Head Sampling (decision at span start)", size=20, color=PALETTE["green"], align="left", w=600))
    els.append(rect(40, 110, 120, 60, stroke=PALETTE["teal"], bg=PALETTE["card"]))
    els.append(text(40, 125, "App", size=16, color=PALETTE["teal"], w=120))
    els.append(diamond(220, 100, 80, 80, stroke=PALETTE["green"]))
    els.append(text(220, 130, "rand <\nratio?", size=11, color=PALETTE["green"], w=80))
    # Two outcomes
    els.append(rect(360, 80, 140, 50, stroke=PALETTE["green"], bg=PALETTE["card"]))
    els.append(text(360, 90, "send", size=14, color=PALETTE["green"], w=140))
    els.append(rect(360, 150, 140, 50, stroke=PALETTE["coral"], bg=PALETTE["card"]))
    els.append(text(360, 160, "drop", size=14, color=PALETTE["coral"], w=140))
    els.append(arrow(165, 140, 215, 140, stroke=PALETTE["text"]))
    els.append(arrow(305, 120, 355, 105, stroke=PALETTE["green"]))
    els.append(arrow(305, 160, 355, 175, stroke=PALETTE["coral"]))
    # Notes
    els.append(text(540, 110, "+ cheap, fast\n+ predictable cost\n− blind to outcome\n− may drop the one error you needed",
                    size=12, color=PALETTE["text"], align="left", w=400))

    # Divider
    els.append(line(40, 270, 1000, 270, stroke=PALETTE["muted"]))

    # Bottom half: Tail sampling
    els.append(text(40, 290, "Tail Sampling (decision at trace completion, in Collector)", size=20, color=PALETTE["purple"], align="left", w=700))
    els.append(rect(40, 330, 120, 60, stroke=PALETTE["teal"], bg=PALETTE["card"]))
    els.append(text(40, 345, "App", size=16, color=PALETTE["teal"], w=120))
    els.append(text(180, 350, "send 100%", size=12, color=PALETTE["muted"], align="left", w=120))
    els.append(arrow(165, 360, 290, 360, stroke=PALETTE["text"]))
    # Collector with buffer
    els.append(rect(295, 320, 250, 100, stroke=PALETTE["purple"], bg=PALETTE["card"]))
    els.append(text(295, 335, "Collector (tail_sampling)", size=14, color=PALETTE["purple"], w=250))
    els.append(text(295, 365, "buffer until trace complete\nthen apply policies", size=11, color=PALETTE["muted"], w=250))
    # Three policy outcomes
    policies = [
        ("status=ERROR → keep 100%", PALETTE["coral"], 595, 305),
        ("latency > 1s → keep 100%", PALETTE["orange"], 595, 360),
        ("else → keep 5%",            PALETTE["muted"], 595, 415),
    ]
    for policy, color, x, y in policies:
        els.append(rect(x, y, 280, 40, stroke=color))
        els.append(text(x + 10, y + 5, policy, size=13, color=color, align="left", w=270))
        els.append(arrow(550, 370, x - 5, y + 20, stroke=color))

    # Notes
    els.append(text(40, 480, "Tail sampling: keep what matters, drop the rest. Costs Collector RAM + complexity.",
                    size=14, color=PALETTE["coral"], align="left", w=940))
    els.append(text(40, 510, "Production answer: parentbased_traceidratio at app + tail_sampling at Collector gateway.",
                    size=12, color=PALETTE["text"], align="left", w=940))

    write_diagram("13-head-vs-tail-sampling.excalidraw", els,
                  "13 — Head vs Tail Sampling")


# =============================================================================
# Diagram 14 — GC pause / trace correlation
# =============================================================================
def diagram_14():
    """Three timelines stacked: HTTP request spans / GC pauses / p99 metric, with vertical alignment markers."""
    els = []

    # Three lane labels
    lanes = [
        ("HTTP request spans",     PALETTE["teal"],   130),
        ("GC pause events",        PALETTE["coral"],  260),
        ("p99 request latency",    PALETTE["green"],  390),
    ]
    for label, color, y in lanes:
        els.append(text(40, y, label, size=14, color=color, align="left", w=240))
        els.append(line(280, y + 10, 1000, y + 10, stroke=color, style="solid"))

    # HTTP spans (lane 1) — small bars, with one slow one
    spans = [(290, 30), (340, 25), (390, 40), (450, 200), (660, 28), (700, 32)]  # x, width
    for x, w in spans:
        color = PALETTE["coral"] if w > 100 else PALETTE["teal"]
        els.append(rect(x, 130, w, 30, stroke=color, bg=PALETTE["card"]))

    # GC pauses (lane 2)
    pauses = [(310, 5, "5ms"), (450, 50, "50ms G1"), (560, 5, "5ms"), (680, 5, "5ms"), (800, 5, "5ms")]
    for x, w, lbl in pauses:
        color = PALETTE["coral"] if w > 20 else PALETTE["green"]
        els.append(rect(x, 260, max(w, 4), 30, stroke=color, bg=color))
        els.append(text(x, 300, lbl, size=10, color=color, w=80))

    # p99 line (lane 3) — wavy
    p99_points = [(290, 410), (340, 408), (390, 405), (440, 410), (470, 360), (520, 410), (560, 410), (660, 408), (700, 410), (760, 410)]
    for i in range(len(p99_points) - 1):
        x1, y1 = p99_points[i]
        x2, y2 = p99_points[i + 1]
        els.append(line(x1, y1, x2, y2, stroke=PALETTE["green"], style="solid"))

    # Vertical alignment markers
    for x in [310, 470, 680]:
        els.append(line(x, 110, x, 460, stroke=PALETTE["muted"], style="dashed"))

    # Annotation at the spike
    els.append(text(420, 480, "G1 50ms pause overlaps with the slow request span\np99 latency rises in the same window",
                    size=14, color=PALETTE["coral"], align="left", w=400))

    # Takeaway
    els.append(text(40, 560, "Observability sees ACROSS the JVM/app boundary — pauses become trace gaps + metric ripples.",
                    size=14, color=PALETTE["teal"], align="left", w=960))

    write_diagram("14-gc-trace-correlation.excalidraw", els,
                  "14 — GC Pauses as Trace Gaps")


# =============================================================================
# Diagram 15 — OpenShift Collector Patterns
# =============================================================================
def diagram_15():
    """Three deployment patterns side by side: sidecar, DaemonSet, gateway Deployment."""
    els = []

    patterns = [
        ("Sidecar",       60,  PALETTE["green"],  ["pod-local Collector",  "+ tightest isolation",   "− 1 Collector / pod",   "− RAM x N"]),
        ("DaemonSet",     400, PALETTE["teal"],   ["one per node",         "+ low overhead",         "+ realistic scaling",   "− cross-pod failures"]),
        ("Deployment",    740, PALETTE["purple"], ["centralized gateway",  "+ scales independently", "+ tail-sampling fits",  "− network hop"]),
    ]

    for name, x, color, lines in patterns:
        # Cluster representation
        els.append(rect(x, 100, 280, 380, stroke=PALETTE["muted"], round_radius=12))
        els.append(text(x, 110, name, size=20, color=color, w=280))

        # Three "node" boxes
        for i in range(3):
            ny = 160 + i * 70
            els.append(rect(x + 20, ny, 240, 50, stroke=PALETTE["muted"]))
            els.append(text(x + 20, ny + 10, f"node {i+1}", size=11, color=PALETTE["muted"], align="left", w=80))

            # Sidecar shows collector inside each pod
            if name == "Sidecar":
                els.append(rect(x + 100, ny + 10, 50, 30, stroke=color, bg=PALETTE["card"]))
                els.append(text(x + 100, ny + 15, "app", size=10, color=PALETTE["text"], w=50))
                els.append(rect(x + 160, ny + 10, 60, 30, stroke=color, bg=PALETTE["card"]))
                els.append(text(x + 160, ny + 15, "col", size=10, color=color, w=60))

            # DaemonSet shows one collector per node
            elif name == "DaemonSet":
                els.append(rect(x + 100, ny + 10, 50, 30, stroke=PALETTE["teal"], bg=PALETTE["card"]))
                els.append(text(x + 100, ny + 15, "app", size=10, color=PALETTE["text"], w=50))
                if i == 0:
                    els.append(rect(x + 160, ny + 10, 60, 30, stroke=color, bg=PALETTE["card"]))
                    els.append(text(x + 160, ny + 15, "col", size=10, color=color, w=60))

            # Deployment shows gateway separately
            elif name == "Deployment":
                els.append(rect(x + 100, ny + 10, 100, 30, stroke=PALETTE["teal"], bg=PALETTE["card"]))
                els.append(text(x + 100, ny + 15, "apps", size=10, color=PALETTE["text"], w=100))

        # Gateway collector for Deployment pattern
        if name == "Deployment":
            els.append(rect(x + 60, 410, 160, 50, stroke=color, bg=PALETTE["card"]))
            els.append(text(x + 60, 420, "Collector gateway", size=12, color=color, w=160))

        # Tradeoffs
        for i, t in enumerate(lines):
            color_t = PALETTE["green"] if t.startswith("+") else PALETTE["coral"] if t.startswith("−") else PALETTE["text"]
            els.append(text(x, 500 + i * 22, t, size=11, color=color_t, align="left", w=280))

    # Takeaway
    els.append(text(60, 620, "Most teams land on DaemonSet → centralized Deployment gateway.",
                    size=15, color=PALETTE["teal"], align="left", w=960))

    write_diagram("15-openshift-collector-patterns.excalidraw", els,
                  "15 — OpenShift Collector Deployment Patterns")


# =============================================================================
# Diagram 16 — Shenandoah vs G1 vs ZGC
# =============================================================================
def diagram_16():
    """Pause-time histograms for three GCs, with the UBI default annotation."""
    els = []

    gcs = [
        ("G1GC",                "10–100ms",  "Throughput-biased\nGenerational always\nMost OpenJDK distros default", PALETTE["orange"], 60),
        ("Shenandoah (gen)",    "5–10ms",    "Concurrent evac\nGenerational since 21\nUBI9 OpenJDK default ✓",       PALETTE["teal"],   400),
        ("ZGC (gen)",           "<1ms",      "Sub-millisecond pauses\nLarger memory overhead\nVery large heaps",      PALETTE["purple"], 740),
    ]

    for name, pause, body, color, x in gcs:
        # Card
        els.append(rect(x, 110, 280, 380, stroke=color, bg=PALETTE["card"]))
        els.append(text(x, 125, name, size=22, color=color, w=280))

        # Pause range banner
        els.append(rect(x + 20, 175, 240, 50, stroke=color))
        els.append(text(x + 20, 185, "p99 pause: " + pause, size=18, color=color, w=240))

        # Histogram skeleton (mini bar chart)
        hist_y = 250
        # Sketch 5 bars whose heights vary by GC profile
        if name == "G1GC":
            heights = [5, 12, 28, 45, 32]      # peak around 50ms
        elif name == "Shenandoah (gen)":
            heights = [40, 35, 22, 8, 2]        # peak low
        else:  # ZGC
            heights = [55, 30, 8, 2, 1]         # peak very low

        for i, h in enumerate(heights):
            bar_x = x + 30 + i * 45
            els.append(rect(bar_x, hist_y + (60 - h), 30, h, stroke=color, bg=color))
            els.append(text(bar_x - 5, hist_y + 65, str([1, 5, 20, 50, 100][i]) + "ms",
                            size=9, color=PALETTE["muted"], w=40))

        els.append(text(x + 20, 340, body, size=12, color=PALETTE["text"], align="left", w=240))

    # Red Hat annotation
    els.append(rect(420, 510, 280, 70, stroke=PALETTE["coral"]))
    els.append(text(420, 520, "Red Hat dividend", size=16, color=PALETTE["coral"], w=280))
    els.append(text(420, 545, "Shenandoah is FREE in UBI9.\nNo flag, no cost, no code change.", size=12, color=PALETTE["text"], w=280))

    # Takeaway
    els.append(text(60, 610, "Spring Boot on UBI9 OpenJDK 21 = Shenandoah by default.  Sub-10ms pauses, no flag flipped.",
                    size=14, color=PALETTE["teal"], align="left", w=960))

    write_diagram("16-shenandoah-vs-g1-zgc.excalidraw", els,
                  "16 — Shenandoah vs G1 vs ZGC for Spring Boot")


# =============================================================================
if __name__ == "__main__":
    print("Generating Excalidraw skeletons...")
    diagram_08()
    diagram_09()
    diagram_10()
    diagram_11()
    diagram_12()
    diagram_13()
    diagram_14()
    diagram_15()
    diagram_16()
    print("\nDone. 9 diagrams in", OUT_DIR)
