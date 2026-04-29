package com.example.coldstart;

import org.springframework.web.bind.annotation.GetMapping;
import org.springframework.web.bind.annotation.RestController;

import java.util.Map;

/**
 * Trivial endpoint so we have a real HTTP path to hit during the AOT training run.
 */
@RestController
public class HelloController {

    @GetMapping("/hello")
    public Map<String, Object> hello() {
        return Map.of(
            "message", "hello from cold-start demo",
            "ts", System.currentTimeMillis()
        );
    }
}
