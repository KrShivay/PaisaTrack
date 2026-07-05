package com.paisatrack

import android.content.Context
import android.content.pm.ApplicationInfo
import android.content.pm.PackageManager
import android.os.Build
import android.security.keystore.KeyGenParameterSpec
import android.security.keystore.KeyProperties
import android.util.Base64
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import java.security.KeyStore
import java.security.SecureRandom
import javax.crypto.Cipher
import javax.crypto.KeyGenerator
import javax.crypto.SecretKey
import javax.crypto.spec.GCMParameterSpec

class MainActivity : FlutterActivity() {
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
    }

    private fun isDebuggable(): Boolean {
        return (applicationInfo.flags and ApplicationInfo.FLAG_DEBUGGABLE) != 0
    }
}

private class DatabasePassphraseStore(
    context: Context,
) {
    private val appContext = context.applicationContext
    private val prefs = appContext.getSharedPreferences(PrefsName, Context.MODE_PRIVATE)
    private val keyStore = KeyStore.getInstance(AndroidKeyStore).apply { load(null) }

    fun getOrCreate(): String {
        val encryptedPassphrase = prefs.getString(PassphraseKey, null)
        val initializationVector = prefs.getString(IvKey, null)

        if (encryptedPassphrase != null && initializationVector != null) {
            return decrypt(encryptedPassphrase, initializationVector)
        }

        val passphrase = generatePassphrase()
        val encrypted = encrypt(passphrase)
        prefs.edit()
            .putString(PassphraseKey, encrypted.ciphertext)
            .putString(IvKey, encrypted.initializationVector)
            .apply()
        return passphrase
    }

    fun clearForTests() {
        prefs.edit().clear().apply()
        keyStore.deleteEntry(KeyAlias)
    }

    private fun encrypt(passphrase: String): EncryptedPassphrase {
        val cipher = Cipher.getInstance(AesGcmNoPadding)
        cipher.init(Cipher.ENCRYPT_MODE, getOrCreateKey())
        val ciphertext = cipher.doFinal(passphrase.toByteArray(Charsets.UTF_8))

        return EncryptedPassphrase(
            ciphertext = Base64.encodeToString(ciphertext, Base64.NO_WRAP),
            initializationVector = Base64.encodeToString(cipher.iv, Base64.NO_WRAP),
        )
    }

    private fun decrypt(ciphertext: String, initializationVector: String): String {
        val cipher = Cipher.getInstance(AesGcmNoPadding)
        val iv = Base64.decode(initializationVector, Base64.NO_WRAP)
        cipher.init(Cipher.DECRYPT_MODE, getOrCreateKey(), GCMParameterSpec(GcmTagBits, iv))

        val decrypted = cipher.doFinal(Base64.decode(ciphertext, Base64.NO_WRAP))
        return decrypted.toString(Charsets.UTF_8)
    }

    private fun getOrCreateKey(): SecretKey {
        keyStore.getKey(KeyAlias, null)?.let { return it as SecretKey }

        val keyGenerator = KeyGenerator.getInstance(
            KeyProperties.KEY_ALGORITHM_AES,
            AndroidKeyStore,
        )
        val strongBoxAvailable = Build.VERSION.SDK_INT >= Build.VERSION_CODES.P &&
            appContext.packageManager.hasSystemFeature(PackageManager.FEATURE_STRONGBOX_KEYSTORE)

        return try {
            keyGenerator.init(keySpec(strongBoxAvailable))
            keyGenerator.generateKey()
        } catch (error: Exception) {
            if (!strongBoxAvailable) {
                throw error
            }

            keyGenerator.init(keySpec(strongBoxBacked = false))
            keyGenerator.generateKey()
        }
    }

    private fun keySpec(strongBoxBacked: Boolean): KeyGenParameterSpec {
        val builder = KeyGenParameterSpec.Builder(
            KeyAlias,
            KeyProperties.PURPOSE_ENCRYPT or KeyProperties.PURPOSE_DECRYPT,
        )
            .setBlockModes(KeyProperties.BLOCK_MODE_GCM)
            .setEncryptionPaddings(KeyProperties.ENCRYPTION_PADDING_NONE)
            .setRandomizedEncryptionRequired(true)

        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.P && strongBoxBacked) {
            builder.setIsStrongBoxBacked(true)
        }

        return builder.build()
    }

    private fun generatePassphrase(): String {
        val bytes = ByteArray(PassphraseByteLength)
        SecureRandom().nextBytes(bytes)
        return Base64.encodeToString(bytes, Base64.NO_WRAP)
    }

    private data class EncryptedPassphrase(
        val ciphertext: String,
        val initializationVector: String,
    )

    private companion object {
        const val AndroidKeyStore = "AndroidKeyStore"
        const val AesGcmNoPadding = "AES/GCM/NoPadding"
        const val GcmTagBits = 128
        const val KeyAlias = "paisatrack_database_passphrase"
        const val PassphraseByteLength = 32
        const val PrefsName = "database_passphrase"
        const val PassphraseKey = "passphrase"
        const val IvKey = "iv"
    }
}
