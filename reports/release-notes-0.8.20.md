# Italic Go 0.8.20+35

Ripristinata la condivisione della singola foto verso iNaturalist su iPhone.
La versione precedente allegava anche il testo della scheda DoLichens:
share_plus crea un elemento di condivisione aggiuntivo per quel testo, mentre
l'estensione iOS ufficiale iNaturalist dichiara l'attivazione per immagini.
Questo può escludere il destinatario dal menu del telefono.

- Su iPhone (app nativa e app web con Web Share) il pulsante dedicato invia una sola immagine, senza testo, titolo, URI o
  oggetto aggiuntivi. I byte originali e il tipo immagine vengono conservati.
- La scheda DoLichens resta copiabile separatamente, comprese le coordinate
  se l'utente sceglie di includerle. Rimane disponibile il pacchetto completo.
- Android conserva la condivisione della foto e del testo facoltativo.
- Il login/invio API rimane separato e richiede ancora il Client ID pubblico.

Verificati il payload iOS e Android con test di piattaforma e la copia della
scheda con nome e coordinate. La comparsa nel menu del telefono richiede una
prova sul dispositivo con la nuova app iNaturalist installata, non Classic.

Fonti verificate il 14 novembre 2026:

- https://github.com/inaturalist/iNaturalistReactNative/blob/main/ios/iNaturalistReactNative-ShareExtension/Info.plist
- https://help.inaturalist.org/en/support/solutions/articles/151000216149-what-s-the-difference-between-inaturalist-and-inaturalist-classic-
- Implementazione iOS di share_plus 13.3.1, `shareFiles`: aggiunge un activity
  item testuale quando `text != nil`.
