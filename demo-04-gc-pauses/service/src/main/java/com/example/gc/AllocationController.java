package com.example.gc;

import io.opentelemetry.api.trace.Span;
import io.opentelemetry.instrumentation.annotations.SpanAttribute;
import io.opentelemetry.instrumentation.annotations.WithSpan;
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

    @GetMapping("/work")
    public Map<String, Object> work() {
        return Map.of("status", "ok");
    }

    @GetMapping("/allocate")
    public Map<String, Object> allocate(
            @RequestParam(defaultValue = "32") int sizeKb,
            @RequestParam(defaultValue = "1000") int objects) {

        log.debug("allocate: sizeKb={} objects={}", sizeKb, objects);

        long bytesBefore = Runtime.getRuntime().freeMemory();
        long start = System.nanoTime();

        churn(sizeKb, objects);

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

    @WithSpan("alloc.churn")
    private void churn(@SpanAttribute("size_kb") int sizeKb,
                       @SpanAttribute("objects") int objects) {
        Span.current().setAttribute("operation", "alloc.churn");
        List<byte[]> hold = new ArrayList<>(objects / 10);
        for (int i = 0; i < objects; i++) {
            byte[] junk = new byte[sizeKb * 1024];
            junk[0] = (byte) i;
            junk[junk.length - 1] = (byte) (i >> 8);
            if (i % 10 == 0) hold.add(junk);
        }
    }
}
