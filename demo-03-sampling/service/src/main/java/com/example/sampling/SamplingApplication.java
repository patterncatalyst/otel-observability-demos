package com.example.sampling;

import org.springframework.boot.SpringApplication;
import org.springframework.boot.autoconfigure.SpringBootApplication;

/**
 * Demo 03 — Sampling.
 *
 * Endpoints emit a controlled mix of healthy / slow / errored traces so that
 * tail-sampling policies have something to filter on.
 */
@SpringBootApplication
public class SamplingApplication {
    public static void main(String[] args) {
        SpringApplication.run(SamplingApplication.class, args);
    }
}
