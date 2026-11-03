import copy
import importlib.util
from pathlib import Path
import unittest

spec = importlib.util.spec_from_file_location('key_paths', Path(__file__).resolve().parents[1] / 'import_italic_key_paths.py')
module = importlib.util.module_from_spec(spec)
spec.loader.exec_module(module)


class KeyPathsTests(unittest.TestCase):
    def setUp(self):
        def row(i, parent, record=None, species=None, taxon=None):
            return dict(leadId=i, parentId=parent, leadText=f'condition {i}' if i else None,
                        leadRecordId=record, leadSpecies=species, italicId=taxon)
        self.full = {'keyData': [row(0,None),row(1,0),row(2,0),
                                 row(3,1,'a','Physcia alpha','1'), row(4,1,'x','Other x','9'),
                                 row(5,2,'a2','Physcia alpha','1'),row(6,2,'b','Physcia beta','2')]}
        self.response = {'records':['a','a2','b','historical'], 'link':'https://italic.units.it/key-maker/test/nodes/1/interactive','key_id':'test'}
        self.reference = [{'italicId':1,'scientificName':'Physcia alpha'}, {'italicId':2,'scientificName':'Physcia beta'}]
        self.adaptation = {'genus':'Physcia','id':'test','title':'test','accessedOn':'2026-11-02',
                           'leads':{str(i):dict(label=f'adapted {i}',bindings={}) for i in [1,2,5,6]}}

    def build(self):
        return module.reconstruct(self.full,self.response,self.reference,self.adaptation,'hash')

    def test_unary_pruning_preserves_outer_condition_and_multiple_species_paths(self):
        result = self.build()
        root = next(n for n in result['nodes'] if n['id']==result['root'])
        self.assertEqual(root['choices'][0]['label'],'adapted 1')
        self.assertEqual(root['choices'][0]['sourceLeadIds'],[1,3])
        self.assertEqual(len(result['paths']),3)
        self.assertEqual([p['taxonId'] for p in result['paths']].count(1),2)
        self.assertEqual(result['diagnostics']['unavailableRecords'],['historical'])

    def test_unknown_identity_and_incomplete_coverage_abort(self):
        self.full['keyData'][3]['leadSpecies']='wrong name'
        with self.assertRaisesRegex(ValueError,'identity'): self.build()
        self.setUp(); self.response['records']=['a']
        with self.assertRaisesRegex(ValueError,'coverage'): self.build()

    def test_untranslated_alternative_is_not_guessed(self):
        del self.adaptation['leads']['1']
        with self.assertRaisesRegex(ValueError,'Adaptation missing'): self.build()

    def test_image_duplicates_are_reported_but_content_conflicts_abort(self):
        extra=copy.deepcopy(self.full['keyData'][3]); extra['speciesImage']='variant.jpg'
        self.full['keyData'].append(extra)
        self.assertEqual(self.build()['diagnostics']['duplicateImageVariants'],[3])
        extra['leadText']='changed condition'
        with self.assertRaisesRegex(ValueError,'Conflicting duplicate'): self.build()

    def test_orphan_and_disconnected_cycle_abort(self):
        self.full['keyData'][1]['parentId']=99
        with self.assertRaisesRegex(ValueError,'Missing parent'): self.build()
        self.setUp()
        self.full['keyData'].extend([dict(leadId=90,parentId=91,leadText='cycle',leadRecordId=None),
                                     dict(leadId=91,parentId=90,leadText='cycle',leadRecordId=None)])
        with self.assertRaises(ValueError): self.build()


if __name__ == '__main__': unittest.main()
