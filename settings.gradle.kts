rootProject.name = "core-banking-ledger"
include("services:accounts-service", "services:transfer-service", "services:audit-service")
include("tests:integration")
