package com.example.coldstart;

import com.example.coldstart.data.Widget;
import com.example.coldstart.data.WidgetRepository;
import org.springframework.http.ResponseEntity;
import org.springframework.web.bind.annotation.GetMapping;
import org.springframework.web.bind.annotation.PathVariable;
import org.springframework.web.bind.annotation.RestController;

import java.util.List;
import java.util.Map;

/**
 * Endpoints used by the AOT training run AND by demo traffic.
 *   GET /hello                          - trivial, no JPA touch
 *   GET /widgets                        - exercises Hibernate findAll path
 *   GET /widgets/{id}                   - exercises Hibernate findById path
 *   GET /widgets/by-category/{cat}      - exercises a custom JPA query
 *
 * Hitting all four during AOT training warms the JIT and captures
 * method profiles for the JPA + connection-pool + serializer code paths.
 */
@RestController
public class HelloController {

    private final WidgetRepository repo;

    public HelloController(WidgetRepository repo) {
        this.repo = repo;
    }

    @GetMapping("/hello")
    public Map<String, Object> hello() {
        return Map.of(
            "message", "hello from cold-start demo",
            "ts", System.currentTimeMillis()
        );
    }

    @GetMapping("/widgets")
    public List<Widget> all() {
        return repo.findAll();
    }

    @GetMapping("/widgets/{id}")
    public ResponseEntity<Widget> one(@PathVariable Long id) {
        return repo.findById(id)
            .map(ResponseEntity::ok)
            .orElse(ResponseEntity.notFound().build());
    }

    @GetMapping("/widgets/by-category/{category}")
    public List<Widget> byCategory(@PathVariable String category) {
        return repo.findByCategory(category);
    }
}
