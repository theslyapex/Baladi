package ir.alishams.baladi.push

import android.Manifest
import android.app.Activity
import android.app.NotificationChannel
import android.app.NotificationManager
import android.content.Context
import android.content.Intent
import android.content.pm.PackageManager
import android.os.Build
import android.view.View
import androidx.core.content.ContextCompat
import com.google.firebase.messaging.FirebaseMessaging
import org.godotengine.godot.Godot
import org.godotengine.godot.plugin.GodotPlugin
import org.godotengine.godot.plugin.SignalInfo
import org.godotengine.godot.plugin.UsedByGodot
import org.json.JSONObject

class BaladiPushNotifications(godot: Godot) : GodotPlugin(godot) {
    override fun getPluginName(): String = "BaladiPushNotifications"

    init { activeInstance = this }

    override fun getPluginSignals(): Set<SignalInfo> = setOf(
        SignalInfo("notification_permission_result", Boolean::class.javaPrimitiveType!!),
        SignalInfo("notification_token_received", String::class.java),
        SignalInfo("notification_error", String::class.java),
        SignalInfo("notification_opened", String::class.java)
    )

    override fun onMainCreate(activity: Activity?): View? {
        activity?.let {
            createNotificationChannel(it)
            BaladiFirebase.app(it.applicationContext)
            forwardNotificationIntent(it.intent)
        }
        return null
    }

    override fun onMainResume() {
        activity?.let { forwardNotificationIntent(it.intent) }
    }

    @UsedByGodot
    fun requestPermission() {
        runOnHostThread {
            val host = activity ?: return@runOnHostThread
            val app = BaladiFirebase.app(host.applicationContext)
            if (app == null) {
                emitSignal("notification_error", "تنظیمات Firebase در نسخه فعلی بازی پیدا نشد.")
                return@runOnHostThread
            }
            createNotificationChannel(host)
            if (Build.VERSION.SDK_INT >= 33 &&
                ContextCompat.checkSelfPermission(host, Manifest.permission.POST_NOTIFICATIONS) != PackageManager.PERMISSION_GRANTED
            ) {
                host.requestPermissions(arrayOf(Manifest.permission.POST_NOTIFICATIONS), REQUEST_NOTIFICATION_PERMISSION)
            } else {
                emitSignal("notification_permission_result", true)
                fetchToken()
            }
        }
    }

    @UsedByGodot
    fun getToken() {
        runOnHostThread { fetchToken() }
    }

    @UsedByGodot
    fun hasPermission(): Boolean {
        val host = activity ?: return false
        return Build.VERSION.SDK_INT < 33 ||
            ContextCompat.checkSelfPermission(host, Manifest.permission.POST_NOTIFICATIONS) == PackageManager.PERMISSION_GRANTED
    }

    private fun fetchToken() {
        val host = activity ?: return
        val app = BaladiFirebase.app(host.applicationContext) ?: run {
            emitSignal("notification_error", "راه‌اندازی سرویس اعلان ناموفق بود.")
            return
        }
        FirebaseMessaging.getInstance().token
            .addOnSuccessListener { token ->
                if (token.isNotBlank()) emitSignal("notification_token_received", token)
            }
            .addOnFailureListener { error ->
                emitSignal("notification_error", error.message ?: "دریافت شناسه اعلان ناموفق بود.")
            }
    }

    override fun onMainRequestPermissionsResult(requestCode: Int, permissions: Array<out String>, grantResults: IntArray) {
        if (requestCode != REQUEST_NOTIFICATION_PERMISSION) return
        val granted = grantResults.isNotEmpty() && grantResults[0] == PackageManager.PERMISSION_GRANTED
        emitSignal("notification_permission_result", granted)
        if (granted) fetchToken()
    }

    private fun createNotificationChannel(context: Context) {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            val channel = NotificationChannel(
                CHANNEL_ID,
                "اعلان‌های بلدی؟",
                NotificationManager.IMPORTANCE_HIGH
            ).apply {
                description = "دعوت‌ها، نتیجه رقابت‌ها و پیام‌های گروه و مدیریت"
                enableVibration(true)
            }
            context.getSystemService(NotificationManager::class.java)?.createNotificationChannel(channel)
        }
    }

    private fun forwardNotificationIntent(intent: Intent?) {
        val payload = intent?.getStringExtra(EXTRA_NOTIFICATION_PAYLOAD) ?: return
        intent.removeExtra(EXTRA_NOTIFICATION_PAYLOAD)
        emitSignal("notification_opened", payload)
    }

    fun forwardToken(token: String) {
        emitSignal("notification_token_received", token)
    }

    companion object {
        @Volatile
        var activeInstance: BaladiPushNotifications? = null

        const val CHANNEL_ID = "baladi_updates"
        const val EXTRA_NOTIFICATION_PAYLOAD = "baladi_notification_payload"
        const val REQUEST_NOTIFICATION_PERMISSION = 7412
    }
}
