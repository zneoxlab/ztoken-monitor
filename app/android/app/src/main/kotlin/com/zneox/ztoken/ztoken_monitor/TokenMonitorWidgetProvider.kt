package com.zneox.ztoken.ztoken_monitor

import android.app.PendingIntent
import android.appwidget.AppWidgetManager
import android.appwidget.AppWidgetProvider
import android.content.ComponentName
import android.content.Context
import android.content.Intent
import android.graphics.Color
import android.util.TypedValue
import android.view.View
import android.widget.RemoteViews
import org.json.JSONObject
import kotlin.math.max

class TokenMonitorWidgetProvider : AppWidgetProvider() {
    override fun onUpdate(
        context: Context,
        appWidgetManager: AppWidgetManager,
        appWidgetIds: IntArray,
    ) {
        val snapshot = TokenMonitorWidgetStore.read(context)
        appWidgetIds.forEach { appWidgetId ->
            appWidgetManager.updateAppWidget(
                appWidgetId,
                TokenMonitorWidgetRenderer.render(context, snapshot, appWidgetId),
            )
        }
    }

    override fun onAppWidgetOptionsChanged(
        context: Context,
        appWidgetManager: AppWidgetManager,
        appWidgetId: Int,
        newOptions: android.os.Bundle,
    ) {
        appWidgetManager.updateAppWidget(
            appWidgetId,
            TokenMonitorWidgetRenderer.render(
                context,
                TokenMonitorWidgetStore.read(context),
                appWidgetId,
            ),
        )
    }

    companion object {
        const val ACTION_OPEN = "com.zneox.ztoken_monitor.action.OPEN_WIDGET"
        const val EXTRA_ROUTE = "widget_route"
        const val EXTRA_REFRESH = "widget_refresh"

        fun updateAll(context: Context) {
            val manager = AppWidgetManager.getInstance(context)
            val component = ComponentName(context, TokenMonitorWidgetProvider::class.java)
            val ids = manager.getAppWidgetIds(component)
            if (ids.isEmpty()) return
            val snapshot = TokenMonitorWidgetStore.read(context)
            ids.forEach { id ->
                manager.updateAppWidget(
                    id,
                    TokenMonitorWidgetRenderer.render(context, snapshot, id),
                )
            }
        }
    }
}

object TokenMonitorWidgetStore {
    private const val PREFS_NAME = "token_monitor_widget"
    private const val KEY_SNAPSHOT = "snapshot"

    fun write(context: Context, payload: Map<String, Any?>) {
        val preferences = context.getSharedPreferences(PREFS_NAME, Context.MODE_PRIVATE)
        val incomingState = payload["state"] as? String ?: "error"
        val existing = preferences.getString(KEY_SNAPSHOT, null)
        val existingState = existing?.let {
            runCatching { JSONObject(it).optString("state") }.getOrNull()
        }
        // 冷启动 loading/error 不能覆盖上次成功快照；断开登录则必须立即清空。
        if ((incomingState == "loading" || incomingState == "error") &&
            existingState == "ready"
        ) {
            return
        }
        preferences.edit()
            .putString(KEY_SNAPSHOT, JSONObject(payload).toString())
            .apply()
    }

    fun read(context: Context): JSONObject {
        val raw = context
            .getSharedPreferences(PREFS_NAME, Context.MODE_PRIVATE)
            .getString(KEY_SNAPSHOT, null)
        return raw?.let { runCatching { JSONObject(it) }.getOrNull() }
            ?: JSONObject().apply {
                put("state", "disconnected")
                put("theme", "graphiteMint")
            }
    }
}

private object TokenMonitorWidgetRenderer {
    private data class Palette(
        val background: Int,
        val text: Int,
        val muted: Int,
        val faint: Int,
        val accent: Int,
        val normal: Int,
        val low: Int,
        val critical: Int,
    )

    fun render(context: Context, data: JSONObject, widgetId: Int): RemoteViews {
        val views = RemoteViews(context.packageName, R.layout.widget_token_monitor)
        val palette = palette(data.optString("theme", "graphiteMint"))
        applyPalette(views, palette)
        bindActions(context, views, widgetId)

        if (data.optString("state", "disconnected") != "ready") {
            renderState(views, data.optString("state", "disconnected"))
            return views
        }

        views.setViewVisibility(R.id.widget_state, View.GONE)
        views.setViewVisibility(R.id.widget_content, View.VISIBLE)
        renderUsage(views, data)
        renderQuotas(context, views, data, palette)
        return views
    }

    private fun applyPalette(views: RemoteViews, palette: Palette) {
        views.setInt(R.id.widget_root, "setBackgroundResource", palette.background)
        val primary = intArrayOf(
            R.id.usage_period,
            R.id.usage_tokens,
            R.id.quota_title,
            R.id.quota_provider_1,
            R.id.quota_provider_2,
            R.id.widget_state_title,
        )
        val muted = intArrayOf(
            R.id.usage_unit,
            R.id.quota_updated,
            R.id.quota_window_1,
            R.id.quota_window_2,
            R.id.widget_state_subtitle,
            R.id.quota_empty_title,
        )
        val faint = intArrayOf(
            R.id.usage_updated,
            R.id.quota_reset_1,
            R.id.quota_reset_2,
            R.id.quota_empty_subtitle,
        )
        primary.forEach { views.setTextColor(it, palette.text) }
        muted.forEach { views.setTextColor(it, palette.muted) }
        faint.forEach { views.setTextColor(it, palette.faint) }
        views.setTextColor(R.id.usage_cost, palette.accent)
    }

    private fun renderState(views: RemoteViews, state: String) {
        views.setViewVisibility(R.id.widget_content, View.GONE)
        views.setViewVisibility(R.id.widget_state, View.VISIBLE)
        views.setImageViewResource(R.id.widget_state_icon, R.drawable.widget_provider_app)
        val (title, subtitle) = when (state) {
            "loading" -> "正在同步" to "首次数据到达后会自动更新"
            "error" -> "同步失败" to "点击打开 App 重试"
            else -> "打开 ZT助手 完成连接" to "连接后显示本月用量和额度"
        }
        views.setTextViewText(R.id.widget_state_title, title)
        views.setTextViewText(R.id.widget_state_subtitle, subtitle)
    }

    private fun renderUsage(views: RemoteViews, data: JSONObject) {
        views.setTextViewText(R.id.usage_period, data.optString("periodLabel", "本月"))
        val hasUsage = data.optBoolean("hasUsage", false)
        if (hasUsage) {
            val tokenText = data.optString("tokens", "0")
            views.setTextViewText(R.id.usage_tokens, tokenText)
            views.setTextViewTextSize(
                R.id.usage_tokens,
                TypedValue.COMPLEX_UNIT_SP,
                when {
                    tokenText.length <= 5 -> 42f
                    tokenText.length == 6 -> 39f
                    tokenText.length == 7 -> 35f
                    else -> 31f
                },
            )
            views.setViewVisibility(R.id.usage_unit, View.VISIBLE)
            views.setViewVisibility(R.id.usage_cost, View.VISIBLE)
            views.setTextViewText(R.id.usage_cost, data.optString("cost", ""))
        } else {
            views.setTextViewText(R.id.usage_tokens, "暂无用量")
            views.setTextViewTextSize(
                R.id.usage_tokens,
                TypedValue.COMPLEX_UNIT_SP,
                18f,
            )
            views.setViewVisibility(R.id.usage_unit, View.GONE)
            views.setViewVisibility(R.id.usage_cost, View.GONE)
        }
        views.setTextViewText(
            R.id.usage_updated,
            freshnessText(
                data.optLong("usageUpdatedAtMs", 0),
                data.optBoolean("usageStale", false),
                suffix = "同步",
            ),
        )
    }

    private fun renderQuotas(
        context: Context,
        views: RemoteViews,
        data: JSONObject,
        palette: Palette,
    ) {
        views.setTextViewText(
            R.id.quota_updated,
            freshnessText(
                data.optLong("limitsUpdatedAtMs", 0),
                data.optBoolean("limitsStale", false),
                suffix = "",
            ),
        )
        val quotas = data.optJSONArray("quotas")
        if (quotas == null || quotas.length() == 0) {
            views.setViewVisibility(R.id.quota_list, View.GONE)
            views.setViewVisibility(R.id.quota_empty, View.VISIBLE)
            views.setTextViewText(R.id.quota_empty_title, "暂未配置额度")
            views.setTextViewText(R.id.quota_empty_subtitle, "在 App 中添加额度账户")
            return
        }

        views.setViewVisibility(R.id.quota_list, View.VISIBLE)
        views.setViewVisibility(R.id.quota_empty, View.GONE)
        bindQuota(context, views, quotas.optJSONObject(0), 1, palette)
        if (quotas.length() > 1) {
            views.setViewVisibility(R.id.quota_divider_2, View.VISIBLE)
            views.setViewVisibility(R.id.quota_row_2, View.VISIBLE)
            bindQuota(context, views, quotas.optJSONObject(1), 2, palette)
        } else {
            views.setViewVisibility(R.id.quota_divider_2, View.GONE)
            views.setViewVisibility(R.id.quota_row_2, View.GONE)
        }
    }

    private fun bindQuota(
        context: Context,
        views: RemoteViews,
        item: JSONObject?,
        index: Int,
        palette: Palette,
    ) {
        if (item == null) return
        val iconId = if (index == 1) R.id.quota_icon_1 else R.id.quota_icon_2
        val providerId = if (index == 1) R.id.quota_provider_1 else R.id.quota_provider_2
        val windowId = if (index == 1) R.id.quota_window_1 else R.id.quota_window_2
        val valueId = if (index == 1) R.id.quota_value_1 else R.id.quota_value_2
        val resetId = if (index == 1) R.id.quota_reset_1 else R.id.quota_reset_2
        views.setImageViewResource(
            iconId,
            providerIconResource(context, item.optString("iconId", "app")),
        )
        views.setTextViewText(providerId, item.optString("providerName", "?"))
        views.setTextViewText(windowId, item.optString("windowLabel", ""))
        views.setTextViewText(valueId, item.optString("value", "—"))
        views.setTextViewText(resetId, item.optString("resetText", ""))

        val tone = item.optString("tone", "normal")
        val valueColor = when (tone) {
            "critical" -> palette.critical
            "low" -> palette.low
            else -> palette.normal
        }
        views.setTextColor(valueId, valueColor)
        bindProgress(
            views,
            index,
            item.optInt("meterPercent", 0).coerceIn(0, 100),
            item.optBoolean("showMeter", false),
            tone,
        )
    }

    private fun bindProgress(
        views: RemoteViews,
        index: Int,
        progress: Int,
        show: Boolean,
        tone: String,
    ) {
        val normal = if (index == 1) R.id.quota_progress_normal_1 else R.id.quota_progress_normal_2
        val low = if (index == 1) R.id.quota_progress_low_1 else R.id.quota_progress_low_2
        val critical = if (index == 1) R.id.quota_progress_critical_1 else R.id.quota_progress_critical_2
        intArrayOf(normal, low, critical).forEach { id ->
            views.setProgressBar(id, 100, progress, false)
            views.setViewVisibility(id, View.GONE)
        }
        if (!show) return
        val selected = when (tone) {
            "critical" -> critical
            "low" -> low
            else -> normal
        }
        views.setViewVisibility(selected, View.VISIBLE)
    }

    private fun bindActions(context: Context, views: RemoteViews, widgetId: Int) {
        views.setOnClickPendingIntent(
            R.id.widget_state,
            openApp(context, widgetId * 10, "/home", refresh = true),
        )
        views.setOnClickPendingIntent(
            R.id.usage_panel,
            openApp(context, widgetId * 10 + 1, "/home", refresh = false),
        )
        views.setOnClickPendingIntent(
            R.id.usage_updated,
            openApp(context, widgetId * 10 + 2, "/home", refresh = true),
        )
        views.setOnClickPendingIntent(
            R.id.quota_panel,
            openApp(context, widgetId * 10 + 3, "/limits", refresh = false),
        )
        views.setOnClickPendingIntent(
            R.id.quota_updated,
            openApp(context, widgetId * 10 + 4, "/limits", refresh = true),
        )
    }

    private fun openApp(
        context: Context,
        requestCode: Int,
        route: String,
        refresh: Boolean,
    ): PendingIntent {
        val intent = Intent(context, MainActivity::class.java).apply {
            action = TokenMonitorWidgetProvider.ACTION_OPEN
            putExtra(TokenMonitorWidgetProvider.EXTRA_ROUTE, route)
            putExtra(TokenMonitorWidgetProvider.EXTRA_REFRESH, refresh)
            addFlags(Intent.FLAG_ACTIVITY_CLEAR_TOP or Intent.FLAG_ACTIVITY_SINGLE_TOP)
        }
        return PendingIntent.getActivity(
            context,
            requestCode,
            intent,
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE,
        )
    }

    private fun providerIconResource(context: Context, raw: String): Int {
        val normalized = raw.lowercase().replace('-', '_').replace(Regex("[^a-z0-9_]"), "_")
        val resource = context.resources.getIdentifier(
            "widget_provider_$normalized",
            "drawable",
            context.packageName,
        )
        return if (resource == 0) R.drawable.widget_provider_app else resource
    }

    private fun freshnessText(timestampMs: Long, stale: Boolean, suffix: String): String {
        if (stale) return "已过期"
        if (timestampMs <= 0) return "暂无同步"
        val elapsedMs = max(0, System.currentTimeMillis() - timestampMs)
        val minutes = elapsedMs / 60_000
        val age = when {
            minutes < 1 -> "刚刚"
            minutes < 60 -> "$minutes 分钟前"
            minutes < 24 * 60 -> "${minutes / 60} 小时前"
            else -> "${minutes / (24 * 60)} 天前"
        }
        return if (suffix.isEmpty() || age == "刚刚") {
            if (suffix.isEmpty()) age else "刚刚$suffix"
        } else {
            "$age$suffix"
        }
    }

    private fun palette(theme: String): Palette {
        return when (theme) {
            "starryBlue" -> Palette(
                R.drawable.widget_bg_starry_blue,
                Color.parseColor("#EAF2FD"),
                Color.parseColor("#93A5C2"),
                Color.parseColor("#62708B"),
                Color.parseColor("#58A6FF"),
                Color.parseColor("#EAF2FD"),
                Color.parseColor("#D4A04A"),
                Color.parseColor("#E5534B"),
            )
            "obsidian" -> Palette(
                R.drawable.widget_bg_obsidian,
                Color.parseColor("#ECEEF2"),
                Color.parseColor("#8F949C"),
                Color.parseColor("#5C626B"),
                Color.parseColor("#E6E8EC"),
                Color.parseColor("#ECEEF2"),
                Color.parseColor("#D4A04A"),
                Color.parseColor("#E5534B"),
            )
            "porcelain" -> Palette(
                R.drawable.widget_bg_porcelain,
                Color.parseColor("#1C1F26"),
                Color.parseColor("#5B626D"),
                Color.parseColor("#9AA2AD"),
                Color.parseColor("#2563EB"),
                Color.parseColor("#1C1F26"),
                Color.parseColor("#B7791F"),
                Color.parseColor("#C53030"),
            )
            else -> Palette(
                R.drawable.widget_bg_graphite_mint,
                Color.parseColor("#EEF5FB"),
                Color.parseColor("#A3ADBB"),
                Color.parseColor("#6B7480"),
                Color.parseColor("#B7EAD4"),
                Color.parseColor("#EEF5FB"),
                Color.parseColor("#D4A04A"),
                Color.parseColor("#E5534B"),
            )
        }
    }
}
