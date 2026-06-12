package org.infinitericks.qt;

import android.os.Bundle;
import android.system.Os;

import org.qtproject.qt5.android.bindings.QtActivity;

import java.io.File;

public class InfiniteRicksQtActivity extends QtActivity
{
    @Override
    public void onCreate(Bundle savedInstanceState)
    {
        final File homeDir = getFilesDir();
        final File dataDir = new File(homeDir.getAbsolutePath() + "/.InfiniteRicks");
        if (!dataDir.exists()) {
            dataDir.mkdirs();
        }

        try {
            Os.setenv("HOME", homeDir.getAbsolutePath(), true);
        } catch (Exception e) {
            e.printStackTrace();
        }

        super.onCreate(savedInstanceState);
    }
}
