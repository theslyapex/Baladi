package ir.alishams.baladi.push

import android.app.NotificationManager
import android.app.PendingIntent
import android.content.Context
import android.content.Intent
import android.os.Build
import androidx.core.app.NotificationCompat
import com.google.firebase.messaging.FirebaseMessagingService
import com.google.firebase.messaging.RemoteMessage
import org.json.JSONObject

class BaladiFirebaseMessagingService : FirebaseMessagingService() {
    override fun onNewToken(token: String) {
        super.onNewToken(token)
        getSharedPreferences("baladi_push", Context.MODE_PRIVATE)
            .edit()
            .putString("fcm_token", token)
            .putLong("token_updated_at", System.currentTimeMillis())
            .apply()
        BaladiPushNotifications.activeInstance?.forwardToken(token)
    }

    override fun onMessageReceived(message: RemoteMessage) {
        super.onMessageReceived(message)
        val title = message.notification?.title ?: message.data["title"] ?: "بلدی؟"
        val body = message.notification?.body ?: message.data["body"] ?: ""
        if (body.isBlank()) return
        showNotification(title, body, message.data)
    }

    private fun showNotification(title: String, body: String, data: Map<String, String>) {
        val manager = getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O &&
            manager.getNotificationChannel(BaladiPushNotifications.CHANNEL_ID) == null
        ) {
            manager.createNotificationChannel(
                android.app.NotificationChannel(
                    BaladiPushNotifications.CHANNEL_ID,
                    "اعلان‌های بلدی؟",
                    NotificationManager.IMPORTANCE_HIGH
                )
            )
        }

        val launchIntent = packageManager.getLaunchIntentForPackage(packageName)?.apply {
            flags = Intent.FLAG_ACTIVITY_CLEAR_TOP or Intent.FLAG_ACTIVITY_SINGLE_TOP
            putExtra(BaladiPushNotifications.EXTRA_NOTIFICATION_PAYLOAD, JSONObject(data as Map<*, *>).toString())
        }
        val pendingIntent = launchIntent?.let {
            PendingIntent.getActivity(
                this,
                (System.currentTimeMillis() and 0x7fffffff).toInt(),
                it,
                PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
            )
        }

        val notification = NotificationCompat.Builder(this, BaladiPushNotifications.CHANNEL_ID)
            .setSmallIcon(android.R.drawable.ic_dialog_info)
            .setContentTitle(title)
            .setContentText(body)
            .setStyle(NotificationCompat.BigTextStyle().bigText(body))
            .setPriority(NotificationCompat.PRIORITY_HIGH)
            .setAutoCancel(true)
            .apply { if (pendingIntent != null) setContentIntent(pendingIntent) }
            .build()
        manager.notify((System.currentTimeMillis() and 0x7fffffff).toInt(), notification)
    }
}
