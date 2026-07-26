package com.paisatrack.intelligence

import android.app.ActivityManager
import android.content.Context
import android.os.Build
import java.io.File

data class DeviceEligibilityResult(
    val supported: Boolean,
    val downloadSupported: Boolean,
    val reason: String,
    val totalMemoryBytes: Long,
    val availableMemoryBytes: Long,
    val lowRamDevice: Boolean,
    val requiredStorageBytes: Long,
    val availableStorageBytes: Long,
    val backend: String,
) {
    fun toMap(): Map<String, Any> = mapOf(
        "supported" to supported,
        "downloadSupported" to downloadSupported,
        "supportReason" to reason,
        "totalMemoryBytes" to totalMemoryBytes,
        "availableMemoryBytes" to availableMemoryBytes,
        "lowRamDevice" to lowRamDevice,
        "requiredStorageBytes" to requiredStorageBytes,
        "availableStorageBytes" to availableStorageBytes,
        "backend" to backend,
    )
}

class DeviceEligibility(
    context: Context,
    private val modelsDirectory: File,
) {
    companion object {
        // Conservative initial tier for the mixed-INT4 candidate. This must
        // only be lowered after physical-device memory/LMK evidence.
        private const val MIN_TOTAL_MEMORY_BYTES = 4_000_000_000L
        private const val MIN_AVAILABLE_MEMORY_BYTES = 1_500_000_000L
        private const val STORAGE_HEADROOM_BYTES = 128L * 1024 * 1024
    }

    private val activityManager =
        context.getSystemService(Context.ACTIVITY_SERVICE) as ActivityManager

    fun evaluate(spec: LlmModelSpec, installed: Boolean): DeviceEligibilityResult {
        val memory = ActivityManager.MemoryInfo()
        activityManager.getMemoryInfo(memory)
        val requiredStorage = if (installed) STORAGE_HEADROOM_BYTES else {
            spec.sizeBytes * 2 + STORAGE_HEADROOM_BYTES
        }
        val availableStorage = existingStorageRoot().usableSpace
        val backendAvailable = Build.SUPPORTED_ABIS.any {
            it == "arm64-v8a" || it == "x86_64"
        }
        val downloadReason = when {
            !backendAvailable -> "backend_unavailable"
            activityManager.isLowRamDevice -> "low_ram_device"
            memory.totalMem < MIN_TOTAL_MEMORY_BYTES -> "insufficient_total_memory"
            availableStorage < requiredStorage -> "insufficient_storage"
            else -> "supported"
        }
        val reason = if (downloadReason != "supported") {
            downloadReason
        } else if (memory.availMem < MIN_AVAILABLE_MEMORY_BYTES) {
            "insufficient_available_memory"
        } else {
            "supported"
        }
        return DeviceEligibilityResult(
            supported = reason == "supported",
            downloadSupported = downloadReason == "supported",
            reason = reason,
            totalMemoryBytes = memory.totalMem,
            availableMemoryBytes = memory.availMem,
            lowRamDevice = activityManager.isLowRamDevice,
            requiredStorageBytes = requiredStorage,
            availableStorageBytes = availableStorage,
            backend = spec.backend,
        )
    }

    private fun existingStorageRoot(): File {
        var candidate: File? = modelsDirectory
        while (candidate != null && !candidate.exists()) {
            candidate = candidate.parentFile
        }
        return candidate ?: modelsDirectory
    }
}
