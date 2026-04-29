package com.example.inventory;

import org.springframework.boot.SpringApplication;
import org.springframework.boot.autoconfigure.SpringBootApplication;

/**
 * inventory-service — looks up stock for a SKU. Exposes /admin/inject so the demo
 * driver can toggle a fault (latency + error rate) at runtime without restarts.
 */
@SpringBootApplication
public class InventoryApplication {

    public static void main(String[] args) {
        SpringApplication.run(InventoryApplication.class, args);
    }
}
