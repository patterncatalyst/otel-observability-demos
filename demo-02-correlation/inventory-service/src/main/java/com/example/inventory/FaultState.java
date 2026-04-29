package com.example.inventory;

import org.springframework.stereotype.Component;
import java.util.concurrent.atomic.AtomicInteger;
import java.util.concurrent.atomic.AtomicReference;

/**
 * Holds the current injected-fault configuration. Mutated by /admin/inject,
 * read by InventoryController. Atomic so we don't need locking on the hot path.
 */
@Component
public class FaultState {

    /** Latency injected before responding, in milliseconds. */
    private final AtomicInteger latencyMs = new AtomicInteger(0);

    /** Probability of returning a 500 error, 0.0 - 1.0. */
    private final AtomicReference<Double> errorRate = new AtomicReference<>(0.0);

    public int getLatencyMs() { return latencyMs.get(); }
    public void setLatencyMs(int ms) { latencyMs.set(Math.max(0, ms)); }

    public double getErrorRate() { return errorRate.get(); }
    public void setErrorRate(double rate) {
        errorRate.set(Math.max(0.0, Math.min(1.0, rate)));
    }

    public boolean isActive() {
        return latencyMs.get() > 0 || errorRate.get() > 0.0;
    }
}
