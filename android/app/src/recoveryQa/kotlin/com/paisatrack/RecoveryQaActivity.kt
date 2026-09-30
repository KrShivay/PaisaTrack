package com.paisatrack

import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

/** Debug-only identity proof used by the recovery QA wrapper before any app work. */
class RecoveryQaActivity : MainActivity() {
    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            IdentityChannel,
        ).setMethodCallHandler { call, result ->
            if (call.method != "identity") {
                result.notImplemented()
            } else {
                val debuggable =
                    applicationInfo.flags and android.content.pm.ApplicationInfo.FLAG_DEBUGGABLE != 0
                result.success(
                    mapOf(
                        "packageName" to applicationContext.packageName,
                        "applicationId" to BuildConfig.APPLICATION_ID,
                        "buildType" to BuildConfig.BUILD_TYPE,
                        "debuggable" to debuggable,
                        "recoveryQa" to resources.getBoolean(R.bool.recovery_qa_enabled),
                    ),
                )
            }
        }
    }

    private companion object {
        const val IdentityChannel = "com.paisatrack/recovery_qa_identity"
    }
}
