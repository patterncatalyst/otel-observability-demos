package com.example.gc;

import io.micrometer.observation.Observation;
import io.micrometer.observation.ObservationRegistry;
import org.slf4j.Logger;
import org.slf4j.LoggerFactory;
import org.springframework.web.bind.annotation.GetMapping;
import org.springframework.web.bind.annotation.RequestParam;
import org.springframework.web.bind.annotation.RestController;

import java.util.ArrayList;
import java.util.List;
import java.util.Map;

@RestController
public class AllocationController {

    private static final Logger log = LoggerFactory.getLogger(AllocationController.class);

    /**
     * Light endpoint — produces clean baseline traces.
     */
    @GetMapping("/work")
    public Map<String, Object> work() {
        return Map.of("status", "ok");
    }

    /**
     * Allocates a target volume of throwaway objects and returns when done.
     * The allocations land in young gen, get collected, eventually trigger
     * old-gen pressure. With G1 you'll see ~50ms pauses in the histogram.
     * With Shenandoah you'll see ~5-10ms. With ZGC you'll see <1ms.
     *
     * Wrapped in a manual Observation so the trace span is named meaningfully.
     */
    @GetMapping("/allocate")
    public Map<String, Object> allocate(
            @RequestParam(defaultValue = "32") int sizeKb,
            @RequestParam(defaultValue = "1000") int objects,
            ObservationRegistry registry) {

        log.debug("allocate: sizeKb={} objects={}", sizeKb, objects);

        long bytesBefore = Runtime.getRuntime().freeMemory();
        long start = System.nanoTime();

        Observation.createNotStarted("alloc.churn", registry)
            .lowCardinalityKeyValue("operation", "alloc.churn")
            .observe(() -> {
                List<byte[]> hold = new ArrayList<>(objects / 10);
                for (int i = 0; i < objects; i++) {
                    byte[] junk = new byte[sizeKb * 1024];
                    // Touch to defeat any clever optimization
                    junk[0] = (byte) i;
                    junk[junk.length - 1] = (byte) (i >> 8);
                    if (i % 10 == 0) hold.add(junk);  // hold ~10% to push old gen
                }
                // Drop hold — let it become garbage
            });

        long durationMs = (System.nanoTime() - start) / 1_000_000;
        long bytesAfter = Runtime.getRuntime().freeMemory();

        return Map.of(
            "status",        "ok",
            "sizeKb",        sizeKb,
            "objects",       objects,
            "totalBytes",    (long) sizeKb * 1024 * objects,
            "durationMs",    durationMs,
            "freeBefore",    bytesBefore,
            "freeAfter",     bytesAfter
        );
    }
}
