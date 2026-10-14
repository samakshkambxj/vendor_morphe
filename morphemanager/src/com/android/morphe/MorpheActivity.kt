package com.android.morphe

import android.Manifest
import android.content.Context
import android.content.pm.PackageManager
import android.os.Bundle
import android.os.PowerManager
import androidx.activity.ComponentActivity
import androidx.activity.compose.rememberLauncherForActivityResult
import androidx.activity.compose.setContent
import androidx.activity.result.contract.ActivityResultContracts
import androidx.compose.foundation.isSystemInDarkTheme
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.items
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.Check
import androidx.compose.material.icons.filled.Refresh
import androidx.compose.material.icons.filled.Warning
import androidx.compose.material3.ButtonDefaults
import androidx.compose.material3.CenterAlignedTopAppBar
import androidx.compose.material3.ElevatedCard
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.FilledTonalButton
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.ListItem
import androidx.compose.material3.ListItemDefaults
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Scaffold
import androidx.compose.material3.SnackbarHost
import androidx.compose.material3.SnackbarHostState
import androidx.compose.material3.Switch
import androidx.compose.material3.Tab
import androidx.compose.material3.TabRow
import androidx.compose.material3.Text
import androidx.compose.material3.dynamicDarkColorScheme
import androidx.compose.material3.dynamicLightColorScheme
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import java.text.SimpleDateFormat
import java.util.Date
import java.util.Locale
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.launch
import kotlinx.coroutines.withContext

class MorpheActivity : ComponentActivity() {
    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        setContent { MorpheApp() }
    }
}

private fun hasNotifPerm(ctx: Context): Boolean =
    ctx.checkSelfPermission(Manifest.permission.POST_NOTIFICATIONS) ==
        PackageManager.PERMISSION_GRANTED

@OptIn(ExperimentalMaterial3Api::class)
@Composable
private fun MorpheApp() {
    val ctx = LocalContext.current
    val colorful = isSystemInDarkTheme()
    MaterialTheme(
        colorScheme = if (colorful) {
            dynamicDarkColorScheme(ctx)
        } else {
            dynamicLightColorScheme(ctx)
        },
    ) {
        var tab by remember { mutableStateOf(0) }
        val bar = remember { SnackbarHostState() }
        Scaffold(
            topBar = {
                CenterAlignedTopAppBar(
                    title = { Text(ctx.getString(R.string.app_name), fontWeight = FontWeight.SemiBold) },
                )
            },
            snackbarHost = { SnackbarHost(bar) },
        ) { pad ->
            Column(Modifier.padding(pad).fillMaxSize()) {
                TabRow(selectedTabIndex = tab) {
                    Tab(
                        selected = tab == 0,
                        onClick = { tab = 0 },
                        text = { Text(ctx.getString(R.string.tab_mods)) },
                    )
                    Tab(
                        selected = tab == 1,
                        onClick = { tab = 1 },
                        text = { Text(ctx.getString(R.string.tab_updates)) },
                    )
                }
                if (tab == 0) ModsTab(bar) else UpdatesTab(bar)
            }
        }
    }
}

/** One mod row: toggle (stock mode) or locked-on state (direct install). */
@Composable
private fun ModsTab(bar: SnackbarHostState) {
    val ctx = LocalContext.current
    val scope = rememberCoroutineScope()
    var states by remember { mutableStateOf(emptyList<AppState>()) }
    var wanted by remember { mutableStateOf(ModApp.values().associateWith { it.wanted() }) }

    fun refresh() {
        scope.launch(Dispatchers.IO) {
            val s = queryAppState(ctx)
            val w = ModApp.values().associateWith { it.wanted() }
            withContext(Dispatchers.Main) {
                states = s
                wanted = w
            }
        }
    }
    LaunchedEffect(Unit) { refresh() }

    LazyColumn(
        Modifier.fillMaxSize().padding(horizontal = 16.dp),
        verticalArrangement = Arrangement.spacedBy(12.dp),
    ) {
        item { Spacer(Modifier.height(4.dp)) }
        items(states, key = { it.app.name }) { s ->
            val on = wanted[s.app] == true
            val stockMode = s.app.stockMode()
            val (line, tint) = when {
                !s.installed -> ctx.getString(R.string.state_missing) to
                    MaterialTheme.colorScheme.error
                s.shadowedByUpdate -> ctx.getString(
                    R.string.overridden_body, ctx.getString(s.app.titleRes)
                ) to MaterialTheme.colorScheme.error
                s.mountActive || !stockMode ->
                    ctx.getString(R.string.state_active) to
                        MaterialTheme.colorScheme.primary
                on -> ctx.getString(R.string.state_pending) to
                    MaterialTheme.colorScheme.tertiary
                else -> ctx.getString(R.string.state_stock) to
                    MaterialTheme.colorScheme.onSurfaceVariant
            }
            ElevatedCard(
                Modifier.fillMaxWidth(),
                shape = RoundedCornerShape(28.dp),
            ) {
                ListItem(
                    headlineContent = {
                        Text(ctx.getString(s.app.titleRes), fontWeight = FontWeight.Medium)
                    },
                    supportingContent = {
                        Text(line, color = tint)
                        if (!stockMode && s.installed && !s.shadowedByUpdate) {
                            Text(ctx.getString(R.string.direct_note))
                        }
                    },
                    trailingContent = {
                        if (s.shadowedByUpdate || !s.installed) {
                            Icon(
                                Icons.Filled.Warning,
                                contentDescription = null,
                                tint = MaterialTheme.colorScheme.error,
                            )
                        } else {
                            Switch(
                                checked = on,
                                enabled = stockMode,
                                onCheckedChange = { v ->
                                    s.app.setWanted(v)
                                    wanted = wanted + (s.app to v)
                                    LauncherIcon.sync(ctx)
                                },
                            )
                        }
                    },
                    colors = ListItemDefaults.colors(containerColor = Color.Transparent),
                )
            }
        }
        item {
            FilledTonalButton(
                onClick = {
                    try {
                        val pm = ctx.getSystemService(Context.POWER_SERVICE) as PowerManager
                        pm.reboot(null)
                        scope.launch { bar.showSnackbar(ctx.getString(R.string.reboot_done)) }
                    } catch (e: Exception) {
                        scope.launch { bar.showSnackbar(ctx.getString(R.string.reboot_manual)) }
                    }
                },
                modifier = Modifier.fillMaxWidth().padding(vertical = 8.dp),
                shape = RoundedCornerShape(20.dp),
            ) { Text(ctx.getString(R.string.reboot)) }
            Spacer(Modifier.height(16.dp))
        }
    }
}

/** Update center: auto-check switch, manual check, per-app versions + module downloads. */
@Composable
private fun UpdatesTab(bar: SnackbarHostState) {
    val ctx = LocalContext.current
    val scope = rememberCoroutineScope()
    var auto by remember { mutableStateOf(UpdateCenter.autoCheck(ctx)) }
    var checking by remember { mutableStateOf(false) }
    var checkedAt by remember { mutableStateOf(UpdateCenter.lastChecked(ctx)) }
    var rows by remember { mutableStateOf(emptyList<UpdateRow>()) }
    var notifOk by remember { mutableStateOf(hasNotifPerm(ctx)) }
    val permLauncher = rememberLauncherForActivityResult(
        ActivityResultContracts.RequestPermission()
    ) { notifOk = hasNotifPerm(ctx) }

    fun reload() {
        scope.launch(Dispatchers.IO) {
            val r = ModApp.values().map { app ->
                UpdateRow(
                    app = app,
                    installed = UpdateCenter.installedVersion(ctx, app),
                    latest = UpdateCenter.latest(ctx, app)?.version,
                    update = UpdateCenter.hasUpdate(ctx, app),
                )
            }
            val t = UpdateCenter.lastChecked(ctx)
            withContext(Dispatchers.Main) {
                rows = r
                checkedAt = t
            }
        }
    }
    LaunchedEffect(Unit) { reload() }

    fun checkNow() {
        if (checking) return
        checking = true
        scope.launch(Dispatchers.IO) {
            val ok = UpdateCenter.check(ctx)
            withContext(Dispatchers.Main) {
                checking = false
                reload()
                scope.launch {
                    bar.showSnackbar(
                        if (ok) ctx.getString(R.string.up_to_date)
                        else ctx.getString(R.string.check_failed)
                    )
                }
            }
        }
    }

    LazyColumn(
        Modifier.fillMaxSize().padding(horizontal = 16.dp),
        verticalArrangement = Arrangement.spacedBy(12.dp),
    ) {
        item { Spacer(Modifier.height(4.dp)) }
        if (!notifOk) {
            item {
                ElevatedCard(Modifier.fillMaxWidth(), shape = RoundedCornerShape(28.dp)) {
                    ListItem(
                        headlineContent = { Text(ctx.getString(R.string.allow_notifications)) },
                        trailingContent = {
                            FilledTonalButton(onClick = {
                                permLauncher.launch(Manifest.permission.POST_NOTIFICATIONS)
                            }) { Text(ctx.getString(R.string.grant)) }
                        },
                        colors = ListItemDefaults.colors(containerColor = Color.Transparent),
                    )
                }
            }
        }
        item {
            ElevatedCard(Modifier.fillMaxWidth(), shape = RoundedCornerShape(28.dp)) {
                Column(Modifier.padding(4.dp)) {
                    ListItem(
                        headlineContent = { Text(ctx.getString(R.string.auto_check)) },
                        supportingContent = { Text(ctx.getString(R.string.auto_check_summary)) },
                        trailingContent = {
                            Switch(
                                checked = auto,
                                onCheckedChange = {
                                    auto = it
                                    UpdateCenter.setAutoCheck(ctx, it)
                                },
                            )
                        },
                        colors = ListItemDefaults.colors(containerColor = Color.Transparent),
                    )
                    ListItem(
                        headlineContent = {
                            Text(
                                if (checkedAt == 0L) ctx.getString(R.string.never_checked)
                                else ctx.getString(
                                    R.string.last_checked,
                                    SimpleDateFormat("MMM d, HH:mm", Locale.getDefault())
                                        .format(Date(checkedAt)),
                                )
                            )
                        },
                        trailingContent = {
                            IconButton(onClick = { checkNow() }, enabled = !checking) {
                                Icon(Icons.Filled.Refresh, contentDescription = null)
                            }
                        },
                        colors = ListItemDefaults.colors(containerColor = Color.Transparent),
                    )
                }
            }
        }
        if (checking) {
            item {
                Row(
                    Modifier.fillMaxWidth().padding(8.dp),
                    horizontalArrangement = Arrangement.Center,
                    verticalAlignment = Alignment.CenterVertically,
                ) { Text(ctx.getString(R.string.checking)) }
            }
        }
        items(rows, key = { it.app.name }) { r ->
            ElevatedCard(Modifier.fillMaxWidth(), shape = RoundedCornerShape(28.dp)) {
                Column(Modifier.padding(4.dp)) {
                    ListItem(
                        headlineContent = {
                            Text(
                                ctx.getString(r.app.titleRes),
                                fontWeight = FontWeight.Medium,
                            )
                        },
                        supportingContent = {
                            Column {
                                Text(
                                    if (r.installed != null) ctx.getString(
                                        R.string.installed_label, r.installed
                                    ) else ctx.getString(R.string.not_installed)
                                )
                                if (r.latest != null) {
                                    Text(ctx.getString(R.string.latest_label, r.latest))
                                }
                            }
                        },
                        trailingContent = {
                            if (r.update) {
                                Icon(
                                    Icons.Filled.Check,
                                    contentDescription = null,
                                    tint = MaterialTheme.colorScheme.primary,
                                )
                            }
                        },
                        colors = ListItemDefaults.colors(containerColor = Color.Transparent),
                    )
                    Row(
                        Modifier.fillMaxWidth().padding(horizontal = 16.dp)
                            .padding(bottom = 12.dp),
                        horizontalArrangement = Arrangement.End,
                    ) {
                        FilledTonalButton(
                            onClick = {
                                if (UpdateCenter.download(ctx, r.app)) {
                                    scope.launch {
                                        bar.showSnackbar(ctx.getString(R.string.download_started))
                                    }
                                }
                            },
                            enabled = r.latest != null,
                            shape = RoundedCornerShape(20.dp),
                            colors = ButtonDefaults.filledTonalButtonColors(),
                        ) {
                            Text(
                                if (r.update) ctx.getString(R.string.update_available)
                                else ctx.getString(R.string.download)
                            )
                        }
                    }
                }
            }
        }
        item { Spacer(Modifier.height(16.dp)) }
    }
}

private data class UpdateRow(
    val app: ModApp,
    val installed: String?,
    val latest: String?,
    val update: Boolean,
)
