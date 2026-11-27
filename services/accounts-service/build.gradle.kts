plugins {
    java
    alias(libs.plugins.spring.boot)
    alias(libs.plugins.dep.mgmt)
    alias(libs.plugins.jib)
}

java { toolchain { languageVersion = JavaLanguageVersion.of(21) } }

dependencies {
    implementation("org.springframework.boot:spring-boot-starter-web")
    implementation("org.springframework.boot:spring-boot-starter-validation")
    implementation("org.springframework.boot:spring-boot-starter-data-jpa")
    implementation("org.springframework.boot:spring-boot-starter-data-redis")
    implementation("org.springframework.boot:spring-boot-starter-actuator")
    implementation("io.micrometer:micrometer-registry-prometheus")
    implementation("io.micrometer:micrometer-tracing-bridge-brave")
    implementation("org.flywaydb:flyway-core")
    implementation("org.flywaydb:flyway-mysql")
    runtimeOnly("com.mysql:mysql-connector-j")
    implementation(libs.logstash.encoder)
    implementation(libs.springdoc)

    testImplementation("org.springframework.boot:spring-boot-starter-test")
    testRuntimeOnly("org.junit.platform:junit-platform-launcher")
}

tasks.test { useJUnitPlatform() }

jib {
    from { image = "eclipse-temurin:21.0.8_9-jre" }
    to { image = (findProperty("ecrRegistry") as String?)?.let { "$it/core-banking/accounts-service:0.1.0" } ?: "core-banking/accounts-service:0.1.0" }
    container {
        ports = listOf("8081")
        creationTime = "USE_CURRENT_TIMESTAMP"
    }
}
