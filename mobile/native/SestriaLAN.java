package com.sestria.platform;

import android.app.Activity;
import android.app.ActivityManager;
import android.app.ApplicationExitInfo;
import android.content.Context;
import android.os.Build;
import android.util.Log;
import android.view.View;
import org.godotengine.godot.Godot;
import org.godotengine.godot.plugin.GodotPlugin;
import org.godotengine.godot.plugin.UsedByGodot;
import java.io.File;
import java.io.FileOutputStream;
import java.io.PrintWriter;
import java.io.StringWriter;
import java.nio.charset.StandardCharsets;
import java.io.FileInputStream;

/** The engine owns its UDP multicast lock; never acquire a second lock on another thread. */
public final class SestriaLAN extends GodotPlugin {
    private volatile boolean requested;
    private volatile String lifecycle="created";
    private Context application;
    private static boolean handlerInstalled;
    public SestriaLAN(Godot godot) { super(godot); }
    @Override public String getPluginName() { return "SestriaLAN"; }
    @Override public View onMainCreate(Activity activity) {
        application=activity.getApplicationContext();
        installCrashHandler(application);
        return null;
    }
    @UsedByGodot public void setDiscoveryEnabled(boolean enabled) { requested=enabled; }
    @UsedByGodot public void recordStage(String stage) {
        if(application==null) return;
        String safe=stage.replaceAll("[^a-zA-Z0-9_:.-]", "");
        if(safe.length()>80) safe=safe.substring(0,80);
        application.getSharedPreferences("sestria_diagnostics",0).edit().putString("stage",safe).apply();
        Log.i("SestriaLAN",safe);
    }
    @UsedByGodot public String getDiagnosticReport() {
        if(application==null) return "Diagnostica non disponibile.";
        StringBuilder out=new StringBuilder("SESTRIA · DIAGNOSTICA LOCALE\n");
        out.append(Build.MANUFACTURER).append(' ').append(Build.MODEL).append(" · Android ")
            .append(Build.VERSION.RELEASE).append(" / API ").append(Build.VERSION.SDK_INT).append('\n');
        out.append("LAN: ").append(application.getSharedPreferences("sestria_diagnostics",0).getString("stage","nessun evento"))
            .append(" · ").append(lifecycle).append(" · ricerca ").append(requested).append('\n');
        try {
            File file=new File(application.getFilesDir(),"last_java_crash.txt");
            if(file.isFile()) {
                byte[] bytes=new byte[16000];
                try(FileInputStream input=new FileInputStream(file)) {
                    int length=input.read(bytes);
                    if(length>0) out.append("\nUltima eccezione Java:\n").append(new String(bytes,0,length,StandardCharsets.UTF_8));
                }
            }
            if(Build.VERSION.SDK_INT>=30) {
                ActivityManager manager=(ActivityManager)application.getSystemService(Context.ACTIVITY_SERVICE);
                for(ApplicationExitInfo exit:manager.getHistoricalProcessExitReasons(application.getPackageName(),0,3))
                    out.append("\nUscita precedente: motivo ").append(exit.getReason()).append(" · stato ")
                        .append(exit.getStatus()).append(" · ").append(exit.getDescription());
            }
        } catch(Exception error) { out.append("\nDettaglio non disponibile: ").append(error.getClass().getSimpleName()); }
        return out.toString().replace(application.getPackageName(),"Sestria");
    }
    private static synchronized void installCrashHandler(Context context) {
        if(handlerInstalled) return;
        handlerInstalled=true;
        Thread.UncaughtExceptionHandler previous=Thread.getDefaultUncaughtExceptionHandler();
        Thread.setDefaultUncaughtExceptionHandler((thread,error)->{
            try {
                StringWriter buffer=new StringWriter();
                error.printStackTrace(new PrintWriter(buffer));
                String report="Thread: "+thread.getName()+"\n"+buffer;
                if(report.length()>16000) report=report.substring(0,16000);
                try(FileOutputStream file=new FileOutputStream(new File(context.getFilesDir(),"last_java_crash.txt"))) {
                    file.write(report.getBytes(StandardCharsets.UTF_8));
                }
            } catch(Exception ignored) { }
            if(previous!=null) previous.uncaughtException(thread,error);
        });
    }
    @Override public void onMainPause() { lifecycle="paused"; }
    @Override public void onMainResume() { lifecycle="resumed"; }
    @Override public void onMainDestroy() { requested=false; lifecycle="destroyed"; }
}
