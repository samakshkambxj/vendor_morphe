// morphe-settings:fragment
package com.android.settings.morphe

import android.os.Bundle
import android.os.SystemProperties
import android.widget.Toast
import androidx.preference.SwitchPreferenceCompat
import com.android.settings.R
import com.android.settings.dashboard.DashboardFragment
import com.android.settings.search.BaseSearchIndexProvider

/**
 * Morphe toggles inside ROM Settings. One switch per
 * persist.sys.morphe.* property; changes need a reboot (init mounts at
 * boot_completed). Writes need set_prop(system_app, morphe_prop), granted
 * by the vendor/morphe sepolicy set.
 */
class MorpheSettingsFragment : DashboardFragment() {

    override fun getPreferenceScreenResId(): Int = R.xml.morphe_settings

    override fun getLogTag(): String = "MorpheSettings"

    // Metrics category unknown: this tree has no com.android.settings.SettingsEnums
    // to reference, and a raw unknown id always compiles. Vendor toggle screen;
    // nothing meaningful to attribute page views to.
    override fun getMetricsCategory(): Int = 0

    override fun onCreatePreferences(savedInstanceState: Bundle?, rootKey: String?) {
        super.onCreatePreferences(savedInstanceState, rootKey)
        bindSwitch("morphe_yt", PROP_YT)
        bindSwitch("morphe_music", PROP_MUSIC)
        bindSwitch("morphe_reddit", PROP_REDDIT)
    }

    private fun bindSwitch(key: String, prop: String) {
        val pref = findPreference<SwitchPreferenceCompat>(key) ?: return
        pref.isChecked = SystemProperties.getBoolean(prop, true)
        pref.onPreferenceChangeListener =
            androidx.preference.Preference.OnPreferenceChangeListener { _, v ->
                SystemProperties.set(prop, v.toString())
                Toast.makeText(
                    activity, "Reboot to apply the change", Toast.LENGTH_LONG
                ).show()
                true
            }
    }

    companion object {
        private const val PROP_YT = "persist.sys.morphe.yt"
        private const val PROP_MUSIC = "persist.sys.morphe.music"
        private const val PROP_REDDIT = "persist.sys.morphe.reddit"

        /** Search indexing also needs one manual registration line (see README). */
        @JvmField
        val SEARCH_INDEX_DATA_PROVIDER = BaseSearchIndexProvider(R.xml.morphe_settings)
    }
}
