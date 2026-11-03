import copy
import importlib.util
from pathlib import Path
import unittest

spec=importlib.util.spec_from_file_location('general_key',Path(__file__).resolve().parents[1]/'build_general_key.py')
module=importlib.util.module_from_spec(spec);spec.loader.exec_module(module)


class GeneralKeyTests(unittest.TestCase):
    def setUp(self):
        def row(i,parent,taxon=None,name=None,group=False):
            return dict(leadId=i,parentId=parent,leadText=f'condition {i}',italicId=str(taxon) if taxon else None,
                        leadSpecies=name,leadSpeciesId=str(i) if taxon or group else None,leadRecordId=str(i) if taxon or group else None,leadTo=None)
        self.full={'keyData':[row(0,None),row(1,0,1,'Alpha one'),row(2,0),row(3,2,9,'Extra nine'),row(4,2),
                              row(5,4,2,'Beta two Servit'),row(6,4),row(7,6,name='Unknown group',group=True),row(8,6)]}
        self.reference=[dict(italicId=1,scientificName='Alpha one'),dict(italicId=2,scientificName='Beta two Servít'),dict(italicId=3,scientificName='Gamma three')]
        self.associated={3:dict(scientific_name='Gamma three',keys=[])}

    def build(self):return module.build(self.full,self.reference,self.associated,'hash')

    def test_all_source_endpoints_and_orthographic_aliases_are_preserved(self):
        result=self.build()
        self.assertEqual(len(result['taxa']),2)
        self.assertEqual(len(result['additionalSourceTaxa']),1)
        self.assertEqual(len(result['unrepresentedTaxa']),1)
        self.assertEqual(result['identityAliases'][0]['italicId'],2)
        self.assertEqual(len(result['diagnostics']['unresolvedTerminals']),2)
        self.assertEqual(result['pathCount'],3)
        self.assertEqual(len(result['nodes']),9)
        self.assertEqual(next(n for n in result['nodes'] if n['id']=='lead_8')['officialNode'],5)

    def test_actual_name_conflict_is_never_reconciled(self):
        self.full['keyData'][5]['leadSpecies']='A different species'
        with self.assertRaisesRegex(ValueError,'Identity conflict'):self.build()

    def test_missing_associated_audit_and_wrong_identity_abort(self):
        self.associated={}
        with self.assertRaisesRegex(ValueError,'audit'):self.build()
        self.associated={3:dict(scientific_name='wrong',keys=[])}
        with self.assertRaisesRegex(ValueError,'audit'):self.build()

    def test_associated_key_domain_and_schema_are_validated(self):
        self.associated[3]['keys']=[dict(link='https://dryades.units.it/home/index.php?procedure=ext_key_home&key_id=4833',title='Official key')]
        self.assertEqual(len(self.build()['unrepresentedTaxa'][0]['associatedKeys']),1)
        self.associated[3]['keys'][0]['link']='https://example.org/private'
        with self.assertRaisesRegex(ValueError,'associated key'):self.build()

    def test_image_variants_are_unified_but_conflicts_and_cycles_abort(self):
        duplicate=copy.deepcopy(self.full['keyData'][1]);duplicate['speciesImage']='image.jpg';self.full['keyData'].append(duplicate)
        self.assertEqual(self.build()['diagnostics']['duplicateImageVariants'],[1])
        duplicate['leadText']='changed'
        with self.assertRaisesRegex(ValueError,'duplicate'):self.build()
        self.setUp();self.full['keyData'][1]['parentId']=99
        with self.assertRaisesRegex(ValueError,'Orphan'):self.build()

    def test_scientific_comparisons_are_not_removed_as_html(self):
        self.assertEqual(module.plain('Thallus < 60 µm, <i>foliose</i> &amp; grey'),'Thallus < 60 µm, foliose & grey')


if __name__=='__main__':unittest.main()
