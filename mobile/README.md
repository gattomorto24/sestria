# Sestria · Android

Edizione verticale 4.5, per Android 7.0 o successivo, ARM64 e ARMv7. L’APK release mantiene la firma e l’identificativo tecnico delle installazioni precedenti, così può aggiornarle senza cancellare profilo, statistiche o progressi.

## Comandi

Le finestre scorrono trascinando da qualsiasi punto, anche da schede e pulsanti; un tocco breve attiva il pulsante, un trascinamento no, e toccare per fermare una spinta non attiva nulla. I cursori e l’ispettore 3D mantengono il proprio trascinamento.

Tocca direttamente i dadi 3D per tenerli; tieni premuto per ispezionarli e ruotarli. Le tattiche compaiono nella barra inferiore e sono consultabili anche sui tasselli del tavolo. Il mirino cambia inquadratura. La pausa sospende la simulazione; il tasto Indietro chiude le finestre. I margini rispettano i ritagli della fotocamera e la barra dei gesti.

## Esperienza e Pass

La saga offline assegna XP dalle vittorie: 100 / 130 / 160 in base alla sfida scelta, più 10 per ciascuna soglia di difficoltà raggiunta e l’eventuale bonus del Pass. Ogni livello guadagnato dà **2 punti**. La soglia dal livello L al successivo è `100 + 35 × (L−1) + 5 × (L−1)²`: 100, 140, 190, 250… Gli XP residui si conservano.

- **Scorta del viandante:** 1 / 2 / 3 gettoni iniziali. Livelli 2 / 4 / 7; costo 2 / 3 / 4 punti.
- **Secondo respiro:** cura 1 / 2 pietre, fino a 15, all’inizio della manche 4. Livelli 3 / 6; costo 3 / 4 punti.
- **Riserva tattica:** 1 / 2 gettoni all’inizio della manche 3. Livelli 3 / 6; costo 3 / 4 punti.
- **Ultima risorsa:** dalla manche 2, se inizi con 5 pietre o meno, 1 / 2 gettoni una sola volta. Livelli 5 / 9; costo 4 / 5 punti.
- **Esperienza sul campo:** +5 / 10 / 15% XP dalle vittorie. Livelli 2 / 5 / 8; costo 2 / 3 / 4 punti.

Puoi riassegnare gratis tutti i punti. I bonus vengono fissati all’avvio della saga. Ai livelli 4, 8 e 12 l’AI diventa più capace e ottiene rispettivamente 1, 2 e 3 gettoni iniziali. Analisi tattica e vantaggi hanno un tetto. Sconfitte, abbandoni e LAN non assegnano XP; la LAN non applica il Pass.

## LAN

1. Collega entrambi i telefoni allo stesso Wi-Fi o hotspot.
2. Il primo crea la stanza e comunica IP e codice di sei cifre.
3. Il secondo tocca **Entra** sulla stanza vicina: il codice è annunciato dalla stanza e non va digitato. Per una connessione manuale (o con una versione precedente) inserisce IP e codice.
4. Il creatore avvia la partita. Le tattiche scelte vengono rivelate quando entrambi hanno confermato.

Usa TCP 32640 e UDP 32641. Il creatore valida le mosse e simula i dadi; l’altro riceve aggiornamenti a 10 Hz. Nessun relay, cloud di gioco, port forwarding o account obbligatorio. La rete deve consentire il traffico tra dispositivi. Una disconnessione interrompe la partita senza inventare un vincitore.

Il protocollo LAN 43 è condiviso da Android 4.3, 4.4 e 4.5 e dalle edizioni Mac e Windows: i dispositivi con la stessa versione di protocollo possono sfidarsi. La ricerca UDP resta attiva solo nella stanza, il motore gestisce il blocco multicast senza un secondo proprietario nativo, gli aggiornamenti del menu sono rinviati fuori dai callback di rete e gli stati incompleti vengono rifiutati prima del rendering. La porta TCP rimane utilizzabile anche quando la ricerca automatica non è disponibile.

In **Opzioni → Diagnostica locale** puoi copiare modello, versione Android, ultima fase LAN ed eventuali motivi di uscita registrati dal sistema. Il rapporto resta sul dispositivo; non viene inviato automaticamente. La causa precisa delle chiusure segnalate su telefoni fisici richiede il relativo log: i test su computer o emulatore non lo sostituiscono.

## Aggiornamenti

**Opzioni → Aggiornamenti → Verifica nuovi aggiornamenti** consulta `gattomorto24/sestria` su GitHub Releases. L’app ignora bozze e prerelease e confronta semanticamente le versioni. Se la release ha un pacchetto contenuti Android firmato e compatibile con l’app installata, **Aggiorna** lo scarica (con avanzamento), ne verifica firma del manifest, SHA-256 e motore e lo registra; **Riavvia per applicare** riavvia l’app, che monta il pacchetto prima di caricare il gioco: nessun APK da installare. Se il pacchetto è corrotto o non si carica, l’app torna ai file integrati da sola. Se la versione cambia anche il motore o il codice nativo, o manca il pacchetto, l’app lo spiega e seleziona l’APK universale: il download è verificato con il digest SHA-256 di GitHub, il ponte Android controlla package, firma, versione e compatibilità prima dell’installatore e la conferma finale spetta ad Android (può chiedere di consentire gli aggiornamenti da Sestria; poi torna all’app e premi Installa). Dettagli, limiti e sicurezza in [docs/releases.md](../docs/releases.md). Con una partita aperta, il riavvio e l’installazione sono disponibili dopo il ritorno al menu.

## Dati e account

Statistiche, progressione, preferenze e profilo Google restano locali. Il profilo è facoltativo, richiede Internet e Google Play Services e non sincronizza i salvataggi. Il token di accesso viene controllato per audience, issuer, nonce e scadenza e poi scartato. Non viene trasmesso ai peer LAN. Nel repository e nell’APK sono presenti soltanto identificativi OAuth pubblici.

Le statistiche conservano le ultime 50 partite e separano computer e LAN. I salvataggi usano sostituzione atomica e gli identificativi dei risultati evitano doppie ricompense. Le preferenze e le tattiche salvate dalle versioni precedenti vengono migrate.

## Build

Installa Godot 4.7.1, i suoi template Android, Java 21 e Android SDK (platform 36, build-tools 35.0.1), quindi genera il template Gradle da Godot. `android/` è una directory generata, esclusa da Git.

```sh
bash tools/export_android.sh
```

Lo script copia i ponti Java e il provider dei file nel template. Riutilizza la chiave release privata: imposta `SESTRIA_SIGNING_DIR`, `SESTRIA_GODOT` e `SESTRIA_ANDROID_TOOLS` se i percorsi differiscono. Nessuna chiave privata viene caricata su GitHub. Le dipendenze native sono dichiarate in `addons/sestria_platform/`.
