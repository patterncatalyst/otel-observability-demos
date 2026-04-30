package com.example.coldstart.data;

import org.slf4j.Logger;
import org.slf4j.LoggerFactory;
import org.springframework.boot.CommandLineRunner;
import org.springframework.stereotype.Component;

import java.util.List;

@Component
public class DataSeeder implements CommandLineRunner {

    private static final Logger log = LoggerFactory.getLogger(DataSeeder.class);
    private final WidgetRepository repo;

    public DataSeeder(WidgetRepository repo) {
        this.repo = repo;
    }

    @Override
    public void run(String... args) {
        repo.saveAll(List.of(
            new Widget("Sprocket A",   "mechanical",  100),
            new Widget("Sprocket B",   "mechanical",   50),
            new Widget("Resistor 10k", "electrical", 1000),
            new Widget("Capacitor 1uF","electrical",  500),
            new Widget("Bolt M6",      "fastener",   2000),
            new Widget("Nut M6",       "fastener",   2000)
        ));
        log.info("Seeded {} widgets", repo.count());
    }
}
