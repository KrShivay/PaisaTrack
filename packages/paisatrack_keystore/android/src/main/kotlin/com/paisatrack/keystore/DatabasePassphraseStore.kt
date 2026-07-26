package com.paisatrack.keystore

import android.content.Context
import android.content.SharedPreferences
import android.content.pm.PackageManager
import android.os.Build
import android.security.keystore.KeyGenParameterSpec
import android.security.keystore.KeyProperties
import java.security.KeyStore
import java.security.SecureRandom
import java.util.Base64
import javax.crypto.Cipher
import javax.crypto.KeyGenerator
import javax.crypto.SecretKey
import javax.crypto.spec.GCMParameterSpec

internal class DatabasePassphraseStore internal constructor(
    private val storage: PassphraseStorage,
    private val cipher: PassphraseCipher,
) {
    constructor(context: Context) : this(
        storage = SharedPreferencesPassphraseStorage(
            context.applicationContext.getSharedPreferences(PrefsName, Context.MODE_PRIVATE),
        ),
        cipher = AndroidKeyStorePassphraseCipher(context.applicationContext),
    )

    fun getOrCreate(): String {
        val encrypted = storage.read()
        if (encrypted != null) {
            return cipher.decrypt(encrypted)
        }

        val passphrase = generatePassphrase()
        storage.write(cipher.encrypt(passphrase))
        return passphrase
    }

    fun clearForTests() {
        clear()
    }

    fun clear() {
        storage.clear()
        cipher.clear()
    }

    private fun generatePassphrase(): String {
        val bytes = ByteArray(PassphraseByteLength)
        SecureRandom().nextBytes(bytes)
        return Base64.getEncoder().encodeToString(bytes)
    }
}

internal data class EncryptedPassphrase(
    val ciphertext: String,
    val initializationVector: String,
)

internal interface PassphraseStorage {
    fun read(): EncryptedPassphrase?
    fun write(passphrase: EncryptedPassphrase)
    fun clear()
}

internal interface PassphraseCipher {
    fun encrypt(passphrase: String): EncryptedPassphrase
    fun decrypt(passphrase: EncryptedPassphrase): String
    fun clear()
}

internal class SharedPreferencesPassphraseStorage(
    private val prefs: SharedPreferences,
) : PassphraseStorage {
    override fun read(): EncryptedPassphrase? {
        val ciphertext = prefs.getString(PassphraseKey, null)
        val initializationVector = prefs.getString(IvKey, null)
        if (ciphertext == null || initializationVector == null) return null

        return EncryptedPassphrase(
            ciphertext = ciphertext,
            initializationVector = initializationVector,
        )
    }

    override fun write(passphrase: EncryptedPassphrase) {
        prefs.edit()
            .putString(PassphraseKey, passphrase.ciphertext)
            .putString(IvKey, passphrase.initializationVector)
            .apply()
    }

    override fun clear() {
        prefs.edit().clear().apply()
    }
}

internal class AndroidKeyStorePassphraseCipher(
    private val appContext: Context,
) : PassphraseCipher {
    private val keyStore = KeyStore.getInstance(AndroidKeyStore).apply { load(null) }

    override fun encrypt(passphrase: String): EncryptedPassphrase {
        val cipher = Cipher.getInstance(AesGcmNoPadding)
        cipher.init(Cipher.ENCRYPT_MODE, getOrCreateKey())
        val ciphertext = cipher.doFinal(passphrase.toByteArray(Charsets.UTF_8))

        return EncryptedPassphrase(
            ciphertext = Base64.getEncoder().encodeToString(ciphertext),
            initializationVector = Base64.getEncoder().encodeToString(cipher.iv),
        )
    }

    override fun decrypt(passphrase: EncryptedPassphrase): String {
        val cipher = Cipher.getInstance(AesGcmNoPadding)
        val iv = Base64.getDecoder().decode(passphrase.initializationVector)
        cipher.init(Cipher.DECRYPT_MODE, getOrCreateKey(), GCMParameterSpec(GcmTagBits, iv))

        val decrypted = cipher.doFinal(Base64.getDecoder().decode(passphrase.ciphertext))
        return decrypted.toString(Charsets.UTF_8)
    }

    override fun clear() {
        keyStore.deleteEntry(KeyAlias)
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
}

private const val AndroidKeyStore = "AndroidKeyStore"
private const val AesGcmNoPadding = "AES/GCM/NoPadding"
private const val GcmTagBits = 128
private const val KeyAlias = "paisatrack_database_passphrase"
private const val PassphraseByteLength = 32
private const val PrefsName = "database_passphrase"
private const val PassphraseKey = "passphrase"
private const val IvKey = "iv"
