package com.corebanking.transfer;

import org.springframework.cloud.openfeign.FeignClient;
import org.springframework.web.bind.annotation.PathVariable;
import org.springframework.web.bind.annotation.PostMapping;
import org.springframework.web.bind.annotation.RequestBody;

@FeignClient(name = "accounts", url = "${accounts.base-url}")
interface AccountsClient {

    @PostMapping("/internal/accounts/{id}/debit")
    LegResult debit(@PathVariable("id") String accountId, @RequestBody LegRequest request);

    @PostMapping("/internal/accounts/{id}/credit")
    LegResult credit(@PathVariable("id") String accountId, @RequestBody LegRequest request);
}
