# Pubblicare una versione di Sestria

Il repository ufficiale è [gattomorto24/sestria](https://github.com/gattomorto24/sestria).

1. Aumenta **version/code** e **version/name** nel preset release `mobile/export_presets.cfg`. Aggiorna anche la versione di fallback in `mobile/scripts/updater.gd` e `mobile/native/SestriaUpdates.java`.
2. Compila e verifica l’APK con la stessa chiave release. Il nome deve essere `Sestria-vVERSIONE-Android.apk`, ad esempio `Sestria-v4.4-Android.apk`.
3. Salva i sorgenti nel repository e crea una release GitHub con tag `vVERSIONE`, ad esempio `v4.4`. Non usare una prerelease per l’aggiornamento stabile.
4. Allega l’APK e le note della versione e pubblica la release. GitHub calcola il digest SHA-256 dell’asset; l’app lo legge dall’API delle release.
5. Dalla versione precedente apri **Opzioni → Aggiornamenti → Verifica nuovi aggiornamenti**. Verifica download, firma e richiesta di installazione.

Non servono server, manifest ospitati altrove, token dentro l’app o cambiamenti al codice per ogni release. La relazione fra nome della versione e versionCode deve restare crescente. Un APK firmato con un’altra chiave, di un’altra app, incompleto o precedente viene rifiutato.

La chiave e la password restano nella cartella privata di firma, esclusa da Git. Conservane una copia privata: senza la stessa chiave non è possibile aggiornare le copie già installate.

## Verifica reale del download

Per provare ricerca, download e SHA-256 contro l’ultima release pubblica, dalla directory `mobile` esegui:

```sh
godot --headless --script res://tests/updater_live_test.gd
```

Il test scarica l’APK su disco e lo rimuove al termine; non sovrascrive un aggiornamento locale già presente. La verifica della firma è coperta separatamente dal collaudo nativo Android in `mobile/tests/native/`. I test non sono inclusi nell’APK release.

Le nuove release possono essere caricate manualmente da GitHub: GitHub Actions non è richiesto per gli aggiornamenti sui telefoni. Il workflow di verifica nel repository è facoltativo e si avvia manualmente.
