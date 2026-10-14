import copy
import json
import tempfile
import unittest
from pathlib import Path

import extractor


class PipelineTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        _, cls.taxa = extractor.load_taxa(extractor.DEFAULT_DATABASE)
        cls.taxon_509 = extractor.find_taxon(cls.taxa, 509)
        cls.reference = extractor.read_json(extractor.ROOT / "fixtures" / "509.manual_reference.json")

    def test_selection_has_required_strata_and_features(self):
        with tempfile.TemporaryDirectory() as directory:
            result = extractor.select_taxa(
                extractor.DEFAULT_DATABASE,
                Path(directory) / "selection.json",
                Path(directory) / "selection.csv",
            )
        rows = result["taxa"]
        self.assertEqual(len(rows), 20)
        self.assertIn(509, [row["italic_id"] for row in rows])
        counts = {group: sum(row["group"] == group for row in rows) for group in ("crustose", "foliose", "fruticose")}
        self.assertEqual(counts, {"crustose": 8, "foliose": 6, "fruticose": 6})
        self.assertEqual({row["length_band"] for row in rows}, {"short", "medium", "long"})
        features = {feature for row in rows for feature in row["explicit_features"]}
        self.assertTrue({"apothecia", "perithecia", "soredia", "isidia"}.issubset(features))

    def test_candelariella_reference_is_traceable(self):
        issues = extractor.validate_result(self.reference, self.taxon_509)
        self.assertEqual(issues, [])
        self.assertEqual(len(self.reference["characters"]), 34)

    def test_invalid_citation_is_rejected(self):
        result = copy.deepcopy(self.reference)
        result["characters"][0]["original_text"] = "testo inventato"
        issues = extractor.validate_result(result, self.taxon_509)
        self.assertIn("citation_not_found", {issue["code"] for issue in issues})

    def test_chemical_alternative_must_be_preserved(self):
        result = copy.deepcopy(self.reference)
        chemical = next(
            item
            for item in result["characters"]
            if item["structure"] == "apothecia" and item["character"] == "chemical_reaction"
        )
        chemical["status"] = "reported"
        chemical["normalized_values"] = chemical["normalized_values"][:1]
        issues = extractor.validate_result(result, self.taxon_509)
        self.assertIn("chemical_alternative_lost", {issue["code"] for issue in issues})

    def test_schema_file_is_valid_json(self):
        with extractor.SCHEMA_PATH.open(encoding="utf-8") as handle:
            schema = json.load(handle)
        self.assertEqual(schema["$schema"], "https://json-schema.org/draft/2020-12/schema")


if __name__ == "__main__":
    unittest.main()
