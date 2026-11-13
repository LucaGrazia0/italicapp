# Italic Go 0.8.17 · build 31

- Nuova icona con il mosaico di licheni e la scritta ITALIC GO su Android, iPhone e web. Lo stesso originale è ridimensionato per le diverse icone; il livello adattivo Android mantiene il testo nell’area visibile. L’immagine condivisa dentro Flutter è WebP per contenere il peso.
- Le medaglie vengono registrate come sbloccate al salvataggio, ma la celebrazione viene mostrata soltanto quando il diario è di nuovo visibile, senza altri pannelli o pagine aperti. La scelta della specie e l’uso delle chiavi non vengono interrotti.
- Dopo foto e posizione si può scegliere una specie dalla checklist prima di salvare. La scelta rimane nella bozza e viene salvata insieme a foto, coordinate e note; un errore di scrittura conserva la bozza.
- Le schede del diario permettono di scegliere o cambiare specie direttamente dalla lista, cercando per nome, sinonimo o ID ITALIC. La stessa lista è disponibile nella scheda dell’osservazione. Restano la chiave e l’inserimento libero del nome.
- Nome scientifico, ID, livello e origine manuale vengono salvati senza alterare foto, dati GPS, incertezza o storico della chiave. Annullamento e scritture fallite non sostituiscono il nome precedente.
- Snelliti titolo del diario, istruzioni ripetute sul GPS, messaggi di salvataggio e indicazioni duplicate sulla determinazione. Conservate le informazioni necessarie su quota, precisione, incertezza e dati mancanti.

L’apertura animata, le sei medaglie, le chiavi e le 3.406 foto offline restano disponibili. I dati locali e l’identità dell’app sono conservati. L’IPA iPhone viene prodotta non firmata e richiede firma/provisioning per l’installazione.

Verifiche: 281 test superati; controllo del codice senza problemi. I casi mirati includono ritorno al diario da una scheda o da un altro pannello, conservazione della bozza in caso di errore e scelta per ID o sinonimo.
