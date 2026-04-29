package com.example.gc;

import org.springframework.boot.SpringApplication;
import org.springframework.boot.autoconfigure.SpringBootApplication;

/**
 * Demo 04 — GC pauses as trace gaps.
 * Service exposes /allocate to create heap pressure on demand.
 */
@SpringBootApplication
public class GcDemoApplication {
    public static void main(String[] args) {
        SpringApplication.run(GcDemoApplication.class, args);
    }
}
