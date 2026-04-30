package com.example.demo01;

import io.opentelemetry.api.trace.Span;
import io.opentelemetry.instrumentation.annotations.SpanAttribute;
import io.opentelemetry.instrumentation.annotations.WithSpan;
import org.slf4j.Logger;
import org.slf4j.LoggerFactory;
import org.springframework.web.bind.annotation.GetMapping;
import org.springframework.web.bind.annotation.RequestParam;
import org.springframework.web.bind.annotation.RestController;

import java.util.Map;
import java.util.concurrent.ThreadLocalRandom;

@RestController
public class HelloController {

    private static final Logger log = LoggerFactory.getLogger(HelloController.class);

    @GetMapping("/hello")
    public Map<String, Object> hello(@RequestParam(defaultValue = "world") String name) {
        log.info("hello called for name={}", name);
        return Map.of("message", "hello, " + name, "ts", System.currentTimeMillis());
    }

    @GetMapping("/work")
    public Map<String, Object> work(@RequestParam(defaultValue = "100") int sizeMs) {
        log.info("work called with sizeMs={}", sizeMs);
        long result = simulateCompute(sizeMs);
        return Map.of("result", result, "sizeMs", sizeMs);
    }

    @WithSpan("compute.fibonacci")
    private long simulateCompute(@SpanAttribute("size_ms") int sizeMs) {
        Span.current().setAttribute("workload", "fibonacci");
        long start = System.nanoTime();
        long target = start + sizeMs * 1_000_000L;
        long acc = 0L;
        while (System.nanoTime() < target) {
            acc += ThreadLocalRandom.current().nextLong();
        }
        return acc;
    }
}
