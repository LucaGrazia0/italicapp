# Italic Go 0.8.14 (27)

## Diario e plot

- Il nome scientifico può essere assegnato direttamente sotto la foto con “Scrivi nome”, senza utilizzare una chiave. Suggerimenti offline dalla checklist, testo libero anche se i suggerimenti non sono disponibili. I nomi con cf./cfr./sp./? restano incerti. Nome, ID e grado di identificazione vengono scritti su una copia e sostituiti solo dopo il salvataggio riuscito.
- La provenienza della determinazione manuale è persistita. Un eventuale percorso precedente resta come storico e non viene presentato come dimostrazione del nuovo nome. La scelta di un candidato nella chiave registra invece la provenienza “key”. L’export completo include la provenienza nei dynamicProperties.
- “Identifica specie” è subito sotto la foto, accanto a “Scrivi nome”.
- Menu copia dei plot: “Copia lista in un altro plot” unisce i nomi manuali e quelli determinati dalle foto, senza duplicare ID o nomi già presenti nella destinazione. Abbondanze e note preesistenti restano conservate.
- “Duplica plot” apre il modulo di un nuovo rilievo con lista specie, superficie, substrato e note del modello. Nome e data sono da rivedere. Coordinate, misure GPS e foto non vengono duplicate; abbondanze e note delle specie si copiano solo selezionando l’opzione esplicita.

## Chiavi

- Nell’esito terminale di una specie locale, “Scegli questo candidato” e “Salva percorso” sono affiancati nella barra inferiore. Il pulsante di ritorno al diario resta disponibile dopo la scelta.
- Eliminato il comando inferiore “Indietro · bivio precedente”. Il comando in alto a destra torna al bivio precedente anche riaprendo un percorso salvato.
- Titolo dei pulsanti di salvataggio uniformato a “Salva percorso”. La rimozione di un percorso vuoto mantiene un’etichetta esplicita.
- Scheda specie e confronto del bivio nella fonte sono pulsanti visibili, con sfondo o bordo. Il collegamento al dizionario è rimosso da questa sezione della chiave.

## Mappe online

- Tutte le mappe mantengono il nord in alto: trascinamento e zoom restano disponibili, rotazione disabilitata.
- Ricerca esplicita per località (città, paesi, monti e luoghi indicizzati in OpenStreetMap) con Photon/komoot. Richieste serializzate, intervallo minimo e cache in memoria. Nessuna ricerca a ogni carattere; non si inviano coordinate del dispositivo o dati del diario per cercare il nome di un luogo. Gli errori lasciano disponibile la mappa precedente.
- Il risultato di ricerca sposta solo la vista. La scelta del punto o dei due angoli dell’area rimane esplicita e non altera una misura GPS automaticamente.
- Selettore Mappa/Satellite su ritrovamenti, scelta posizione e filtro area. Fonte satellitare Esri World Imagery con attribuzione visibile. Le verifiche di connessione della selezione posizione usano il livello effettivamente selezionato.
- In “I tuoi ritrovamenti”, il filtro diario precede la selezione dei colori. La mappa resta esplorabile anche se i filtri non restituiscono punti.
- Queste mappe e la ricerca richiedono internet; chiavi, diario e dati scientifici locali continuano a funzionare offline.

## Fonti e verifiche

Photon, documentazione ufficiale e condizioni del server dimostrativo:
https://github.com/komoot/photon
https://photon.komoot.io/
Dati geografici OpenStreetMap, ODbL: https://www.openstreetmap.org/copyright

World Imagery, servizio e attribuzione verificati:
https://services.arcgisonline.com/ArcGIS/rest/services/World_Imagery/MapServer?f=pjson
https://www.arcgis.com/home/item.html?id=10df2279f9684e4a9f6a7f08febac2a9
Attribuzione restituita dal servizio: Source: Esri, Vantor, Earthstar Geographics, and the GIS User Community.
Ricerca di prova “Paneveggio”: risposta GeoJSON valida. Tessera satellitare: risposta HTTP 200, image/jpeg.

Le prove automatiche controllano riapertura dei dati salvati, tentativi falliti, fusione senza perdita dei dati di destinazione, duplicazione senza foto/GPS, assegnazione manuale, posizione dei pulsanti, ritorno al bivio dai percorsi salvati, assenza della rotazione, selettore satellitare e ricerca attivata solo dall’utente. Le compilazioni non includono dati dimostrativi del diario.

L’IPA rimane non firmata e richiede firma e provisioning Apple per essere installata. L’inoltro alle applicazioni esterne e l’acquisizione GNSS restano da verificare su telefoni fisici.
