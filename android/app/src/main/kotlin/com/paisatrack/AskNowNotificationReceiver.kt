package com.paisatrack

import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.os.Build
import androidx.core.app.NotificationCompat
import androidx.core.app.NotificationManagerCompat
import androidx.core.app.RemoteInput
import java.nio.charset.StandardCharsets
import java.util.Base64

class AskNowNotificationReceiver : BroadcastReceiver() {
    override fun onReceive(context: Context, intent: Intent) {
        val txnId = intent.getStringExtra(ExtraTxnId) ?: return
        val categoryId = intent.getStringExtra(ExtraCategoryId)
        val freeText = RemoteInput.getResultsFromIntent(intent)
            ?.getCharSequence(RemoteInputKey)
            ?.toString()
            ?.trim()
            ?.takeIf { it.isNotEmpty() }

        AskNowNotifications.storeResponse(context, txnId, categoryId, freeText)
        NotificationManagerCompat.from(context).cancel(txnId.hashCode())

        context.packageManager.getLaunchIntentForPackage(context.packageName)
            ?.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_SINGLE_TOP)
            ?.let(context::startActivity)
    }
}

object AskNowNotifications {
    fun show(context: Context, payload: Map<*, *>) {
        ensureChannel(context)

        val txnId = payload["txnId"] as? String ?: return
        val title = payload["title"] as? String ?: return
        val body = payload["body"] as? String ?: return
        val actions = payload["actions"] as? List<*> ?: emptyList<Any>()

        val builder = NotificationCompat.Builder(context, ChannelId)
            .setSmallIcon(android.R.drawable.ic_dialog_info)
            .setContentTitle(title)
            .setContentText(body)
            .setStyle(NotificationCompat.BigTextStyle().bigText(body))
            .setAutoCancel(true)
            .setPriority(NotificationCompat.PRIORITY_HIGH)
            .setCategory(NotificationCompat.CATEGORY_STATUS)

        actions.take(3).forEach { raw ->
            val action = raw as? Map<*, *> ?: return@forEach
            val categoryId = action["categoryId"] as? String ?: return@forEach
            val label = action["label"] as? String ?: return@forEach
            builder.addAction(
                NotificationCompat.Action.Builder(
                    android.R.drawable.ic_menu_set_as,
                    label,
                    responseIntent(context, txnId, categoryId, null),
                ).build(),
            )
        }

        val remoteInput = RemoteInput.Builder(RemoteInputKey)
            .setLabel("Category or note")
            .build()
        builder.addAction(
            NotificationCompat.Action.Builder(
                android.R.drawable.ic_menu_edit,
                "Type",
                responseIntent(context, txnId, null, "free_text"),
            ).addRemoteInput(remoteInput).build(),
        )

        NotificationManagerCompat.from(context).notify(txnId.hashCode(), builder.build())
    }

    fun takePendingResponses(context: Context): List<Map<String, String?>> {
        val prefs = context.getSharedPreferences(PrefsName, Context.MODE_PRIVATE)
        val raw = prefs.getString(PrefsResponses, "[]") ?: "[]"
        return AskNowPendingResponseCodec.decode(raw)
    }

    fun ackPendingResponses(context: Context, txnIds: List<String>) {
        if (txnIds.isEmpty()) return
        val prefs = context.getSharedPreferences(PrefsName, Context.MODE_PRIVATE)
        val raw = prefs.getString(PrefsResponses, "[]") ?: "[]"
        prefs.edit()
            .putString(PrefsResponses, AskNowPendingResponseCodec.remove(raw, txnIds.toSet()))
            .apply()
    }

    fun storeResponse(
        context: Context,
        txnId: String,
        categoryId: String?,
        freeText: String?,
    ) {
        val prefs = context.getSharedPreferences(PrefsName, Context.MODE_PRIVATE)
        val raw = prefs.getString(PrefsResponses, "[]") ?: "[]"
        prefs.edit()
            .putString(
                PrefsResponses,
                AskNowPendingResponseCodec.append(raw, txnId, categoryId, freeText),
            )
            .apply()
    }

    private fun responseIntent(
        context: Context,
        txnId: String,
        categoryId: String?,
        action: String?,
    ): PendingIntent {
        val intent = Intent(context, AskNowNotificationReceiver::class.java)
            .putExtra(ExtraTxnId, txnId)
            .putExtra(ExtraCategoryId, categoryId)
            .putExtra(ExtraAction, action)
        return PendingIntent.getBroadcast(
            context,
            (txnId + (categoryId ?: action ?: "")).hashCode(),
            intent,
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_MUTABLE,
        )
    }

    private fun ensureChannel(context: Context) {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.O) return
        val manager = context.getSystemService(NotificationManager::class.java)
        val channel = NotificationChannel(
            ChannelId,
            "Ask now",
            NotificationManager.IMPORTANCE_HIGH,
        )
        manager.createNotificationChannel(channel)
    }

    private const val ChannelId = "ask_now"
    private const val PrefsName = "ask_now_notifications"
    private const val PrefsResponses = "responses"
}

object AskNowPendingResponseCodec {
    fun append(
        raw: String,
        txnId: String,
        categoryId: String?,
        freeText: String?,
    ): String {
        val line = listOf(txnId, categoryId ?: "", freeText ?: "")
            .joinToString("\t") { encode(it) }
        return (responseLines(raw) + line)
            .joinToString("\n")
    }

    fun decode(raw: String): List<Map<String, String?>> {
        return responseLines(raw)
            .map { line ->
                val parts = line.split("\t")
                val txnId = decodePart(parts.getOrElse(0) { "" })
                val categoryId = decodePart(parts.getOrElse(1) { "" })
                val freeText = decodePart(parts.getOrElse(2) { "" })
                mapOf<String, String?>(
                    "txnId" to txnId,
                    "categoryId" to categoryId.takeIf { it.isNotEmpty() },
                    "freeText" to freeText.takeIf { it.isNotEmpty() },
            )
            }
            .toList()
    }

    fun remove(raw: String, txnIds: Set<String>): String {
        if (txnIds.isEmpty()) return raw
        val remaining = responseLines(raw)
            .filter { line ->
                val txnId = decodePart(line.split("\t").getOrElse(0) { "" })
                txnId !in txnIds
            }
            .toList()
        return if (remaining.isEmpty()) "[]" else remaining.joinToString("\n")
    }

    private fun responseLines(raw: String): Sequence<String> {
        if (raw == "[]") return emptySequence()
        return raw.lineSequence().filter { it.isNotBlank() }
    }

    private fun encode(value: String): String {
        return Base64.getUrlEncoder()
            .withoutPadding()
            .encodeToString(value.toByteArray(StandardCharsets.UTF_8))
    }

    private fun decodePart(value: String): String {
        if (value.isEmpty()) return ""
        return String(Base64.getUrlDecoder().decode(value), StandardCharsets.UTF_8)
    }
}

private const val ExtraTxnId = "txnId"
private const val ExtraCategoryId = "categoryId"
private const val ExtraAction = "action"
private const val RemoteInputKey = "ask_now_text"
