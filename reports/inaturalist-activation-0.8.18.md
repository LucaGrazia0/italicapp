# iNaturalist: attivazione e limiti della versione 0.8.18

La versione 0.8.17 era già pubblicata sul ramo `codex/simplify-navigation`
(commit `b850c95ae1e21a28efee65c4b3cdac87c42ff564`).

## Flusso preparato

Da Impostazioni o dalla condivisione del diario, **Collega iNaturalist** apre
il login ufficiale nel browser di sistema. AppAuth gestisce Authorization Code,
PKCE e state. Dopo l'autorizzazione l'utente torna in Italic Go. Il token OAuth
è conservato nel Keychain iPhone / archivio cifrato Android; la password non
viene richiesta dall'app. Scollega account rimuove la sessione locale, senza
eliminare le osservazioni remote. Le autorizzazioni si possono revocare anche
nelle impostazioni del proprio account iNaturalist.

La pagina di invio prepara foto, nome, data con fuso orario, coordinate del
diario (comprese quelle corrette sulla mappa), incertezza e note DoLichens.
Un riepilogo richiede conferma prima dell'invio. La posizione è facoltativa;
la visibilità predefinita è privata. Le coordinate non vengono ripetute nelle
note pubbliche. La quota s.l.m. è conservata nelle note quando si include la
posizione. Il nome originale viene inviato come `species_guess`: un ID ITALIC
non viene convertito impropriamente in un taxon ID iNaturalist.

Una copia della foto, lunga al massimo 2048 pixel sul lato maggiore, viene
ricodificata in PNG senza i vecchi metadati. Questo evita che le coordinate
originali dell'immagine contraddicano il punto corretto o la scelta di non
includere la posizione. La foto originale nel diario non cambia.

L'app conserva checkpoint locali separati per account e ritrovamento. Se cade
la connessione dopo una richiesta di creazione, cerca la stessa osservazione
tramite UUID e proprietario; se non è ancora visibile non ripete il POST.
Una foto con risposta persa viene riconciliata tramite l'UUID dell'allegato.
Un invio incompleto con opzioni diverse viene fermato: non si cambiano in
silenzio i dati già confermati. Un invio completato restituisce il collegamento
esistente. Non c'è sincronizzazione generale o modifica automatica remota.

## Configurazione ancora mancante

**Non è ancora presente un Client ID pubblico registrato per Italic Go. Il
login reale e una pubblicazione autenticata non sono stati eseguiti.**
Senza configurazione la build mostra «Invio completo in preparazione» e
mantiene la condivisione tramite il menu del telefono. Non mostra un login
finto o un pulsante di pubblicazione non funzionante.

Una sola registrazione OAuth per Italic Go, non una per utilizzatore:

- Nome: Italic Go.
- Callback da registrare esattamente: `it.italic.italicapp:/oauthredirect`.
- Client pubblico / non confidential, PKCE, scope `write`.
- Nessun Client Secret nell'app, nel codice o nei parametri di compilazione.
- Compilazione: `--dart-define=INATURALIST_CLIENT_ID=CLIENT_ID_PUBBLICO`.
- La compilazione iOS su GitHub legge la variabile della repository
  `INATURALIST_CLIENT_ID`. Il valore vuoto lascia il collegamento disattivato.

La registrazione e il callback devono essere accettati dal servizio. Dopo la
configurazione occorre provare il login e un invio autorizzato su entrambi i
telefoni, verificando foto, nome, data, coordinate, incertezza e visibilità.
I test locali simulano il servizio e non sostituiscono questa prova.

## Condivisione del telefono

Ora allega la foto **e il testo** con nome e scheda DoLichens (coordinate solo
se richieste). iNaturalist può ignorare il testo: questa funzione non viene
presentata come equivalente all'invio API. Gli originali possono contenere
EXIF propri, come indicato nella schermata. La scelta di non includere il GPS
nel testo non rimuove gli EXIF dalla foto originale di questa modalità.

## Fluidità

- Il diario usa griglie lazy nello stesso scorrimento: non costruisce tutte
  le schede fotografiche di ogni giornata. Test con 500 ritrovamenti.
- La selezione di una specie o la correzione del punto copiano i metadati
  mantenendo il buffer della foto, evitando copie inutili e nuove decodifiche.
- Excel e ZIP sono preparati con `compute` fuori dal thread UI su Android/iOS.
  Sul web rimane il fallback supportato da Flutter.

## Fonti ufficiali consultate

- https://www.inaturalist.org/pages/api+reference — OAuth e PKCE.
- https://api.inaturalist.org/v1/docs/ — endpoint observations / observation_photos.
- https://github.com/inaturalist/iNaturalistAPI/blob/main/lib/models/observation_query_builder.js
  — filtro UUID e proprietario.
- https://github.com/inaturalist/iNaturalistAPI/blob/main/lib/controllers/v1/observation_photos_controller.js
  — creazione allegati.
- https://github.com/inaturalist/iNaturalistReactNative/blob/main/src/sharedHelpers/parseExif.ts
  — lettura posizione/data delle foto importate, senza contratto per il nome.
- https://pub.dev/packages/flutter_appauth — configurazione nativa Android/iOS.
- https://pub.dev/packages/flutter_secure_storage — archivio protetto dei token.
