package com.corebanking.accounts;

import jakarta.validation.Valid;
import java.util.List;
import java.util.Map;
import org.springframework.http.HttpStatus;
import org.springframework.http.ResponseEntity;
import org.springframework.web.bind.MethodArgumentNotValidException;
import org.springframework.web.bind.annotation.ExceptionHandler;
import org.springframework.web.bind.annotation.GetMapping;
import org.springframework.web.bind.annotation.PathVariable;
import org.springframework.web.bind.annotation.PostMapping;
import org.springframework.web.bind.annotation.RequestBody;
import org.springframework.web.bind.annotation.ResponseStatus;
import org.springframework.web.bind.annotation.RestController;
import org.springframework.web.bind.annotation.RestControllerAdvice;

@RestController
class AccountController {

    private final AccountService service;

    AccountController(AccountService service) {
        this.service = service;
    }

    @PostMapping("/accounts")
    @ResponseStatus(HttpStatus.CREATED)
    AccountView create(@Valid @RequestBody CreateAccountRequest req) {
        return service.create(req);
    }

    @GetMapping("/accounts")
    List<AccountView> list() {
        return service.list();
    }

    @GetMapping("/accounts/{id}")
    AccountView get(@PathVariable String id) {
        return service.get(id);
    }

    @PostMapping("/accounts/{id}/deposit")
    AccountView deposit(@PathVariable String id, @Valid @RequestBody AmountRequest req) {
        return service.deposit(id, req.amount());
    }

    @PostMapping("/internal/accounts/{id}/debit")
    LegResult debit(@PathVariable String id, @Valid @RequestBody LegRequest req) {
        return service.applyLeg(id, new LegRequest(req.transferId(), "DEBIT", req.amount()));
    }

    /** Also serves the compensating credit-back leg (leg = CREDIT_BACK). */
    @PostMapping("/internal/accounts/{id}/credit")
    LegResult credit(@PathVariable String id, @Valid @RequestBody LegRequest req) {
        String leg = "CREDIT_BACK".equals(req.leg()) ? "CREDIT_BACK" : "CREDIT";
        return service.applyLeg(id, new LegRequest(req.transferId(), leg, req.amount()));
    }
}

@RestControllerAdvice
class ApiExceptionHandler {

    @ExceptionHandler(AccountNotFoundException.class)
    ResponseEntity<Map<String, String>> notFound(AccountNotFoundException e) {
        return error(HttpStatus.NOT_FOUND, "ACCOUNT_NOT_FOUND", e.getMessage());
    }

    @ExceptionHandler(InsufficientFundsException.class)
    ResponseEntity<Map<String, String>> insufficient(InsufficientFundsException e) {
        return error(HttpStatus.UNPROCESSABLE_ENTITY, "INSUFFICIENT_FUNDS", e.getMessage());
    }

    @ExceptionHandler(MethodArgumentNotValidException.class)
    ResponseEntity<Map<String, String>> invalid(MethodArgumentNotValidException e) {
        return error(HttpStatus.BAD_REQUEST, "VALIDATION_FAILED", "request validation failed");
    }

    private static ResponseEntity<Map<String, String>> error(HttpStatus status, String code, String message) {
        return ResponseEntity.status(status).body(Map.of("code", code, "message", message));
    }
}
