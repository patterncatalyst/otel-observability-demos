package com.example.order;

import org.slf4j.Logger;
import org.slf4j.LoggerFactory;
import org.springframework.beans.factory.annotation.Value;
import org.springframework.http.ResponseEntity;
import org.springframework.web.bind.annotation.GetMapping;
import org.springframework.web.bind.annotation.RestController;
import org.springframework.web.client.RestClient;
import org.springframework.web.client.RestClientException;

import java.util.List;
import java.util.Map;
import java.util.Random;

@RestController
public class OrderController {

    private static final Logger log = LoggerFactory.getLogger(OrderController.class);
    private static final List<String> SKUS = List.of(
        "SKU-101", "SKU-102", "SKU-103", "SKU-104", "SKU-105"
    );

    private final RestClient restClient;
    private final Random random = new Random();

    public OrderController(RestClient.Builder builder, @Value("${inventory.base-url}") String inventoryBaseUrl) {
        this.restClient = builder.baseUrl(inventoryBaseUrl).build();
    }

    /**
     * Picks a random SKU, calls inventory-service to check stock, returns an order summary.
     * The trace produced will have:
     *   order-service: HTTP server span (GET /orders/random)
     *     └── order-service: HTTP client span (GET /stock/{sku})
     *           └── inventory-service: HTTP server span (GET /stock/{sku})
     *                 └── inventory-service: findStock business span (where the latency lives)
     */
    @GetMapping("/orders/random")
    public ResponseEntity<Map<String, Object>> randomOrder() {
        String sku = SKUS.get(random.nextInt(SKUS.size()));
        log.info("placing order for sku={}", sku);

        try {
            Map<String, Object> stock = restClient.get()
                .uri("/stock/{sku}", sku)
                .retrieve()
                .body(Map.class);

            Map<String, Object> response = Map.of(
                "sku", sku,
                "stock", stock,
                "ts", System.currentTimeMillis()
            );
            return ResponseEntity.ok(response);
        } catch (RestClientException e) {
            log.error("inventory call failed for sku={}: {}", sku, e.getMessage());
            return ResponseEntity.status(502).body(Map.of(
                "sku", sku,
                "error", "inventory unavailable",
                "detail", e.getMessage()
            ));
        }
    }
}
