package com.example.coldstart.data;

import org.springframework.data.jpa.repository.JpaRepository;
import java.util.List;

public interface WidgetRepository extends JpaRepository<Widget, Long> {
    List<Widget> findByCategory(String category);
}
