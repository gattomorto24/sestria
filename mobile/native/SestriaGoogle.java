package com.sestria.platform;

import android.app.Activity;
import android.os.CancellationSignal;
import android.util.Base64;
import androidx.core.content.ContextCompat;
import androidx.credentials.ClearCredentialStateRequest;
import androidx.credentials.Credential;
import androidx.credentials.CredentialManager;
import androidx.credentials.CredentialManagerCallback;
import androidx.credentials.CustomCredential;
import androidx.credentials.GetCredentialRequest;
import androidx.credentials.GetCredentialResponse;
import androidx.credentials.exceptions.ClearCredentialException;
import androidx.credentials.exceptions.GetCredentialCancellationException;
import androidx.credentials.exceptions.GetCredentialException;
import androidx.credentials.exceptions.NoCredentialException;
import com.google.android.libraries.identity.googleid.GetSignInWithGoogleOption;
import com.google.android.libraries.identity.googleid.GoogleIdTokenCredential;
import org.godotengine.godot.Godot;
import org.godotengine.godot.plugin.GodotPlugin;
import org.godotengine.godot.plugin.SignalInfo;
import org.godotengine.godot.plugin.UsedByGodot;
import org.json.JSONObject;
import java.nio.charset.StandardCharsets;
import java.security.SecureRandom;
import java.util.Arrays;
import java.util.HashSet;
import java.util.Set;

/** Native, explicit Google Credential Manager sign-in; tokens never reach disk or LAN. */
public final class SestriaGoogle extends GodotPlugin {
    private volatile boolean pending = false;
    public SestriaGoogle(Godot godot) { super(godot); }
    @Override public String getPluginName() { return "SestriaGoogle"; }
    @Override public Set<SignalInfo> getPluginSignals() {
        return new HashSet<>(Arrays.asList(new SignalInfo("signed_in", String.class),
            new SignalInfo("sign_in_failed", String.class), new SignalInfo("signed_out")));
    }
    @UsedByGodot public void signIn(String clientId) {
        Activity activity = getActivity();
        if (activity == null || pending) return;
        if (!clientId.endsWith(".apps.googleusercontent.com")) {
            emitSignal("sign_in_failed", "Configurazione Google non disponibile.");
            return;
        }
        pending = true;
        byte[] bytes = new byte[32];
        new SecureRandom().nextBytes(bytes);
        final String nonce = Base64.encodeToString(bytes, Base64.URL_SAFE | Base64.NO_WRAP | Base64.NO_PADDING);
        activity.runOnUiThread(() -> {
            try {
                GetSignInWithGoogleOption option = new GetSignInWithGoogleOption.Builder(clientId)
                    .setNonce(nonce).build();
                GetCredentialRequest request = new GetCredentialRequest.Builder().addCredentialOption(option).build();
                CredentialManager.create(activity).getCredentialAsync(activity, request, new CancellationSignal(),
                    ContextCompat.getMainExecutor(activity), new CredentialManagerCallback<GetCredentialResponse, GetCredentialException>() {
                        @Override public void onResult(GetCredentialResponse response) {
                            pending = false;
                            try {
                                Credential credential = response.getCredential();
                                if (!(credential instanceof CustomCredential) || !GoogleIdTokenCredential.TYPE_GOOGLE_ID_TOKEN_CREDENTIAL.equals(credential.getType())) throw new IllegalStateException();
                                GoogleIdTokenCredential google = GoogleIdTokenCredential.createFrom(((CustomCredential) credential).getData());
                                String[] parts = google.getIdToken().split("\\.");
                                if (parts.length != 3) throw new IllegalStateException();
                                JSONObject claims = new JSONObject(new String(Base64.decode(parts[1], Base64.URL_SAFE), StandardCharsets.UTF_8));
                                String issuer = claims.optString("iss");
                                if (!(issuer.equals("https://accounts.google.com") || issuer.equals("accounts.google.com"))
                                    || !claims.optString("aud").equals(clientId) || !claims.optString("nonce").equals(nonce)
                                    || claims.optLong("exp") <= System.currentTimeMillis()/1000L
                                    || !claims.optString("sub").matches("[0-9]{1,64}")) throw new IllegalStateException();
                                JSONObject profile = new JSONObject();
                                profile.put("sub", claims.getString("sub"));
                                profile.put("name", google.getDisplayName() == null ? "Giocatore" : google.getDisplayName());
                                profile.put("email", claims.optString("email", google.getId()));
                                emitSignal("signed_in", profile.toString());
                            } catch (Exception ignored) {
                                emitSignal("sign_in_failed", "Non è stato possibile leggere il profilo Google. Riprova.");
                            }
                        }
                        @Override public void onError(GetCredentialException error) {
                            pending = false;
                            String message = error instanceof GetCredentialCancellationException ? "Accesso annullato. Puoi continuare come ospite."
                                : error instanceof NoCredentialException ? "Nessun account Google disponibile. Aggiungilo nelle impostazioni Android e aggiorna Google Play Services."
                                : "Accesso Google non riuscito. Controlla Internet, Google Play Services e riprova.";
                            emitSignal("sign_in_failed", message);
                        }
                    });
            } catch (Exception ignored) {
                pending = false;
                emitSignal("sign_in_failed", "Accesso Google non disponibile su questo dispositivo.");
            }
        });
    }
    @UsedByGodot public void signOut() {
        Activity activity = getActivity();
        if (activity == null) { emitSignal("signed_out"); return; }
        activity.runOnUiThread(() -> CredentialManager.create(activity).clearCredentialStateAsync(
            new ClearCredentialStateRequest(), new CancellationSignal(), ContextCompat.getMainExecutor(activity),
            new CredentialManagerCallback<Void, ClearCredentialException>() {
                @Override public void onResult(Void value) { emitSignal("signed_out"); }
                @Override public void onError(ClearCredentialException error) { emitSignal("signed_out"); }
            }));
    }
}
