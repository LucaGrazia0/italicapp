# Italic Go 0.8.13 (26)

Checkpoint precedente: tag GitHub v0.8.12, commit e715b64f40277acf37fa79fb85d49243f0033e2f.

- Plot: condivisione Excel/CSV e ZIP con foto; eliminazione con scelta ogni volta fra conservare le foto nel diario e rimuoverle. La rimozione completa richiede una seconda conferma. Un registro locale permette di completare la scelta anche dopo un’interruzione; conservando le foto restano data, substrato e posizione ereditata del rilievo con provenienza esplicita.
- Traguardi: sei immagini originali fornite dall’utente, legno/Cesi 1, bronzo/Anzi 10, argento/Massalongo 50, oro/Cengia Sambo 100, platino/Acharius 500, diamante/Nimis 1000. Conteggio di specie determinate distinte, risolte nella checklist locale.
- Mappa: colori per determinazione, forma di crescita ITALIC o substrato effettivamente annotato. Punti coincidenti con categorie diverse mostrano settori colorati, non una classificazione maggioritaria. Valori mancanti restano espliciti.
- Diario: intervallo di date inclusivo, regioni italiane e rettangolo selezionato sulla mappa online. Stessi filtri per mappa ed esportazione. I plot usano data e posizione del rilievo.
- Excel reale Office Open XML: fogli Occurrences, Plots, Lista specie plot e Campi. CSV UTF-8 con BOM e separatore virgola. Testo potenzialmente interpretabile come formula neutralizzato; nessuna formula generata. Riferimenti foto relativi ai file nel ZIP opzionale. Coordinate e quote sono opt-in; le immagini originali possono contenere propri metadati.
- Condivisione con iNaturalist: menu nativo di condivisione immagini, un’immagine per invio; accesso e pubblicazione gestiti dall’app ricevente. Nessun account condiviso, token o password in Italic Go. Scheda completa DoLichens/Darwin Core copiabile nelle note di ciascuna foto; pacchetto ZIP con Excel, CSV DoLichens, CSV adattato ai campi iNaturalist, schede testuali e foto. I campi senza equivalente iNaturalist restano nella description come testo, non diventano automaticamente Observation Fields. I percorsi locali non allegano foto al CSV: associazione manuale dopo l’importazione web, con controllo dei nomi e dei possibili duplicati. Riepilogo copiabile a parte perché specie/data/posizione del diario non sono trasferite con certezza dal sistema operativo. Su iPhone la nuova app iNaturalist supporta il ricevimento immagini, Classic no. Browser: download dell’immagine e collegamento al caricamento sul sito. Non viene effettuato un POST alle API di pubblicazione.

## Fonti e attribuzioni

DoLichens, elenco e significato dei campi: https://italic.units.it/dolichens/?c=60&procedure=base&t=59
Darwin Core: https://dwc.tdwg.org/terms/
`substratum`, `specific_substratum`, `data_type` sono estensioni DoLichens, non termini Darwin Core. Provincia/comune non vengono inventati. La quota esportata è sul livello del mare, mai la quota ellissoidica grezza. Le abbondanze senza metodo dichiarato non vengono convertite in individui o percentuali.

Regioni: Istat, Confini amministrativi generalizzati al 1 gennaio 2026, CC BY 4.0. Trasformati da WGS84 UTM32N a EPSG:4326, coordinate arrotondate a sei decimali; conservati anelli, isole e fori. Uso statistico, indicativo vicino ai confini. Calcolo sul dispositivo, nessun invio di coordinate per attribuire la regione.
https://www.istat.it/notizia/confini-delle-unita-amministrative-a-fini-statistici-al-1-gennaio-2018-2/
https://www.istat.it/storage/cartografia/confini_amministrativi/generalizzati/2026/Limiti01012026_g.zip

iNaturalist, confronto ufficiale fra app iPhone:
https://inaturalist.freshdesk.com/en/support/solutions/articles/151000216149-what-s-the-difference-between-inaturalist-and-inaturalist-classic-
API e autenticazione (valutate, non necessarie per la condivisione nativa scelta dall’utente):
https://www.inaturalist.org/pages/api+reference
https://www.inaturalist.org/pages/api+recommended+practices

## Limiti di verifica

La disponibilità di iNaturalist nel menu e l’importazione effettiva dipendono dall’app ricevente installata: vanno provate su telefoni fisici. Le verifiche automatiche controllano i file immagine, il tipo MIME, il riepilogo e l’apertura della condivisione, senza pubblicare osservazioni. L’IPA generata dalla compilazione resta non firmata e richiede firma/provisioning Apple per l’installazione.

Ultime richieste: nel diario filtro e condivisione sono icone affiancate; nelle pagine di acquisizione, osservazione e plot GPS e mappa sono sulla stessa riga.
