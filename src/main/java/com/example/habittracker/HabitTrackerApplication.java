package com.example.habittracker;

import org.springframework.boot.SpringApplication;
import org.springframework.boot.autoconfigure.SpringBootApplication;
import org.springframework.context.annotation.Bean;
import java.time.Clock;

@SpringBootApplication
public class HabitTrackerApplication {
    @Bean
    Clock applicationClock() {
        return Clock.systemUTC();
    }

    public static void main(String[] args) {
        SpringApplication.run(HabitTrackerApplication.class, args);
    }

}
