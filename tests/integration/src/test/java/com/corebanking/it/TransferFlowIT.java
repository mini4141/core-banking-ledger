package com.corebanking.it;

import static org.junit.jupiter.api.Assertions.assertEquals;
import static org.junit.jupiter.api.Assertions.assertTrue;

import com.fasterxml.jackson.databind.JsonNode;
import com.fasterxml.jackson.databind.ObjectMapper;
import java.net.URI;
import java.net.http.HttpClient;
import java.net.http.HttpRequest;
import java.net.http.HttpResponse;
import java.time.Duration;
import java.util.UUID;
import org.junit.jupiter.api.Test;
import org.awaitility.Awaitility;

/** Transfer persists in MySQL, TransferCompleted flows through Kafka and lands in DynamoDB. */
class TransferFlowIT {

    private static final String ACCOUNTS = System.getProperty("accounts.url", "http://localhost:8081");
    private static final String TRANSFER = System.getProperty("transfer.url", "http://localhost:8082");
    private static final String AUDIT = System.getProperty("audit.url", "http://localhost:8083");

    private final HttpClient http = HttpClient.newHttpClient();
    private final ObjectMapper json = new ObjectMapper();

    @Test
    void transferMovesMoneyIsIdempotentAndAuditedInDynamoDb() throws Exception {
        String alice = createAccount("Alice IT");
        String bob = createAccount("Bob IT");
        post(ACCOUNTS + "/accounts/" + alice + "/deposit", "{\"amount\":50000}");

        String key = UUID.randomUUID().toString();
        String body = "{\"idempotencyKey\":\"" + key + "\",\"fromAccountId\":\"" + alice
                + "\",\"toAccountId\":\"" + bob + "\",\"amount\":10000}";

        HttpResponse<String> first = post(TRANSFER + "/transfers", body);
        assertEquals(201, first.statusCode(), first.body());
        HttpResponse<String> replay = post(TRANSFER + "/transfers", body);
        assertEquals(200, replay.statusCode(), replay.body());
        assertEquals("true", replay.headers().firstValue("Idempotent-Replayed").orElse(""));
        assertEquals(json.readTree(first.body()).get("id"), json.readTree(replay.body()).get("id"));

        assertEquals(0, new java.math.BigDecimal("40000").compareTo(balance(alice)));
        assertEquals(0, new java.math.BigDecimal("10000").compareTo(balance(bob)));

        String transferId = json.readTree(first.body()).get("id").asText();
        Awaitility.await().atMost(Duration.ofSeconds(60)).pollInterval(Duration.ofSeconds(1)).untilAsserted(() -> {
            assertTrue(get(AUDIT + "/audit/accounts/" + alice).body().contains(transferId), "alice audit item");
            assertTrue(get(AUDIT + "/audit/accounts/" + bob).body().contains(transferId), "bob audit item");
        });
    }

    private String createAccount(String name) throws Exception {
        HttpResponse<String> res = post(ACCOUNTS + "/accounts", "{\"customerName\":\"" + name + "\",\"currency\":\"JPY\"}");
        assertEquals(201, res.statusCode(), res.body());
        return json.readTree(res.body()).get("id").asText();
    }

    private java.math.BigDecimal balance(String id) throws Exception {
        JsonNode n = json.readTree(get(ACCOUNTS + "/accounts/" + id).body());
        return n.get("balance").decimalValue();
    }

    private HttpResponse<String> post(String url, String body) throws Exception {
        return http.send(HttpRequest.newBuilder(URI.create(url)).header("Content-Type", "application/json")
                .POST(HttpRequest.BodyPublishers.ofString(body)).build(), HttpResponse.BodyHandlers.ofString());
    }

    private HttpResponse<String> get(String url) throws Exception {
        return http.send(HttpRequest.newBuilder(URI.create(url)).GET().build(), HttpResponse.BodyHandlers.ofString());
    }
}
