package com.example.inventory;

import io.micrometer.observation.Observation;
import io.micrometer.observation.ObservationRegistry;
import org.slf4j.Logger;
import org.slf4j.LoggerFactory;
import org.springframework.web.bind.annotation.GetMapping;
import org.springframework.web.bind.annotation.PathVariable;
import org.springframework.web.bind.annotation.PostMapping;
import org.springframework.web.bind.annotation.RequestParam;
import org.springframework.web.bind.annotation.RestController;
import org.springframework.web.server.ResponseStatusException;
import org.springframework.http.HttpStatus;

import java.util.Map;
import java.util.Random;
import java.util.concurrent.ThreadLocalRandom;

@RestController
public class InventoryController {

    private static final Logger log = LoggerFactory.getLogger(InventoryController.class);
    private static final Map<String, Integer> CATALOG = Map.of(
        "SKU-101", 42,
        "SKU-102", 17,
        "SKU-103", 8,
        "SKU-104", 0,
        "SKU-105", 99
    );

    private final FaultState fault;
    private final ObservationRegistry observations;
    private final Random random = new Random();

    public InventoryController(FaultState fault, ObservationRegistry observations) {
        this.fault = fault;
        this.observations = observations;
    }

    /**
     * Stock lookup. Wrapped in a manual Observation so the slow span has a clear name
     * the audience can spot in Tempo. Honors the injected fault state.
     */
    @GetMapping("/stock/{sku}")
    public Map<String, Object> findStock(@PathVariable String sku) {
        log.info("findStock for sku={}", sku);

        return Observation.createNotStarted("inventory.findStock", observations)
            .lowCardinalityKeyValue("operation", "findStock")
            .highCardinalityKeyValue("sku", sku)
            .observe(() -> doFindStock(sku));
    }

    private Map<String, Object> doFindStock(String sku) {
        // Apply injected latency
        int latency = fault.getLatencyMs();
        if (latency > 0) {
            try {
                Thread.sleep(latency);
            } catch (InterruptedException ie) {
                Thread.currentThread().interrupt();
            }
        }

        // Apply injected error rate
        double errorRate = fault.getErrorRate();
        if (errorRate > 0.0 && ThreadLocalRandom.current().nextDouble() < errorRate) {
            log.error("simulated downstream failure looking up sku={}", sku);
            throw new ResponseStatusException(
                HttpStatus.INTERNAL_SERVER_ERROR,
                "downstream inventory database connection refused"
            );
        }

        Integer count = CATALOG.get(sku);
        if (count == null) {
            log.warn("unknown sku={}", sku);
            throw new ResponseStatusException(HttpStatus.NOT_FOUND, "sku not found");
        }
        return Map.of("sku", sku, "available", count);
    }

    /**
     * Toggles fault injection at runtime. Used by demo.sh during the live demo.
     *
     * Example:
     *   curl -X POST 'http://localhost:8092/admin/inject?latencyMs=500&errorRate=0.05'
     */
    @PostMapping("/admin/inject")
    public Map<String, Object> inject(
            @RequestParam(defaultValue = "0") int latencyMs,
            @RequestParam(defaultValue = "0.0") double errorRate) {
        fault.setLatencyMs(latencyMs);
        fault.setErrorRate(errorRate);
        log.warn("FAULT injection updated: latencyMs={} errorRate={}",
            fault.getLatencyMs(), fault.getErrorRate());
        return Map.of(
            "latencyMs", fault.getLatencyMs(),
            "errorRate", fault.getErrorRate(),
            "active", fault.isActive()
        );
    }

    @GetMapping("/admin/inject")
    public Map<String, Object> currentFault() {
        return Map.of(
            "latencyMs", fault.getLatencyMs(),
            "errorRate", fault.getErrorRate(),
            "active", fault.isActive()
        );
    }
}
