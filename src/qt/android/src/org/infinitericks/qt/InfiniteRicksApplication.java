package org.infinitericks.qt;

import android.content.Context;
import android.system.Os;
import android.util.Log;

import org.qtproject.qt5.android.bindings.QtApplication;

import java.io.File;

public class InfiniteRicksApplication extends QtApplication
{
    private static final String TAG = "InfiniteRicks";

    @Override
    protected void attachBaseContext(Context base)
    {
        super.attachBaseContext(base);
        try {
            final File homeDir = base.getFilesDir();
            final File dataDir = new File(homeDir, ".InfiniteRicks");
            if (!dataDir.exists() && !dataDir.mkdirs()) {
                Log.w(TAG, "Could not create wallet data directory: " + dataDir);
            }
            Os.setenv("HOME", homeDir.getAbsolutePath(), true);
            Os.setenv("TMPDIR", base.getCacheDir().getAbsolutePath(), true);
        } catch (Exception e) {
            Log.e(TAG, "Failed to configure Android environment", e);
        }
    }
}
