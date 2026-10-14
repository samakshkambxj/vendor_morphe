package com.android.morphe

import android.content.Context
import android.content.pm.PackageManager
import android.os.SystemProperties
import java.io.File

/** One patched app: its toggle property, package, mount point and asset match. */
enum class ModApp(
    val titleRes: Int,
    val prop: String,
    val pkg: String,
    /** Path the patched build mounts over in stock mode (also the direct-install path). */
    val stockApkPath: String,
    /** Inert patched blob; present only in stock mode (mount source). */
    val rvApkPath: String,
    /** Substring identifying this app's module zip in builder release assets. */
    val moduleMatch: String,
) {
    YOUTUBE(
        R.string.mod_youtube,
        "persist.sys.morphe.yt",
        "com.google.android.youtube",
        "/product/app/YouTube/com.google.android.youtube.apk",
        "/product/etc/rv/YTPatched.apk",
        "youtube-morphe-module-",
    ),
    MUSIC(
        R.string.mod_music,
        "persist.sys.morphe.music",
        "com.google.android.apps.youtube.music",
        "/product/app/YTMusic/com.google.android.apps.youtube.music.apk",
        "/product/etc/rv/YTMusicPatched.apk",
        "music-morphe-module-",
    ),
    REDDIT(
        R.string.mod_reddit,
        "persist.sys.morphe.reddit",
        "com.reddit.frontpage",
        "/product/app/Reddit/com.reddit.frontpage.apk",
        "/product/etc/rv/RedditPatched.apk",
        "reddit-morphe-module-",
    );

    fun wanted(): Boolean = SystemProperties.getBoolean(prop, true)

    fun setWanted(on: Boolean) = SystemProperties.set(prop, if (on) "true" else "false")

    /** Stock mode (mount over a stock base) vs direct install (no stock to restore). */
    fun stockMode(): Boolean = try {
        File(rvApkPath).exists()
    } catch (e: Exception) {
        false
    }
}

/** Live install state of one app, resolved from PackageManager + /proc/mounts. */
data class AppState(
    val app: ModApp,
    val installed: Boolean,
    val versionName: String?,
    /** True when a /data update shadows the system build (Play overrode the mod). */
    val shadowedByUpdate: Boolean,
    /** True when the patched build is currently mounted over the stock path. */
    val mountActive: Boolean,
)

private fun readMounts(): Set<String> = try {
    File("/proc/mounts").readLines()
        .mapNotNull { it.split(" ").getOrNull(1) }
        .toSet()
} catch (e: Exception) {
    emptySet()
}

fun queryAppState(ctx: Context, mounts: Set<String> = readMounts()): List<AppState> =
    ModApp.values().map { app ->
        val info = try {
            ctx.packageManager.getPackageInfo(
                app.pkg, PackageManager.PackageInfoFlags.of(0)
            )
        } catch (e: PackageManager.NameNotFoundException) {
            null
        }
        // A /data sourceDir means an update installed over the system build —
        // in stock mode that shadows both stock and our mount: mod bypassed.
        val shadowed = info?.applicationInfo?.sourceDir?.startsWith("/data/") == true &&
            (info.lastUpdateTime != info.firstInstallTime)
        AppState(
            app = app,
            installed = info != null,
            versionName = info?.versionName,
            shadowedByUpdate = shadowed,
            mountActive = app.stockApkPath in mounts,
        )
    }
