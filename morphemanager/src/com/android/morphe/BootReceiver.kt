package com.android.morphe

import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.launch

/**
 * BOOT_COMPLETED: re-arm the daily check and flag any app a store update
 * shadowed while we were away. PACKAGE_REPLACED: same check for the app
 * that just changed — a store build over our system build silently
 * disables the mod in stock mode.
 */
class BootReceiver : BroadcastReceiver() {
    override fun onReceive(ctx: Context, intent: Intent) {
        when (intent.action) {
            Intent.ACTION_BOOT_COMPLETED -> {
                UpdateCenter.reschedule(ctx)
                checkOverrides(ctx)
            }
            Intent.ACTION_PACKAGE_REPLACED -> {
                val pkg = intent.data?.schemeSpecificPart ?: return
                val app = ModApp.values().firstOrNull { it.pkg == pkg } ?: return
                checkOne(ctx, app)
            }
        }
    }

    private fun checkOverrides(ctx: Context) {
        CoroutineScope(Dispatchers.IO).launch {
            for (s in queryAppState(ctx)) {
                if (s.installed && s.shadowedByUpdate) {
                    UpdateCenter.notifyOverride(ctx, s.app)
                }
            }
        }
    }

    private fun checkOne(ctx: Context, app: ModApp) {
        CoroutineScope(Dispatchers.IO).launch {
            val s = queryAppState(ctx).firstOrNull { it.app == app } ?: return@launch
            if (s.installed && s.shadowedByUpdate) {
                UpdateCenter.notifyOverride(ctx, app)
            }
        }
    }
}
