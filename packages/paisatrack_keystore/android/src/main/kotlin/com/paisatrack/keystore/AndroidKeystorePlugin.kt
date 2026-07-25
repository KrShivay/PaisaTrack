package com.paisatrack.keystore

import android.content.Context
import android.content.pm.ApplicationInfo
import io.flutter.embedding.engine.plugins.FlutterPlugin
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import io.flutter.plugin.common.MethodChannel.MethodCallHandler
import io.flutter.plugin.common.MethodChannel.Result

class AndroidKeystorePlugin : FlutterPlugin, MethodCallHandler {
    private var channel: MethodChannel? = null
    private var context: Context? = null
    private var passphraseStore: DatabasePassphraseStore? = null

    override fun onAttachedToEngine(binding: FlutterPlugin.FlutterPluginBinding) {
        context = binding.applicationContext
        passphraseStore = DatabasePassphraseStore(binding.applicationContext)
        channel = MethodChannel(binding.binaryMessenger, "com.paisatrack/database_passphrase")
        channel?.setMethodCallHandler(this)
    }

    override fun onDetachedFromEngine(binding: FlutterPlugin.FlutterPluginBinding) {
        channel?.setMethodCallHandler(null)
        channel = null
        context = null
        passphraseStore = null
    }

    override fun onMethodCall(call: MethodCall, result: Result) {
        val store = passphraseStore ?: run {
            result.error("uninitialized", "PassphraseStore is not initialized", null)
            return
        }

        try {
            when (call.method) {
                "getPassphrase" -> result.success(store.getOrCreate())
                "clearPassphrase" -> {
                    store.clear()
                    result.success(null)
                }
                "debugResetForTests" -> {
                    val isDebuggable = context?.let {
                        (it.applicationInfo.flags and ApplicationInfo.FLAG_DEBUGGABLE) != 0
                    } ?: false

                    if (!isDebuggable) {
                        result.error(
                            "unavailable",
                            "Passphrase reset is only available in debug builds.",
                            null,
                        )
                        return
                    }

                    store.clearForTests()
                    result.success(null)
                }
                else -> result.notImplemented()
            }
        } catch (error: Exception) {
            result.error("database_passphrase", error.message, null)
        }
    }
}
