package com.example.order;

import org.springframework.boot.SpringApplication;
import org.springframework.boot.autoconfigure.SpringBootApplication;
import org.springframework.context.annotation.Bean;
import org.springframework.web.client.RestClient;

/**
 * order-service — calls inventory-service for stock checks.
 *
 * The OTel Java agent (attached via JAVA_TOOL_OPTIONS) auto-instruments the
 * Spring MVC server and the RestClient HTTP calls, so trace context propagates
 * through to inventory-service over the W3C traceparent header automatically.
 */
@SpringBootApplication
public class OrderApplication {

    public static void main(String[] args) {
        SpringApplication.run(OrderApplication.class, args);
    }

    @Bean
    public RestClient.Builder restClientBuilder() {
        return RestClient.builder();
    }
}
