package com.example.coldstart;

import org.springframework.boot.SpringApplication;
import org.springframework.boot.autoconfigure.SpringBootApplication;

/**
 * Demo 05 — Cold start comparison.
 *
 * Two builds of the same source: one classic JVM, one with JDK 25 AOT cache.
 * The point of the demo is the cold-start time difference and how the OTel
 * traces of startup explain WHERE the time was saved.
 */
@SpringBootApplication
public class ColdStartApplication {

    public static void main(String[] args) {
        long startNanos = System.nanoTime();
        SpringApplication app = new SpringApplication(ColdStartApplication.class);
        app.setLogStartupInfo(true);
        app.run(args);
        long elapsedMs = (System.nanoTime() - startNanos) / 1_000_000;
        System.out.printf("=== application started in %d ms ===%n", elapsedMs);
    }
}
