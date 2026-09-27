package com.paisatrack.keystore

import java.io.File
import java.util.concurrent.CountDownLatch
import java.util.concurrent.Executors
import java.util.concurrent.TimeUnit
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test

class DatabaseFileLockManagerTest {
    @Test
    fun serializesConcurrentFlutterEngineCallersInOneProcess() {
        val lockFile = File.createTempFile("paisatrack-lock", ".lck")
        lockFile.deleteOnExit()
        val firstToken = DatabaseFileLockManager.acquire(lockFile.absolutePath)
        val secondAcquired = CountDownLatch(1)
        val executor = Executors.newSingleThreadExecutor()
        var firstReleased = false
        var secondToken: String? = null

        try {
            val nextToken = executor.submit<String> {
                val token = DatabaseFileLockManager.acquire(lockFile.absolutePath)
                secondAcquired.countDown()
                token
            }

            assertFalse(secondAcquired.await(100, TimeUnit.MILLISECONDS))
            DatabaseFileLockManager.release(firstToken)
            firstReleased = true
            assertTrue(secondAcquired.await(2, TimeUnit.SECONDS))
            secondToken = nextToken.get(2, TimeUnit.SECONDS)
            DatabaseFileLockManager.release(secondToken!!)
            secondToken = null
        } finally {
            if (!firstReleased) DatabaseFileLockManager.release(firstToken)
            secondToken?.let(DatabaseFileLockManager::release)
            executor.shutdownNow()
            lockFile.delete()
        }
    }
}
