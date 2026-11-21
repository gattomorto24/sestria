package com.sestria.platform;

import android.app.Activity;
import android.content.Intent;
import android.content.pm.PackageInfo;
import android.content.pm.PackageManager;
import android.content.pm.Signature;
import android.net.Uri;
import android.os.Build;
import android.provider.Settings;
import androidx.core.content.FileProvider;
import org.godotengine.godot.Godot;
import org.godotengine.godot.plugin.GodotPlugin;
import org.godotengine.godot.plugin.UsedByGodot;
import java.io.File;
import java.util.Arrays;

/** Installs only a newer APK for this application, signed by the installed application's key. */
public final class SestriaUpdates extends GodotPlugin {
    public SestriaUpdates(Godot godot) { super(godot); }
    @Override public String getPluginName() { return "SestriaUpdates"; }
    private int flags() { return Build.VERSION.SDK_INT>=28 ? PackageManager.GET_SIGNING_CERTIFICATES : PackageManager.GET_SIGNATURES; }
    private PackageInfo installed() throws Exception { return getContext().getPackageManager().getPackageInfo(getContext().getPackageName(),flags()); }
    private long code(PackageInfo info) { return Build.VERSION.SDK_INT>=28 ? info.getLongVersionCode() : info.versionCode; }
    @UsedByGodot public String getVersionName() { try { return installed().versionName; } catch(Exception error) { return "4.6"; } }
    @UsedByGodot public int getVersionCode() { try { return (int)code(installed()); } catch(Exception error) { return 45; } }
    private Signature[] signatures(PackageInfo info) {
        return Build.VERSION.SDK_INT>=28 ? (info.signingInfo==null ? new Signature[0] : info.signingInfo.getApkContentsSigners()) : info.signatures;
    }
    private String normalized(String version) {
        if(version==null || !version.matches("[0-9]{1,5}\\.[0-9]{1,5}(\\.[0-9]{1,5})?")) return "";
        String[] parts=version.split("\\.");
        return Integer.parseInt(parts[0])+"."+Integer.parseInt(parts[1])+"."+(parts.length==3?Integer.parseInt(parts[2]):0);
    }
    private File updateFile(String path) throws Exception {
        File directory=new File(getContext().getFilesDir(),"updates").getCanonicalFile();
        File file=new File(path).getCanonicalFile();
        if(!directory.equals(file.getParentFile()) || !file.isFile() || file.length()>180L*1024*1024) throw new IllegalArgumentException();
        return file;
    }
    @UsedByGodot public String validateUpdate(String path,String expectedVersion) {
        try {
            File file=updateFile(path);
            PackageInfo candidate=getContext().getPackageManager().getPackageArchiveInfo(file.getPath(),flags());
            PackageInfo current=installed();
            if(candidate==null || !current.packageName.equals(candidate.packageName)) return "Il file non è un aggiornamento di questa app.";
            if(code(candidate)<=code(current)) return "Questa versione è già installata o è precedente.";
            if(normalized(expectedVersion).isEmpty() || !normalized(expectedVersion).equals(normalized(candidate.versionName))) return "La versione dell’APK non corrisponde alla release.";
            if(Build.VERSION.SDK_INT>=24 && candidate.applicationInfo!=null && candidate.applicationInfo.minSdkVersion>Build.VERSION.SDK_INT) return "L’aggiornamento richiede una versione Android più recente.";
            Signature[] a=signatures(current),b=signatures(candidate);
            if(a==null || b==null || a.length==0 || a.length!=b.length) return "Firma dell’aggiornamento non valida.";
            for(Signature signer:a) if(!Arrays.asList(b).contains(signer)) return "La firma dell’APK è diversa da quella dell’app installata.";
            return "";
        } catch(Exception error) { return "Impossibile verificare l’APK. Scaricalo nuovamente."; }
    }
    /** Restarts the app in a fresh process so the next start mounts a downloaded content pack. */
    @UsedByGodot public boolean restartApp() {
        Activity activity=getActivity();
        if(activity==null) return false;
        Intent launch=activity.getPackageManager().getLaunchIntentForPackage(activity.getPackageName());
        if(launch==null) return false;
        launch.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK | Intent.FLAG_ACTIVITY_CLEAR_TASK);
        Intent phoenix=new Intent(activity,SestriaRestartActivity.class)
            .putExtra(SestriaRestartActivity.TARGET,launch).putExtra(SestriaRestartActivity.PID,android.os.Process.myPid());
        activity.runOnUiThread(()->activity.startActivity(phoenix));
        return true;
    }
    @UsedByGodot public String installUpdate(String path,String expectedVersion) {
        String error=validateUpdate(path,expectedVersion);
        if(!error.isEmpty()) return error;
        Activity activity=getActivity();
        if(activity==null) return "Torna all’app e riprova.";
        activity.runOnUiThread(()->{
            try {
                if(Build.VERSION.SDK_INT>=26 && !activity.getPackageManager().canRequestPackageInstalls()) {
                    activity.startActivity(new Intent(Settings.ACTION_MANAGE_UNKNOWN_APP_SOURCES,Uri.parse("package:"+activity.getPackageName())));
                    return;
                }
                Uri uri=FileProvider.getUriForFile(activity,activity.getPackageName()+".sestria.updates",updateFile(path));
                Intent install=new Intent(Intent.ACTION_VIEW).setDataAndType(uri,"application/vnd.android.package-archive")
                    .addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION | Intent.FLAG_ACTIVITY_NEW_TASK);
                activity.startActivity(install);
            } catch(Exception failure) { android.util.Log.e("SestriaUpdates","Installer non disponibile",failure); }
        });
        return "";
    }
}
