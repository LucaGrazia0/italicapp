import copy
import json
from pathlib import Path
import sys
import unittest

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))
from build_character_matrix import build, chemistry, morphology, validate

ROOT = Path(__file__).resolve().parents[2]
PILOT = json.loads((ROOT / 'assets/italic/flavoparmelia_key.json').read_text())


class CharacterMatrixTests(unittest.TestCase):
    def test_missing_and_reproductive_strategy_do_not_imply_absence(self):
        snapshot = {'taxa': [{'italicId': 1, 'scientificName': 'Example taxon',
                    'description': '', 'ecologyCodes': {'reproductiveStrategy': 'S'}}]}
        matrix = build(snapshot, PILOT)
        cells = matrix['taxa'][0]['cells']
        self.assertNotIn('soredia', cells)
        self.assertNotIn('isidia', cells)
        self.assertEqual(cells['reproductiveStrategy']['values'], ['S'])
        validate(matrix, snapshot)

    def test_explicit_absence_presence_and_variability_stay_distinct(self):
        cells = morphology('Isidia cylindrical. Soredia absent. Lower surface with black rhizines, sometimes without rhizines.')
        self.assertEqual(cells['isidia']['values'], ['present'])
        self.assertEqual(cells['isidia']['status'], 'recorded')
        self.assertEqual(cells['soredia']['values'], ['absent'])
        self.assertEqual(cells['rhizines']['status'], 'ambiguous')
        self.assertTrue(all(c['review'] == 'needs_review' for c in cells.values()))

    def test_word_mention_is_not_presence(self):
        cells = morphology('A species resembling taxa with isidia-like structures. The name refers to soredia.')
        self.assertEqual(cells['isidia']['status'], 'ambiguous')
        self.assertEqual(cells['soredia']['status'], 'ambiguous')
        self.assertEqual(cells['soredia']['values'], [])

    def test_compartments_reagents_and_ki_are_not_conflated(self):
        cells = chemistry('Asci K/I+ blue. Spot tests: upper cortex K+ yellow, C-, KC-, P-; medulla K-, C+ red, KC+ red, P-, UV+. Chemistry: test.')
        self.assertEqual(cells['upper_cortex_K']['values'], ['positive'])
        self.assertEqual(cells['upper_cortex_C']['values'], ['negative'])
        self.assertEqual(cells['upper_cortex_KC']['values'], ['negative'])
        self.assertEqual(cells['medulla_K']['values'], ['negative'])
        self.assertEqual(cells['medulla_C']['values'], ['positive'])
        self.assertEqual(cells['medulla_UV']['values'], ['positive'])
        self.assertNotIn('thallus_K', cells)
        self.assertNotIn('upper_cortex_UV', cells)
        self.assertEqual(chemistry('Asci K/I+ blue. No spot tests reported.'), {})

    def test_documented_soralia_or_soralium_propose_soredia_with_source(self):
        for description in ['Lobes with terminal, hood-shaped soralia.',
                            'SORALIA capitate.', 'Thallus with a terminal soralium.']:
            entry = morphology(description)['soredia']
            self.assertEqual(entry['values'], ['present'])
            self.assertEqual(entry['status'], 'recorded')
            self.assertEqual(entry['review'], 'needs_review')
            proof = entry['evidence'][0]
            self.assertEqual(proof['rule'], 'morphology-soredia-from-soralia-v1')
            self.assertEqual(description[proof['start']:proof['end']], proof['quote'])

    def test_no_soralia_does_not_mean_no_soredia(self):
        for description in ['Soralia absent.', 'Thallus without soralia.',
                            'Thallus not with soralia.', 'No soralia.']:
            entry = morphology(description)['soredia']
            self.assertEqual(entry['values'], [])
            self.assertEqual(entry['status'], 'ambiguous')
        entry = morphology('Soredia diffuse, without soralia.')['soredia']
        self.assertEqual(entry['values'], ['present'])
        self.assertEqual(entry['status'], 'recorded')

    def test_soralia_comparisons_and_conditions_are_not_confirmations(self):
        for description in ['A species resembling taxa with soralia.',
                            'Thallus with soralia-like structures.',
                            'The name refers to soralia.']:
            entry = morphology(description)['soredia']
            self.assertEqual(entry['values'], [])
            self.assertEqual(entry['status'], 'ambiguous')
        entry = morphology('Thallus sometimes with soralia.')['soredia']
        self.assertEqual(entry['values'], ['present'])
        self.assertEqual(entry['status'], 'ambiguous')
        conflict = morphology('Soredia absent. Soralia capitate.')['soredia']
        self.assertEqual(conflict['values'], ['absent', 'present'])
        self.assertEqual(conflict['status'], 'ambiguous')

    def test_cilia_and_cilium_are_recognized_as_ciglia(self):
        for description in ['Cilia black.', 'Lobes with marginal cilia.',
                            'Lobes with a terminal cilium.']:
            entry = morphology(description)['cilia']
            self.assertEqual(entry['values'], ['present'])
            self.assertEqual(entry['status'], 'recorded')
            self.assertEqual(entry['review'], 'needs_review')
        for description in ['Cilia absent.', 'Thallus without cilia.', 'Cilium absent.']:
            entry = morphology(description)['cilia']
            self.assertEqual(entry['values'], ['absent'])
        entry = morphology('Thallus with cilia-like structures.')['cilia']
        self.assertEqual(entry['values'], [])
        self.assertEqual(entry['status'], 'ambiguous')

    def test_unspecified_cortex_is_not_upper_cortex(self):
        cells = chemistry('Spot tests: cortex K+ yellow; lower cortex C-; medulla K-. Chemistry: none.')
        self.assertNotIn('upper_cortex_K', cells)
        self.assertNotIn('upper_cortex_C', cells)
        self.assertEqual(cells['medulla_K']['values'], ['negative'])

    def test_reaction_alternatives_remain_ambiguous_and_sequence_is_preserved(self):
        cells = chemistry('Spot tests: medulla K- or K+ yellow turning red. Chemistry: test.')
        entry = cells['medulla_K']
        self.assertEqual(entry['status'], 'ambiguous')
        self.assertEqual(entry['values'], ['negative', 'positive'])
        self.assertIn('yellow turning red', entry['evidence'][0]['quote'])

    def test_full_matrix_has_exact_coverage_traceable_sources_and_curated_scope(self):
        snapshot = json.loads((ROOT / 'assets/italic/italic_checklist.json').read_text())
        matrix = build(snapshot, PILOT)
        validate(matrix, snapshot)
        self.assertEqual(len(matrix['taxa']), 3588)
        self.assertEqual(len(matrix['characters']), 25)
        self.assertEqual({r['italicId'] for r in matrix['taxa']}, {r['italicId'] for r in snapshot['taxa']})
        for identifier in ['pilot_soredia', 'pilot_medulla_K']:
            self.assertEqual({r['italicId'] for r in matrix['taxa'] if identifier in r['cells']}, {978, 979})
        self.assertEqual(matrix, build(snapshot, PILOT))
        broken = copy.deepcopy(matrix)
        first = next(r for r in broken['taxa'] if r['cells'])
        next(iter(first['cells'].values()))['evidence'][0]['quote'] = 'Not in source'
        with self.assertRaisesRegex(ValueError, 'Evidence not present'):
            validate(broken, snapshot)

    def test_duplicate_taxon_id_is_rejected(self):
        row = {'italicId': 1, 'scientificName': 'Example taxon', 'description': ''}
        with self.assertRaises(ValueError):
            build({'taxa': [row, row]}, PILOT)


if __name__ == '__main__':
    unittest.main()
