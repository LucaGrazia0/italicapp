# Limiti e stato dell'esperimento

## Stato

- Database letto senza modificarlo: 3.588 taxa, 3.566 descrizioni non vuote.
- La struttura osservata è `taxa` a livello principale; `metadata` è un oggetto separato. Questo differisce dalla struttura `metadata → taxa` indicata nel brief.
- Venti taxa selezionati deterministicamente tramite campi e testo del database.
- Pipeline, prompt, schema, validatori e report implementati.
- Riferimento manuale di *Candelariella plumbea* creato per verificare 34 caratteri e i casi scientifici critici.
- Estrazione automatica LLM non eseguita: nessun modello locale o provider remoto configurato.

## Limiti scientifici

- La presenza di una parola nel testo viene usata soltanto per stratificare il campione, non come estrazione morfologica.
- I validatori provano tracciabilità e coerenza formale, non correttezza dell'interpretazione.
- La separazione semantica tra strutture può essere controllata solo parzialmente in modo automatico.
- Le descrizioni possono contenere coordinazioni, ellissi e ambiti chimici che richiedono revisione specialistica.
- Il riferimento manuale di ID 509 è `needs_review` e non equivale a una validazione scientifica approvata.

## Ambiguità osservate nel riferimento

- Il tallo di *C. plumbea* potrebbe appartenere a un lichene ospite.
- Le escrescenze sono descritte come `isidia-like`; non sono registrate come veri isidi.
- La reazione K degli apoteci presenta l'alternativa K− oppure K+ rosso-arancio.
- La larghezza `0.1-0.25` delle escrescenze simili a isidi non riporta un'unità nel testo e resta senza unità.

## Passo necessario per completare l'esperimento

Configurare Ollama con un modello adatto oppure un endpoint remoto autorizzato, eseguire i 20 taxa, quindi sottoporre ogni estrazione a revisione lichenologica manuale. Non usare i JSON per una chiave diagnostica prima dell'approvazione.
