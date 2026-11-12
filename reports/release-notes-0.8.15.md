# Italic Go 0.8.15 — build 29

- La selezione del punto sulla mappa offre, prima del punto, un campo facoltativo
  per il raggio d’incertezza stimato in metri. Accetta virgola e punto decimali,
  rifiuta zero, numeri negativi o non finiti e mostra il cerchio sulla mappa.
- Il valore resta distinto dall’accuratezza GPS e viene conservato nel diario,
  nei plot, alla riapertura e nelle esportazioni. Una nuova misura GPS rimuove la
  precedente stima manuale; un nuovo punto senza stima non eredita una vecchia.
- Coordinate e incertezza restano escluse dalle esportazioni quando l’utente
  non include la posizione. L’incertezza del plot passa ai suoi record derivati,
  anche quando si elimina il plot conservando le foto.
- Il filtro del colore conserva il comportamento prudente già presente:
  sconosciuto non significa incompatibile. Test sui dati reali per tutti i gruppi
  di colore, oltre a una spiegazione più esplicita nell’interfaccia. Copertura
  attuale: 857 taxa confrontabili e 2.731 con colore non confrontabile.
- Nessuna conversione aggiuntiva delle foto: le 3.406 immagini delle specie sono
  già WebP, 183.639.130 byte totali, media 53,9 kB. Il precedente profilo approvato
  aveva ridotto il totale da 370.116.120 byte del precedente catalogo WebP.
  Le immagini personali del diario mantengono il formato acquisito.
- Studio dell’integrazione iNaturalist su Android e iPhone: confronto tra
  condivisione nativa già presente e invio completo OAuth2/PKCE da implementare.
  Dettagli e fonti nel rapporto dell’11 novembre 2026. Nessuna pubblicazione
  di osservazioni o connessione di account eseguita.

Verifica: 251 test Flutter superati; analizzatore senza segnalazioni.
