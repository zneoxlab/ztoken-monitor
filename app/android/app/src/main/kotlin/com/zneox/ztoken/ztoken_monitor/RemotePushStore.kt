package com.zneox.ztoken.ztoken_monitor

import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.content.Context
import android.content.Intent
import android.os.Build
import androidx.core.app.NotificationCompat
import com.google.firebase.FirebaseApp
import io.flutter.plugin.common.MethodChannel
import org.json.JSONObject

/**
 * Firebase 的配置和令牌都只留在原生层。没有 google-services.json 时，
 * [isFirebaseConfigured] 返回 false，调用端无需为普通/自托管构建增加特殊分支。
 */
object RemotePushStore {
    const val ACTION_OPEN_REMOTE_PUSH = "com.zneox.ztoken_monitor.OPEN_REMOTE_PUSH"

    private const val preferencesName = "remote_push"
    private const val tokenKey = "fcm_token"
    private const val openedEventKey = "opened_event"
    private const val notificationChannel = "quota_status"
    private const val notificationChannelName = "配额提醒"
    private val eventKeys = setOf(
        "eventId",
        "eventType",
        "type",
        "route",
        "targetId",
        "windowId",
        "cycleId",
        "remainingPercent",
        "thresholdPercent",
    )

    fun isFirebaseConfigured(context: Context): Boolean = try {
        FirebaseApp.getApps(context.applicationContext).isNotEmpty() ||
            FirebaseApp.initializeApp(context.applicationContext) != null
    } catch (_: Exception) {
        false
    }

    fun saveToken(context: Context, token: String) {
        preferences(context).edit().putString(tokenKey, token).apply()
    }

    fun savedToken(context: Context): String? =
        preferences(context).getString(tokenKey, null)?.trim()?.takeIf { it.isNotEmpty() }

    fun tokenPayload(token: String): Map<String, String> = mapOf(
        "provider" to "fcm",
        "token" to token,
    )

    fun eventFromData(data: Map<String, String>): Map<String, String>? =
        normalizeEvent(data)

    fun rememberOpenedEvent(context: Context, intent: Intent?): Map<String, String>? {
        val event = eventFromIntent(intent) ?: return null
        preferences(context).edit().putString(openedEventKey, JSONObject(event).toString()).apply()
        return event
    }

    fun takeOpenedEvent(context: Context): Map<String, String>? {
        val raw = preferences(context).getString(openedEventKey, null) ?: return null
        preferences(context).edit().remove(openedEventKey).apply()
        return try {
            val json = JSONObject(raw)
            normalizeEvent(eventKeys.associateWith { key -> json.optString(key, "") })
        } catch (_: Exception) {
            null
        }
    }

    fun showRemoteNotification(
        context: Context,
        event: Map<String, String>,
        title: String?,
        body: String?,
    ) {
        val eventId = event["eventId"] ?: return
        ensureNotificationChannel(context)
        val manager = context.getSystemService(NotificationManager::class.java)
        val openIntent = Intent(context, MainActivity::class.java).apply {
            action = ACTION_OPEN_REMOTE_PUSH
            addFlags(Intent.FLAG_ACTIVITY_SINGLE_TOP or Intent.FLAG_ACTIVITY_CLEAR_TOP)
            event.forEach { (key, value) -> putExtra(key, value) }
        }
        val pendingIntent = PendingIntent.getActivity(
            context,
            eventId.hashCode(),
            openIntent,
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE,
        )
        val visibleTitle = title?.trim().takeUnless { it.isNullOrEmpty() } ?: "配额状态变化"
        val visibleBody = body?.trim().takeUnless { it.isNullOrEmpty() } ?: "打开应用查看详情"
        val notification = NotificationCompat.Builder(context, notificationChannel)
            .setSmallIcon(android.R.drawable.ic_dialog_info)
            .setContentTitle(visibleTitle)
            .setContentText(visibleBody)
            .setStyle(NotificationCompat.BigTextStyle().bigText(visibleBody))
            .setAutoCancel(true)
            .setOnlyAlertOnce(true)
            .setContentIntent(pendingIntent)
            .build()
        manager.notify(eventId.hashCode(), notification)
    }

    fun ensureNotificationChannel(context: Context) {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.O) return
        context.getSystemService(NotificationManager::class.java).createNotificationChannel(
            NotificationChannel(
                notificationChannel,
                notificationChannelName,
                NotificationManager.IMPORTANCE_DEFAULT,
            ),
        )
    }

    private fun eventFromIntent(intent: Intent?): Map<String, String>? {
        intent ?: return null
        val values = eventKeys.associateWith { key -> intent.getStringExtra(key).orEmpty() }
        return if (intent.action == ACTION_OPEN_REMOTE_PUSH ||
            intent.hasExtra("eventId") || intent.hasExtra("event_id")
        ) {
            normalizeEvent(
                values + mapOf("eventId" to (values["eventId"] ?: intent.getStringExtra("event_id").orEmpty())),
            )
        } else {
            null
        }
    }

    private fun normalizeEvent(values: Map<String, String>): Map<String, String>? {
        val eventId = values["eventId"]?.trim().orEmpty().ifEmpty {
            values["event_id"]?.trim().orEmpty()
        }
        if (eventId.isEmpty()) return null
        return buildMap {
            put("eventId", eventId)
            eventKeys.filter { it != "eventId" }.forEach { key ->
                values[key]?.trim()?.takeIf { it.isNotEmpty() }?.let { put(key, it) }
            }
        }
    }

    private fun preferences(context: Context) =
        context.applicationContext.getSharedPreferences(preferencesName, Context.MODE_PRIVATE)
}

object RemotePushBridge {
    @Volatile private var channel: MethodChannel? = null

    fun attach(value: MethodChannel) {
        channel = value
    }

    fun detach(value: MethodChannel?) {
        if (channel === value) channel = null
    }

    fun publishToken(token: String) {
        channel?.invokeMethod("pushTokenRefreshed", RemotePushStore.tokenPayload(token))
    }
}
