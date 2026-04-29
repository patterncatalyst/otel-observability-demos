package com.example.demo01;

import io.micrometer.observation.Observation;
import io.micrometer.observation.ObservationRegistry;
import org.slf4j.Logger;
import org.slf4j.LoggerFactory;
import org.springframework.web.bind.annotation.GetMapping;
import org.springframework.web.bind.annotation.RequestParam;
import org.springframework.web.bind.annotation.RestController;

import java.util.Map;
import java.util.Random;
import java.util.concurrent.ThreadLocalRandom;

/**
 * Endpoints used to compare instrumentation modes.
 *
 * GET /hello       — trivial endpoint; the auto-agent will produce an HTTP server span.
 * GET /work        — calls a "business" method wrapped in a manual Observation; produces a child span.
 * GET /actuator/*  — auto-agent will trace these too; useful for showing zero-code coverage.
 */
@RestController
public class HelloController {

    private static final Logger log = LoggerFactory.getLogger(HelloController.class);
    private final ObservationRegistry registry;
    private final Random random = new Random();

    public HelloController(ObservationRegistry registry) {
        this.registry = registry;
    }

    @GetMapping("/hello")
    public Map<String, Object> hello(@RequestParam(defaultValue = "world") String name) {
        log.info("hello called for name={}", name);
        return Map.of(
            "message", "hello, " + name,
            "ts", System.currentTimeMillis()
        );
    }

    /**
     * Wraps a synthetic "compute" workload in a manual Observation. With the
     * auto-agent attached, this nests under the HTTP server span. Without the agent,
     * Micrometer Observation still produces a span via the OTel bridge — but only
     * for the explicitly observed block, not for the HTTP entry/exit.
     */
    @GetMapping("/work")
    public Map<String, Object> work(@RequestParam(defaultValue = "100") int sizeMs) {
        log.info("work called with sizeMs={}", sizeMs);

        // Manual observation — adds an attribute, records the duration, ties to current trace.
        long result = Observation.createNotStarted("compute.fibonacci", registry)
            .lowCardinalityKeyValue("workload", "fibonacci")
            .highCardinalityKeyValue("size_ms", String.valueOf(sizeMs))
            .observe(() -> simulateCompute(sizeMs));

        return Map.of(
            "result", result,
            "sizeMs", sizeMs
        );
    }

    /**
     * Simulates CPU + a tiny bit of randomness so the span has nonzero duration
     * and the histogram populates real exemplars.
     */
    private long simulateCompute(int sizeMs) {
        long start = System.nanoTime();
        long target = start + sizeMs * 1_000_000L;
        long acc = 0L;
        while (System.nanoTime() < target) {
            acc += ThreadLocalRandom.current().nextLong();
        }
        return acc;
    }
}
