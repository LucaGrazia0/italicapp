import importlib.util
import json
from pathlib import Path
import tempfile
import unittest

TOOLS = Path(__file__).resolve().parents[1]


def load_module(name, file):
    spec = importlib.util.spec_from_file_location(name, TOOLS / file)
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


importer = load_module('ecology_import', 'import_italic_ecology.py')
parser = load_module('taxon_parser', 'build_italic_taxa.py')


class EcologyImportTests(unittest.TestCase):
    def tables(self):
        return {
            'ecology1': {1: {'NUM': 1, 'SP': 'Taxon A', 'GROWTH': ' Cr',
                'PHOTO': ' Ch-Cy.h', 'REPRO': ' S-A.s', 'SUBST': ' Epiph-Sax'}},
            'ecology2': {1: {'NUM': 1, 'SP': 'Taxon A', 'PH1': 1, 'PH2': 1,
                'PF1': 0, 'PF2': 0, 'A': 0, 'C': 6}},
            'distribution': {1: {'NUM': 1, 'SP': 'Taxon A', 'REGIONS': 'Emil'}},
        }

    def snapshot(self):
        return {'metadata': {'count': 2}, 'taxa': [
            {'italicId': 1, 'scientificName': 'Taxon A', 'description': 'Original description',
             'synonyms': ['Synonym A'], 'distribution': 'Newer distribution',
             'ecologicalScales': {}, 'belts': {}},
            {'italicId': 99, 'scientificName': 'New taxon', 'description': 'Keep me'},
        ]}

    def test_single_classes_zero_and_preservation(self):
        original = self.snapshot()
        result, report = importer.enrich(original, self.tables())
        taxon = result['taxa'][0]
        self.assertEqual(taxon['ecologicalScales']['Poleotolerance'], {'min': 0, 'max': 0, 'values': [0]})
        self.assertEqual(taxon['ecologicalScales']['pH of the substrata']['values'], [1])
        self.assertEqual(taxon['belts'], {'Alpine belt': 'absent', 'Montane belt': 'common'})
        self.assertEqual(taxon['description'], 'Original description')
        self.assertEqual(taxon['synonyms'], ['Synonym A'])
        self.assertEqual(taxon['distribution'], 'Newer distribution')
        self.assertEqual(result['taxa'][1], original['taxa'][1])
        self.assertEqual(original, self.snapshot())
        self.assertEqual(report['preserved_without_sql'], [99])

    def test_id_name_mismatch_does_not_merge(self):
        tables = self.tables(); tables['ecology1'][1]['SP'] = 'Different taxon'
        original = self.snapshot()
        result, report = importer.enrich(original, tables)
        self.assertEqual(result, original)
        self.assertEqual(report['conflicts'], [{'id': 1, 'field': 'scientificName'}])

    def test_invalid_ranges_are_reported_and_existing_values_not_overwritten(self):
        tables = self.tables(); tables['ecology2'][1].update({'PH1': 4, 'PH2': 1})
        original = self.snapshot()
        original['taxa'][0]['ecologicalScales']['Poleotolerance'] = {'min': 1, 'max': 2, 'values': [1, 2]}
        result, report = importer.enrich(original, tables)
        self.assertEqual(len(report['invalid_ranges']), 1)
        self.assertEqual(len(report['conflicts']), 1)
        self.assertEqual(result['taxa'][0]['ecologicalScales'], original['taxa'][0]['ecologicalScales'])

    def test_stream_reader_only_reads_allowlist_and_handles_escaping(self):
        sql = """INSERT INTO `users` (`ID`, `password`) VALUES
(1, 'do not export');
INSERT INTO `ecology1` (`NUM`, `SP`, `NOTE`) VALUES
(1, 'Taxon A', 'quotes: \\' and \\n and ),;'), (2, 'Taxon B', NULL);
INSERT INTO `ecology2` (`NUM`, `SP`) VALUES (1, 'Taxon A');
INSERT INTO `distribution` (`NUM`, `SP`) VALUES
(1, 'Taxon A');
"""
        with tempfile.TemporaryDirectory() as directory:
            path = Path(directory) / 'dump.sql'; path.write_text(sql)
            tables = importer.read_scientific_tables(path)
        self.assertEqual(set(tables), importer.ALLOWED_TABLES)
        self.assertEqual(tables['ecology1'][1]['NOTE'], "quotes: ' and \n and ),;")
        self.assertIsNone(tables['ecology1'][2]['NOTE'])
        self.assertNotIn('password', json.dumps(tables))

    def test_sql_literal_does_not_execute_expressions(self):
        with self.assertRaises(ValueError):
            importer.parse_tuple('(NOW(), 1)')
        self.assertEqual(importer.parse_tuple("(1, 'l''alga', NULL)"), [1, "l'alga", None])

    def test_html_parser_keeps_single_value_cells(self):
        html = '''<div class="eco-grid-container"><h4>pH of the substrata:</h4>
<table class="eco-table"><tr><td class="only-cell">1</td><td>2</td></tr></table>
<div class="eco-grid-container"><h4>Poleotolerance:</h4>
<table class="eco-table"><tr><td class="only-cell-2">0</td><td>1</td></tr></table>
<div class="eco-grid-container"><h4>Aridity:</h4>
<table class="eco-table"><tr><td class="left-cell">2</td><td class="right-cell">3</td></tr></table>'''
        scales = parser._extract_ecological_scales(html)
        self.assertEqual(scales['pH of the substrata']['values'], [1])
        self.assertEqual(scales['Poleotolerance']['values'], [0])
        self.assertEqual(scales['Aridity']['values'], [2, 3])


if __name__ == '__main__':
    unittest.main()
