package com.paisatrack

import android.app.Application
import android.content.Context

/** Reject a misconfigured recovery build before Flutter plugins or app storage start. */
class RecoveryQaApplication : Application() {
    override fun attachBaseContext(base: Context) {
        val debuggable =
            base.applicationInfo.flags and android.content.pm.ApplicationInfo.FLAG_DEBUGGABLE != 0
        val recoveryQaEnabled = base.resources.getBoolean(R.bool.recovery_qa_enabled)
        check(
            base.packageName == ExpectedApplicationId &&
                BuildConfig.APPLICATION_ID == ExpectedApplicationId &&
                BuildConfig.BUILD_TYPE == "debug" &&
                debuggable && recoveryQaEnabled,
        ) {
            "Recovery QA requires the isolated debug application identity."
        }
        super.attachBaseContext(base)
    }

    private companion object {
        const val ExpectedApplicationId = "com.paisatrack.recoveryqa"
    }
}
