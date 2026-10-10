package com.paisatrack

import android.content.Intent
import android.content.pm.ApplicationInfo
import android.util.Log
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import org.json.JSONObject

/** Debug-only identity proof used by the recovery QA wrapper before any app work. */
class RecoveryQaActivity : MainActivity() {
    override fun onCreate(savedInstanceState: android.os.Bundle?) {
        super.onCreate(savedInstanceState)
        if (savedInstanceState == null) {
            runSyntheticProbeIfRequested(intent)
        }
    }

    override fun onNewIntent(intent: Intent) {
        super.onNewIntent(intent)
        setIntent(intent)
        runSyntheticProbeIfRequested(intent)
    }

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            IdentityChannel,
        ).setMethodCallHandler { call, result ->
            if (call.method != "identity") {
                result.notImplemented()
            } else {
                result.success(
                    mapOf(
                        "packageName" to applicationContext.packageName,
                        "applicationId" to BuildConfig.APPLICATION_ID,
                        "buildType" to BuildConfig.BUILD_TYPE,
                        "debuggable" to isDebuggable(),
                        "recoveryQa" to resources.getBoolean(R.bool.recovery_qa_enabled),
                    ),
                )
            }
        }
        MethodChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            SmsIdentityProbeChannel,
        ).setMethodCallHandler { call, result ->
            if (call.method != "runSyntheticProbe") {
                result.notImplemented()
                return@setMethodCallHandler
            }
            if (!hasExpectedRecoveryQaIdentity()) {
                result.error(
                    "qa_identity_mismatch",
                    "Synthetic probe requires the isolated RecoveryQA identity.",
                    null,
                )
                return@setMethodCallHandler
            }
            try {
                result.success(SmsIdentityQaProbe.run(applicationContext))
            } catch (_: Exception) {
                result.error(
                    "synthetic_probe_failed",
                    "Synthetic SMS identity probe did not complete.",
                    null,
                )
            }
        }
    }

    private fun runSyntheticProbeIfRequested(candidate: Intent?) {
        if (candidate?.action != RunSyntheticProbeAction) return
        val target = candidate.component ?: return
        if (target.packageName != ExpectedApplicationId ||
            target.className != RecoveryQaActivity::class.java.name ||
            !hasExpectedRecoveryQaIdentity()
        ) {
            return
        }

        try {
            val result = SmsIdentityQaProbe.run(applicationContext)
            val sentAt = (result["liveTimestampEpochMillis"] as Number).toLong()
            val receivedAt = (result["inboxTimestampEpochMillis"] as Number).toLong()
            val safeMarker = mapOf(
                "acceptedByLiveReceiver" to (result["acceptedByLiveReceiver"] == true),
                "acceptedByInboxReader" to (result["acceptedByInboxReader"] == true),
                "senderMatchesFixture" to (result["senderMatchesFixture"] == true),
                "bodyMatchesFixture" to (result["bodyMatchesFixture"] == true),
                "liveTimestampMatchesPdu" to (result["liveTimestampMatchesPdu"] == true),
                "idsMatch" to (result["idsMatch"] == true),
                "legacyIdPresent" to (result["legacyIdPresent"] == true),
                "legacyReceiptIdMatches" to
                    (result["legacyReceiptIdMatches"] == true),
                "dateSentRequested" to (result["dateSentRequested"] == true),
                "pageHasMore" to (result["pageHasMore"] == true),
                "nextCursorUsesReceivedDate" to
                    (result["nextCursorUsesReceivedDate"] == true),
                "nextCursorIdMatches" to (result["nextCursorIdMatches"] == true),
                "sortOrderUsesReceiptDate" to
                    (result["sortOrderUsesReceiptDate"] == true),
                "timestampDifferenceMillis" to (receivedAt - sentAt),
            )
            Log.i(QaLogTag, "$QaMarker ${JSONObject(safeMarker)}")
        } catch (_: Exception) {
            Log.e(QaLogTag, "SMS_IDENTITY_QA_FAILED")
        }
    }

    private fun hasExpectedRecoveryQaIdentity(): Boolean =
        applicationContext.packageName == ExpectedApplicationId &&
            BuildConfig.APPLICATION_ID == ExpectedApplicationId &&
            BuildConfig.BUILD_TYPE == "debug" &&
            isDebuggable() &&
            resources.getBoolean(R.bool.recovery_qa_enabled)

    private fun isDebuggable(): Boolean =
        applicationInfo.flags and ApplicationInfo.FLAG_DEBUGGABLE != 0

    private companion object {
        const val IdentityChannel = "com.paisatrack/recovery_qa_identity"
        const val SmsIdentityProbeChannel = "com.paisatrack/recovery_qa_sms_identity"
        const val ExpectedApplicationId = "com.paisatrack.recoveryqa"
        const val RunSyntheticProbeAction = "com.paisatrack.recoveryqa.RUN_SMS_IDENTITY_PROBE"
        const val QaLogTag = "PaisaTrackRecoveryQA"
        const val QaMarker = "SMS_IDENTITY_QA_OBSERVED"
    }
}
