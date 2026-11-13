# Italic Go 0.8.17 · progetto iPhone e IPA non firmata

Il progetto include i sorgenti Flutter e il progetto iOS dell’ultima versione,
con 3.406 foto offline. Sul Mac locale non sono installati Xcode e l’SDK iOS;
la compilazione è predisposta su un runner macOS di GitHub Actions.

Il workflow `.github/workflows/ios-unsigned.yml` produce
`Italic-Go-0.8.17-iPhone-non-firmata.ipa`, un bundle arm64 per iPhone fisico con
versione e checksum delle foto verificati. **L’IPA non è firmata per
l’installazione: va firmata e installata con un metodo compatibile, ad esempio
AltStore Classic. Non si installa toccando il file nei Download e non è un
pacchetto TestFlight.** Il workflow non richiede credenziali Apple e non pubblica
l’app su App Store. Gli artefatti GitHub hanno conservazione di un giorno;
la copia scaricata sul Mac rimane disponibile.

Sono predisposti il nome Italic Go, il logo, l'identificativo
`it.italic.italicapp`, iOS 15 o successivo e le descrizioni dei permessi per
fotocamera, galleria e posizione durante l'uso. Il codice comprende diario,
chiavi e matrici offline, condivisione e scelta della posizione su mappa online
della versione 0.8.17, i filtri iniziali, i plot con lista specie e foto multiple, i traguardi offline e le fotografie dimostrative.
La versione 0.8.17 (build 31) usa la nuova icona con licheni e ITALIC GO.
Permette di scegliere la specie dalla lista dopo foto e posizione, oppure
sulle schede del diario. Le celebrazioni delle medaglie aspettano il ritorno
al diario. I testi ripetuti sono stati snelliti. Conserva l’apertura animata,
i filtri, le chiavi e i dati offline della versione precedente.
La firma e il Team Apple non sono inclusi.

## Per compilare e provare su iPhone

1. Installare Xcode dal Mac App Store. Aprirlo e completare l'installazione dei
   componenti iOS; accedere con il proprio account Apple nelle impostazioni di
   Xcode. Le credenziali vanno inserite direttamente in Xcode.
2. Usare Flutter stabile compatibile con il progetto (preparato con Flutter
   3.47.6 / Dart 3.13.5). Dalla cartella del progetto eseguire `flutter pub get`.
3. Eseguire `flutter build ios --config-only --no-codesign` per preparare le
   dipendenze native. Flutter usa Swift Package Manager e, per i plugin che lo
   richiedono, CocoaPods.
4. Aprire `ios/Runner.xcworkspace`, selezionare il target **Runner** e impostare
   il proprio Team in **Signing & Capabilities**, con firma automatica.
   L'identificativo dell'app deve essere disponibile per il proprio account.
5. Collegare l'iPhone, selezionarlo e avviare l'app da Xcode. Per le prove sul
   proprio dispositivo è possibile usare un account Apple gratuito, con i
   limiti di provisioning previsti da Apple.

## Per produrre un IPA da distribuire

La distribuzione tramite TestFlight, App Store o ai dispositivi registrati
richiede l'iscrizione ad Apple Developer Program, il Team e i profili di firma
appropriati. Dopo averli configurati e aver provato l'app su iPhone, eseguire
`flutter build ipa --release`: il file esportato si troverà in `build/ios/ipa/`.
Il metodo di esportazione deve corrispondere al canale di distribuzione scelto.
Non basta rinominare un APK o uno ZIP in `.ipa`.

Prima della distribuzione vanno verificati su iPhone foto, GPS e riferimento
della quota, archivio locale, condivisione e permessi. Su iOS viene usata la quota ortometrica di Core Location, con accuratezza
verticale positiva. L’acquisizione attende misure tridimensionali valide;
se la quota non arriva, il dato resta mancante. Il diario del Mac o di Android non viene trasferito automaticamente.

Per creare manualmente l’IPA non firmata su un Mac con Xcode:

```sh
flutter pub get
flutter build ios --release --no-codesign --no-pub
python3 tools/package_unsigned_ipa.py build/ios/iphoneos/Runner.app \
  dist/Italic-Go-0.8.17-iPhone-non-firmata.ipa --version 0.8.17 --build 31
```

Fonti ufficiali:
- https://docs.flutter.dev/deployment/ios
- https://docs.flutter.dev/platform-integration/ios/setup
- https://developer.apple.com/help/account/basics/about-your-developer-account/
- https://developer.apple.com/documentation/xcode/distributing-your-app-for-beta-testing-and-releases
