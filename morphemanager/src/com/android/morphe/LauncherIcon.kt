package com.android.morphe

import android.content.ComponentName
import android.content.Context
import android.content.pm.PackageManager

/**
 * Dynamic launcher icon: the red badge shows while any mod is wanted, the
 * muted badge when everything is stock. Implemented as two LAUNCHER
 * activity-aliases flipped via setComponentEnabledSetting — an app may
 * always change its own components, no permission needed. Exactly one
 * alias is enabled at any time so a single icon shows.
 */
object LauncherIcon {
    private const val ACTIVE = "com.android.morphe.LauncherActive"
    private const val IDLE = "com.android.morphe.LauncherIdle"

    fun sync(ctx: Context) {
        val pm = ctx.packageManager
        val active = try {
            ModApp.values().any { it.wanted() }
        } catch (e: Exception) {
            true
        }
        set(pm, ctx, ACTIVE, active)
        set(pm, ctx, IDLE, !active)
    }

    private fun set(pm: PackageManager, ctx: Context, cls: String, on: Boolean) {
        try {
            pm.setComponentEnabledSetting(
                ComponentName(ctx.packageName, cls),
                if (on) PackageManager.COMPONENT_ENABLED_STATE_ENABLED
                else PackageManager.COMPONENT_ENABLED_STATE_DISABLED,
                PackageManager.DONT_KILL_APP,
            )
        } catch (e: Exception) {
            // Best effort: a stale icon never breaks the mod itself.
        }
    }
}
