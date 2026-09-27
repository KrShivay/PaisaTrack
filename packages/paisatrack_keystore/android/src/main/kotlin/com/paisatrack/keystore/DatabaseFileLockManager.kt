package com.paisatrack.keystore

import java.io.File
import java.nio.channels.FileChannel
import java.nio.channels.FileLock
import java.nio.file.StandardOpenOption
import java.util.UUID
import java.util.concurrent.ConcurrentHashMap
import java.util.concurrent.Semaphore

/**
 * Serializes database writers across Flutter engines in this process and
 * across processes. POSIX file locks alone are process-scoped, so the local
 * semaphore is required for WorkManager's background Flutter isolate.
 */
internal object DatabaseFileLockManager {
    private data class HeldLock(
        val channel: FileChannel,
        val fileLock: FileLock,
        val semaphore: Semaphore,
    )

    private val semaphores = ConcurrentHashMap<String, Semaphore>()
    private val heldLocks = ConcurrentHashMap<String, HeldLock>()

    fun acquire(path: String): String {
        val lockFile = File(path).canonicalFile
        lockFile.parentFile?.mkdirs()
        val semaphore = semaphores.computeIfAbsent(lockFile.path) { Semaphore(1, true) }
        semaphore.acquire()
        try {
            val channel = FileChannel.open(
                lockFile.toPath(),
                StandardOpenOption.CREATE,
                StandardOpenOption.WRITE,
            )
            try {
                val fileLock = channel.lock()
                val token = UUID.randomUUID().toString()
                heldLocks[token] = HeldLock(channel, fileLock, semaphore)
                return token
            } catch (error: Throwable) {
                channel.close()
                throw error
            }
        } catch (error: Throwable) {
            semaphore.release()
            throw error
        }
    }

    fun release(token: String) {
        val held = heldLocks.remove(token)
            ?: throw IllegalStateException("Database file lock token is unknown")
        try {
            held.fileLock.release()
        } finally {
            try {
                held.channel.close()
            } finally {
                held.semaphore.release()
            }
        }
    }
}
