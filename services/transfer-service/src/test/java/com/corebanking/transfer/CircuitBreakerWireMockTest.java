package com.corebanking.transfer;

import static com.github.tomakehurst.wiremock.client.WireMock.aResponse;
import static com.github.tomakehurst.wiremock.client.WireMock.post;
import static com.github.tomakehurst.wiremock.client.WireMock.urlPathMatching;
import static org.junit.jupiter.api.Assertions.assertEquals;
import static org.junit.jupiter.api.Assertions.assertTrue;
import static org.mockito.ArgumentMatchers.anyString;
import static org.mockito.Mockito.when;

import com.github.tomakehurst.wiremock.WireMockServer;
import com.github.tomakehurst.wiremock.core.WireMockConfiguration;
import io.github.resilience4j.circuitbreaker.CircuitBreaker;
import io.github.resilience4j.circuitbreaker.CircuitBreakerRegistry;
import java.util.UUID;
import org.junit.jupiter.api.AfterAll;
import org.junit.jupiter.api.BeforeAll;
import org.junit.jupiter.api.Test;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.boot.test.context.SpringBootTest;
import org.springframework.boot.test.web.client.TestRestTemplate;
import org.springframework.test.context.DynamicPropertyRegistry;
import org.springframework.test.context.DynamicPropertySource;
import org.springframework.test.context.bean.override.mockito.MockitoBean;

@SpringBootTest(webEnvironment = SpringBootTest.WebEnvironment.RANDOM_PORT, properties = {
        "spring.datasource.url=jdbc:h2:mem:transfers;MODE=MySQL",
        "spring.datasource.username=sa",
        "spring.datasource.password=",
        "spring.flyway.enabled=false",
        "spring.jpa.hibernate.ddl-auto=create-drop",
        "spring.kafka.admin.auto-create=false",
        "management.tracing.enabled=false"})
class CircuitBreakerWireMockTest {

    static WireMockServer accountsStub = new WireMockServer(WireMockConfiguration.options().dynamicPort());

    @MockitoBean
    IdempotencyStore idempotency;
    @MockitoBean
    TransferEventPublisher publisher;

    @Autowired
    TestRestTemplate rest;
    @Autowired
    CircuitBreakerRegistry registry;

    @BeforeAll
    static void startStub() {
        accountsStub.start();
        accountsStub.stubFor(post(urlPathMatching("/internal/accounts/.*"))
                .willReturn(aResponse().withStatus(500)));
    }

    @AfterAll
    static void stopStub() {
        accountsStub.stop();
    }

    @DynamicPropertySource
    static void props(DynamicPropertyRegistry registry) {
        registry.add("accounts.base-url", accountsStub::baseUrl);
    }

    @Test
    void breakerOpensAndTransfersFailFastWith503() {
        when(idempotency.tryAcquire(anyString())).thenReturn(true);

        for (int i = 0; i < 6; i++) {
            submit("a", "b");
        }
        assertEquals(CircuitBreaker.State.OPEN, registry.circuitBreaker("accounts").getState());

        int callsBefore = accountsStub.getAllServeEvents().size();
        long start = System.nanoTime();
        var response = submit("a", "b");
        long millis = (System.nanoTime() - start) / 1_000_000;

        assertEquals(503, response.getStatusCode().value());
        assertTrue(response.getBody().contains("ACCOUNTS_UNAVAILABLE"));
        assertTrue(millis < 500, "open circuit must fail fast, took " + millis + " ms");
        assertEquals(callsBefore, accountsStub.getAllServeEvents().size(), "no call may reach accounts");
    }

    private org.springframework.http.ResponseEntity<String> submit(String from, String to) {
        String body = "{\"idempotencyKey\":\"" + UUID.randomUUID() + "\",\"fromAccountId\":\"" + from
                + "\",\"toAccountId\":\"" + to + "\",\"amount\":100}";
        var headers = new org.springframework.http.HttpHeaders();
        headers.setContentType(org.springframework.http.MediaType.APPLICATION_JSON);
        return rest.postForEntity("/transfers", new org.springframework.http.HttpEntity<>(body, headers), String.class);
    }
}
