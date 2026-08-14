package com.zneox.ztoken.ztoken_monitor

import android.Manifest
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.content.Intent
import android.content.pm.PackageManager
import android.net.Uri
import android.os.Build
import android.provider.Settings
import androidx.core.content.FileProvider
import androidx.core.app.NotificationCompat
import androidx.core.content.ContextCompat
import androidx.core.app.NotificationManagerCompat
import com.google.firebase.messaging.FirebaseMessaging
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import java.io.File
import java.security.MessageDigest

class MainActivity : FlutterActivity() {
    companion object {
        private const val CHANNEL_NAME = "com.zneox.ztoken_monitor/app_update"
        private const val APK_MIME_TYPE = "application/vnd.android.package-archive"
        private const val HOME_WIDGET_CHANNEL = "com.zneox.ztoken_monitor/home_widget"
        private const val NOTIFICATION_CHANNEL = "quota_status"
        private const val NOTIFICATION_CHANNEL_NAME = "配额提醒"
        private const val NOTIFICATION_PERMISSION_REQUEST = 4101
        private const val NOTIFICATION_CHANNEL_NAME_DART =
            "com.zneox.ztoken_monitor/notifications"
    }

    private var homeWidgetChannel: MethodChannel? = null
    private var pendingWidgetAction: Map<String, Any>? = null
    private var notificationChannel: MethodChannel? = null
    private var pendingNotificationPermissionResult: MethodChannel.Result? = null

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        // FCM 在后台由系统展示 notification payload；首次取得令牌前先创建
        // manifest 指定的默认 channel，避免进程被杀时回落到不一致的频道。
        RemotePushStore.ensureNotificationChannel(this)
        MethodChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            CHANNEL_NAME,
        ).setMethodCallHandler(::handleUpdateCall)
        rememberWidgetAction(intent)
        RemotePushStore.rememberOpenedEvent(this, intent)
        homeWidgetChannel = MethodChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            HOME_WIDGET_CHANNEL,
        ).also { channel ->
            channel.setMethodCallHandler(::handleHomeWidgetCall)
        }
        notificationChannel = MethodChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            NOTIFICATION_CHANNEL_NAME_DART,
        ).also { channel ->
            channel.setMethodCallHandler(::handleNotificationCall)
            RemotePushBridge.attach(channel)
        }
    }

    override fun onNewIntent(intent: Intent) {
        super.onNewIntent(intent)
        setIntent(intent)
        RemotePushStore.rememberOpenedEvent(this, intent)?.let { event ->
            notificationChannel?.invokeMethod("pushNotificationOpened", event)
        }
        val action = widgetAction(intent) ?: return
        val channel = homeWidgetChannel
        if (channel == null) {
            pendingWidgetAction = action
        } else {
            channel.invokeMethod("openRoute", action)
        }
    }

    private fun handleHomeWidgetCall(call: MethodCall, result: MethodChannel.Result) {
        when (call.method) {
            "updateWidget" -> {
                @Suppress("UNCHECKED_CAST")
                val payload = call.arguments as? Map<String, Any?>
                if (payload == null) {
                    result.error("invalid_arguments", "小组件数据无效", null)
                    return
                }
                TokenMonitorWidgetStore.write(this, payload)
                TokenMonitorWidgetProvider.updateAll(this)
                result.success(null)
            }
            "getPendingAction" -> {
                val action = pendingWidgetAction
                pendingWidgetAction = null
                result.success(action)
            }
            else -> result.notImplemented()
        }
    }

    private fun handleNotificationCall(call: MethodCall, result: MethodChannel.Result) {
        when (call.method) {
            "requestPermission" -> requestNotificationPermission(result)
            "getNotificationPermissionStatus" -> result.success(areNotificationsEnabled())
            "getRemotePushToken" -> getRemotePushToken(result)
            "getInitialPushEvent" -> result.success(RemotePushStore.takeOpenedEvent(this))
            "showQuotaNotification" -> {
                @Suppress("UNCHECKED_CAST")
                val payload = call.arguments as? Map<Any?, Any?>
                if (payload == null) {
                    result.error("invalid_arguments", "通知内容无效", null)
                    return
                }
                showQuotaNotification(payload)
                result.success(null)
            }
            else -> result.notImplemented()
        }
    }

    private fun requestNotificationPermission(result: MethodChannel.Result) {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.TIRAMISU ||
            ContextCompat.checkSelfPermission(
                this,
                Manifest.permission.POST_NOTIFICATIONS,
            ) == PackageManager.PERMISSION_GRANTED
        ) {
            result.success(areNotificationsEnabled())
            return
        }
        if (pendingNotificationPermissionResult != null) {
            result.success(false)
            return
        }
        pendingNotificationPermissionResult = result
        requestPermissions(
            arrayOf(Manifest.permission.POST_NOTIFICATIONS),
            NOTIFICATION_PERMISSION_REQUEST,
        )
    }

    private fun getRemotePushToken(result: MethodChannel.Result) {
        if (!RemotePushStore.isFirebaseConfigured(this)) {
            result.success(null)
            return
        }
        try {
            FirebaseMessaging.getInstance().token.addOnCompleteListener { task ->
                val token = if (task.isSuccessful) {
                    task.result?.trim().takeUnless { it.isNullOrEmpty() }
                } else {
                    null
                }
                if (task.isSuccessful && token != null) {
                    RemotePushStore.saveToken(this, token)
                    result.success(RemotePushStore.tokenPayload(token))
                } else {
                    result.success(RemotePushStore.savedToken(this)?.let(RemotePushStore::tokenPayload))
                }
            }
        } catch (_: Exception) {
            result.success(RemotePushStore.savedToken(this)?.let(RemotePushStore::tokenPayload))
        }
    }

    private fun areNotificationsEnabled(): Boolean =
        NotificationManagerCompat.from(this).areNotificationsEnabled()

    override fun onRequestPermissionsResult(
        requestCode: Int,
        permissions: Array<out String>,
        grantResults: IntArray,
    ) {
        super.onRequestPermissionsResult(requestCode, permissions, grantResults)
        if (requestCode != NOTIFICATION_PERMISSION_REQUEST) return
        val result = pendingNotificationPermissionResult ?: return
        pendingNotificationPermissionResult = null
        result.success(
            grantResults.firstOrNull() == PackageManager.PERMISSION_GRANTED &&
                areNotificationsEnabled(),
        )
    }

    override fun onDestroy() {
        RemotePushBridge.detach(notificationChannel)
        notificationChannel = null
        super.onDestroy()
    }

    private fun showQuotaNotification(payload: Map<Any?, Any?>) {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU &&
            ContextCompat.checkSelfPermission(
                this,
                Manifest.permission.POST_NOTIFICATIONS,
            ) != PackageManager.PERMISSION_GRANTED
        ) {
            return
        }

        val title = payload["title"] as? String ?: return
        val body = payload["body"] as? String ?: return
        if (title.isBlank() || body.isBlank()) return
        val tag = (payload["tag"] as? String).orEmpty().ifBlank { "quota-status" }

        val manager = getSystemService(NotificationManager::class.java)
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            manager.createNotificationChannel(
                NotificationChannel(
                    NOTIFICATION_CHANNEL,
                    NOTIFICATION_CHANNEL_NAME,
                    NotificationManager.IMPORTANCE_DEFAULT,
                ),
            )
        }

        val launchIntent = packageManager.getLaunchIntentForPackage(packageName)
        val pendingIntent = launchIntent?.let {
            PendingIntent.getActivity(
                this,
                tag.hashCode(),
                it.apply {
                    addFlags(Intent.FLAG_ACTIVITY_SINGLE_TOP or Intent.FLAG_ACTIVITY_CLEAR_TOP)
                },
                PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE,
            )
        }
        val notification = NotificationCompat.Builder(this, NOTIFICATION_CHANNEL)
            .setSmallIcon(android.R.drawable.ic_dialog_info)
            .setContentTitle(title)
            .setContentText(body)
            .setStyle(NotificationCompat.BigTextStyle().bigText(body))
            .setPriority(NotificationCompat.PRIORITY_DEFAULT)
            .setAutoCancel(true)
            .setOnlyAlertOnce(true)
            .apply {
                if (pendingIntent != null) setContentIntent(pendingIntent)
            }
            .build()
        manager.notify(tag.hashCode(), notification)
    }

    private fun rememberWidgetAction(intent: Intent?) {
        val action = intent?.let(::widgetAction) ?: return
        pendingWidgetAction = action
    }

    private fun widgetAction(intent: Intent): Map<String, Any>? {
        if (intent.action != TokenMonitorWidgetProvider.ACTION_OPEN) return null
        return mapOf(
            "route" to (intent.getStringExtra(TokenMonitorWidgetProvider.EXTRA_ROUTE) ?: "/home"),
            "refresh" to intent.getBooleanExtra(TokenMonitorWidgetProvider.EXTRA_REFRESH, false),
        )
    }

    private fun handleUpdateCall(call: MethodCall, result: MethodChannel.Result) {
        when (call.method) {
            "getDistribution" -> result.success(BuildConfig.FLAVOR)
            "getCacheDirectory" -> result.success(cacheDir.absolutePath)
            "verifyAndInstallApk" -> verifyAndInstallApk(call, result)
            else -> result.notImplemented()
        }
    }

    private fun verifyAndInstallApk(call: MethodCall, result: MethodChannel.Result) {
        if (BuildConfig.FLAVOR != "website") {
            result.error("distribution_forbidden", "当前渠道不允许直接安装 APK", null)
            return
        }

        val path = call.argument<String>("path")
        val expectedSha256 = call.argument<String>("sha256")?.lowercase()
        if (path.isNullOrBlank() || expectedSha256?.matches(Regex("^[0-9a-f]{64}$")) != true) {
            result.error("invalid_arguments", "安装包路径或 SHA-256 无效", null)
            return
        }

        val apk = try {
            File(path).canonicalFile
        } catch (_: Exception) {
            result.error("invalid_path", "安装包路径无效", null)
            return
        }
        val trustedRoot = cacheDir.canonicalPath + File.separator
        if (!apk.path.startsWith(trustedRoot) || !apk.isFile) {
            result.error("invalid_path", "安装包不在应用缓存目录", null)
            return
        }

        val actualSha256 = try {
            sha256(apk)
        } catch (_: Exception) {
            result.error("read_failed", "无法读取安装包", null)
            return
        }
        if (actualSha256 != expectedSha256) {
            apk.delete()
            result.error("sha_mismatch", "安装包 SHA-256 校验失败", null)
            return
        }

        val packageInfo = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
            packageManager.getPackageArchiveInfo(
                apk.path,
                android.content.pm.PackageManager.PackageInfoFlags.of(0),
            )
        } else {
            @Suppress("DEPRECATION")
            packageManager.getPackageArchiveInfo(apk.path, 0)
        }
        if (packageInfo?.packageName != packageName) {
            apk.delete()
            result.error("package_mismatch", "安装包应用 ID 不匹配", null)
            return
        }
        val archiveVersionCode = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.P) {
            packageInfo.longVersionCode
        } else {
            @Suppress("DEPRECATION")
            packageInfo.versionCode.toLong()
        }
        if (archiveVersionCode <= BuildConfig.VERSION_CODE) {
            apk.delete()
            result.error("version_not_newer", "安装包构建号不高于当前版本", null)
            return
        }

        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O &&
            !packageManager.canRequestPackageInstalls()
        ) {
            val settingsIntent = Intent(
                Settings.ACTION_MANAGE_UNKNOWN_APP_SOURCES,
                Uri.parse("package:$packageName"),
            )
            startActivity(settingsIntent)
            result.success("permissionRequired")
            return
        }

        try {
            val contentUri = FileProvider.getUriForFile(
                this,
                "$packageName.update-files",
                apk,
            )
            val installIntent = Intent(Intent.ACTION_VIEW).apply {
                setDataAndType(contentUri, APK_MIME_TYPE)
                addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION)
            }
            startActivity(installIntent)
            result.success("installerOpened")
        } catch (error: Exception) {
            result.error("installer_failed", error.message ?: "无法打开系统安装器", null)
        }
    }

    private fun sha256(file: File): String {
        val digest = MessageDigest.getInstance("SHA-256")
        file.inputStream().use { input ->
            val buffer = ByteArray(DEFAULT_BUFFER_SIZE)
            while (true) {
                val count = input.read(buffer)
                if (count <= 0) break
                digest.update(buffer, 0, count)
            }
        }
        return digest.digest().joinToString("") { byte -> "%02x".format(byte) }
    }
}
