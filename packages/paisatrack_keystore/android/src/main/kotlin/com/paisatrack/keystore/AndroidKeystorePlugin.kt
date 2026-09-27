package com.paisatrack.keystore

import android.content.Context
import android.content.pm.ApplicationInfo
import android.os.Handler
import android.os.Looper
import io.flutter.embedding.engine.plugins.FlutterPlugin
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import io.flutter.plugin.common.MethodChannel.MethodCallHandler
import io.flutter.plugin.common.MethodChannel.Result
import java.util.concurrent.Executors
import java.util.concurrent.ConcurrentHashMap

class AndroidKeystorePlugin : FlutterPlugin, MethodCallHandler {
    private var channel: MethodChannel? = null
    private var context: Context? = null
    private var passphraseStore: DatabasePassphraseStore? = null
    private val ownedLockTokens = ConcurrentHashMap.newKeySet<String>()
    @Volatile private var detached = false

    override fun onAttachedToEngine(binding: FlutterPlugin.FlutterPluginBinding) {
        detached = false
        context = binding.applicationContext
        passphraseStore = DatabasePassphraseStore(binding.applicationContext)
        channel = MethodChannel(binding.binaryMessenger, "com.paisatrack/database_passphrase")
        channel?.setMethodCallHandler(this)
    }

    override fun onDetachedFromEngine(binding: FlutterPlugin.FlutterPluginBinding) {
        detached = true
        ownedLockTokens.toList().forEach(::releaseOwnedLock)
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
                "createGenerationPassphrase" -> {
                    val generationId = call.argument<String>("generationId")
                        ?: throw IllegalArgumentException("Missing generation id")
                    result.success(store.createGenerationPassphrase(generationId))
                }
                "getGenerationPassphrase" -> {
                    val generationId = call.argument<String>("generationId")
                        ?: throw IllegalArgumentException("Missing generation id")
                    result.success(store.getGenerationPassphrase(generationId))
                }
                "deleteGenerationPassphrase" -> {
                    val generationId = call.argument<String>("generationId")
                        ?: throw IllegalArgumentException("Missing generation id")
                    store.deleteGenerationPassphrase(generationId)
                    result.success(null)
                }
                "getGenerationIds" -> result.success(store.getGenerationIds().toList())
                "getActiveGenerationId" -> result.success(store.getActiveGenerationId())
                "getStagingGenerationIds" -> result.success(store.getStagingGenerationIds().toList())
                "activateGeneration" -> {
                    val generationId = call.argument<String>("generationId")
                        ?: throw IllegalArgumentException("Missing generation id")
                    store.activateGeneration(generationId)
                    result.success(null)
                }
                "clearAllGenerationPassphrases" -> {
                    store.clearAllGenerationPassphrases()
                    result.success(null)
                }
                "acquireDatabaseFileLock" -> {
                    val path = call.argument<String>("path")
                        ?: throw IllegalArgumentException("Missing database lock path")
                    lockExecutor.execute {
                        try {
                            val token = DatabaseFileLockManager.acquire(path)
                            ownedLockTokens.add(token)
                            mainHandler.post {
                                if (detached) {
                                    releaseOwnedLock(token)
                                    result.error(
                                        "engine_detached",
                                        "Flutter engine detached while acquiring database lock",
                                        null,
                                    )
                                } else {
                                    result.success(token)
                                }
                            }
                        } catch (error: Exception) {
                            mainHandler.post {
                                result.error("database_lock", error.message, null)
                            }
                        }
                    }
                }
                "releaseDatabaseFileLock" -> {
                    val token = call.argument<String>("token")
                        ?: throw IllegalArgumentException("Missing database lock token")
                    releaseOwnedLock(token)
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

    private fun releaseOwnedLock(token: String) {
        if (ownedLockTokens.remove(token)) {
            DatabaseFileLockManager.release(token)
        }
    }

    companion object {
        private val lockExecutor = Executors.newCachedThreadPool()
        private val mainHandler = Handler(Looper.getMainLooper())
    }
}
