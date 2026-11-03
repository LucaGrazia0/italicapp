import importlib.util
from pathlib import Path
import sys
import tempfile
import unittest

TOOLS = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(TOOLS))
spec = importlib.util.spec_from_file_location('genus_import', TOOLS / 'import_italic_genus_keys.py')
module = importlib.util.module_from_spec(spec); spec.loader.exec_module(module)


class GenusKeysTests(unittest.TestCase):
    def read(self, body):
        with tempfile.TemporaryDirectory() as directory:
            path = Path(directory) / 'input.sql'; path.write_text(body)
            return module.read_keys(path)

    def test_preserves_multiple_keys_for_one_genus_without_exporting_notes(self):
        result = self.read("""INSERT INTO `users` (`id`, `password`) VALUES
(1, 'private');
INSERT INTO `Generi_note` (`ID`, `genus`, `note`, `chiave`) VALUES
(1, 'Caloplaca s.lat.', 'do not export notes', 'https://italic.units.it/flora/index.php?procedure=ext_key_home&key_id=1'),
(2, 'Caloplaca s.str.', 'more notes', 'https://italic.units.it/flora/index.php?procedure=ext_key_home&key_id=2');
""")
        self.assertEqual(len(result), 2)
        self.assertEqual([row['genus'] for row in result], ['Caloplaca', 'Caloplaca'])
        self.assertTrue(all(set(row) == {'id', 'genus', 'name', 'url'} for row in result))

    def test_non_official_url_is_rejected(self):
        with self.assertRaises(ValueError):
            self.read("""INSERT INTO `Generi_note` (`ID`, `genus`, `chiave`) VALUES
(1, 'Test', 'https://example.com/flora/index.php?procedure=ext_key_home&key_id=1');
""")


if __name__ == '__main__':
    unittest.main()
