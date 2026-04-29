package com.example.sampling;

import org.slf4j.Logger;
import org.slf4j.LoggerFactory;
import org.springframework.http.HttpStatus;
import org.springframework.web.bind.annotation.GetMapping;
import org.springframework.web.bind.annotation.RestController;
import org.springframework.web.server.ResponseStatusException;

import java.util.Map;
import java.util.concurrent.ThreadLocalRandom;

/**
 * Endpoints engineered to produce traces of distinct categories so tail-sampling
 * has something interesting to keep / drop.
 *
 *   /work        — fast, successful (~20ms). The "baseline" trace.
 *   /work/slow   — slow, successful (~1500ms). Survives tail latency policy.
 *   /work/error  — fast, fails with 500. Survives tail status_code policy.
 *   /work/random — picks one of the above at random. Used for traffic mix.
 */
@RestController
public class WorkController {

    private static final Logger log = LoggerFactory.getLogger(WorkController.class);

    @GetMapping("/work")
    public Map<String, Object> work() {
        sleep(ThreadLocalRandom.current().nextInt(10, 30));
        return Map.of("status", "ok", "kind", "fast");
    }

    @GetMapping("/work/slow")
    public Map<String, Object> slow() {
        log.info("intentionally slow path");
        sleep(ThreadLocalRandom.current().nextInt(1100, 1800));
        return Map.of("status", "ok", "kind", "slow");
    }

    @GetMapping("/work/error")
    public Map<String, Object> error() {
        log.error("intentionally errored path");
        throw new ResponseStatusException(HttpStatus.INTERNAL_SERVER_ERROR, "synthetic failure");
    }

    /**
     * Mix: 90% fast, 5% slow, 5% error.
     * That ratio is what tail sampling will reshape — the dashboard shows the
     * "kept" traces concentrating on slow + error + 5% of fast.
     */
    @GetMapping("/work/random")
    public Map<String, Object> random() {
        int dice = ThreadLocalRandom.current().nextInt(100);
        if (dice < 90)      return work();
        else if (dice < 95) return slow();
        else                return error();
    }

    private static void sleep(long ms) {
        try { Thread.sleep(ms); } catch (InterruptedException ie) { Thread.currentThread().interrupt(); }
    }
}
