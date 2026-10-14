package com.android.morphe;

import android.app.Activity;
import android.content.Context;
import android.os.Bundle;
import android.os.PowerManager;
import android.os.SystemProperties;
import android.view.Gravity;
import android.widget.Button;
import android.widget.LinearLayout;
import android.widget.Switch;
import android.widget.TextView;
import android.widget.Toast;

/**
 * One-screen toggle for persist.sys.morphe.mod.
 * The init script reads the property at boot_completed and bind-mounts
 * the patched APKs, so every change needs a reboot to take effect.
 */
public class MorpheActivity extends Activity {

    private static final String PROP_MOD = "persist.sys.morphe.mod";

    @Override
    protected void onCreate(Bundle savedInstanceState) {
        super.onCreate(savedInstanceState);

        LinearLayout root = new LinearLayout(this);
        root.setOrientation(LinearLayout.VERTICAL);
        root.setPadding(64, 64, 64, 64);
        root.setGravity(Gravity.CENTER_VERTICAL);

        TextView title = new TextView(this);
        title.setText(R.string.toggle_title);
        title.setTextSize(22);
        root.addView(title);

        TextView summary = new TextView(this);
        summary.setText(R.string.toggle_summary);
        summary.setPadding(0, 16, 0, 32);
        root.addView(summary);

        Switch toggle = new Switch(this);
        toggle.setChecked(isModEnabled());
        toggle.setOnCheckedChangeListener((buttonView, isChecked) -> {
            SystemProperties.set(PROP_MOD, isChecked ? "true" : "false");
        });
        root.addView(toggle);

        Button reboot = new Button(this);
        reboot.setText(R.string.reboot);
        reboot.setOnClickListener(v -> rebootOrToast());
        root.addView(reboot);

        setContentView(root);
    }

    private boolean isModEnabled() {
        return SystemProperties.getBoolean(PROP_MOD, true);
    }

    private void rebootOrToast() {
        try {
            PowerManager pm = (PowerManager) getSystemService(Context.POWER_SERVICE);
            pm.reboot(null);
            Toast.makeText(this, R.string.reboot_done, Toast.LENGTH_SHORT).show();
        } catch (Exception e) {
            Toast.makeText(this, R.string.reboot_manual, Toast.LENGTH_LONG).show();
        }
    }
}
