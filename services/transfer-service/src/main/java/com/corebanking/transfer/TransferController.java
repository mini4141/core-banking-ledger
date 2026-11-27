package com.corebanking.transfer;

import feign.FeignException;
import io.github.resilience4j.bulkhead.BulkheadFullException;
import io.github.resilience4j.circuitbreaker.CallNotPermittedException;
import io.github.resilience4j.ratelimiter.RequestNotPermitted;
import jakarta.validation.Valid;
import java.util.List;
import java.util.Map;
import org.slf4j.Logger;
import org.slf4j.LoggerFactory;
import org.springframework.http.HttpStatus;
import org.springframework.http.ResponseEntity;
import org.springframework.web.bind.MethodArgumentNotValidException;
import org.springframework.web.bind.annotation.ExceptionHandler;
import org.springframework.web.bind.annotation.GetMapping;
import org.springframework.web.bind.annotation.PathVariable;
import org.springframework.web.bind.annotation.PostMapping;
import org.springframework.web.bind.annotation.RequestBody;
import org.springframework.web.bind.annotation.RequestParam;
import org.springframework.web.bind.annotation.RestController;
import org.springframework.web.bind.annotation.RestControllerAdvice;

@RestController
class TransferController {

    private final TransferService service;

    TransferController(TransferService service) {
        this.service = service;
    }

    @PostMapping("/transfers")
    ResponseEntity<TransferView> create(@Valid @RequestBody TransferRequest request) {
        TransferOutcome outcome = service.transfer(request);
        return ResponseEntity.status(outcome.replayed() ? HttpStatus.OK : HttpStatus.CREATED)
                .header("Idempotent-Replayed", String.valueOf(outcome.replayed()))
                .body(outcome.transfer());
    }

    @GetMapping("/transfers/{id}")
    TransferView get(@PathVariable String id) {
        return service.get(id);
    }

    @GetMapping("/transfers")
    List<TransferView> list(@RequestParam(required = false) String accountId) {
        return service.list(accountId);
    }
}

class BusinessException extends RuntimeException {
    private final String code;
    private final int status;

    BusinessException(String code, String message, int status) {
        super(message);
        this.code = code;
        this.status = status;
    }

    String code() { return code; }
    int status() { return status; }
}

@RestControllerAdvice
class ApiExceptionHandler {

    private static final Logger log = LoggerFactory.getLogger(ApiExceptionHandler.class);

    @ExceptionHandler(BusinessException.class)
    ResponseEntity<Map<String, String>> business(BusinessException e) {
        return ResponseEntity.status(e.status()).body(Map.of("code", e.code(), "message", e.getMessage()));
    }

    @ExceptionHandler(MethodArgumentNotValidException.class)
    ResponseEntity<Map<String, String>> invalid(MethodArgumentNotValidException e) {
        return ResponseEntity.badRequest().body(Map.of("code", "VALIDATION_FAILED", "message", "request validation failed"));
    }

    /** Circuit open, bulkhead/rate limit exhausted, or accounts-service failing after retries. */
    @ExceptionHandler({CallNotPermittedException.class, BulkheadFullException.class, RequestNotPermitted.class,
            FeignException.class})
    ResponseEntity<Map<String, String>> unavailable(Exception e) {
        log.warn("accounts-service unavailable: {}", e.getClass().getSimpleName());
        return ResponseEntity.status(HttpStatus.SERVICE_UNAVAILABLE)
                .body(Map.of("code", "ACCOUNTS_UNAVAILABLE", "message", "accounts-service is unavailable, retry later"));
    }
}
