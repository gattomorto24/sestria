package com.sestria.smoke;

import android.app.Activity;
import android.app.Instrumentation;
import android.content.ComponentName;
import android.content.Intent;
import android.os.Bundle;
import android.os.SystemClock;
import android.graphics.Bitmap;
import android.view.accessibility.AccessibilityNodeInfo;
import java.io.File;
import java.io.FileOutputStream;
import java.lang.reflect.Method;

/** Debug-only test APK. The production APK contains no test hooks. */
public final class SestriaSmoke extends Instrumentation {
    private String mode;
    @Override public void onCreate(Bundle arguments) {
        super.onCreate(arguments);
        mode=arguments.getString("mode","plugins");
        start();
    }
    @Override public void onStart() {
        Bundle result=new Bundle();
        try {
            Intent intent=new Intent(Intent.ACTION_MAIN).setComponent(new ComponentName("com.orlog.valhalla.debug","com.godot.game.GodotAppLauncher"));
            intent.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK);
            Activity activity=startActivitySync(intent);
            Object godot=null;
            for(int i=0;i<150;i++) {
                godot=activity.getClass().getMethod("getGodot").invoke(activity);
                if(godot!=null && "STARTED".equals(String.valueOf(godot.getClass().getMethod("getRunStatus").invoke(godot)))) break;
                SystemClock.sleep(100);
            }
            if(godot==null) throw new IllegalStateException("Godot non avviato");
            Object registry=null;
            for(Method method:godot.getClass().getMethods()) {
                if(method.getName().startsWith("getPluginRegistry")) { registry=method.invoke(godot); break; }
            }
            if(registry==null) throw new IllegalStateException("Registry plugin assente");
            Object google=registry.getClass().getMethod("getPlugin",String.class).invoke(registry,"SestriaGoogle");
            Object lan=registry.getClass().getMethod("getPlugin",String.class).invoke(registry,"SestriaLAN");
            if(google==null || lan==null) throw new IllegalStateException("Plugin nativi non caricati");
            Object updates=registry.getClass().getMethod("getPlugin",String.class).invoke(registry,"SestriaUpdates");
            if(updates==null) throw new IllegalStateException("Plugin aggiornamenti assente");
            result.putString("plugins","SestriaGoogle + SestriaLAN + SestriaUpdates caricati");
            if(mode.equals("lan")) {
                for(int i=0;i<2000;i++) {
                    lan.getClass().getMethod("setDiscoveryEnabled",boolean.class).invoke(lan,i%2==0);
                    lan.getClass().getMethod("onMainPause").invoke(lan);
                    lan.getClass().getMethod("onMainResume").invoke(lan);
                }
                result.putString("lifecycle","2000 cicli ricerca/pausa/ripresa completati");
                result.putString("diagnostics",String.valueOf(lan.getClass().getMethod("getDiagnosticReport").invoke(lan)));
            }
            if(mode.equals("updates")) {
                Method validate=updates.getClass().getMethod("validateUpdate",String.class,String.class);
                File folder=new File(getTargetContext().getFilesDir(),"updates");
                String valid=new File(folder,"valid44.apk").getAbsolutePath();
                String bad=new File(folder,"wrong-signature44.apk").getAbsolutePath();
                String old=new File(folder,"old43.apk").getAbsolutePath();
                if(!"".equals(validate.invoke(updates,valid,"4.4"))) throw new IllegalStateException("Aggiornamento valido rifiutato: "+validate.invoke(updates,valid,"4.4"));
                if("".equals(validate.invoke(updates,bad,"4.4"))) throw new IllegalStateException("Firma estranea accettata");
                if("".equals(validate.invoke(updates,old,"4.3"))) throw new IllegalStateException("Versione precedente accettata");
                if("".equals(validate.invoke(updates,valid,"4.5"))) throw new IllegalStateException("Nome versione incoerente accettato");
                if("".equals(validate.invoke(updates,"/data/local/tmp/valid44.apk","4.4"))) throw new IllegalStateException("Percorso esterno accettato");
                result.putString("updates","Valida 4.4 accettata; firma diversa, versione vecchia, metadati errati e percorso esterno respinti");
            }
            if(mode.equals("google")) {
                google.getClass().getMethod("signIn",String.class).invoke(google,"563705322283-0inp39rrv6qlbkbhirhalank93thjv15.apps.googleusercontent.com");
                SystemClock.sleep(5000);
                AccessibilityNodeInfo root=getUiAutomation().getRootInActiveWindow();
                result.putString("foreground_package",root==null?"":String.valueOf(root.getPackageName()));
                result.putString("native_flow",root==null?"unavailable":"visible");
                Bitmap bitmap=getUiAutomation().takeScreenshot();
                if(bitmap!=null) {
                    File file=new File(getTargetContext().getExternalFilesDir(null),"google-native-smoke.png");
                    try(FileOutputStream out=new FileOutputStream(file)) { bitmap.compress(Bitmap.CompressFormat.PNG,100,out); }
                    result.putString("screenshot",file.toString());
                }
            }
            result.putString("result","OK");
            finish(Activity.RESULT_OK,result);
        } catch(Throwable error) {
            result.putString("error",error.toString());
            finish(Activity.RESULT_CANCELED,result);
        }
    }
}
