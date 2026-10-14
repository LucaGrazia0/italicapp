# Estrattore morfologico ITALIC

Questo sottoprogetto prepara dati morfologici verificabili senza modificare l'app Flutter o `assets/italic/italic_checklist.json`.

## Contenuto

- `extractor.py`: selezione, provider LLM, validazione e report.
- `schema/extraction.schema.json`: JSON Schema Draft 2020-12.
- `schema/SCHEMA.md`: vocabolario e semantica dei campi.
- `prompts/extraction_prompt.txt`: regole scientifiche inviate al modello.
- `selected_taxa.json` e `.csv`: campione deterministico di 20 taxa e criteri.
- `fixtures/509.manual_reference.json`: riferimento manuale, non automatico, per *Candelariella plumbea*.
- `reports/509.validation.html`: confronto leggibile tra descrizione e 34 caratteri del riferimento.
- `reports/selection_review.html`: descrizioni, criteri e stato di tutti i 20 taxa.
- `results/`: destinazione esclusiva delle future estrazioni realmente eseguite.
- `LIMITI.md`: stato, ambiguità e lavoro ancora necessario.

## Installazione semplice su Mac

Apri Terminale nella cartella del progetto e usa Python 3.11 o successivo:

```bash
cd ~/Desktop/italicapp/morphology_extractor
python3 -m venv .venv
source .venv/bin/activate
python3 -m pip install -r requirements.txt
```

Non serve installare Flutter per usare l'estrattore.

## Riprodurre selezione e test

```bash
python3 extractor.py select
python3 -m unittest discover -s tests -v
python3 extractor.py validate \
  --input fixtures/509.manual_reference.json \
  --output reports/509.validation.json
python3 extractor.py report \
  --input fixtures/509.manual_reference.json \
  --output reports/509.validation.html
python3 extractor.py selection-report
```

Il report HTML si apre su Mac con:

```bash
open reports/509.validation.html
```

## Eseguire con Ollama

Ollama e il modello devono essere già installati e autorizzati. Il programma non li installa:

```bash
python3 extractor.py extract \
  --provider ollama \
  --model NOME_MODELLO \
  --endpoint http://127.0.0.1:11434
```

Prima prova un solo taxon aggiungendo `--limit 1`. I file vengono scritti in `results/`; `_run_summary.json` distingue successi e fallimenti.

## Endpoint remoto compatibile OpenAI

Imposta la chiave in una variabile d'ambiente senza inserirla nei file:

```bash
export ITALIC_LLM_API_KEY='valore-segreto'
python3 extractor.py extract \
  --provider openai-compatible \
  --endpoint https://HOST_AUTORIZZATO \
  --model NOME_MODELLO \
  --api-key-env ITALIC_LLM_API_KEY
```

Questa modalità non è stata eseguita durante la preparazione perché non era configurato alcun provider autorizzato. Verifica costi e trattamento dei dati prima della chiamata.

## Importare risultati prodotti altrove

Salva un file per taxon come `RISULTATI_ESTERNI/509.json`, quindi:

```bash
python3 extractor.py extract \
  --provider external \
  --external-dir RISULTATI_ESTERNI
```

Il provider esterno non finge un'estrazione: copia e marca i risultati con `extraction_method=external_results`, quindi possono essere validati e confrontati.

## Controllo dei risultati

```bash
python3 extractor.py validate --input results --output reports/all.validation.json
python3 extractor.py report --input results --output reports/all.validation.html
```

Un risultato con zero errori automatici può comunque essere scientificamente scorretto. Controlla citazione, struttura, ambito chimico e qualificatori direttamente nel report e cambia `review_status` soltanto dopo revisione umana.
