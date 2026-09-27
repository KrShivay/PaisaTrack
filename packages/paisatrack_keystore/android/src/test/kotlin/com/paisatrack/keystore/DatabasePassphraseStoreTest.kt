package com.paisatrack.keystore

import android.content.SharedPreferences
import org.junit.Assert.assertEquals
import org.junit.Assert.assertNotEquals
import org.junit.Assert.assertTrue
import org.junit.Test

class DatabasePassphraseStoreTest {
    @Test
    fun reusesPersistedEncryptedPassphrase() {
        val storage = FakePassphraseStorage()
        val cipher = FakePassphraseCipher()
        val store = DatabasePassphraseStore(storage, cipher)

        val first = store.getOrCreate()
        val second = store.getOrCreate()

        assertEquals(first, second)
        assertTrue(storage.lastWritten?.ciphertext?.startsWith("encrypted:") == true)
        assertNotEquals(first, storage.lastWritten?.ciphertext)
        assertEquals(1, cipher.encryptCalls)
        // getOrCreate decrypts once to verify the new write and again on reuse.
        assertEquals(2, cipher.decryptCalls)
    }

    @Test
    fun clearForTestsClearsStorageAndCipher() {
        val storage = FakePassphraseStorage()
        val cipher = FakePassphraseCipher()
        val store = DatabasePassphraseStore(storage, cipher)

        val first = store.getOrCreate()
        store.clearForTests()
        val second = store.getOrCreate()

        assertEquals(1, storage.clearCalls)
        assertTrue(cipher.cleared)
        assertNotEquals(first, second)
    }

    @Test
    fun corruptedPersistedPassphraseFailsClosed() {
        val storage = FakePassphraseStorage(
            EncryptedPassphrase(
                ciphertext = "not-decryptable",
                initializationVector = "iv",
            ),
        )
        val cipher = FakePassphraseCipher()
        val store = DatabasePassphraseStore(storage, cipher)

        val error = runCatching { store.getOrCreate() }.exceptionOrNull()

        assertTrue(error is IllegalStateException)
        assertEquals("not-decryptable", storage.lastWritten?.ciphertext)
        assertEquals(0, cipher.encryptCalls)
    }

    @Test
    fun generationKeyUsesAnIndependentSlotAndLeavesLegacyWrapperUntouched() {
        val legacyStorage = FakePassphraseStorage(
            EncryptedPassphrase("legacy-wrapper", "legacy-iv"),
        )
        val legacyCipher = FakePassphraseCipher()
        val state = FakeSharedPreferences()
        val generationStores = mutableMapOf<String, FakePassphraseStorage>()
        val generationCiphers = mutableMapOf<String, FakePassphraseCipher>()
        val store = DatabasePassphraseStore(
            storage = legacyStorage,
            cipher = legacyCipher,
            recoveryState = state,
            recoveryStoreFactory = { id ->
                val storage = generationStores.getOrPut(id) { FakePassphraseStorage() }
                val cipher = generationCiphers.getOrPut(id) { FakePassphraseCipher() }
                DatabasePassphraseStore(storage, cipher)
            },
        )
        val id = validGenerationId

        val created = store.createGenerationPassphrase(id)
        val reopened = store.getGenerationPassphrase(id)

        assertEquals(created, reopened)
        assertEquals("legacy-wrapper", legacyStorage.lastWritten?.ciphertext)
        assertEquals(0, legacyStorage.clearCalls)
        assertEquals(0, legacyCipher.clearCalls)
        assertEquals(setOf(id), store.getStagingGenerationIds())
    }

    @Test
    fun missingGenerationKeyDoesNotCreateReplacement() {
        val state = FakeSharedPreferences()
        val childStorage = FakePassphraseStorage()
        val childCipher = FakePassphraseCipher()
        val store = DatabasePassphraseStore(
            storage = FakePassphraseStorage(),
            cipher = FakePassphraseCipher(),
            recoveryState = state,
            recoveryStoreFactory = { DatabasePassphraseStore(childStorage, childCipher) },
        )

        val error = runCatching { store.getGenerationPassphrase(validGenerationId) }
            .exceptionOrNull()

        assertTrue(error is IllegalStateException)
        assertEquals(null, childStorage.lastWritten)
        assertEquals(0, childCipher.encryptCalls)
    }

    @Test
    fun activationCommitsPointerAndStagingRemovalAtomically() {
        val state = FakeSharedPreferences()
        val childStorage = FakePassphraseStorage()
        val childCipher = FakePassphraseCipher()
        val store = DatabasePassphraseStore(
            storage = FakePassphraseStorage(),
            cipher = FakePassphraseCipher(),
            recoveryState = state,
            recoveryStoreFactory = { DatabasePassphraseStore(childStorage, childCipher) },
        )
        val id = validGenerationId
        store.createGenerationPassphrase(id)

        state.failNextCommit = true
        val error = runCatching { store.activateGeneration(id) }.exceptionOrNull()
        assertTrue(error is IllegalStateException)
        assertEquals(null, store.getActiveGenerationId())
        assertEquals(setOf(id), store.getStagingGenerationIds())

        store.activateGeneration(id)
        assertEquals(id, store.getActiveGenerationId())
        assertEquals(emptySet<String>(), store.getStagingGenerationIds())
    }

    @Test
    fun clearAllRemovesEveryGenerationKeyAndSelectorButKeepsLegacyUntilExplicitClear() {
        val legacyStorage = FakePassphraseStorage(
            EncryptedPassphrase("legacy-wrapper", "legacy-iv"),
        )
        val legacyCipher = FakePassphraseCipher()
        val state = FakeSharedPreferences()
        val generationStores = mutableMapOf<String, FakePassphraseStorage>()
        val generationCiphers = mutableMapOf<String, FakePassphraseCipher>()
        val store = DatabasePassphraseStore(
            storage = legacyStorage,
            cipher = legacyCipher,
            recoveryState = state,
            recoveryStoreFactory = { id ->
                val storage = generationStores.getOrPut(id) { FakePassphraseStorage() }
                val cipher = generationCiphers.getOrPut(id) { FakePassphraseCipher() }
                DatabasePassphraseStore(storage, cipher)
            },
        )
        val id = validGenerationId
        store.createGenerationPassphrase(id)
        store.activateGeneration(id)

        store.clearAllGenerationPassphrases()

        assertEquals(null, store.getActiveGenerationId())
        assertEquals(emptySet<String>(), store.getStagingGenerationIds())
        assertEquals(null, generationStores.getValue(id).lastWritten)
        assertEquals(1, generationCiphers.getValue(id).clearCalls)
        assertEquals("legacy-wrapper", legacyStorage.lastWritten?.ciphertext)
        assertEquals(0, legacyStorage.clearCalls)
        assertEquals(0, legacyCipher.clearCalls)
    }

    @Test
    fun failedResetSelectorCommitPreservesActiveGenerationKey() {
        val state = FakeSharedPreferences()
        val childStorage = FakePassphraseStorage()
        val childCipher = FakePassphraseCipher()
        val store = DatabasePassphraseStore(
            storage = FakePassphraseStorage(),
            cipher = FakePassphraseCipher(),
            recoveryState = state,
            recoveryStoreFactory = { DatabasePassphraseStore(childStorage, childCipher) },
        )
        val id = validGenerationId
        val originalKey = store.createGenerationPassphrase(id)
        store.activateGeneration(id)

        state.failNextCommit = true
        val error = runCatching { store.clearAllGenerationPassphrases() }.exceptionOrNull()

        assertTrue(error is IllegalStateException)
        assertEquals(id, store.getActiveGenerationId())
        assertEquals(originalKey, store.getGenerationPassphrase(id))
        assertEquals(0, childStorage.clearCalls)
        assertEquals(0, childCipher.clearCalls)

        store.clearAllGenerationPassphrases()
        assertEquals(null, store.getActiveGenerationId())
    }

    @Test
    fun generationOperationsRejectInvalidIdentifiers() {
        val store = DatabasePassphraseStore(
            storage = FakePassphraseStorage(),
            cipher = FakePassphraseCipher(),
            recoveryState = FakeSharedPreferences(),
            recoveryStoreFactory = { DatabasePassphraseStore(FakePassphraseStorage(), FakePassphraseCipher()) },
        )

        assertTrue(runCatching { store.createGenerationPassphrase("../database") }.exceptionOrNull() is IllegalArgumentException)
        assertTrue(runCatching { store.activateGeneration("../database") }.exceptionOrNull() is IllegalArgumentException)
    }
}

private const val validGenerationId = "d92f2cb4-c682-4e38-95e4-7c9a88e43f1a"

private class FakePassphraseStorage(
    initialValue: EncryptedPassphrase? = null,
) : PassphraseStorage {
    var lastWritten: EncryptedPassphrase? = initialValue
        private set
    var clearCalls = 0
        private set

    override fun read(): EncryptedPassphrase? = lastWritten

    override fun write(passphrase: EncryptedPassphrase) {
        lastWritten = passphrase
    }

    override fun clear() {
        clearCalls += 1
        lastWritten = null
    }
}

private class FakePassphraseCipher : PassphraseCipher {
    var encryptCalls = 0
        private set
    var decryptCalls = 0
        private set
    var cleared = false
        private set
    var clearCalls = 0
        private set

    override fun encrypt(passphrase: String): EncryptedPassphrase {
        encryptCalls += 1
        return EncryptedPassphrase(
            ciphertext = "encrypted:$passphrase",
            initializationVector = "iv",
        )
    }

    override fun decrypt(passphrase: EncryptedPassphrase): String {
        decryptCalls += 1
        if (!passphrase.ciphertext.startsWith("encrypted:")) {
            throw IllegalStateException("Stored passphrase could not be decrypted.")
        }

        return passphrase.ciphertext.removePrefix("encrypted:")
    }

    override fun clear() {
      cleared = true
      clearCalls += 1
    }
}

private class FakeSharedPreferences : SharedPreferences {
    private val values = mutableMapOf<String, Any>()
    var failNextCommit = false

    override fun getAll(): MutableMap<String, *> = values.toMutableMap()
    override fun getString(key: String, defValue: String?): String? =
        values[key] as? String ?: defValue
    @Suppress("UNCHECKED_CAST")
    override fun getStringSet(key: String, defValues: MutableSet<String>?): MutableSet<String>? =
        (values[key] as? Set<String>)?.toMutableSet() ?: defValues
    override fun getInt(key: String, defValue: Int): Int = values[key] as? Int ?: defValue
    override fun getLong(key: String, defValue: Long): Long = values[key] as? Long ?: defValue
    override fun getFloat(key: String, defValue: Float): Float = values[key] as? Float ?: defValue
    override fun getBoolean(key: String, defValue: Boolean): Boolean = values[key] as? Boolean ?: defValue
    override fun contains(key: String): Boolean = values.containsKey(key)
    override fun edit(): SharedPreferences.Editor = Editor()
    override fun registerOnSharedPreferenceChangeListener(listener: SharedPreferences.OnSharedPreferenceChangeListener?) = Unit
    override fun unregisterOnSharedPreferenceChangeListener(listener: SharedPreferences.OnSharedPreferenceChangeListener?) = Unit

    private inner class Editor : SharedPreferences.Editor {
        private val updates = mutableMapOf<String, Any?>()
        private var clear = false

        override fun putString(key: String, value: String?): SharedPreferences.Editor = put(key, value)
        override fun putStringSet(key: String, values: MutableSet<String>?): SharedPreferences.Editor = put(key, values?.toSet())
        override fun putInt(key: String, value: Int): SharedPreferences.Editor = put(key, value)
        override fun putLong(key: String, value: Long): SharedPreferences.Editor = put(key, value)
        override fun putFloat(key: String, value: Float): SharedPreferences.Editor = put(key, value)
        override fun putBoolean(key: String, value: Boolean): SharedPreferences.Editor = put(key, value)
        override fun remove(key: String): SharedPreferences.Editor = put(key, null)
        override fun clear(): SharedPreferences.Editor = apply { clear = true }
        override fun commit(): Boolean {
            if (failNextCommit) {
                failNextCommit = false
                return false
            }
            if (clear) values.clear()
            updates.forEach { (key, value) ->
                if (value == null) values.remove(key) else values[key] = value
            }
            return true
        }
        override fun apply() { commit() }
        private fun put(key: String, value: Any?): SharedPreferences.Editor = apply { updates[key] = value }
    }
}
