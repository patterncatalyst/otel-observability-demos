package com.example.demo01;

import org.springframework.boot.SpringApplication;
import org.springframework.boot.autoconfigure.SpringBootApplication;

/**
 * Demo 01 — Auto vs Manual Instrumentation.
 *
 * Single Spring Boot service used to demonstrate the difference between:
 *   1. Running with no instrumentation
 *   2. Running with the OTel Java agent attached (-javaagent:opentelemetry-javaagent.jar)
 *   3. Running with manual spans created via the OTel API / Observation API
 *
 * The container's ENTRYPOINT switches between (1) and (2) based on AGENT_ENABLED;
 * (3) is always present in the code path triggered by GET /work.
 */
@SpringBootApplication
public class Demo01Application {

    public static void main(String[] args) {
        SpringApplication.run(Demo01Application.class, args);
    }
}
