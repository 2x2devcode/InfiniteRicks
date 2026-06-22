package org.infinitericks.qt;

import android.os.Bundle;

import org.qtproject.qt5.android.bindings.QtActivity;

import java.io.File;

public class InfiniteRicksQtActivity extends QtActivity
{
    @Override
    public void onCreate(Bundle savedInstanceState)
    {
        final File homeDir = getFilesDir();
        final File dataDir = new File(homeDir, ".InfiniteRicks");
        dataDir.mkdirs();

        // Qt reads these before native startup (see QtActivity.onCreateHook).
        ENVIRONMENT_VARIABLES = "QT_USE_ANDROID_NATIVE_DIALOGS=0\t"
                + "HOME=" + homeDir.getAbsolutePath() + "\t"
                + "TMPDIR=" + getCacheDir().getAbsolutePath() + "\t";
        APPLICATION_PARAMETERS = "-datadir=" + dataDir.getAbsolutePath();

        super.onCreate(savedInstanceState);
    }
}
