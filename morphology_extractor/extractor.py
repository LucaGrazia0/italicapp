#!/usr/bin/env python3
"""Pipeline riproducibile per l'estrazione di caratteri lichenologici.

L'estrazione linguistica è delegata a un provider esplicito; selezione,
validazione e report restano deterministici.
"""

from __future__ import annotations

import argparse
import csv
import hashlib
import html
import json
import os
import re
import sys
import urllib.error
import urllib.request
from dataclasses import dataclass
from pathlib import Path
from typing import Any, Iterable


ROOT = Path(__file__).resolve().parent
DEFAULT_DATABASE = ROOT.parent / "assets" / "italic" / "italic_checklist.json"
DEFAULT_SELECTION = ROOT / "selected_taxa.json"
DEFAULT_RESULTS = ROOT / "results"
PROMPT_PATH = ROOT / "prompts" / "extraction_prompt.txt"
SCHEMA_PATH = ROOT / "schema" / "extraction.schema.json"

STRUCTURES = {
    "thallus",
    "lobes",
    "squamules",
    "cortex",
    "medulla",
    "apothecia",
    "apothecial_disc",
    "proper_margin",
    "thalline_margin",
    "perithecia",
    "soredia",
    "soralia",
    "isidia",
    "isidia_like_structures",
    "pycnidia",
    "exciple",
    "epithecium",
    "hymenium",
    "paraphyses",
    "asci",
    "ascospores",
    "photobiont",
    "other",
}

STATUS_VALUES = {"present", "absent", "variable", "ambiguous", "reported"}
CERTAINTY_VALUES = {"high", "medium", "low"}
REVIEW_VALUES = {"unreviewed", "needs_review", "manually_reviewed", "approved"}
QUALIFIERS = (
    "usually",
    "sometimes",
    "rarely",
    "often",
    "occasionally",
    "mostly",
    "mainly",
    "in sun-forms",
    "more or less",
    "weakly",
    "slightly",
    "might",
    "may",
)
FEATURE_PATTERNS = {
    "apothecia": re.compile(r"\bapothec\w*", re.I),
    "perithecia": re.compile(r"\bperithec\w*", re.I),
    "soredia": re.compile(r"\bsored\w*", re.I),
    "isidia": re.compile(r"\bisid\w*", re.I),
}
UNIT_PATTERN = re.compile(r"(?<![A-Za-z])(mm|cm|µm|μm|um)(?![A-Za-z])", re.I)
ABSENCE_PATTERN = re.compile(
    r"\b(absent|without|lacking|not present|non-sorediate|non-isidiate)\b|"
    r"(?:^|[\s,;])(K|C|KC|P|UV|I)\s*[−-]",
    re.I,
)


def read_json(path: Path) -> Any:
    with path.open(encoding="utf-8") as handle:
        return json.load(handle)


def write_json(path: Path, value: Any) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    with path.open("w", encoding="utf-8") as handle:
        json.dump(value, handle, ensure_ascii=False, indent=2)
        handle.write("\n")


def sha256_text(text: str) -> str:
    return hashlib.sha256(text.encode("utf-8")).hexdigest()


def load_taxa(database: Path) -> tuple[dict[str, Any], list[dict[str, Any]]]:
    payload = read_json(database)
    taxa = payload.get("taxa")
    if not isinstance(taxa, list):
        raise ValueError("Il database deve contenere un array top-level 'taxa'.")
    return payload.get("metadata", {}), taxa


def growth_group(value: str | None) -> str | None:
    lowered = (value or "").lower()
    if lowered.startswith("crustose"):
        return "crustose"
    if lowered.startswith("foliose"):
        return "foliose"
    if lowered.startswith("fruticose"):
        return "fruticose"
    return None


def description_features(description: str) -> list[str]:
    return [name for name, pattern in FEATURE_PATTERNS.items() if pattern.search(description)]


def quantile_bounds(lengths: list[int]) -> tuple[int, int]:
    ordered = sorted(lengths)
    return ordered[len(ordered) // 3], ordered[(2 * len(ordered)) // 3]


def length_band(length: int, bounds: tuple[int, int]) -> str:
    if length <= bounds[0]:
        return "short"
    if length <= bounds[1]:
        return "medium"
    return "long"


def select_taxa(database: Path, output_json: Path, output_csv: Path) -> dict[str, Any]:
    metadata, taxa = load_taxa(database)
    candidates: list[dict[str, Any]] = []
    for taxon in taxa:
        description = taxon.get("description") or ""
        group = growth_group(taxon.get("growthForm"))
        if description and group:
            candidates.append(
                {
                    "italic_id": taxon["italicId"],
                    "scientific_name": taxon["scientificName"],
                    "growth_form": taxon.get("growthForm"),
                    "group": group,
                    "description_length": len(description),
                    "explicit_features": description_features(description),
                }
            )

    by_group = {group: [c for c in candidates if c["group"] == group] for group in ("crustose", "foliose", "fruticose")}
    bounds = {
        group: quantile_bounds([c["description_length"] for c in rows])
        for group, rows in by_group.items()
    }
    for row in candidates:
        row["length_band"] = length_band(row["description_length"], bounds[row["group"]])

    mandatory = next((row for row in candidates if row["italic_id"] == 509), None)
    if mandatory is None:
        raise ValueError("ITALIC ID 509 non trovato o privo di descrizione.")

    selected = [mandatory]
    selected_ids = {mandatory["italic_id"]}
    observed_features = set(mandatory["explicit_features"])
    observed_lengths = [mandatory["description_length"]]
    quotas = {"crustose": 8, "foliose": 6, "fruticose": 6}
    feature_cycle = ("apothecia", "perithecia", "soredia", "isidia")
    band_cycle = ("short", "medium", "long")

    for group in ("crustose", "foliose", "fruticose"):
        current = sum(1 for row in selected if row["group"] == group)
        for slot in range(current, quotas[group]):
            desired_feature = feature_cycle[slot % len(feature_cycle)]
            desired_band = band_cycle[slot % len(band_cycle)]
            best: tuple[float, int, dict[str, Any]] | None = None
            for row in by_group[group]:
                if row["italic_id"] in selected_ids:
                    continue
                features = set(row["explicit_features"])
                novelty = len(features - observed_features)
                length_distance = min(abs(row["description_length"] - n) for n in observed_lengths)
                score = (
                    (80 if row["length_band"] == desired_band else 0)
                    + (65 if desired_feature in features else 0)
                    + (35 * novelty)
                    + min(length_distance / 25, 40)
                )
                candidate_key = (score, -int(row["italic_id"]), row)
                if best is None or candidate_key[:2] > best[:2]:
                    best = candidate_key
            if best is None:
                raise ValueError(f"Impossibile soddisfare la quota per {group}.")
            chosen = best[2]
            selected.append(chosen)
            selected_ids.add(chosen["italic_id"])
            observed_features.update(chosen["explicit_features"])
            observed_lengths.append(chosen["description_length"])

    selected.sort(key=lambda row: (0 if row["italic_id"] == 509 else 1, row["group"], row["italic_id"]))
    for row in selected:
        row["selection_reason"] = [
            f"forma di crescita dichiarata: {row['growth_form']}",
            f"fascia di lunghezza della descrizione: {row['length_band']}",
            "strutture esplicitamente menzionate: "
            + (", ".join(row["explicit_features"]) if row["explicit_features"] else "nessuna tra i quattro marcatori campionati"),
        ]
        if row["italic_id"] == 509:
            row["selection_reason"].insert(0, "taxon obbligatorio del protocollo")

    database_hash = hashlib.sha256(database.read_bytes()).hexdigest()
    result = {
        "selection_method": {
            "version": "1.0",
            "database": str(database.relative_to(ROOT.parent)),
            "database_sha256": database_hash,
            "database_generated_at": metadata.get("generated_at"),
            "rules": [
                "Candelariella plumbea (ITALIC ID 509) inclusa obbligatoriamente.",
                "Quote: 8 crostosi, 6 fogliosi, 6 fruticosi, usando esclusivamente growthForm.",
                "Campionamento stratificato per terzili della lunghezza della descrizione.",
                "Preferenza per copertura esplicita di apoteci, periteci, soredi e isidi nel testo.",
                "Il nome scientifico non partecipa al punteggio di selezione; l'ID risolve soltanto i pareggi.",
            ],
            "length_band_boundaries": {
                group: {"short_max": limits[0], "medium_max": limits[1]}
                for group, limits in bounds.items()
            },
        },
        "taxa": selected,
    }
    write_json(output_json, result)
    output_csv.parent.mkdir(parents=True, exist_ok=True)
    with output_csv.open("w", encoding="utf-8", newline="") as handle:
        writer = csv.DictWriter(
            handle,
            fieldnames=["italic_id", "scientific_name", "growth_form", "length_band", "description_length", "explicit_features", "selection_reason"],
            lineterminator="\n",
        )
        writer.writeheader()
        for row in selected:
            writer.writerow(
                {
                    **{key: row[key] for key in ("italic_id", "scientific_name", "growth_form", "length_band", "description_length")},
                    "explicit_features": "; ".join(row["explicit_features"]),
                    "selection_reason": " | ".join(row["selection_reason"]),
                }
            )
    return result


def make_prompt(taxon: dict[str, Any]) -> tuple[str, str]:
    system = PROMPT_PATH.read_text(encoding="utf-8")
    user_payload = {
        "italic_id": taxon["italicId"],
        "scientific_name": taxon["scientificName"],
        "description": taxon.get("description") or "",
    }
    return system, json.dumps(user_payload, ensure_ascii=False, indent=2)


def parse_model_json(text: str) -> dict[str, Any]:
    stripped = text.strip()
    if stripped.startswith("```"):
        stripped = re.sub(r"^```(?:json)?\s*", "", stripped)
        stripped = re.sub(r"\s*```$", "", stripped)
    value = json.loads(stripped)
    if not isinstance(value, dict):
        raise ValueError("La risposta del modello non è un oggetto JSON.")
    return value


class Provider:
    name = "provider"

    def extract(self, taxon: dict[str, Any]) -> tuple[dict[str, Any], str]:
        raise NotImplementedError


@dataclass
class ExternalProvider(Provider):
    directory: Path
    name = "external_results"

    def extract(self, taxon: dict[str, Any]) -> tuple[dict[str, Any], str]:
        path = self.directory / f"{taxon['italicId']}.json"
        if not path.exists():
            raise FileNotFoundError(f"Risultato esterno mancante: {path}")
        return read_json(path), "external"


@dataclass
class OllamaProvider(Provider):
    endpoint: str
    model: str
    name = "ollama"

    def extract(self, taxon: dict[str, Any]) -> tuple[dict[str, Any], str]:
        system, user = make_prompt(taxon)
        payload = {
            "model": self.model,
            "stream": False,
            "format": "json",
            "messages": [
                {"role": "system", "content": system},
                {"role": "user", "content": user},
            ],
        }
        response = post_json(self.endpoint.rstrip("/") + "/api/chat", payload)
        content = response.get("message", {}).get("content")
        if not isinstance(content, str):
            raise ValueError("Risposta Ollama priva di message.content.")
        return parse_model_json(content), self.model


@dataclass
class OpenAICompatibleProvider(Provider):
    endpoint: str
    model: str
    api_key_env: str
    name = "openai_compatible"

    def extract(self, taxon: dict[str, Any]) -> tuple[dict[str, Any], str]:
        api_key = os.environ.get(self.api_key_env)
        if not api_key:
            raise RuntimeError(f"Variabile segreta non disponibile: {self.api_key_env}")
        system, user = make_prompt(taxon)
        payload = {
            "model": self.model,
            "response_format": {"type": "json_object"},
            "messages": [
                {"role": "system", "content": system},
                {"role": "user", "content": user},
            ],
        }
        response = post_json(
            self.endpoint.rstrip("/") + "/v1/chat/completions",
            payload,
            headers={"Authorization": f"Bearer {api_key}"},
        )
        content = response["choices"][0]["message"]["content"]
        return parse_model_json(content), self.model


def post_json(url: str, payload: dict[str, Any], headers: dict[str, str] | None = None) -> dict[str, Any]:
    request_headers = {"Content-Type": "application/json", **(headers or {})}
    request = urllib.request.Request(
        url,
        data=json.dumps(payload).encode("utf-8"),
        headers=request_headers,
        method="POST",
    )
    try:
        with urllib.request.urlopen(request, timeout=180) as response:
            value = json.load(response)
    except urllib.error.URLError as error:
        raise RuntimeError(f"Chiamata al provider fallita: {error}") from error
    if not isinstance(value, dict):
        raise ValueError("Il provider ha restituito un JSON non-oggetto.")
    return value


def build_provider(args: argparse.Namespace) -> Provider:
    if args.provider == "external":
        if not args.external_dir:
            raise ValueError("--external-dir è obbligatorio per il provider external.")
        return ExternalProvider(Path(args.external_dir))
    if args.provider == "ollama":
        if not args.model:
            raise ValueError("--model è obbligatorio per Ollama.")
        return OllamaProvider(args.endpoint or "http://127.0.0.1:11434", args.model)
    if args.provider == "openai-compatible":
        if not (args.model and args.endpoint and args.api_key_env):
            raise ValueError("--model, --endpoint e --api-key-env sono obbligatori.")
        return OpenAICompatibleProvider(args.endpoint, args.model, args.api_key_env)
    raise ValueError(f"Provider sconosciuto: {args.provider}")


def normalize_result_metadata(result: dict[str, Any], taxon: dict[str, Any], provider: Provider, model_name: str) -> dict[str, Any]:
    result["italic_id"] = taxon["italicId"]
    result["scientific_name"] = taxon["scientificName"]
    result.setdefault("characters", [])
    result.setdefault("warnings", [])
    result["extraction_method"] = provider.name
    result["model_name"] = model_name
    result.setdefault("review_status", "unreviewed")
    result["source_description_sha256"] = sha256_text(taxon.get("description") or "")
    return result


def validation_issue(level: str, code: str, message: str, character_index: int | None = None) -> dict[str, Any]:
    value = {"level": level, "code": code, "message": message}
    if character_index is not None:
        value["character_index"] = character_index
    return value


def validate_result(result: dict[str, Any], taxon: dict[str, Any]) -> list[dict[str, Any]]:
    issues: list[dict[str, Any]] = []
    description = taxon.get("description") or ""
    try:
        import jsonschema

        validator = jsonschema.Draft202012Validator(read_json(SCHEMA_PATH))
        for error in sorted(validator.iter_errors(result), key=lambda item: list(item.absolute_path)):
            location = ".".join(str(part) for part in error.absolute_path) or "root"
            issues.append(validation_issue("error", "schema_violation", f"{location}: {error.message}"))
    except ImportError:
        issues.append(validation_issue("warning", "schema_validator_unavailable", "Pacchetto jsonschema non installato; eseguiti soltanto i controlli interni."))
    if result.get("italic_id") != taxon.get("italicId"):
        issues.append(validation_issue("error", "italic_id_mismatch", "ITALIC ID non corrispondente al database."))
    if result.get("scientific_name") != taxon.get("scientificName"):
        issues.append(validation_issue("error", "scientific_name_mismatch", "Nome scientifico non corrispondente al database."))
    if result.get("review_status") not in REVIEW_VALUES:
        issues.append(validation_issue("error", "invalid_review_status", "review_status non valido."))
    characters = result.get("characters")
    if not isinstance(characters, list):
        return issues + [validation_issue("error", "invalid_characters", "characters deve essere un array.")]

    for index, character in enumerate(characters):
        if not isinstance(character, dict):
            issues.append(validation_issue("error", "invalid_character", "Carattere non-oggetto.", index))
            continue
        required = ("structure", "part", "character", "original_text", "normalized_values", "qualifiers", "status", "certainty", "review_required")
        for field in required:
            if field not in character:
                issues.append(validation_issue("error", "missing_field", f"Campo mancante: {field}.", index))
        structure = character.get("structure")
        if structure not in STRUCTURES:
            issues.append(validation_issue("warning", "uncontrolled_structure", f"Struttura non controllata: {structure!r}.", index))
        if character.get("status") not in STATUS_VALUES:
            issues.append(validation_issue("error", "invalid_status", "status non valido.", index))
        if character.get("certainty") not in CERTAINTY_VALUES:
            issues.append(validation_issue("error", "invalid_certainty", "certainty non valida.", index))
        citation = character.get("original_text")
        if not isinstance(citation, str) or not citation.strip():
            issues.append(validation_issue("error", "missing_citation", "Citazione vuota.", index))
            continue
        if citation not in description:
            issues.append(validation_issue("error", "citation_not_found", "La citazione non è una sottostringa esatta della descrizione.", index))
        qualifiers = character.get("qualifiers")
        if not isinstance(qualifiers, list):
            issues.append(validation_issue("error", "invalid_qualifiers", "qualifiers deve essere un array.", index))
            qualifiers = []
        citation_lower = citation.lower()
        missing_qualifiers = [q for q in QUALIFIERS if q in citation_lower and q not in [str(v).lower() for v in qualifiers]]
        if missing_qualifiers:
            issues.append(validation_issue("warning", "qualifier_not_preserved", "Qualificatori non preservati: " + ", ".join(missing_qualifiers), index))
        if character.get("status") == "absent" and not ABSENCE_PATTERN.search(citation):
            issues.append(validation_issue("error", "unsupported_absence", "Assenza priva di evidenza esplicita nella citazione.", index))
        values = character.get("normalized_values")
        if not isinstance(values, list):
            issues.append(validation_issue("error", "invalid_normalized_values", "normalized_values deve essere un array.", index))
            values = []
        cited_units = {match.group(1).replace("μ", "µ").lower() for match in UNIT_PATTERN.finditer(citation)}
        normalized_units = {
            str(value.get("unit", "")).replace("μ", "µ").lower()
            for value in values
            if isinstance(value, dict) and value.get("unit")
        }
        if cited_units - normalized_units:
            issues.append(validation_issue("warning", "unit_not_normalized", "Unità citate ma non rappresentate: " + ", ".join(sorted(cited_units - normalized_units)), index))
        if character.get("character") == "chemical_reaction" and " or " in citation_lower:
            if character.get("status") != "variable" or len(values) < 2:
                issues.append(validation_issue("error", "chemical_alternative_lost", "Alternativa chimica non rappresentata come variabile con almeno due valori.", index))
        if ("host lichen" in citation_lower or "might belong" in citation_lower) and not character.get("review_required"):
            issues.append(validation_issue("error", "host_uncertainty_not_flagged", "Possibile struttura dell'ospite non segnalata per revisione.", index))
        if character.get("status") in {"ambiguous", "variable"} and not character.get("review_required"):
            issues.append(validation_issue("warning", "uncertainty_not_flagged", "Carattere ambiguo/variabile non segnalato per revisione.", index))

    expected_hash = sha256_text(description)
    if result.get("source_description_sha256") and result["source_description_sha256"] != expected_hash:
        issues.append(validation_issue("error", "description_hash_mismatch", "Hash della descrizione non corrispondente."))
    return issues


def find_taxon(taxa: Iterable[dict[str, Any]], italic_id: int) -> dict[str, Any]:
    for taxon in taxa:
        if taxon.get("italicId") == italic_id:
            return taxon
    raise KeyError(f"ITALIC ID {italic_id} non trovato.")


def iter_result_files(path: Path) -> list[Path]:
    if path.is_file():
        return [path]
    return sorted(file for file in path.glob("*.json") if not file.name.startswith("_"))


def validate_files(input_path: Path, database: Path) -> dict[str, Any]:
    _, taxa = load_taxa(database)
    rows = []
    for path in iter_result_files(input_path):
        try:
            result = read_json(path)
            taxon = find_taxon(taxa, int(result["italic_id"]))
            issues = validate_result(result, taxon)
            rows.append(
                {
                    "file": str(path),
                    "italic_id": result.get("italic_id"),
                    "scientific_name": result.get("scientific_name"),
                    "character_count": len(result.get("characters", [])),
                    "errors": sum(i["level"] == "error" for i in issues),
                    "warnings": sum(i["level"] == "warning" for i in issues),
                    "issues": issues,
                }
            )
        except (OSError, ValueError, KeyError, json.JSONDecodeError) as error:
            rows.append({"file": str(path), "errors": 1, "warnings": 0, "issues": [validation_issue("error", "unreadable_result", str(error))]})
    return {
        "files_checked": len(rows),
        "valid_files": sum(row["errors"] == 0 for row in rows),
        "total_errors": sum(row["errors"] for row in rows),
        "total_warnings": sum(row["warnings"] for row in rows),
        "json_schema": str(SCHEMA_PATH),
        "results": rows,
        "scientific_accuracy_note": "Questi controlli verificano forma e tracciabilità, non l'accuratezza dell'interpretazione scientifica.",
    }


def extract_selected(args: argparse.Namespace) -> dict[str, Any]:
    _, taxa = load_taxa(Path(args.database))
    selection = read_json(Path(args.selection))
    provider = build_provider(args)
    output_dir = Path(args.output)
    output_dir.mkdir(parents=True, exist_ok=True)
    selected_rows = selection["taxa"][: args.limit or None]
    completed = []
    failed = []
    for selected in selected_rows:
        italic_id = int(selected["italic_id"])
        try:
            taxon = find_taxon(taxa, italic_id)
            result, model_name = provider.extract(taxon)
            result = normalize_result_metadata(result, taxon, provider, model_name)
            write_json(output_dir / f"{italic_id}.json", result)
            completed.append(italic_id)
        except Exception as error:  # per-taxon isolation is intentional
            failed.append({"italic_id": italic_id, "error": str(error)})
    summary = {"provider": provider.name, "completed": completed, "failed": failed}
    write_json(output_dir / "_run_summary.json", summary)
    return summary


def generate_report(input_path: Path, database: Path, output: Path) -> dict[str, Any]:
    _, taxa = load_taxa(database)
    validation = validate_files(input_path, database)
    cards = []
    for row in validation["results"]:
        result = read_json(Path(row["file"])) if "italic_id" in row else {}
        taxon = find_taxon(taxa, int(row["italic_id"])) if "italic_id" in row else {}
        characters = result.get("characters", [])
        character_rows = "".join(
            "<tr>"
            f"<td>{html.escape(str(char.get('structure', '')))}</td>"
            f"<td>{html.escape(str(char.get('part', '')))}</td>"
            f"<td>{html.escape(str(char.get('character', '')))}</td>"
            f"<td>{html.escape(str(char.get('status', '')))}</td>"
            f"<td>{html.escape(str(char.get('original_text', '')))}</td>"
            f"<td><pre>{html.escape(json.dumps(char.get('normalized_values', []), ensure_ascii=False, indent=2))}</pre></td>"
            "</tr>"
            for char in characters
        ) or '<tr><td colspan="6">Nessun carattere.</td></tr>'
        issue_items = "".join(
            f"<li class='{issue['level']}'>{html.escape(issue['code'])}: {html.escape(issue['message'])}</li>"
            for issue in row["issues"]
        ) or "<li>Nessun problema automatico.</li>"
        cards.append(
            f"<section><h2>{html.escape(str(row.get('scientific_name', row['file'])))} — ID {html.escape(str(row.get('italic_id', '')))}</h2>"
            f"<p><strong>Metodo:</strong> {html.escape(str(result.get('extraction_method', '')))}; "
            f"<strong>modello:</strong> {html.escape(str(result.get('model_name', '')))}; "
            f"<strong>revisione:</strong> {html.escape(str(result.get('review_status', '')))}</p>"
            f"<details><summary>Descrizione originale</summary><p>{html.escape(str(taxon.get('description', '')))}</p></details>"
            "<table><thead><tr><th>Struttura</th><th>Parte</th><th>Carattere</th><th>Stato</th><th>Citazione</th><th>Valori</th></tr></thead>"
            f"<tbody>{character_rows}</tbody></table><h3>Validazione</h3><ul>{issue_items}</ul></section>"
        )
    document = f"""<!doctype html>
<html lang="it"><head><meta charset="utf-8"><title>Validazione estrazioni ITALIC</title>
<style>body{{font-family:system-ui,sans-serif;max-width:1400px;margin:auto;padding:2rem;color:#172018}}section{{border-top:2px solid #78947b;padding:1rem 0 2rem}}table{{border-collapse:collapse;width:100%;font-size:.9rem}}th,td{{border:1px solid #ccd5cd;padding:.45rem;vertical-align:top}}th{{background:#eef3ee}}pre{{white-space:pre-wrap;margin:0}}.error{{color:#9b1c1c}}.warning{{color:#855d00}}details p{{white-space:pre-wrap}}</style></head>
<body><h1>Report di validazione morfologica</h1>
<p>File: {validation['files_checked']}; validi strutturalmente: {validation['valid_files']}; errori: {validation['total_errors']}; avvisi: {validation['total_warnings']}.</p>
<p><strong>Limite:</strong> {html.escape(validation['scientific_accuracy_note'])}</p>{''.join(cards)}</body></html>"""
    output.parent.mkdir(parents=True, exist_ok=True)
    output.write_text(document, encoding="utf-8")
    return validation


def generate_selection_report(selection_path: Path, database: Path, output: Path) -> None:
    selection = read_json(selection_path)
    _, taxa = load_taxa(database)
    cards = []
    for row in selection["taxa"]:
        taxon = find_taxon(taxa, int(row["italic_id"]))
        if row["italic_id"] == 509:
            extraction_state = "Riferimento manuale disponibile (34 caratteri); estrazione automatica non eseguita"
        else:
            extraction_state = "In attesa di un modello linguistico configurato"
        reasons = "".join(f"<li>{html.escape(reason)}</li>" for reason in row["selection_reason"])
        cards.append(
            f"<section><h2>{html.escape(row['scientific_name'])} — ID {row['italic_id']}</h2>"
            f"<p><strong>Forma:</strong> {html.escape(str(row['growth_form']))}; "
            f"<strong>fascia:</strong> {html.escape(row['length_band'])}; "
            f"<strong>caratteri:</strong> {row['description_length']}</p>"
            f"<p><strong>Stato:</strong> {html.escape(extraction_state)}</p>"
            f"<ul>{reasons}</ul><details><summary>Descrizione originale</summary>"
            f"<p>{html.escape(taxon.get('description') or '')}</p></details></section>"
        )
    document = f"""<!doctype html>
<html lang="it"><head><meta charset="utf-8"><title>Campione morfologico ITALIC</title>
<style>body{{font-family:system-ui,sans-serif;max-width:1100px;margin:auto;padding:2rem;color:#172018}}section{{border-top:2px solid #78947b;padding:1rem 0}}details p{{white-space:pre-wrap;line-height:1.45}}</style></head>
<body><h1>Campione di 20 taxa</h1><p>Questo report documenta campionamento e stato. Solo ID 509 possiede un riferimento manuale; nessuna estrazione automatica è stata eseguita.</p>{''.join(cards)}</body></html>"""
    output.parent.mkdir(parents=True, exist_ok=True)
    output.write_text(document, encoding="utf-8")


def command_select(args: argparse.Namespace) -> int:
    result = select_taxa(Path(args.database), Path(args.output), Path(args.csv))
    print(f"Selezionati {len(result['taxa'])} taxa in {args.output}")
    return 0


def command_extract(args: argparse.Namespace) -> int:
    summary = extract_selected(args)
    print(json.dumps(summary, ensure_ascii=False, indent=2))
    return 1 if summary["failed"] else 0


def command_validate(args: argparse.Namespace) -> int:
    report = validate_files(Path(args.input), Path(args.database))
    if args.output:
        write_json(Path(args.output), report)
    print(json.dumps(report, ensure_ascii=False, indent=2))
    return 1 if report["total_errors"] else 0


def command_report(args: argparse.Namespace) -> int:
    validation = generate_report(Path(args.input), Path(args.database), Path(args.output))
    print(f"Report scritto in {args.output}: {validation['total_errors']} errori, {validation['total_warnings']} avvisi")
    return 1 if validation["total_errors"] else 0


def command_selection_report(args: argparse.Namespace) -> int:
    generate_selection_report(Path(args.selection), Path(args.database), Path(args.output))
    print(f"Report del campione scritto in {args.output}")
    return 0


def build_parser() -> argparse.ArgumentParser:
    parser = argparse.ArgumentParser(description=__doc__)
    subparsers = parser.add_subparsers(dest="command", required=True)
    select_parser = subparsers.add_parser("select", help="Seleziona deterministicamente i 20 taxa.")
    select_parser.add_argument("--database", default=str(DEFAULT_DATABASE))
    select_parser.add_argument("--output", default=str(DEFAULT_SELECTION))
    select_parser.add_argument("--csv", default=str(ROOT / "selected_taxa.csv"))
    select_parser.set_defaults(func=command_select)

    extract_parser = subparsers.add_parser("extract", help="Esegue l'estrazione tramite un provider esplicito.")
    extract_parser.add_argument("--database", default=str(DEFAULT_DATABASE))
    extract_parser.add_argument("--selection", default=str(DEFAULT_SELECTION))
    extract_parser.add_argument("--output", default=str(DEFAULT_RESULTS))
    extract_parser.add_argument("--provider", required=True, choices=("external", "ollama", "openai-compatible"))
    extract_parser.add_argument("--external-dir")
    extract_parser.add_argument("--endpoint")
    extract_parser.add_argument("--model")
    extract_parser.add_argument("--api-key-env")
    extract_parser.add_argument("--limit", type=int)
    extract_parser.set_defaults(func=command_extract)

    validate_parser = subparsers.add_parser("validate", help="Valida JSON e tracciabilità delle citazioni.")
    validate_parser.add_argument("--database", default=str(DEFAULT_DATABASE))
    validate_parser.add_argument("--input", required=True)
    validate_parser.add_argument("--output")
    validate_parser.set_defaults(func=command_validate)

    report_parser = subparsers.add_parser("report", help="Genera un report HTML comparativo.")
    report_parser.add_argument("--database", default=str(DEFAULT_DATABASE))
    report_parser.add_argument("--input", required=True)
    report_parser.add_argument("--output", default=str(ROOT / "reports" / "validation_report.html"))
    report_parser.set_defaults(func=command_report)

    selection_report_parser = subparsers.add_parser("selection-report", help="Genera un report HTML dei 20 taxa e del loro stato.")
    selection_report_parser.add_argument("--database", default=str(DEFAULT_DATABASE))
    selection_report_parser.add_argument("--selection", default=str(DEFAULT_SELECTION))
    selection_report_parser.add_argument("--output", default=str(ROOT / "reports" / "selection_review.html"))
    selection_report_parser.set_defaults(func=command_selection_report)
    return parser


def main() -> int:
    parser = build_parser()
    args = parser.parse_args()
    try:
        return args.func(args)
    except (OSError, ValueError, KeyError, json.JSONDecodeError) as error:
        parser.error(str(error))
    return 2


if __name__ == "__main__":
    sys.exit(main())
