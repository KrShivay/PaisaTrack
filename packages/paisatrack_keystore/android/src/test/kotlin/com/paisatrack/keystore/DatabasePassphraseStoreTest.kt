package com.paisatrack.keystore

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
        assertEquals(1, cipher.decryptCalls)
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
}

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
    }
}
