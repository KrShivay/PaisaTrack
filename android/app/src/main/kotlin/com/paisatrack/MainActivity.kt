package com.paisatrack

import android.Manifest
import android.app.Activity
import android.content.Context
import android.content.Intent
import android.content.pm.ApplicationInfo
import android.content.pm.PackageManager
import android.os.Build
import android.os.Handler
import android.os.Looper
import androidx.core.app.ActivityCompat
import androidx.core.content.ContextCompat
import com.paisatrack.capture.CapturedSms
import com.paisatrack.capture.CapturedSmsSink
import com.paisatrack.capture.SmsInboxReader
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.EventChannel
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import java.util.concurrent.ConcurrentLinkedQueue
import java.util.concurrent.ExecutorService
import java.util.concurrent.Executors

class MainActivity : FlutterActivity() {
    private var pendingPermissionResult: MethodChannel.Result? = null
    private var notificationPermissionRequestInFlight = false
    private val pendingAskNowRequests = mutableListOf<PendingAskNowRequest>()
    private val capturedSmsBridge = CapturedSmsEventChannelBridge()
    private val mainHandler = Handler(Looper.getMainLooper())
    private val backfillExecutor: ExecutorService = Executors.newSingleThreadExecutor()
    private var pendingDocumentRequest: PendingDocumentRequest? = null

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)

        val passphraseStore = DatabasePassphraseStore(applicationContext)
        MethodChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            "com.paisatrack/database_passphrase",
        ).setMethodCallHandler { call, result ->
            try {
                when (call.method) {
                    "getPassphrase" -> result.success(passphraseStore.getOrCreate())
                    "clearPassphrase" -> {
                        passphraseStore.clear()
                        result.success(null)
                    }
                    "debugResetForTests" -> {
                        if (!isDebuggable()) {
                            result.error(
                                "unavailable",
                                "Passphrase reset is only available in debug builds.",
                                null,
                            )
                            return@setMethodCallHandler
                        }

                        passphraseStore.clearForTests()
                        result.success(null)
                    }
                    else -> result.notImplemented()
                }
            } catch (error: Exception) {
                result.error("database_passphrase", error.message, null)
            }
        }

        MethodChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            "com.paisatrack/sms_permissions",
        ).setMethodCallHandler { call, result ->
            when (call.method) {
                "status" -> result.success(currentSmsPermissionStatus())
                "request" -> requestSmsPermissions(result)
                else -> result.notImplemented()
            }
        }

        EventChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            "com.paisatrack/sms_events",
        ).setStreamHandler(capturedSmsBridge)
        CapturedSmsSink.current = capturedSmsBridge

        val inboxReader = SmsInboxReader(applicationContext)
        val backfillState = BackfillStateStore(applicationContext)
        MethodChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            "com.paisatrack/sms_backfill",
        ).setMethodCallHandler { call, result ->
            when (call.method) {
                "readInbox" -> readInbox(inboxReader, call, result)
                "isBackfillComplete" -> result.success(backfillState.isComplete())
                "markBackfillComplete" -> {
                    backfillState.markComplete()
                    result.success(null)
                }
                else -> result.notImplemented()
            }
        }

        MethodChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            "com.paisatrack/ask_now",
        ).setMethodCallHandler { call, result ->
            when (call.method) {
                "show" -> {
                    @Suppress("UNCHECKED_CAST")
                    showAskNowNotification(
                        call.arguments as? Map<*, *> ?: emptyMap<Any, Any>(),
                        result,
                    )
                }
                "takePendingResponses" -> {
                    result.success(AskNowNotifications.takePendingResponses(applicationContext))
                }
                "ackPendingResponses" -> {
                    val txnIds = (call.arguments as? List<*>)?.mapNotNull { it as? String }
                        ?: emptyList()
                    AskNowNotifications.ackPendingResponses(applicationContext, txnIds)
                    result.success(null)
                }
                else -> result.notImplemented()
            }
        }

        MethodChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            "com.paisatrack/documents",
        ).setMethodCallHandler { call, result ->
            when (call.method) {
                "saveDocument" -> saveDocument(call, result)
                "openDocument" -> openDocument(call, result)
                else -> result.notImplemented()
            }
        }
    }

    override fun cleanUpFlutterEngine(flutterEngine: FlutterEngine) {
        pendingDocumentRequest?.result?.error(
            "engine_detached",
            "Document picker was interrupted.",
            null,
        )
        pendingDocumentRequest = null
        if (CapturedSmsSink.current === capturedSmsBridge) {
            CapturedSmsSink.current = CapturedSmsSink { }
        }
        capturedSmsBridge.detach()
        backfillExecutor.shutdown()
        super.cleanUpFlutterEngine(flutterEngine)
    }

    private fun saveDocument(call: MethodCall, result: MethodChannel.Result) {
        val suggestedName = call.argument<String>("suggestedName")
        val mimeType = call.argument<String>("mimeType")
        val bytes = call.argument<ByteArray>("bytes")
        if (suggestedName == null || mimeType == null || bytes == null) {
            result.error("invalid_arguments", "Missing document save arguments.", null)
            return
        }
        if (!reserveDocumentRequest(PendingDocumentRequest.Save(result, bytes))) return

        val intent = Intent(Intent.ACTION_CREATE_DOCUMENT).apply {
            addCategory(Intent.CATEGORY_OPENABLE)
            type = mimeType
            putExtra(Intent.EXTRA_TITLE, suggestedName)
        }
        launchDocumentPicker(intent, SaveDocumentRequestCode, result)
    }

    private fun openDocument(call: MethodCall, result: MethodChannel.Result) {
        val mimeType = call.argument<String>("mimeType")
        if (mimeType == null) {
            result.error("invalid_arguments", "Missing document MIME type.", null)
            return
        }
        if (!reserveDocumentRequest(PendingDocumentRequest.Open(result))) return

        val intent = Intent(Intent.ACTION_OPEN_DOCUMENT).apply {
            addCategory(Intent.CATEGORY_OPENABLE)
            type = mimeType
        }
        launchDocumentPicker(intent, OpenDocumentRequestCode, result)
    }

    private fun reserveDocumentRequest(request: PendingDocumentRequest): Boolean {
        if (pendingDocumentRequest != null) {
            request.result.error("in_progress", "A document picker is already open.", null)
            return false
        }
        pendingDocumentRequest = request
        return true
    }

    private fun launchDocumentPicker(
        intent: Intent,
        requestCode: Int,
        result: MethodChannel.Result,
    ) {
        try {
            startActivityForResult(intent, requestCode)
        } catch (error: Exception) {
            pendingDocumentRequest = null
            result.error("document_picker", error.message, null)
        }
    }

    @Deprecated("Uses the stable activity-result bridge required by FlutterActivity.")
    override fun onActivityResult(requestCode: Int, resultCode: Int, data: Intent?) {
        super.onActivityResult(requestCode, resultCode, data)
        if (requestCode != SaveDocumentRequestCode && requestCode != OpenDocumentRequestCode) {
            return
        }

        val request = pendingDocumentRequest ?: return
        pendingDocumentRequest = null
        if (resultCode != Activity.RESULT_OK || data?.data == null) {
            request.result.success(null)
            return
        }

        try {
            val uri = data.data!!
            when (request) {
                is PendingDocumentRequest.Save -> {
                    contentResolver.openOutputStream(uri, "w").use { stream ->
                        checkNotNull(stream) { "Could not open the selected document." }
                        stream.write(request.bytes)
                        stream.flush()
                    }
                    request.result.success(true)
                }
                is PendingDocumentRequest.Open -> {
                    val bytes = contentResolver.openInputStream(uri).use { stream ->
                        checkNotNull(stream) { "Could not open the selected document." }
                        stream.readBytes()
                    }
                    request.result.success(bytes)
                }
            }
        } catch (error: Exception) {
            request.result.error("document_io", error.message, null)
        }
    }

    private fun readInbox(
        inboxReader: SmsInboxReader,
        call: MethodCall,
        result: MethodChannel.Result,
    ) {
        if (currentSmsPermissionStatus() != STATUS_GRANTED) {
            result.error(
                "permission_denied",
                "READ_SMS permission is required to read the inbox.",
                null,
            )
            return
        }

        val sinceEpochMillis = (call.argument<Number>("sinceEpochMillis"))?.toLong() ?: 0L
        // Query the content provider off the main thread; the inbox can be large.
        backfillExecutor.execute {
            val response = try {
                Result.success(inboxReader.readSince(sinceEpochMillis))
            } catch (error: Exception) {
                Result.failure(error)
            }
            mainHandler.post {
                response.fold(
                    onSuccess = { result.success(it) },
                    // Never surface message bodies in the error payload.
                    onFailure = { result.error("sms_backfill", it.message, null) },
                )
            }
        }
    }

    private fun requestSmsPermissions(result: MethodChannel.Result) {
        if (currentSmsPermissionStatus() == STATUS_GRANTED) {
            result.success(STATUS_GRANTED)
            return
        }
        if (pendingPermissionResult != null) {
            result.error(
                "in_progress",
                "An SMS permission request is already in progress.",
                null,
            )
            return
        }

        pendingPermissionResult = result
        ActivityCompat.requestPermissions(this, smsPermissions(), SmsPermissionRequestCode)
    }

    override fun onRequestPermissionsResult(
        requestCode: Int,
        permissions: Array<out String>,
        grantResults: IntArray,
    ) {
        super.onRequestPermissionsResult(requestCode, permissions, grantResults)
        if (requestCode == NotificationPermissionRequestCode) {
            notificationPermissionRequestInFlight = false
            val requests = pendingAskNowRequests.toList()
            pendingAskNowRequests.clear()
            val granted = grantResults.isNotEmpty() &&
                grantResults.all { it == PackageManager.PERMISSION_GRANTED }
            if (!granted) {
                requests.forEach { request -> request.result.success(false) }
                return
            }

            val displayedTxnIds = mutableSetOf<Any?>()
            requests.forEach { request ->
                val txnId = request.payload["txnId"]
                if (displayedTxnIds.add(txnId)) {
                    AskNowNotifications.show(applicationContext, request.payload)
                }
                request.result.success(true)
            }
            return
        }
        if (requestCode != SmsPermissionRequestCode) {
            return
        }

        val result = pendingPermissionResult ?: return
        pendingPermissionResult = null

        val granted = grantResults.isNotEmpty() &&
            grantResults.all { it == PackageManager.PERMISSION_GRANTED }
        val status = when {
            granted -> STATUS_GRANTED
            // No rationale after a denial means "Don't ask again" was selected.
            smsPermissions().any { ActivityCompat.shouldShowRequestPermissionRationale(this, it) } ->
                STATUS_DENIED
            else -> STATUS_PERMANENTLY_DENIED
        }
        result.success(status)
    }

    private fun currentSmsPermissionStatus(): String {
        val allGranted = smsPermissions().all { permission ->
            ContextCompat.checkSelfPermission(this, permission) ==
                PackageManager.PERMISSION_GRANTED
        }
        return if (allGranted) STATUS_GRANTED else STATUS_DENIED
    }

    private fun smsPermissions(): Array<String> {
        return arrayOf(
            Manifest.permission.RECEIVE_SMS,
            Manifest.permission.READ_SMS,
        )
    }

    private fun showAskNowNotification(payload: Map<*, *>, result: MethodChannel.Result) {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU &&
            ContextCompat.checkSelfPermission(
                this,
                Manifest.permission.POST_NOTIFICATIONS,
            ) != PackageManager.PERMISSION_GRANTED
        ) {
            pendingAskNowRequests.add(PendingAskNowRequest(payload, result))
            if (!notificationPermissionRequestInFlight) {
                notificationPermissionRequestInFlight = true
                ActivityCompat.requestPermissions(
                    this,
                    arrayOf(Manifest.permission.POST_NOTIFICATIONS),
                    NotificationPermissionRequestCode,
                )
            }
            return
        }

        AskNowNotifications.show(applicationContext, payload)
        result.success(true)
    }

    private fun isDebuggable(): Boolean {
        return (applicationInfo.flags and ApplicationInfo.FLAG_DEBUGGABLE) != 0
    }

    private companion object {
        const val SmsPermissionRequestCode = 4201
        const val NotificationPermissionRequestCode = 4202
        const val SaveDocumentRequestCode = 4301
        const val OpenDocumentRequestCode = 4302
        const val STATUS_GRANTED = "granted"
        const val STATUS_DENIED = "denied"
        const val STATUS_PERMANENTLY_DENIED = "permanentlyDenied"
    }
}

private sealed class PendingDocumentRequest(open val result: MethodChannel.Result) {
    data class Save(
        override val result: MethodChannel.Result,
        val bytes: ByteArray,
    ) : PendingDocumentRequest(result)

    data class Open(
        override val result: MethodChannel.Result,
    ) : PendingDocumentRequest(result)
}

private data class PendingAskNowRequest(
    val payload: Map<*, *>,
    val result: MethodChannel.Result,
)

private class CapturedSmsEventChannelBridge : EventChannel.StreamHandler, CapturedSmsSink {
    private val mainHandler = Handler(Looper.getMainLooper())
    private val pendingEvents = ConcurrentLinkedQueue<Map<String, Any>>()

    @Volatile
    private var eventSink: EventChannel.EventSink? = null

    override fun onListen(arguments: Any?, events: EventChannel.EventSink) {
        eventSink = events
        drainPendingEvents()
    }

    override fun onCancel(arguments: Any?) {
        eventSink = null
    }

    override fun accept(sms: CapturedSms) {
        val payload = mapOf(
            "id" to sms.id,
            "sender" to sms.sender,
            "body" to sms.body,
            "receivedAtEpochMillis" to sms.receivedAtEpochMillis,
        )
        if (eventSink == null) {
            pendingEvents.add(payload)
            return
        }

        emit(payload)
    }

    fun detach() {
        eventSink = null
        pendingEvents.clear()
    }

    private fun drainPendingEvents() {
        while (true) {
            val payload = pendingEvents.poll() ?: return
            emit(payload)
        }
    }

    private fun emit(payload: Map<String, Any>) {
        mainHandler.post {
            val sink = eventSink
            if (sink == null) {
                pendingEvents.add(payload)
                return@post
            }

            sink.success(payload)
        }
    }
}

/**
 * Persists whether the one-time historical inbox backfill (T-023) has run, so
 * it fires only on the genuine first permission grant and never re-scans on
 * later launches (which would duplicate live-captured messages).
 */
private class BackfillStateStore(context: Context) {
    private val prefs = context.applicationContext
        .getSharedPreferences(PrefsName, Context.MODE_PRIVATE)

    fun isComplete(): Boolean = prefs.getBoolean(CompleteKey, false)

    fun markComplete() {
        prefs.edit().putBoolean(CompleteKey, true).apply()
    }

    private companion object {
        const val PrefsName = "sms_backfill_state"
        const val CompleteKey = "backfill_complete"
    }
}
