import sys
from pathlib import Path
import unittest

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))
from probe_italic_traits_api import coverage, normalize_row, description_conflicts, augment_reproduction
from import_italic_ecology import REPRODUCTION


class TraitsApiTests(unittest.TestCase):
    def setUp(self):
        self.taxon = {'italicId': 1717, 'scientificName': 'Physcia adscendens H. Olivier'}
        self.payload = {'scientific_name': self.taxon['scientificName'], 'data_about': 'traits',
                        'apothecia_lecanorine': 0, 'ascocarps_present': 1}

    def test_missing_is_not_zero_and_non_lecanorine_is_not_absent_ascocarps(self):
        row = normalize_row(self.taxon, self.payload)
        self.assertEqual(row['cells']['apothecia_lecanorine'], 0)
        self.assertEqual(row['cells']['ascocarps_present'], 1)
        self.assertIsNone(row['cells']['cortex_k_red'])
        self.assertEqual(row['review'], 'api_source_unreviewed')

    def test_only_binary_integers_are_accepted(self):
        for value in [True, '1', 2, -1, 0.5, []]:
            with self.subTest(value=value):
                self.payload['apothecia_lecanorine'] = value
                row = normalize_row(self.taxon, self.payload)
                self.assertIsNone(row['cells']['apothecia_lecanorine'])
                self.assertTrue(row['schemaIssues'])

    def test_wrong_identity_or_response_is_rejected(self):
        for field, value in [('scientific_name', 'Physcia aipolia'), ('data_about', 'error')]:
            payload = dict(self.payload, **{field: value})
            with self.assertRaises(ValueError):
                normalize_row(self.taxon, payload)

    def test_coverage_checks_id_and_name_not_fuzzy_names(self):
        local = [{'italicId': 1, 'scientificName': 'Bibbya lutosa A. & B.'},
                 {'italicId': 2, 'scientificName': 'Physcia example'}]
        remote = [{'taxon_id': 1, 'scientific_name': 'Bibbya lutosa A. &  B.'},
                  {'taxon_id': 2, 'scientific_name': 'Other species'}]
        result = coverage(local, remote)
        self.assertEqual(result[0]['identity'], 'whitespace_equivalent')
        self.assertEqual(result[1]['identity'], 'unresolved')

    def test_new_fields_are_flagged_not_silently_discarded(self):
        self.payload['soredia_present'] = 1
        row = normalize_row(self.taxon, self.payload)
        self.assertEqual(row['schemaIssues'][0]['field'], 'soredia_present')

    def test_explicit_description_conflict_is_flagged_without_repair(self):
        taxon = dict(self.taxon, description='Asci 8-spored. Spot tests: upper cortex K+ yellow, C-.')
        self.payload.update(ascospores_less_than_8_per_ascus=1,
                            ascospores_8_per_ascus=0, cortex_k_yellow_turning_to_red=1)
        row = normalize_row(taxon, self.payload)
        self.assertEqual(len(description_conflicts(taxon, row)), 2)
        self.assertEqual(row['cells']['ascospores_8_per_ascus'], 0)
        self.assertEqual(row['cells']['cortex_k_yellow_turning_to_red'], 1)

    def test_taxa_without_a_description_can_still_import_api_traits(self):
        for description in [None, '']:
            taxon = dict(self.taxon, description=description)
            row = normalize_row(taxon, self.payload)
            self.assertEqual(description_conflicts(taxon, row), [])

    def test_reproduction_is_positive_only_and_keeps_similar_structures(self):
        for code in ['A.s', 'S-A.s', 'A.i', 'S', 'A.c', 'A.f', 'S-A.c', '']:
            with self.subTest(code=code):
                taxon = dict(self.taxon, ecologyCodes={'reproductiveStrategy': code},
                             reproductiveStrategy=REPRODUCTION.get(code, ''))
                row = normalize_row(taxon, self.payload)
                matrix = {'schemaVersion': 1, 'characters': [], 'taxa': [row]}
                enriched = augment_reproduction(matrix, {'taxa': [taxon]})
                cells = enriched['taxa'][0]['cells']
                self.assertEqual(cells['reproduction_soredia_or_similar'], 1 if code in ['A.s', 'S-A.s'] else None)
                self.assertEqual(cells['reproduction_isidia_or_similar'], 1 if code == 'A.i' else None)
                self.assertNotIn('reproduction_soredia_or_similar', row['cells'])

    def test_reproduction_code_label_conflict_is_not_promoted(self):
        taxon = dict(self.taxon, ecologyCodes={'reproductiveStrategy': 'A.s'}, reproductiveStrategy='mainly sexual')
        row = normalize_row(taxon, self.payload)
        enriched = augment_reproduction({'characters': [], 'taxa': [row]}, {'taxa': [taxon]})['taxa'][0]
        self.assertIsNone(enriched['cells']['reproduction_soredia_or_similar'])
        self.assertEqual(enriched['reproductionEvidence']['status'], 'source_mismatch')


if __name__ == '__main__':
    unittest.main()
