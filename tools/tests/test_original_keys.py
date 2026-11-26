import importlib.util
from pathlib import Path
import unittest

TOOLS = Path(__file__).resolve().parents[1]
spec = importlib.util.spec_from_file_location('original_keys', TOOLS / 'import_original_keys.py')
module = importlib.util.module_from_spec(spec)
spec.loader.exec_module(module)


def row(number, label, target):
    return f'<tr bgcolor="#FFFFFF"><td><b>{number}</b></td><td><b>{label}</b></td><td><b>{target}</b></td></tr>'


class OriginalKeyTests(unittest.TestCase):
    def test_verbatim_conditions_aliases_and_nested_descriptions(self):
        index = module.taxon_index([
            {'italicId': 1, 'scientificName': 'Accepted species', 'synonyms': ['Old species']},
            {'italicId': 2, 'scientificName': 'Other species', 'synonyms': []},
        ])
        html = ('<table>' + row(1, 'Lobes &lt;1 cm, without soralia', 2)
                + row(1, 'Lobes &gt;1 cm', 'Old species')
                + '<tr><td colspan="3"><table><tr><td>Original description.</td></tr></table></td></tr>'
                + row(2, 'C+', 'Other species') + row(2, 'C-', 'Not in checklist') + '</table>')
        nodes, missing, disconnected = module.parse_key(html, index)
        self.assertEqual(nodes[0]['choices'][0], {'label': 'Lobes <1 cm, without soralia', 'target': 2})
        self.assertEqual(nodes[0]['choices'][1]['name'], 'Old species')
        self.assertEqual(nodes[0]['choices'][1]['italicId'], 1)
        self.assertEqual(nodes[0]['choices'][1]['description'], 'Original description.')
        self.assertNotIn('italicId', nodes[1]['choices'][1])
        self.assertEqual(missing, [])
        self.assertEqual(disconnected, [])

    def test_ambiguous_synonyms_are_not_assigned(self):
        index = module.taxon_index([
            {'italicId': 1, 'scientificName': 'One species', 'synonyms': ['Ambiguous name']},
            {'italicId': 2, 'scientificName': 'Two species', 'synonyms': ['Ambiguous name']},
        ])
        nodes, _, _ = module.parse_key(row(1, 'A', 'Ambiguous name') + row(1, 'B', 'Unknown name'), index)
        self.assertNotIn('italicId', nodes[0]['choices'][0])

    def test_missing_continuation_is_explicit(self):
        nodes, missing, _ = module.parse_key(row(1, 'A', 55) + row(1, 'B', 'Some species'), {})
        self.assertEqual(missing, [55])
        self.assertEqual(nodes[0]['choices'][0]['target'], 55)

    def test_rejects_cycles_and_unpaired_couplets(self):
        for text in [
            row(1, 'A', 1) + row(1, 'B', 'Species'),
            row(1, 'A', 'Species'),
            '<html>A service error, not a key</html>',
        ]:
            with self.assertRaises(ValueError):
                module.parse_key(text, {})

    def test_shared_continuations_are_preserved(self):
        text = (row(1, 'A', 2) + row(1, 'B', 2)
                + row(2, 'C', 'One species') + row(2, 'D', 'Two species'))
        nodes, missing, _ = module.parse_key(text, {})
        self.assertEqual(len(nodes), 2)
        self.assertEqual(missing, [])

    def test_disconnected_source_material_is_preserved_and_flagged(self):
        text = (row(1, 'A', 'Species') + row(1, 'B', 4)
                + row(2, 'C', 'Species C') + row(2, 'D', 'Species D'))
        nodes, missing, disconnected = module.parse_key(text, {})
        self.assertEqual([n['number'] for n in nodes], [1, 2])
        self.assertEqual(missing, [4])
        self.assertEqual(disconnected, [2])

    def test_visible_title_is_preserved_even_without_keys_to_prefix(self):
        data = module.metadata('<title>Generic head</title><center><font size="4"><b>Lichens of the Alps</b></font><br>Author<br><div align="justify">Intro</div></center>', 1611)
        self.assertEqual(data['title'], 'Lichens of the Alps')
        self.assertEqual(data['credits'], 'Author')


if __name__ == '__main__':
    unittest.main()
