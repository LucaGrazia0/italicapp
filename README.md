# italicapp

Diario di campo per licheni in Flutter Web: foto, coordinate GPS e note salvate nel browser,
checklist ITALIC locale e confronto spiegabile dei criteri ecologici.

## Avvio

Con Flutter installato e disponibile nel PATH:

```sh
flutter pub get
flutter run -d chrome
```

La pagina ITALIC permette di cercare nomi e sinonimi, filtrare per regione, fascia,
substrato, forma di crescita, fotobionte, strategia riproduttiva e tutte le sei scale
ecologiche. Attivando «Classifica per compatibilità ecologica», i risultati mostrano
il confronto per ogni criterio. Il punteggio non è una probabilità di identificazione.

## Dati ecologici

Lo snapshot contiene 3.588 taxa. L'integrazione del dump ITALIC del 29 settembre 2026
ha recuperato 7.526 intervalli mancanti per 3.585 taxa, conservando descrizioni,
sinonimi e i tre taxa più recenti senza corrispondenza nelle tabelle ecologiche.
Il dump originale contiene anche dati account e rimane fuori dal repository.

Per ripetere l'integrazione con un dump autorizzato:

```sh
python3 tools/import_italic_ecology.py --sql /percorso/italic.sql
```

Lo script legge esclusivamente `ecology1`, `ecology2` e `distribution` senza
eseguire SQL. Non modifica il dump. La checklist aggiornata si trova in
`assets/italic/italic_checklist.json`; il rapporto in `reports/ecology_import.json`.
Conflitti di identità o intervalli non validi bloccano la scrittura dello snapshot.
Le successive esecuzioni sullo stesso snapshot non aggiungono nuovamente gli intervalli.

Le classi sono indici ITALIC, non valori fisici: il pH non è una misura di laboratorio
e la distribuzione altitudinale usa classi 1–6, senza convertirle in metri.

## Verifica

```sh
python3 -m unittest discover -s tools/tests -v
flutter analyze
flutter test
flutter build web --no-pub --no-wasm-dry-run
python3 tools/prepare_offline_web.py
```

La determinazione morfologica completa e il riconoscimento fotografico non fanno parte
del motore ecologico. Il sottoprogetto `morphology_extractor` prepara dati morfologici
da sottoporre a revisione specialistica.

## Compatibilità e dati mancanti

- Filtri: tutti i criteri selezionati devono coincidere; l'opzione «Includi taxa con
  dati ecologici mancanti» permette di mantenere anche i casi non valutabili.
- Classifica: conserva i candidati e ordina prima per evidenze positive, poi per minori
  contraddizioni e maggiore copertura. La ricerca per testo e iniziale resta attiva.
- Un taxon non segnalato in una regione è «non documentato», non «assente».
- Una fascia indicata come `absent` è un'evidenza contraria distinta dai dati mancanti
  e partecipa al denominatore del punteggio.
- Il confronto sulle scale include entrambi gli estremi dell'intervallo e gestisce
  anche intervalli di un singolo valore e poleotolleranza 0.

Fonte dei dati: [ITALIC 8.0](https://italic.units.it/).

## Percorsi dicotomici sperimentali

Da **ITALIC → Chiavi di determinazione** si accede senza foto o GPS a:

- **Chiavi · tutti i taxa**: accesso all’albero generale, a un genere già
  riconosciuto o alla ricerca dei percorsi di una specie. Il catalogo comprende
  tutti i 3.588 taxa locali: 3.557 hanno un percorso nella fonte, 31 sono elencati
  come non rappresentati. Sono mantenuti separati anche cinque taxa aggiuntivi
  della fonte, quattro continuazioni interrotte e un esito al gruppo Cladonia
  coccifera. Le alternative generali conservano il testo inglese originale;
  il percorso italiano Physcia rimane disponibile. Le parole dei bivi sono
  richiami al dizionario, senza inferire automaticamente presenze o assenze.
- **Identifica una specie**: percorso adattivo sui 3.588 taxa. Confronta i quattro
  gruppi strutturati, sette gruppi selezionati dai traits API e, quando i candidati
  sono Physcia, i caratteri revisionati manualmente. Puoi saltare le domande,
  correggere le risposte, annullare una modifica e indicare un genere già riconosciuto.
  I candidati con dati insufficienti rimangono possibili. Da 2 a 100 taxa puoi
  preparare e aprire una chiave originale online tramite ITALIC Keymaker, includendo
  anche i candidati incerti. Il limite di 100 è una scelta dell’app, non dell’API.
  Non vengono usati i campi API K e numero di spore per asco, che presentano
  discrepanze. Nessuna proposta del dizionario diventa una conferma automatica.
  Il risultato locale è un profilo da verificare: il nome non viene assegnato al campione.
  Nel gruppo Physcia, **Segui i bivi Physcia nell’app** apre il primo percorso
  ricostruito dalla chiave: 22 taxa, 24 bivi e 25 occorrenze terminali. Le alternative
  sono sintetizzate in italiano e collegano i caratteri codificabili alla matrice,
  mantenendo fonte, condizioni composte e percorsi multipli della stessa specie.
  **Non so** mantiene entrambe le alternative e mostra i taxa rimasti; ogni bivio
  ha un collegamento alla corrispondente pagina ITALIC. Le condizioni dei rami
  non vengono salvate come revisioni dei caratteri.
- **Percorso guidato · 4 caratteri**: selezione preliminare con i quattro gruppi
  strutturati della matrice, con corrispondenze, dati mancanti e fonti.
- **Macrocaratteri**: bivi sulla forma principale del tallo; una risposta positiva
  conclude il gruppo. I taxa con caratteri non documentati restano consultabili
  separatamente. Non si usano dati ecologici per dedurre caratteri morfologici.
- **Flavoparmelia**: confronto pilota delle due specie presenti nella checklist,
  `F. caperata` (978) e `F. soredians` (979), a genere già riconosciuto. I due
  caratteri sono l'aspetto dei soredi e la reazione K della **medulla**. I dati e
  le citazioni sono in `assets/italic/flavoparmelia_key.json`, con stato
  `needs_expert_review`. È una selezione manuale da descrizioni, non una chiave
  originale ITALIC riprodotta o una determinazione scientificamente approvata.
- **Chiavi originali ITALIC**: indice cercabile di 509 collegamenti per genere,
  esportati dal solo campo `Generi_note.chiave`. Sono conservate anche più chiavi
  riferite allo stesso genere. I collegamenti richiedono una connessione.

Ogni bivio propone due alternative e **Non so / Non verificato**. Risposte
discordanti possono lasciare zero candidati; nessuna specie viene forzata.
Le citazioni vengono confrontate con la descrizione locale prima di usare il
carattere: se una descrizione cambia, il carattere diventa non valutabile.
Il **Confronto dei caratteri** affianca le risposte ai dati ITALIC e distingue
coerenza, discordanza, dato mancante e risposta non verificata. Nel pilota sono
consultabili anche i taxa esclusi, con le citazioni che spiegano il conflitto.

Dal diario, aprire un'osservazione e poi **Non determinato** per utilizzare gli stessi
percorsi e salvare l'ultimo percorso nell'osservazione. È possibile riprenderlo e
modificare le risposte. La barra inferiore mostra sempre lo stato del salvataggio.
**Annulla ultima modifica** recupera anche i bivi successivi dopo una correzione o
un riavvio. Dopo **Ricomincia**, il percorso già salvato resta intatto finché non si
preme **Rimuovi percorso salvato**. Il salvataggio non assegna un nome o un rango al campione,
conserva foto e dati GPS e rimane compatibile con osservazioni precedenti.

Per rigenerare esclusivamente l'indice dei collegamenti:

```sh
python3 tools/import_italic_genus_keys.py --sql /percorso/italic.sql
```

Il prototipo usa i dati locali e funziona senza servizi LLM. Per estenderlo ad altri
generi occorre una revisione dei caratteri e dell'ambito delle descrizioni.


## Matrice specie × caratteri

Da **ITALIC → Chiavi di determinazione → Matrice specie × caratteri**:

- 3.588 taxa (incluse entità infraspecifiche) × 25 caratteri;
- 4 colonne di dati strutturati: crescita/tipo biologico, fotobionte, strategia
  riproduttiva prevalente e substrati;
- 4 colonne morfologiche: soredi, isidi, ciglia, rizine;
- 15 colonne chimiche: K, C, KC, P, UV separati per tallo, corteccia superiore e medulla;
- 2 colonne manuali del pilota Flavoparmelia, sempre da revisionare.

La matrice permette ricerca per nome, genere, sinonimo o ID; filtro per gruppo di
caratteri; pagine di 20 taxa; scorrimento orizzontale con nomi fissati a sinistra.
Toccando una cella si leggono valore, stato di revisione, campo sorgente e citazioni.
I valori lunghi possono essere troncati nella griglia e sono interi nel dettaglio.

La matrice canonica è `assets/italic/character_matrix_v2.json`. Le celle omesse sono
**sconosciute**, mai assenze. `recorded` indica un valore codificato, non una
validazione scientifica; `ambiguous` conserva menzioni, alternative e variabilità.
Le estrazioni testuali sono `needs_review` e non alimentano esclusioni automatiche
nelle chiavi. Le reazioni riportano soltanto il segno nella griglia: colori e
sequenze rimangono nella citazione. La corteccia non specificata non viene
trasformata in corteccia superiore; K/I non diventa K.

La generazione è locale, deterministica e non usa un LLM o il dump SQL:

```sh
python3 tools/build_character_matrix.py
```

Il generatore valida ID, nomi, vocabolari e ogni citazione con i suoi offset.
L'app ricontrolla le fonti: celle non più sostenute dai dati vengono sospese;
cambi di identità o copertura richiedono la rigenerazione della matrice.
Le coperture per colonna e i limiti sono in `reports/character_matrix.md`.
Il sottoprogetto `morphology_extractor` rimane separato: il suo riferimento manuale
è un fixture di test, non viene importato come risultato approvato.


## Percorso guidato con i quattro caratteri strutturati

In **ITALIC → Chiavi di determinazione → Percorso guidato · 4 caratteri**,
oppure dal pulsante nell’intestazione della matrice, si confrontano in sequenza:
forma di crescita/tipo biologico, fotobionte, strategia riproduttiva prevalente e
substrato. Ogni passaggio offre **Non so / Non verificato**. Questa risposta non
restringe i candidati. Il percorso è una selezione preliminare del profilo ITALIC,
non una determinazione definitiva né una chiave dicotomica originale pubblicata.

Il motore usa soltanto le quattro colonne `structured_source` della matrice,
con citazione ancora verificabile e valori identici ai codici attuali della
checklist. Supporta sottotipi di crescita, fotobionti principali/secondari,
strategie miste e substrati multipli. I risultati separano corrispondenze,
dati insufficienti e profili diversi/substrati non documentati; ogni taxon mostra
il confronto e le fonti per i quattro passaggi. Non viene dedotta l’assenza di
strutture dalla strategia prevalente, né l’assenza assoluta da un substrato non elencato.

Dal diario sono disponibili salvataggio, ripresa, modifica, annullamento e
riavvio reversibile. Il salvataggio sostituisce l’ultimo percorso
nell’osservazione, mantenendo foto, GPS, note e identificazione. I vecchi percorsi
binari sono ancora leggibili: le nuove scelte usano il campo opzionale `selections`.

I restanti caratteri della matrice non partecipano a questo percorso. Per la
loro futura integrazione consultare `reports/characters_to_keys.md`.

## Revisione manuale pilota · Physcia

Da **ITALIC → Chiavi di determinazione → Physcia · revisione e prova** oppure dal
pulsante «Revisiona Physcia» della matrice si accede a 22 taxa × 27 caratteri:
presenza di soredi, sorali, isidi veri, ciglia e rizine; forma e posizione dei sorali;
consistenza dei soredi; forma degli isidi; tipo di ciglia e rizine; tipo e forma
degli apoteci, inserzione e pruina del disco; tipo di tallo, colori delle due superfici e della medulla; larghezza
descritta, forma, profilo e portamento dei lobi; adesione e contorno del tallo;
pruina e macule della superficie superiore. Ogni campo Physcia della matrice offre «Revisiona questa cella».
Le proposte sono calcolate dal dizionario corrente sulle descrizioni originali,
con la stessa decisione conservativa usata dal rapporto automatico. Le proposte
univoche precompilano valore e citazione; i casi ambigui restano incerti e mostrano
le evidenze da controllare. Le modifiche salvate hanno sempre precedenza, anche
se sono bozze o indicano un valore incerto. «Usa proposta come bozza» permette
di riprendere esplicitamente una proposta senza confermarla o salvarla.

La tabella carica automaticamente l'ultima modifica salvata per ogni cella e
mostra valore, stato e autore, anche per le bozze. Si aggiorna al ritorno dal
modulo di revisione e alla riapertura. La vista comprende 48 colonne: le 25
iniziali più i ventitré campi aggiuntivi di morfologia e colore. Le modifiche restano nel registro
persistente del browser, separato dall'asset originale, e non vengono perse
rigenerando l'asset. Se il registro non è accessibile compare un avviso esplicito.
Il pulsante con l'icona tabella nell'area Physcia apre la matrice aggiornata.
La scelta **Assente** può essere salvata senza citazione e senza motivazione:
è una valutazione manuale dell'autore. Se viene inserita una citazione, deve
comunque corrispondere alla descrizione. L'estrattore non genera automaticamente
assenze dalle informazioni mancanti. Anche per questo valore il filtro della
chiave richiede lo stato Revisionato manualmente.
Per **Apoteci · tipo** sono disponibili Lecideini, Lecanorini, Biatorini, Assenti, Variabile,
Altro tipo e Non documentato/incerto. Le proposte dalle descrizioni conservano
anche qualificatori come «very rare» e non diventano revisioni automatiche.

L'estrattore riconosce anche **soralia** e **soralium** per proporre soredi
presenti, conservando frase e offset della fonte. Negazioni, confronti e
condizioni restano da chiarire; l'assenza dei sorali non viene tradotta in
assenza dei soredi. La rigenerazione delle proposte non sovrascrive le modifiche
manuali già salvate nel browser.
Per **Ciglia** riconosce i termini inglesi **cilia** e **cilium**, mantenendo
distinte presenza, assenza esplicita, strutture simili e casi da chiarire.

**Struttura assente → forme e tipi dipendenti non applicabili.**
Soredi assenti disattivano forma/posizione dei sorali e consistenza dei soredi;
isidi, ciglia o rizine assenti disattivano i relativi tipi; apoteci assenti
disattivano la forma degli apoteci. La matrice
e l'area Physcia mostrano automaticamente questo stato e non richiedono di
compilare i campi dipendenti. La revisione della struttura è la fonte della dipendenza:
anche una bozza rende visibili i campi non applicabili, ma non conferma un
criterio diagnostico. Le versioni precedenti di forma/posizione sono conservate
e tornano disponibili cambiando la presenza dei soredi. Incerto/variabile non
viene trasformato in non applicabile. Il salvataggio impedisce nuove forme o
posizioni finché i soredi restano registrati come assenti, anche da altre schede.
Nella prova della chiave, scegliere soredi assenti azzera e disattiva forma e
posizione; una loro forma specifica non corrisponde a taxa con soredi revisionati
come assenti. Bozze o fonti cambiate non eliminano candidati.

Ogni cella mostra la proposta e consente di inserire un valore, una citazione
esatta, autore/iniziali, note e stato della revisione. La descrizione integrale
e le note ITALIC sono consultabili nella stessa pagina. Valore e stato sono
separati: **Bozza**, **Da chiarire**, **Revisionato manualmente**. Il default è
sempre Bozza, anche quando si riedita una revisione precedente. Non sono state
precaricate revisioni manuali approvate e il nome inserito non è autenticato.

Il registro `italicapp_character_reviews` è separato dalle osservazioni e
conserva versioni append-only, autore, data UTC, citazione, descrizione e note
sorgente. Salvataggi concorrenti basati su una versione superata vengono
rifiutati senza sovrascrivere le revisioni. La cronologia permette di riprendere
una versione come nuova bozza. Il pulsante Backup JSON rende copiabile l'intera
cronologia; va incollata e salvata in un file per conservarla fuori dal browser.
Il backup non viene caricato su servizi esterni. In questa versione non è
presente un comando di importazione del backup.

La **prova libera della chiave revisionata** richiede il genere già riconosciuto.
Usa soltanto l'ultima revisione manuale di ogni cella, con valore stabile,
citazione valida e descrizione/note immutate. Bozze, stati da chiarire, variabili,
altri stati non codificati, celle mancanti o fonti cambiate rimangono non valutabili.
Una bozza successiva sospende il valore precedente: non viene recuperata una
vecchia conferma. I taxa non valutabili restano visibili tra le possibilità.
La prova usa i dati locali correnti, non assegna specie e non salva un percorso
nell'osservazione. Le revisioni manuali non costituiscono certificazioni scientifiche.

Le revisioni sono locali al browser e all'origine: usare lo stesso indirizzo e
la stessa porta per ritrovarle. L'anteprima di riferimento resta `http://127.0.0.1:8765/`.
Il rapporto di verifica è `reports/physcia_review_validation.md`.

### Tallo, colori e lobi

I dodici nuovi campi leggono la descrizione per struttura: superficie superiore
o lobi, superficie inferiore e medulla. Le caratteristiche di ciglia, rizine,
sorali, apoteci e anatomia sono tenute fuori dai colori delle superfici; il
colore delle macule e della pruina non diventa quello del tallo. Le sezioni
Spot tests/Chemistry e le formule dei reagenti non forniscono colori naturali.

Per colori, forme e profili è possibile selezionare più stati documentati:
«foliose to subfruticose» conserva foglioso e subfruticoso; «flat to slightly
convex» conserva piatto e convesso. La citazione conserva sfumature, intensità
e localizzazioni. I qualificatori condizionali restano da controllare, mentre
la mancata menzione non genera un'assenza. I millimetri rimangono nel testo:
la classe «lobi stretti» viene proposta solo se è esplicitamente descritta.

Il salvataggio mantiene il modello precedente: i valori multipli sono codificati
nel campo `value` come identificatori separati da `|`; non cambia lo schema del
database e i record già salvati rimangono leggibili. La matrice mostra tutti gli
stati. Nella prova della chiave, solo una revisione manuale stabile può filtrare:
una scelta corrisponde se è compresa tra gli stati registrati. Il rapporto JSON
esporta anche `suggestedValues` per rendere esplicite le combinazioni.

## Dizionario dei caratteri

Da **ITALIC → Chiavi di determinazione → Dizionario dei caratteri** si consultano
27 gruppi di termini italiani/inglesi: presenza di soredi, sorali, isidi, ciglia e rizine;
forma e posizione dei sorali; aspetto dei soredi; forma degli isidi; forme/tipi
di ciglia e rizine; tipo, forma e inserzione degli apoteci, pruina del disco; tallo, colori, lobi, pruina
e macule. Si può incollare una descrizione
e cercare termini come `soralia`, `simple`, `squarrose` o `labriform`.

Il vocabolario modificabile è `assets/italic/character_dictionary_v3.json`.
Contiene sinonimi, singolari/plurali, tipi e contesto richiesto. Le proprietà
`matrixTerms` e `matrixImpliedTerms` guidano anche l'estrattore della matrice.
Le altre varianti e forme sono aiuti alla revisione: non nuovi dati validati.

Il pulsante **Cerca termini, forme e tipi nella descrizione** nel modulo di
revisione apre la fonte originale e filtra i concetti collegati. **Usa citazione
come bozza** copia la frase e aggiunge l'eventuale forma/tipo alle note, senza
cambiare automaticamente il valore della cella. Il successivo salvataggio
conserva citazione e note nel registro delle revisioni. I 27 concetti del
dizionario sono ora anche campi strutturati della revisione Physcia: per salvarne un tipo come valore apri
la relativa cella (per esempio «Tipo di rizine»).

Descrittori come `capitate` o `branched` vengono associati al contesto della
struttura, evitando altre strutture interposte. Negazioni, confronti e più
stati nella stessa frase rimangono segnalati per il controllo umano. La ricerca
non è un'analisi linguistica completa e l'assenza di risultati non dimostra
assenza della struttura. Le fonti terminologiche sono consultabili nella pagina.

### Lettura automatica delle Physcia

Nell'area **Physcia · revisione e prova**, il pulsante **Riesamina le Physcia
con il dizionario** confronta le descrizioni dei 22 taxa con i 27 caratteri e le
ultime revisioni salvate. I filtri separano proposte disponibili, valori da
confrontare, testi incerti, caratteri non documentati e valutazioni concordanti.
Ogni risultato apre la relativa revisione: non salva né approva automaticamente.
Le valutazioni manuali restano prioritarie e le fonti cambiate sono segnalate.

La lettura distingue la pruina della superficie superiore da quella del disco
e l'inserzione degli apoteci dalla loro forma. «Apothecia very rare» descrive la
frequenza e non rende incerto un tipo esplicito come «lecanorine»; qualifiche
come «sometimes pruinose» restano invece da chiarire. I sorali assenti rendono
non applicabili forma e posizione, senza implicare da soli l'assenza dei soredi.


`dart tools/analyze_physcia_dictionary.dart` applica lo stesso motore del
dizionario alle descrizioni dei 22 taxa Physcia. Produce
`reports/physcia_dictionary_proposals.md` e il corrispondente JSON con citazioni,
termini e offset. Sono proposte di lavoro, non revisioni approvate: lo strumento
non accede all'archivio delle revisioni dell'utente e non ne modifica i record.
I risultati distinguono stati esplicitamente documentati secondo le regole, casi da controllare e
assenza di riscontri nel vocabolario attuale. I conteggi misurano copertura,
non accuratezza scientifica.


## Matrice dei traits da ITALIC API

Da **ITALIC → Chiavi di determinazione → Matrice dei traits · ITALIC API** si
consulta la raccolta per tutti i 3.588 taxa locali. La vista ha 31 colonne: 29 stati
restituiti dall’API (tallo, fotobionte, ascocarpi, apoteci, ascospore e reazione K)
e due indicazioni della strategia riproduttiva nella checklist locale.

La vista permette ricerca per nome, sinonimo o ID, selezione dei gruppi,
paginazione e filtro dei taxa con segnalazioni. Ogni cella apre valore originale,
campo API, fonte, data di acquisizione ed eventuali contrasti con la descrizione
locale. I controlli testuali coprono il numero di spore per asco e alcuni casi di
reazione K: nessuna segnalazione non significa verifica scientifica completa.

Questa raccolta è separata dalla matrice di revisione: non modifica le valutazioni
salvate e non alimenta automaticamente la chiave. Zero significa stato non
selezionato nella fonte; dati mancanti o non interpretabili restano null (`?`).
Non si deduce l’assenza di un organo da uno zero riferito al suo tipo.

Il file locale è `assets/italic/api_traits_matrix_v2.json`. Le risposte originali,
la riconciliazione delle identità e il rapporto sono in `reports/italic_api_traits/`.
La raccolta si riprende dalla cache con:

```sh
python3 tools/probe_italic_traits_api.py --all --interval 0.25
python3 tools/probe_italic_traits_api.py --all --offline --write-app-asset
```

L’intervallo di 0,25 secondi resta sotto le 50 richieste ogni 10 secondi dichiarate
dall’OpenAPI 1.1.0 verificata per questa raccolta. Le risposte 429 e gli errori
transitori hanno tentativi limitati. Una nuova raccolta richiede comunque verifica
delle identità e dei limiti correnti della fonte.

Il gruppo **Riproduzione** riporta «soredi o strutture simili» per 516 taxa e
«isidi o strutture simili» per 130. Si usano i codici ecologici `A.s`, `S-A.s`
e `A.i` già presenti nella checklist importata. Le altre strategie restano `?`
per queste due indicazioni; non diventano assenze. I valori non sono trasferiti
nei campi soredi veri o isidi veri e non cambiano le revisioni salvate. I dettagli
mostrano la citazione e la data dell’importazione ecologica locale, distinta
dalla data delle risposte API. Una fonte locale cambiata sospende l’indicazione.

Per l’inventario degli altri dati disponibili ma non ancora inseriti nella
matrice consulta `reports/italic_api_traits/reproduction_and_data_inventory.md`.


## Chiavi: caratteri iniziali e uso offline

In **ITALIC → Chiavi di determinazione → Chiavi · tutti i taxa** puoi scegliere
facoltativamente forma del tallo/tipo biologico, fotobionte e substrato, oltre al
genere già riconosciuto. Il numero dei candidati si aggiorna prima di partire.
I confronti usano le tre colonne strutturate documentate della matrice: un dato
mancante o non verificabile mantiene il taxon. Il substrato confronta il profilo
documentato, senza dimostrare un’assenza assoluta. Le continuazioni irrisolte
della fonte restano disponibili; il filtro non inventa percorsi per i taxa
senza percorso. Colori, soredi/isidi e altre estrazioni non revisionate non
vengono convertiti in esclusioni automatiche.

La chiave ridotta salta i rami esclusi e conserva i riferimenti ai bivi originali.
**Indietro** torna al bivio precedente anche dopo la riapertura di un percorso
salvato. Dal primo bivio torna alla selezione iniziale. Quando salvi nell’osservazione
si conservano anche genere e filtri iniziali; il nome della specie non viene
assegnato automaticamente.

Nelle **Impostazioni** e nella pagina delle chiavi trovi **Prepara uso offline**.
Attendi **Copia offline pronta su questo browser** prima di partire. Il pacchetto
comprende app, renderer, font Roboto locali (licenza in assets/fonts), checklist,
chiavi, matrici e dizionario; ogni risorsa viene verificata prima di dichiarare
completo il download. Apri lo stesso indirizzo nello stesso browser. La pulizia
dei dati del sito o lo spazio insufficiente possono rimuovere la copia. Lo stato
controlla anche l’eventuale mancanza di risorse già scaricate. Le osservazioni e
le revisioni rimangono nell’IndexedDB esistente: il pacchetto non è un backup.

Le pagine e le immagini esterne ITALIC, nuove descrizioni e la creazione di chiavi
sul servizio remoto richiedono internet. Per questa anteprima, localhost indica
il computer su cui gira l’app: per il telefono occorre pubblicare l’app su HTTPS
o installarne una build adatta al dispositivo.

Per ogni build web esegui anche `python3 tools/prepare_offline_web.py` dopo la
compilazione Flutter: genera il service worker con versione e impronte delle
sole risorse necessarie, escludendo vecchi file e duplicati della cartella build.
Servi su localhost o HTTPS. `flutter run` da solo non prepara questo pacchetto.

Verifiche: `flutter test --no-pub`, `python3 -m unittest discover -s tools/tests`
e `node --test tools/tests/offline_worker.test.mjs`. La prova browser del
2 novembre 2026 ha riaperto la checklist e la chiave filtrata dopo lo spegnimento
del server isolato di prova, senza modificare i dati del sito principale.

## APK Android

La cartella `android/` contiene la configurazione nativa. L'app usa la directory
privata di supporto Android per osservazioni, foto, percorsi e revisioni, con lo
stesso schema dei repository web. Il web continua a usare IndexedDB. I dati del
browser non vengono copiati automaticamente nell'installazione Android.

Le otto raccolte scientifiche e i font sono inclusi nell'APK: per consultare
checklist, matrici, dizionario e bivi non occorre scaricare un pacchetto offline
aggiuntivo. I servizi esterni ITALIC richiedono ancora connessione. GPS e
fotocamera richiedono i permessi del telefono; non viene richiesta localizzazione
in background. Il salvataggio nativo viene verificato con
`test/native_storage_test.dart`, inclusa la riapertura dei file, i byte della foto
e la cronologia delle revisioni.

Per generare un APK di prova con Flutter e Java configurati localmente:

```sh
flutter pub get
flutter test --no-pub
flutter build apk --release --no-pub
```

La configurazione corrente ottimizza la build release e usa la firma Android di
sviluppo esistente: è destinata alle prove e all'installazione diretta, non alla
pubblicazione sullo store. Nessuna nuova chiave privata di produzione è stata
creata. Il file preparato per la consegna è
`dist/Italicapp-0.8.5-Android.apk`, con la relativa impronta SHA-256.
La cartella `dist/` e il materiale di firma sono esclusi da Git.

### Scelta del candidato dal diario

Nelle chiavi aperte da un'osservazione, **Scegli questo candidato** salva
esplicitamente il nome e il livello specie, insieme alle risposte correnti del
percorso. Foto, coordinate, quote, data e note rimangono conservate. Un errore di
scrittura mantiene il nome e il percorso precedenti. Le risposte ai bivi da sole
continuano a non assegnare una specie. La lista **Specie rimaste** segue il ramo
corrente, offre ricerca e paginazione e conserva i candidati quando si risponde
Non so; i rami irrisolti sono distinti dai nomi selezionabili.

Dal menu principale sono state rimosse, con approvazione dell'utente, le voci
**Macrocaratteri**, **Percorso guidato · 4 caratteri** e **Flavoparmelia · 2 specie**.
I vecchi percorsi salvati si possono ancora riprendere. Matrici, dizionario,
revisione Physcia e collegamenti alle chiavi originali rimangono disponibili.

### iPhone: app web dalla schermata Home

La versione web è predisposta per l'installazione dalla Home tramite Safari,
con icona, nome, modalità standalone e copia offline verificata. In Impostazioni
sono spiegati i passaggi e l'anteprima locale è distinta da un link pubblicato.
Un indirizzo `127.0.0.1` sul Mac non rende l'app raggiungibile dall'iPhone:
per la distribuzione serve un host statico HTTPS.

Per preparare un pacchetto destinato, ad esempio, al percorso `/italicapp/`:

```sh
flutter build web --no-pub --no-wasm-dry-run --base-href /italicapp/ --output build/iphone-web
python3 tools/prepare_offline_web.py build/iphone-web
python3 tools/package_iphone_web.py build/iphone-web dist/Italicapp-iPhone-web.zip
```

Il pacchetto contiene soltanto risorse verificate dell'app e il service worker:
non comprende APK, osservazioni personali o vecchi file rimasti nella build.
Non è un IPA e non si installa aprendo lo ZIP sull'iPhone. I file vanno serviti
all'indirizzo HTTPS e al percorso scelto durante la compilazione. Per un sito
alla radice usare invece `--base-href /`.

Dopo la pubblicazione: aprire il link in Safari su iPhone, usare Condividi →
Aggiungi alla schermata Home e riaprire dall'icona. In quella stessa app toccare
Impostazioni → Prepara uso offline, attendere la conferma e verificare la
riapertura in modalità aereo. I dati del Mac non sono trasferiti automaticamente;
la copia delle risorse non è un backup del diario. Foto e GPS vanno verificati
su un iPhone reale, concedendo i relativi permessi quando richiesti.

La distribuzione nativa tramite TestFlight o App Store resta una procedura
separata: richiede Xcode, un progetto iOS e la configurazione di firma Apple.
Non è stato prodotto né firmato alcun IPA.

### Condivisione dei risultati (0.8.4)

Dalla singola osservazione usare l'icona Condividi; per esportare più record
aprire Impostazioni → Condividi ed esporta risultati. Si possono selezionare le
osservazioni e scegliere riepilogo testuale, CSV, GeoJSON o CSV con termini
Darwin Core (non un Darwin Core Archive). Coordinate, quote e accuratezza GPS
sono escluse inizialmente e si includono con una scelta esplicita. La foto si
può allegare per una singola osservazione; i suoi metadati originali possono
contenere posizione indipendentemente dai campi GPS esportati.

La condivisione usa il menu del dispositivo tramite share_plus; nei browser
senza supporto alla condivisione dei file viene avviato un download. Il
riepilogo si può anche copiare. I file tabellari conservano il percorso salvato;
il GeoJSON usa longitudine prima della latitudine e, senza GPS, geometrie nulle.
Il diario non viene modificato. Le determinazioni esportate rimangono da
verificare. La copia offline non costituisce un backup delle osservazioni.

Verifica: 153 test Flutter superati, analisi senza rilievi, APK compilato e firma
di sviluppo esistente verificata; nessuna prova fisica sul telefono effettuata.
Riferimenti: https://pub.dev/packages/share_plus e https://dwc.tdwg.org/terms/.

### Foto dalla galleria e icona Android (0.8.5)

In Fotocamera i comandi **Scatta foto** e **Scegli dalla galleria** aprono
rispettivamente la fotocamera e il selettore di immagini del dispositivo.
L'annullamento o un errore non cancellano la foto già scelta. Se Android
ricrea l'attività durante la selezione, al riavvio viene controllato il risultato
recuperabile tramite `retrieveLostData`; la foto può poi essere salvata insieme
a GPS e note. La galleria usa image_picker_android 0.8.13+25, già presente nel
lockfile, senza richiedere accesso generale ai file del telefono.

L'icona Android deriva dall'immagine fornita dall'utente, conservata in
`assets/branding/italicapp-logo-original.png` senza modifiche. Le risorse
launcher mantengono le proporzioni e il disegno completo su fondo bianco;
Android 8 e successivi usano i livelli dell'icona adattiva, Android 7 le PNG
alle cinque densità. Il manifest punta a `@mipmap/ic_launcher`.

Verifica 0.8.5: 157 test Flutter superati, analisi senza rilievi. I test delle
foto coprono sorgente galleria/fotocamera, annullamento, errore, recupero Android,
uscita dalla pagina e salvataggio nel diario. La prova fisica sul telefono
rimane da effettuare.


### Rilievi, prefiltri e aggiornamenti (0.8.6)

In Android **Rileva posizione** richiede la posizione precisa e acquisisce nuove
misure dal ricevitore satellitare per un massimo di 35 secondi. Mostra accuratezza
orizzontale, satelliti usati quando disponibili e accuratezza verticale. La quota
**m s.l.m.** è distinta dalla misura sull’ellissoide WGS84. La conversione usa
AndroidX AltitudeConverterCompat 1.0.1 e il modello geoidico incluso nell’APK:
non richiede una connessione. Se manca una quota convertibile, l’app lo indica.
Le vecchie osservazioni conservano il valore originale senza rietichettarlo
come quota sul livello del mare. La ricezione e la precisione effettive vanno
provate all’aperto su un telefono Android reale.

In **Chiavi · tutti i taxa**, la sezione unica **Caratteri del campione** confronta
31 stati (29 API e 2 indicazioni riproduttive) con i taxa dell’albero. Si possono
combinare con genere e substrato, senza ripetere tallo e fotobionte in due zone. Una cella
attendibile discordante esclude il taxon e i rami che non hanno più candidati;
valori mancanti, descrizioni cambiate e conflitti pertinenti al carattere
mantengono i candidati come incerti. Per soredi/isidi, la strategia riproduttiva
non dimostra l’assenza: le celle sconosciute non vengono convertite in “no”.
Nei gruppi si scelgono direttamente i tipi tramite pulsanti, senza menu annidati. Cambiare tipo sostituisce la scelta precedente e non assegna assenze ai tipi non selezionati. Ogni gruppo mostra un riepilogo delle scelte; un solo conteggio e un pulsante avviano la chiave con tutti i filtri. I vecchi percorsi con i precedenti filtri restano riapribili. I filtri sono conservati nel percorso del diario. Le alternative A/B sono
presentate in schede con conteggi, il totale resta in alto e dopo una scelta,
Indietro o Annulla il bivio corrente torna in vista.

In **Impostazioni → Aggiornamenti ITALIC**, **Controlla aggiornamenti** legge
il manifesto della release GitHub più recente. **Scarica dati offline** verifica
dimensione, SHA-256, struttura e coerenza dei singoli archivi prima di attivare
l’intero pacchetto in una transazione. Se il download fallisce resta attiva
l’edizione precedente. Il pacchetto contiene soltanto gli otto archivi
scientifici; diario, foto e revisioni sono conservati nel loro archivio separato.
Le edizioni delle chiavi già usate vengono archiviate localmente, e i percorsi
salvati si riaprono con l’edizione originaria. L’aggiornamento dell’APK rimane
separato e può essere proposto tramite un collegamento alla nuova versione.

Le modifiche del sito ITALIC non si trasformano automaticamente in una nuova
release dell’app: prima occorre acquisire, verificare e impacchettare dati e
chiavi coerenti. Per preparare un pacchetto, senza pubblicarlo:

```sh
python3 tools/prepare_data_update.py --revision 2026110301 --version 0.8.6 \
  --output dist/data-update-0.8.6 \
  --release-url https://github.com/LucaGrazia0/italicapp/releases/download/v0.8.6
```

Le edizioni successive devono avere una revisione numerica crescente. Pubblicare
`italicapp-data.json` e `italicapp-data-manifest.json`, insieme all’APK se presente,
come allegati della stessa release GitHub accessibile pubblicamente. Il manifesto
limita i dati all’app compatibile (build minima 19). La repository GitHub è privata: gli allegati delle Release si scaricano da GitHub
con un account autorizzato. Il pulsante nell’app interroga il canale pubblico e
non può vedere le Release private (GitHub risponde 404). Per distribuire futuri
aggiornamenti direttamente nell’app occorre un canale accessibile ai dispositivi
o un sistema di autenticazione dedicato; non inserire credenziali GitHub nell’APK.

Verifica 0.8.6: 169 test Flutter superati e analisi senza rilievi. Inclusi test
su filtro effettivo dei rami, conflitti, scorrimento su telefono, aggiornamento
persistente offline, conservazione di diario e chiave storica, separazione delle
quote e consenso GPS negli export. Anteprima visiva controllata. Nessuna misura
GNSS effettuata su un telefono fisico.
Riferimento conversione: https://developer.android.com/reference/androidx/core/location/altitude/AltitudeConverterCompat


### Navigazione essenziale (0.8.7)

In ITALIC il pulsante **Chiavi di determinazione** è ora un comando principale
verde subito sotto il titolo, prima della ricerca e dei filtri del catalogo.
Il menu mette in primo piano **Chiavi · tutti i taxa**. **Riprendi il percorso
salvato** resta visibile quando l'osservazione contiene una determinazione.

**Strumenti e dati**, chiuso inizialmente, raccoglie Identifica una specie,
Physcia · revisione e prova, Matrice specie × caratteri, Matrice dei traits,
dizionario e chiavi originali online. Le matrici hanno fonti e funzioni diverse;
la revisione Physcia conserva modifiche, evidenze e controllo dei caratteri.
Il percorso alternativo di confronto dei caratteri resta accessibile, insieme
alla ripresa delle determinazioni salvate nelle versioni precedenti.
La chiave generale rimane apribile anche se il caricamento degli strumenti
aggiuntivi non riesce.

Verifica: 172 test Flutter superati, analisi senza rilievi e controllo visivo
del comando ITALIC e del menu semplificato. La Release GitHub 0.8.6 rimane
invariata; la 0.8.7 è una nuova build locale finché non viene pubblicata.
