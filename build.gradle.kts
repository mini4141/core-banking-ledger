plugins {
    alias(libs.plugins.spring.boot) apply false
    alias(libs.plugins.dep.mgmt) apply false
    alias(libs.plugins.kotlin.jvm) apply false
    alias(libs.plugins.kotlin.spring) apply false
    alias(libs.plugins.jib) apply false
}

allprojects {
    group = "com.corebanking"
    version = "0.1.0"
    repositories { mavenCentral() }
}
