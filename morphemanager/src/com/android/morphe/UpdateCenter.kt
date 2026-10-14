package com.android.morphe

import android.Manifest
import android.app.DownloadManager
import android.app.job.JobInfo
import android.app.job.JobScheduler
import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.content.ComponentName
import android.content.Context
import android.content.pm.PackageManager
import android.net.Uri
import android.os.Environment
import java.net.HttpURLConnection
import java.net.URL
import org.json.JSONArray
import org.json.JSONObject

private const val PREFS = "morphe_updates"
private const val KEY_AUTO = "auto_check"
private const val KEY_LAST_CHECK = "last_checked"
private const val CHANNEL = "morphe_updates"
private const val JOB_ID = 4101
private const val DAY_MS = 24L * 60 * 60 * 1000
private const val BUILDER = "j-hc/revanced-magisk-module"

/** Latest known module per app: parsed base version + download URL. */
data class LatestModule(val version: String, val url: String)

object UpdateCenter {

    private fun prefs(ctx: Context) =
        ctx.getSharedPreferences(PREFS, Context.MODE_PRIVATE)

    fun autoCheck(ctx: Context): Boolean = prefs(ctx).getBoolean(KEY_AUTO, true)

    fun setAutoCheck(ctx: Context, on: Boolean) {
        prefs(ctx).edit().putBoolean(KEY_AUTO, on).apply()
        reschedule(ctx)
    }

    fun lastChecked(ctx: Context): Long = prefs(ctx).getLong(KEY_LAST_CHECK, 0)

    fun ignored(ctx: Context, app: ModApp): Boolean =
        prefs(ctx).getBoolean("ignore_${app.name}", false)

    fun setIgnored(ctx: Context, app: ModApp, ignore: Boolean) {
        prefs(ctx).edit().putBoolean("ignore_${app.name}", ignore).apply()
    }

    /** Release notes of the tag the last check selected (empty when unknown). */
    fun notes(ctx: Context): Pair<String, String> =
        prefs(ctx).getString("notes_tag", "")!! to
            prefs(ctx).getString("notes_body", "")!!

    fun latest(ctx: Context, app: ModApp): LatestModule? {
        val v = prefs(ctx).getString("latest_${app.name}_v", null) ?: return null
        val u = prefs(ctx).getString("latest_${app.name}_u", null) ?: return null
        return LatestModule(v, u)
    }

    private fun get(url: String): String {
        val c = URL(url).openConnection() as HttpURLConnection
        try {
            c.connectTimeout = 15000
            c.readTimeout = 15000
            c.setRequestProperty("Accept", "application/vnd.github+json")
            if (c.responseCode !in 200..299) throw RuntimeException("HTTP ${c.responseCode}")
            return c.inputStream.bufferedReader().readText()
        } finally {
            c.disconnect()
        }
    }

    /** Version embedded in a module asset name: youtube-morphe-module-v21.20.405-all.zip -> 21.20.405. */
    fun assetVersion(name: String): String? {
        val m = Regex("v(\\d[\\d.]*)").find(name) ?: return null
        return m.groupValues[1].trimEnd('.')
    }

    fun cmpVer(a: String, b: String): Int {
        val pa = a.split(".").map { it.toIntOrNull() ?: 0 }
        val pb = b.split(".").map { it.toIntOrNull() ?: 0 }
        for (i in 0 until maxOf(pa.size, pb.size)) {
            val d = (pa.getOrElse(i) { 0 }) - (pb.getOrElse(i) { 0 })
            if (d != 0) return d
        }
        return 0
    }

    private fun assetUrls(release: JSONObject): Map<ModApp, Pair<String, String>> {
        val out = mutableMapOf<ModApp, Pair<String, String>>()
        val assets: JSONArray = release.optJSONArray("assets") ?: return out
        for (i in 0 until assets.length()) {
            val a = assets.optJSONObject(i) ?: continue
            val url = a.optString("browser_download_url", "")
            if (!url.endsWith(".zip")) continue
            val name = url.substringAfterLast('/')
            val app = ModApp.values().firstOrNull { name.contains(it.moduleMatch) }
                ?: continue
            // Prefer arm64 music builds; first zip wins otherwise.
            val cur = out[app]
            if (cur == null || (app == ModApp.MUSIC && "arm64" in name && "arm64" !in cur.first)) {
                val v = assetVersion(name) ?: continue
                out[app] = url to v
            }
        }
        return out
    }

    /**
     * Scan newest-first for the first release holding all three modules.
     * The builder rotates tag names across daily runs; the newest release
     * does not always carry every app. Runs on the caller's thread.
     */
    fun check(ctx: Context): Boolean {
        return try {
            val list = JSONArray(get("https://api.github.com/repos/$BUILDER/releases?per_page=10"))
            var found: Map<ModApp, Pair<String, String>>? = null
            var foundTag = ""
            var foundBody = ""
            for (i in 0 until list.length()) {
                val tag = list.optJSONObject(i)?.optString("tag_name", "") ?: ""
                if (tag.isEmpty()) continue
                val rel = JSONObject(get("https://api.github.com/repos/$BUILDER/releases/tags/$tag"))
                val urls = assetUrls(rel)
                if (ModApp.values().all { it in urls }) {
                    found = urls
                    foundTag = tag
                    foundBody = rel.optString("body", "")
                    break
                }
            }
            val ok = found != null
            if (ok) {
                val ed = prefs(ctx).edit()
                for ((app, nv) in found!!) {
                    ed.putString("latest_${app.name}_v", nv.second)
                    ed.putString("latest_${app.name}_u", nv.first)
                }
                ed.putString("notes_tag", foundTag)
                ed.putString("notes_body", foundBody.take(4000))
                ed.putLong(KEY_LAST_CHECK, System.currentTimeMillis())
                ed.apply()
                notifyUpdates(ctx)
            }
            ok
        } catch (e: Exception) {
            false
        }
    }

    /** Installed base version per app, or null when absent. */
    fun installedVersion(ctx: Context, app: ModApp): String? = try {
        ctx.packageManager.getPackageInfo(app.pkg, PackageManager.PackageInfoFlags.of(0)).versionName
    } catch (e: PackageManager.NameNotFoundException) {
        null
    }

    fun hasUpdate(ctx: Context, app: ModApp): Boolean {
        if (ignored(ctx, app)) return false
        val inst = installedVersion(ctx, app) ?: return false
        val lat = latest(ctx, app) ?: return false
        return cmpVer(lat.version, inst) > 0
    }

    private fun canNotify(ctx: Context): Boolean =
        ctx.checkSelfPermission(Manifest.permission.POST_NOTIFICATIONS) ==
            PackageManager.PERMISSION_GRANTED

    private fun channel(ctx: Context) {
        val nm = ctx.getSystemService(NotificationManager::class.java) ?: return
        if (nm.getNotificationChannel(CHANNEL) == null) {
            nm.createNotificationChannel(
                NotificationChannel(
                    CHANNEL,
                    ctx.getString(R.string.notify_channel),
                    NotificationManager.IMPORTANCE_DEFAULT,
                )
            )
        }
    }

    private fun post(ctx: Context, id: Int, title: String, body: String) {
        if (!canNotify(ctx)) return
        channel(ctx)
        val nm = ctx.getSystemService(NotificationManager::class.java) ?: return
        nm.notify(
            id,
            Notification.Builder(ctx, CHANNEL)
                .setSmallIcon(R.drawable.ic_morphe)
                .setContentTitle(title)
                .setContentText(body)
                .setStyle(Notification.BigTextStyle().bigText(body))
                .build(),
        )
    }

    /** Notify once per app that has a newer base staged upstream. */
    fun notifyUpdates(ctx: Context) {
        for (app in ModApp.values()) {
            if (!hasUpdate(ctx, app)) continue
            val inst = installedVersion(ctx, app) ?: continue
            val lat = latest(ctx, app) ?: continue
            post(
                ctx, 5000 + app.ordinal,
                ctx.getString(R.string.notify_update_title),
                ctx.getString(
                    R.string.notify_update_body,
                    ctx.getString(app.titleRes), inst, lat.version,
                ),
            )
        }
    }

    fun notifyOverride(ctx: Context, app: ModApp) {
        post(
            ctx, 6000 + app.ordinal,
            ctx.getString(R.string.notify_override_title),
            ctx.getString(R.string.overridden_body, ctx.getString(app.titleRes)),
        )
    }

    /** Enqueue the module zip into public Downloads. Returns false when unknown. */
    fun download(ctx: Context, app: ModApp): Boolean {
        val lat = latest(ctx, app) ?: return false
        val dm = ctx.getSystemService(DownloadManager::class.java) ?: return false
        val file = lat.url.substringAfterLast('/')
        dm.enqueue(
            DownloadManager.Request(Uri.parse(lat.url))
                .setTitle("${ctx.getString(app.titleRes)} $file")
                .setDestinationInExternalPublicDir(Environment.DIRECTORY_DOWNLOADS, file)
                .setNotificationVisibility(
                    DownloadManager.Request.VISIBILITY_VISIBLE_NOTIFY_COMPLETED
                ),
        )
        return true
    }

    fun reschedule(ctx: Context) {
        val js = ctx.getSystemService(JobScheduler::class.java) ?: return
        js.cancel(JOB_ID)
        if (!autoCheck(ctx)) return
        js.schedule(
            JobInfo.Builder(JOB_ID, ComponentName(ctx, UpdateJob::class.java))
                .setRequiredNetworkType(JobInfo.NETWORK_TYPE_ANY)
                .setPeriodic(DAY_MS)
                .setPersisted(true)
                .build(),
        )
    }
}