# VYBE MUSIC 1.0.2 — verifica di sicurezza

Data: 13 ottobre 2026. Revisione del codice e dell’APK 1.0.1, con prove di regressione per le correzioni 1.0.2.

## Ambito e metodo

Sono stati esaminati il server audio HTTP locale, le richieste di aggiornamento, i permessi e il backup Android, la gestione dei file importati e i percorsi di salvataggio/log delle credenziali. Le prove del server utilizzano la sua implementazione reale con NanoHTTPD e file sintetici; il provider Deezer è sostituito da stub. I test degli aggiornamenti simulano risposte HTTP, contenuti alterati e redirect.

Non sono stati attaccati Deezer o altri servizi esterni. Non sono stati utilizzati password, ARL o file personali nelle prove. Non è un audit indipendente né una certificazione: non comprende prove su un telefono reale, root, malware installato, intercettazione del traffico di un dispositivo o una verifica completa delle dipendenze.

## Risultati e correzioni

### Server locale: accesso senza autenticazione e percorsi non confinati

Nella 1.0.1 il server ascolta solo su 127.0.0.1 e usa una porta assegnata dal sistema, ma un’altra applicazione sullo stesso dispositivo può tentare connessioni loopback. Il parametro `id` veniva utilizzato direttamente per costruire il percorso del file: sequenze di attraversamento directory potevano indirizzare la lettura verso altri file accessibili al processo VYBE.

Nella 1.0.2 ogni istanza genera un token casuale di 256 bit. Il server richiede il token prima di elaborare qualsiasi endpoint, rifiuta parametri di autenticazione duplicati e accetta solo gli endpoint previsti. Gli ID dei file sono limitati a nomi semplici; la verifica del percorso canonico impedisce l’uscita dalla directory offline, anche tramite link simbolici. Il token è escluso dai log esportati.

La regressione verifica autenticazione errata, attraversamento directory normale e codificato, percorso assoluto, link simbolico verso un file sintetico esterno, richieste audio valide e range HTTP. La protezione non riguarda attaccanti con root o controllo del processo.

### Aggiornamenti APK: integrità non verificata dall’app

Nella 1.0.1 il downloader non verificava lo stato HTTP, la dimensione e l’hash dell’asset prima di aprire l’installazione. Android controlla la firma durante un aggiornamento, ma questo controllo non sostituisce la verifica del download.

La 1.0.2 accetta inizialmente solo asset HTTPS della repository PiElJay/VYBE-MUSIC. Rifiuta redirect verso HTTP, richiede dimensione e digest SHA-256 forniti da GitHub, limita dimensione e tempi di attesa e verifica i byte ricevuti. Il file temporaneo viene promosso ad APK installabile solo dopo i controlli; in caso di errore viene eliminato senza sostituire un APK precedente verificato.

Questa verifica si affida ai metadati HTTPS di GitHub: non protegge da una compromissione dell’account GitHub o della chiave di firma. La firma dell’APK resta verificata dall’installer Android.

### Backup e trasporto

Le impostazioni contengono l’ARL in un file privato dell’app. Nella 1.0.2 sono disabilitati i backup dell’app e vengono escluse le directory anche dalle regole di trasferimento Android. Questo evita la normale inclusione delle credenziali nei backup configurati dal sistema, senza cancellare i dati già presenti sul dispositivo.

Il traffico HTTP in chiaro gestito dalla configurazione di rete Android è consentito soltanto per il server loopback. Il resto richiede HTTPS. Questa configurazione non è una prova completa di tutte le librerie di rete; il downloader degli aggiornamenti verifica esplicitamente anche lo schema dei redirect.

### Permessi

Sono rimossi dal manifest finale i permessi READ_MEDIA_IMAGES e READ_MEDIA_VIDEO aggiunti dalle dipendenze. Restano l’accesso audio, i permessi necessari alla riproduzione e alle notifiche, la gestione dell’archivio per le funzionalità di esportazione e il permesso di installazione per gli aggiornamenti APK.

La verifica sull’APK compilato controlla anche l’assenza di permessi per microfono, contatti, posizione precisa e fotocamera, oltre alle configurazioni di backup e rete.

## Limiti residui

- L’ARL resta memorizzata in chiaro nello spazio privato dell’app: il sandbox Android e l’esclusione dai backup riducono l’esposizione, ma non proteggono da root o compromissione del processo. La migrazione a un archivio basato su Android Keystore richiede una modifica separata e test sul dispositivo.
- L’accesso esteso all’archivio resta disponibile per le funzionalità che lo richiedono. Una futura migrazione completa allo Storage Access Framework potrebbe ridurre questo permesso.
- La verifica non certifica che l’app sia priva di vulnerabilità. Restano da provare su dispositivi Android reali installazione, aggiornamenti, trasferimento dati, interazione con altre app e tutte le funzioni audio.

Per segnalazioni di sicurezza, evita di pubblicare ARL, password, token o file personali nelle issue.
