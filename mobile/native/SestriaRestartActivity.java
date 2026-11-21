package com.sestria.platform;

import android.app.Activity;
import android.content.Intent;
import android.os.Bundle;

/**
 * Runs in its own process (":restart"): kills the main process and starts the app again, so a downloaded
 * content pack is mounted by a fresh engine. Starting the activity from the same process before it dies
 * would reuse that process and be lost with it.
 */
public final class SestriaRestartActivity extends Activity {
    static final String TARGET = "sestria_target";
    static final String PID = "sestria_pid";
    @Override protected void onCreate(Bundle state) {
        super.onCreate(state);
        Intent source = getIntent();
        Intent target = source == null ? null : (Intent) source.getParcelableExtra(TARGET);
        int pid = source == null ? -1 : source.getIntExtra(PID, -1);
        if (pid > 0 && pid != android.os.Process.myPid()) android.os.Process.killProcess(pid);
        if (target != null) startActivity(target);
        finish();
        Runtime.getRuntime().exit(0);
    }
}
