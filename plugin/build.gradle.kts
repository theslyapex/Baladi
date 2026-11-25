import org.jetbrains.kotlin.gradle.dsl.JvmTarget
import groovy.json.JsonSlurper

val firebaseJson = System.getenv("GOOGLE_SERVICES_JSON")
val firebaseRoot = firebaseJson?.takeIf { it.isNotBlank() }?.let { JsonSlurper().parseText(it) as Map<*, *> }
val firebaseProject = firebaseRoot?.get("project_info") as? Map<*, *>
val firebaseClient = (firebaseRoot?.get("client") as? List<*>)?.firstOrNull() as? Map<*, *>
val firebaseClientInfo = firebaseClient?.get("client_info") as? Map<*, *>
val firebaseAndroidInfo = firebaseClientInfo?.get("android_client_info") as? Map<*, *>
val firebaseApiKey = ((firebaseClient?.get("api_key") as? List<*>)?.firstOrNull() as? Map<*, *>)?.get("current_key")?.toString() ?: ""
val firebaseProjectId = firebaseProject?.get("project_id")?.toString() ?: ""
val firebaseSenderId = firebaseProject?.get("project_number")?.toString() ?: ""
val firebaseAppId = firebaseClientInfo?.get("mobilesdk_app_id")?.toString() ?: ""
val firebasePackage = firebaseAndroidInfo?.get("package_name")?.toString() ?: ""
fun buildConfigString(value: String): String = "\"" + value.replace("\\", "\\\\").replace("\"", "\\\"") + "\""

plugins {
    id("com.android.library")
    id("org.jetbrains.kotlin.android")
}

val pluginName = "BaladiMediaPicker"
val pluginPackageName = "ir.alishams.baladi.mediapicker"

android {
    namespace = pluginPackageName
    compileSdk = 36

    buildFeatures {
        buildConfig = true
    }

    defaultConfig {
        minSdk = 24
        manifestPlaceholders["godotPluginName"] = pluginName
        manifestPlaceholders["godotPluginPackageName"] = pluginPackageName
        buildConfigField("String", "GODOT_PLUGIN_NAME", "\"BaladiMediaPicker\"")
        buildConfigField("String", "FIREBASE_PROJECT_ID", buildConfigString(firebaseProjectId))
        buildConfigField("String", "FIREBASE_SENDER_ID", buildConfigString(firebaseSenderId))
        buildConfigField("String", "FIREBASE_APP_ID", buildConfigString(firebaseAppId))
        buildConfigField("String", "FIREBASE_API_KEY", buildConfigString(firebaseApiKey))
        setProperty("archivesBaseName", pluginName)
    }

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

}

kotlin {
    compilerOptions {
        jvmTarget.set(JvmTarget.JVM_17)
    }
}

dependencies {
    implementation("org.godotengine:godot:4.7.2.stable")
    implementation("androidx.webkit:webkit:1.14.0")
    implementation("androidx.core:core-ktx:1.16.0")
    implementation("com.google.firebase:firebase-messaging:24.1.2")
}
