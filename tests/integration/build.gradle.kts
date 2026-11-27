plugins {
    java
}

java { toolchain { languageVersion = JavaLanguageVersion.of(21) } }

dependencies {
    testImplementation(platform("org.junit:junit-bom:5.12.2"))
    testImplementation("org.junit.jupiter:junit-jupiter")
    testImplementation("com.fasterxml.jackson.core:jackson-databind:2.19.2")
    testImplementation(libs.awaitility)
    testRuntimeOnly("org.junit.platform:junit-platform-launcher")
}

// Needs the compose stack (scripts/dev-up.sh); run with ./gradlew :tests:integration:integrationTest
tasks.test { enabled = false }

tasks.register<Test>("integrationTest") {
    useJUnitPlatform()
    testClassesDirs = sourceSets.test.get().output.classesDirs
    classpath = sourceSets.test.get().runtimeClasspath
    outputs.upToDateWhen { false }
    systemProperty("accounts.url", System.getenv("ACCOUNTS_URL") ?: "http://localhost:8081")
    systemProperty("transfer.url", System.getenv("TRANSFER_URL") ?: "http://localhost:8082")
    systemProperty("audit.url", System.getenv("AUDIT_URL") ?: "http://localhost:8083")
}
