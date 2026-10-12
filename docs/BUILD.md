# Compilare VYBE MUSIC

Richiede Flutter 3.47.7, Java 17, Android SDK 36, Build Tools 36.0.0 e NDK 28.2.13676358.

```sh
git clone --recurse-submodules https://github.com/PiElJay/RE-refreezer.git
cd RE-refreezer
sh tool/bootstrap.sh
flutter test
flutter build apk --release --target-platform android-arm64 --split-per-abi
```

Il bootstrap crea `lib/.env` dall’esempio se manca. Browser e ARL non richiedono chiavi applicative nel file. Per il login diretto email/password occorrono `deezerClientId` e `deezerClientSecret` di un’applicazione Deezer autorizzata; la build non li include automaticamente.

La pipeline legge i secrets Actions `DEEZER_CLIENT_ID` e `DEEZER_CLIENT_SECRET`. In locale puoi usare le stesse variabili d’ambiente oppure `lib/.env`. Non pubblicare questi valori.

Per la firma release configura `android/key.properties` e il tuo keystore. In assenza di configurazione il build di sviluppo usa una firma temporanea. Per aggiornare un’installazione esistente devi mantenere applicationId e certificato della versione installata; gli APK distribuiti di VYBE mantengono la firma usata dalle versioni precedenti.
