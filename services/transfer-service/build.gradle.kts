plugins {
    java
    alias(libs.plugins.spring.boot)
    alias(libs.plugins.dep.mgmt)
    alias(libs.plugins.jib)
}

java { toolchain { languageVersion = JavaLanguageVersion.of(21) } }

dependencyManagement {
    imports { mavenBom("org.springframework.cloud:spring-cloud-dependencies:${libs.versions.spring.cloud.get()}") }
}

val r4j = libs.versions.resilience4j.get()
ext["resilience4j.version"] = r4j

dependencies {
    implementation("org.springframework.boot:spring-boot-starter-web")
    implementation("org.springframework.boot:spring-boot-starter-validation")
    implementation("org.springframework.boot:spring-boot-starter-data-jpa")
    implementation("org.springframework.boot:spring-boot-starter-data-redis")
    implementation("org.springframework.boot:spring-boot-starter-actuator")
    implementation("org.springframework.boot:spring-boot-starter-aop")
    implementation("org.springframework.kafka:spring-kafka")
    implementation("org.springframework.cloud:spring-cloud-starter-openfeign")
    implementation("io.github.openfeign:feign-micrometer")
    implementation("io.github.resilience4j:resilience4j-spring-boot3:$r4j")
    implementation("io.github.resilience4j:resilience4j-micrometer:$r4j")
    implementation("io.micrometer:micrometer-registry-prometheus")
    implementation("io.micrometer:micrometer-tracing-bridge-brave")
    implementation("org.flywaydb:flyway-core")
    implementation("org.flywaydb:flyway-mysql")
    runtimeOnly("com.mysql:mysql-connector-j")
    implementation(libs.logstash.encoder)
    implementation(libs.springdoc)

    testImplementation("org.springframework.boot:spring-boot-starter-test")
    testImplementation(libs.wiremock)
    testRuntimeOnly("com.h2database:h2")
    testRuntimeOnly("org.junit.platform:junit-platform-launcher")
}

tasks.test { useJUnitPlatform() }

jib {
    from { image = "eclipse-temurin:21.0.8_9-jre" }
    to { image = "core-banking/transfer-service:0.1.0" }
    container {
        ports = listOf("8082")
        jvmFlags = listOf("-XX:MaxRAMPercentage=70", "-XX:+UseG1GC", "-XX:+ExitOnOutOfMemoryError")
        creationTime = "USE_CURRENT_TIMESTAMP"
    }
}
