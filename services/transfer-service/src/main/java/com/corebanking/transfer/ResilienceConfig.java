package com.corebanking.transfer;

import io.github.resilience4j.circuitbreaker.CircuitBreakerRegistry;
import org.slf4j.Logger;
import org.slf4j.LoggerFactory;
import org.springframework.boot.context.event.ApplicationReadyEvent;
import org.springframework.context.annotation.Bean;
import org.springframework.context.annotation.Configuration;
import org.springframework.context.event.EventListener;
import org.springframework.kafka.config.TopicBuilder;
import org.apache.kafka.clients.admin.NewTopic;

@Configuration
class ResilienceConfig {

    private static final Logger log = LoggerFactory.getLogger(ResilienceConfig.class);

    /** Logs every breaker transition (CLOSED, OPEN, HALF_OPEN) so the drill is visible in ELK. */
    @EventListener(ApplicationReadyEvent.class)
    void logStateTransitions(ApplicationReadyEvent ready) {
        CircuitBreakerRegistry registry = ready.getApplicationContext().getBean(CircuitBreakerRegistry.class);
        registry.circuitBreaker("accounts").getEventPublisher().onStateTransition(
                e -> log.warn("circuit breaker state transition name={} transition={}",
                        e.getCircuitBreakerName(), e.getStateTransition()));
    }

    @Bean
    NewTopic transfersTopic() {
        return TopicBuilder.name("banking.transfers").partitions(3).replicas(1).build();
    }
}
