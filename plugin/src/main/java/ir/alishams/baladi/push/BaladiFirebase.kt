package ir.alishams.baladi.push

import android.content.Context
import android.util.Log
import com.google.firebase.FirebaseApp
import com.google.firebase.FirebaseOptions
import ir.alishams.baladi.mediapicker.BuildConfig

internal object BaladiFirebase {
    private const val TAG = "BaladiFirebase"

    @Synchronized
    fun app(context: Context): FirebaseApp? {
        val projectId = BuildConfig.FIREBASE_PROJECT_ID
        val senderId = BuildConfig.FIREBASE_SENDER_ID
        val appId = BuildConfig.FIREBASE_APP_ID
        val apiKey = BuildConfig.FIREBASE_API_KEY
        if (projectId.isBlank() || senderId.isBlank() || appId.isBlank() || apiKey.isBlank()) {
            Log.w(TAG, "Firebase configuration is missing.")
            return null
        }

        return try {
            FirebaseApp.getApps(context).firstOrNull { it.name == FirebaseApp.DEFAULT_APP_NAME }
                ?: FirebaseApp.initializeApp(
                    context,
                    FirebaseOptions.Builder()
                        .setProjectId(projectId)
                        .setGcmSenderId(senderId)
                        .setApplicationId(appId)
                        .setApiKey(apiKey)
                        .build()
                )
        } catch (error: Exception) {
            Log.e(TAG, "Firebase initialization failed.", error)
            null
        }
    }
}
