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
    private val recoveryStoreFactory: ((String) -> DatabasePassphraseStore)? = null,
    private val recoveryState: SharedPreferences? = null,
) {
    constructor(context: Context) : this(
        storage = SharedPreferencesPassphraseStorage(
            context.applicationContext.getSharedPreferences(PrefsName, Context.MODE_PRIVATE),
        ),
        cipher = AndroidKeyStorePassphraseCipher(context.applicationContext, KeyAlias),
        recoveryState = context.applicationContext.getSharedPreferences(
            RecoveryStatePrefsName,
            Context.MODE_PRIVATE,
        ),
        recoveryStoreFactory = { generationId ->
            val appContext = context.applicationContext
            DatabasePassphraseStore(
                storage = SharedPreferencesPassphraseStorage(
                    appContext.getSharedPreferences(
                        "$RecoveryPrefsName.$generationId",
                        Context.MODE_PRIVATE,
                    ),
                ),
                cipher = AndroidKeyStorePassphraseCipher(
                    appContext,
                    "$RecoveryKeyAlias.$generationId",
                ),
            )
        },
    )

    fun getOrCreate(): String = synchronized(lock) {
        val encrypted = storage.read()
        if (encrypted != null) {
            return cipher.decrypt(encrypted)
        }

        val passphrase = generatePassphrase()
        val encryptedPassphrase = cipher.encrypt(passphrase)
        storage.write(encryptedPassphrase)

        val reread = storage.read()
            ?: throw IllegalStateException("Passphrase storage read failed immediately after write")
        val verifiedPassphrase = cipher.decrypt(reread)
        check(verifiedPassphrase == passphrase) { "Passphrase verification mismatch after write" }
        return verifiedPassphrase
    }

    private fun getExisting(): String = synchronized(lock) {
        val encrypted = storage.read()
            ?: throw IllegalStateException("Database generation key is missing")
        cipher.decrypt(encrypted)
    }

    fun clearForTests() {
        clear()
    }

    fun createGenerationPassphrase(generationId: String): String {
        validateGenerationId(generationId)
        val store = recoveryStoreFactory?.invoke(generationId)
            ?: throw IllegalStateException("Recovery key slots are unavailable")
        registerGeneration(generationId)
        updateStagingGenerationIds { ids -> ids + generationId }
        return store.getOrCreate()
    }

    fun getGenerationPassphrase(generationId: String): String {
        validateGenerationId(generationId)
        val store = recoveryStoreFactory?.invoke(generationId)
            ?: throw IllegalStateException("Recovery key slots are unavailable")
        return store.getExisting()
    }

    fun deleteGenerationPassphrase(generationId: String) {
        validateGenerationId(generationId)
        check(getActiveGenerationId() != generationId) {
            "Cannot delete the active database generation key"
        }
        val store = recoveryStoreFactory?.invoke(generationId)
            ?: throw IllegalStateException("Recovery key slots are unavailable")
        store.clear()
        updateGenerationIds { ids -> ids - generationId }
        updateStagingGenerationIds { ids -> ids - generationId }
    }

    fun getActiveGenerationId(): String? {
        val generationId = recoveryState?.getString(ActiveGenerationKey, null)
            ?: return null
        validateGenerationId(generationId)
        return generationId
    }

    fun getGenerationIds(): Set<String> {
        val ids = recoveryState?.getStringSet(RecoveryGenerationIdsKey, emptySet())
            ?: return emptySet()
        ids.forEach { validateGenerationId(it) }
        return ids.toSet()
    }

    fun getStagingGenerationIds(): Set<String> {
        val ids = recoveryState?.getStringSet(StagingGenerationIdsKey, emptySet())
            ?: return emptySet()
        ids.forEach { validateGenerationId(it) }
        return ids.toSet()
    }

    fun activateGeneration(generationId: String) {
        validateGenerationId(generationId)
        getGenerationPassphrase(generationId)
        val state = recoveryState
            ?: throw IllegalStateException("Recovery key slots are unavailable")
        val stagingIds = getStagingGenerationIds() - generationId
        val editor = state.edit().putString(ActiveGenerationKey, generationId)
        if (stagingIds.isEmpty()) {
            editor.remove(StagingGenerationIdsKey)
        } else {
            editor.putStringSet(StagingGenerationIdsKey, stagingIds)
        }
        check(editor.commit()) {
            "Failed to activate database generation"
        }
    }

    fun clearAllGenerationPassphrases() {
        val state = recoveryState
            ?: throw IllegalStateException("Recovery key slots are unavailable")
        val ids = state.getStringSet(RecoveryGenerationIdsKey, emptySet()).orEmpty().toSet()
        // Unpublish the active generation before deleting any of its key
        // material. If this durable commit fails, every key remains usable and
        // the previous selector is still intact.
        check(state.edit().remove(ActiveGenerationKey).commit()) {
            "Failed to deactivate database generation keys"
        }
        ids.forEach { generationId ->
            if (GenerationIdPattern.matches(generationId)) {
                recoveryStoreFactory?.invoke(generationId)?.clear()
            }
        }
        check(
            state.edit()
                .remove(RecoveryGenerationIdsKey)
                .remove(StagingGenerationIdsKey)
                .commit(),
        ) { "Failed to clear database generation keys" }
    }

    private fun registerGeneration(generationId: String) {
        updateGenerationIds { ids -> ids + generationId }
    }

    private fun updateStagingGenerationIds(transform: (Set<String>) -> Set<String>) {
        val state = recoveryState
            ?: throw IllegalStateException("Recovery key slots are unavailable")
        val ids = getStagingGenerationIds()
        val updated = transform(ids)
        val editor = state.edit()
        if (updated.isEmpty()) {
            editor.remove(StagingGenerationIdsKey)
        } else {
            editor.putStringSet(StagingGenerationIdsKey, updated)
        }
        check(editor.commit()) { "Failed to persist staging generation index" }
    }

    private fun updateGenerationIds(transform: (Set<String>) -> Set<String>) {
        val state = recoveryState
            ?: throw IllegalStateException("Recovery key slots are unavailable")
        val ids = state.getStringSet(RecoveryGenerationIdsKey, emptySet()).orEmpty()
        check(state.edit().putStringSet(RecoveryGenerationIdsKey, transform(ids)).commit()) {
            "Failed to persist database generation index"
        }
    }

    fun clear() = synchronized(lock) {
        storage.clear()
        cipher.clear()
    }

    private fun generatePassphrase(): String {
        val bytes = ByteArray(PassphraseByteLength)
        SecureRandom().nextBytes(bytes)
        return Base64.getEncoder().encodeToString(bytes)
    }

    private fun validateGenerationId(generationId: String) {
        require(GenerationIdPattern.matches(generationId)) {
            "Invalid database generation id"
        }
    }

    companion object {
        private val lock = Any()
        private val GenerationIdPattern =
            Regex("^[0-9a-f]{8}-[0-9a-f]{4}-4[0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$")
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
        val success = prefs.edit()
            .putString(PassphraseKey, passphrase.ciphertext)
            .putString(IvKey, passphrase.initializationVector)
            .commit()
        if (!success) {
            throw IllegalStateException("Failed to commit database passphrase to SharedPreferences")
        }
    }

    override fun clear() {
        prefs.edit().clear().commit()
    }
}

internal class AndroidKeyStorePassphraseCipher(
    private val appContext: Context,
    private val keyAlias: String,
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
        keyStore.deleteEntry(keyAlias)
    }

    private fun getOrCreateKey(): SecretKey {
        keyStore.getKey(keyAlias, null)?.let { return it as SecretKey }

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
            keyAlias,
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
private const val RecoveryKeyAlias = "paisatrack_database_recovery"
private const val RecoveryPrefsName = "database_passphrase_recovery"
private const val RecoveryStatePrefsName = "database_recovery_state"
private const val RecoveryGenerationIdsKey = "generation_ids"
private const val StagingGenerationIdsKey = "staging_generation_ids"
private const val ActiveGenerationKey = "active_generation"
private const val PassphraseByteLength = 32
private const val PrefsName = "database_passphrase"
private const val PassphraseKey = "passphrase"
private const val IvKey = "iv"
