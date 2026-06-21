import com.android.build.gradle.LibraryExtension

allprojects {
    repositories {
        google()
        mavenCentral()
    }
}

val newBuildDir: Directory =
    rootProject.layout.buildDirectory
        .dir("../../build")
        .get()
rootProject.layout.buildDirectory.value(newBuildDir)

subprojects {
    val newSubprojectBuildDir: Directory = newBuildDir.dir(project.name)
    project.layout.buildDirectory.value(newSubprojectBuildDir)
}

// Reown pulls in coinbase_wallet_sdk, which ships with compileSdk 31 and missing
// consumer-rules.pro — patch all Android library plugins before tasks run.
subprojects {
    afterEvaluate {
        plugins.withId("com.android.library") {
            extensions.configure<LibraryExtension>("android") {
                compileSdk = 36
            }
        }
        if (name == "coinbase_wallet_sdk") {
            val consumer = file("consumer-rules.pro")
            if (!consumer.exists()) {
                consumer.writeText("# placeholder — coinbase_wallet_sdk omits this file\n")
            }
            val proguard = file("proguard-rules.pro")
            if (!proguard.exists()) {
                proguard.writeText("# placeholder — coinbase_wallet_sdk omits this file\n")
            }
        }
    }
}

subprojects {
    project.evaluationDependsOn(":app")
}

tasks.register<Delete>("clean") {
    delete(rootProject.layout.buildDirectory)
}