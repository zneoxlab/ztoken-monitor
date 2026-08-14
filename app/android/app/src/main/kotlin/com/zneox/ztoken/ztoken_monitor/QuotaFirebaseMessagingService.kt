package com.zneox.ztoken.ztoken_monitor

import com.google.firebase.messaging.FirebaseMessagingService
import com.google.firebase.messaging.RemoteMessage

/** Firebase data message 的原生接收端；通知点击由 MainActivity 统一回传 Flutter。 */
class QuotaFirebaseMessagingService : FirebaseMessagingService() {
    override fun onNewToken(token: String) {
        super.onNewToken(token)
        val normalized = token.trim()
        if (normalized.isEmpty()) return
        RemotePushStore.saveToken(this, normalized)
        RemotePushBridge.publishToken(normalized)
    }

    override fun onMessageReceived(message: RemoteMessage) {
        super.onMessageReceived(message)
        val event = RemotePushStore.eventFromData(message.data) ?: return
        RemotePushStore.showRemoteNotification(
            this,
            event,
            message.data["title"] ?: message.notification?.title,
            message.data["body"] ?: message.notification?.body,
        )
    }
}
