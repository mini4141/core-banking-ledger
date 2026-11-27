package com.corebanking.accounts;

import org.springframework.data.jpa.repository.JpaRepository;

interface AccountRepository extends JpaRepository<Account, String> {
}

interface AccountLegRepository extends JpaRepository<AccountLeg, Long> {
    boolean existsByTransferIdAndLeg(String transferId, String leg);
}
