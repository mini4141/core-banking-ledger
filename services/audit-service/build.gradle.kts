plugins {
    alias(libs.plugins.kotlin.jvm)
    alias(libs.plugins.kotlin.spring)
    alias(libs.plugins.spring.boot)
    alias(libs.plugins.dep.mgmt)
    alias(libs.plugins.jib)
}

kotlin { jvmToolchain(21) }

dependencyManagement {
    imports { mavenBom("software.amazon.awssdk:bom:${libs.versions.awssdk.get()}") }
}

dependencies {
    implementation("org.springframework.boot:spring-boot-starter-web")
    implementation("org.springframework.boot:spring-boot-starter-actuator")
    implementation("org.springframework.kafka:spring-kafka")
    implementation("com.fasterxml.jackson.module:jackson-module-kotlin")
    implementation("org.jetbrains.kotlin:kotlin-reflect")
    implementation("software.amazon.awssdk:dynamodb")
    implementation("software.amazon.awssdk:url-connection-client")
    implementation("io.micrometer:micrometer-registry-prometheus")
    implementation("io.micrometer:micrometer-tracing-bridge-brave")
    implementation(libs.logstash.encoder)

    testImplementation("org.springframework.boot:spring-boot-starter-test")
    testImplementation("org.jetbrains.kotlin:kotlin-test-junit5")
    testRuntimeOnly("org.junit.platform:junit-platform-launcher")
}

tasks.test { useJUnitPlatform() }

jib {
    from { image = "eclipse-temurin:21.0.8_9-jre" }
    to { image = (findProperty("ecrRegistry") as String?)?.let { "$it/core-banking/audit-service:0.1.0" } ?: "core-banking/audit-service:0.1.0" }
    container {
        ports = listOf("8083")
        creationTime = "USE_CURRENT_TIMESTAMP"
    }
}
