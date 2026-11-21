# Pubblicare una versione di Sestria

Il repository ufficiale è [gattomorto24/sestria](https://github.com/gattomorto24/sestria).

1. Aumenta **version/code** e **version/name** nel preset release `mobile/export_presets.cfg`. Aggiorna anche la versione di fallback in `mobile/scripts/updater.gd` e `mobile/native/SestriaUpdates.java`. Per i computer aggiorna `config/version` in `project.godot`, le versioni dei preset macOS e Windows in `export_presets.cfg` e `FALLBACK_VERSION` in `scripts/desktop_updater.gd`.
2. Compila e verifica l’APK con la stessa chiave release. Il nome deve essere `Sestria-vVERSIONE-Android.apk`, ad esempio `Sestria-v4.4-Android.apk`.
3. Esporta Mac (`Sestria-vVERSIONE-macOS-universal.zip`, app universale con firma ad hoc) e Windows (`Sestria-vVERSIONE-Windows-x64.zip`). Genera `SHA256SUMS.txt` con i tre pacchetti.
4. Salva i sorgenti nel repository e crea una release GitHub con tag `vVERSIONE`, ad esempio `v4.4`. Non usare una prerelease per l’aggiornamento stabile.
5. Allega i tre pacchetti, `SHA256SUMS.txt` e le note della versione e pubblica la release. GitHub calcola il digest SHA-256 di ogni asset; le app lo leggono dall’API delle release. Android sceglie l’APK, Mac e Windows il proprio archivio.
6. **Edizione web (passo fisso a ogni release).** Con la versione già aggiornata in `project.godot`, esegui `tools/export_web.sh VERSIONE --publish`. Lo script esporta in `build/web` (Godot 4.7.1, template web single-thread, renderer Compatibility) e sostituisce il branch `gh-pages` con un unico commit che contiene solo la build web; GitHub Pages la serve su https://gattomorto24.github.io/sestria/. Non servono Actions. Senza `--publish` esporta soltanto, per provarla con `python3 tools/web/serve.py build/web`. Controlla che la pagina carichi e che `version.json` riporti la versione appena pubblicata; vedi la sezione «Edizione web» più sotto.
7. Dalla versione precedente apri **Opzioni → Aggiornamenti → Verifica nuovi aggiornamenti**. Verifica download, firma e richiesta di installazione.

Non servono server, manifest ospitati altrove, token dentro l’app o cambiamenti al codice per ogni release. La relazione fra nome della versione e versionCode deve restare crescente. Un APK firmato con un’altra chiave, di un’altra app, incompleto o precedente viene rifiutato.

La chiave e la password restano nella cartella privata di firma, esclusa da Git. Conservane una copia privata: senza la stessa chiave non è possibile aggiornare le copie già installate.

## Edizione web

La versione web ha la stessa base del progetto desktop (`project.godot`, `scripts/`, `scenes/`, `assets/`) e usa il preset **Web** di `export_presets.cfg`. Funziona solo con il renderer Compatibility (WebGL2) e senza thread, perché GitHub Pages non può inviare gli header COOP/COEP. I template web 4.7.1 (`web_nothreads_release.zip`) si trovano in `~/Library/Application Support/Godot/export_templates/4.7.1.stable`; lo script li copia accanto al binario di Godot se mancano. Sul web non esistono LAN TCP/UDP, aggiornatore e pulsante Esci: `scripts/platform.gd` decide cosa mostrare, ed è il punto dove la sessione online WebRTC dichiarerà `online_available()`. I salvataggi di `user://` vanno in IndexedDB del browser. La pagina si aggiorna da sola: dopo la pubblicazione il browser scarica i file nuovi (la cache di Pages dura fino a circa 10 minuti).

## Verifica reale del download

Per provare ricerca, download e SHA-256 contro l’ultima release pubblica, dalla directory `mobile` esegui:

```sh
godot --headless --script res://tests/updater_live_test.gd
```

Il test scarica l’APK su disco e lo rimuove al termine; non sovrascrive un aggiornamento locale già presente. La verifica della firma è coperta separatamente dal collaudo nativo Android in `mobile/tests/native/`. I test non sono inclusi nell’APK release.

Le nuove release possono essere caricate manualmente da GitHub: GitHub Actions non è richiesto per gli aggiornamenti sui telefoni. Il workflow di verifica nel repository è facoltativo e si avvia manualmente.
