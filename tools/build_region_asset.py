"""Convert the official ISTAT generalized 2026 regions to the offline app asset.

Usage: python build_region_asset.py Limiti01012026_g.zip OUTPUT.json
Requires pyshp and pyproj. Keeps multipart polygons and holes; does not simplify.
Source/license are embedded in the resulting JSON. Coordinates are EPSG:4326.
"""
import argparse
import io
import json
import zipfile
from pathlib import Path

import shapefile
from pyproj import Transformer


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('archive', type=Path)
    parser.add_argument('output', type=Path)
    args = parser.parse_args()
    with zipfile.ZipFile(args.archive) as archive:
        stem = 'Reg01012026_g/Reg01012026_g_WGS84'
        reader = shapefile.Reader(shp=io.BytesIO(archive.read(stem + '.shp')),
                                  dbf=io.BytesIO(archive.read(stem + '.dbf')),
                                  encoding='utf-8')
        transform = Transformer.from_crs(archive.read(stem + '.prj').decode(),
                                         'EPSG:4326', always_xy=True)
        regions = []
        for record in reader.iterShapeRecords():
            data = record.record.as_dict()
            parts = list(record.shape.parts) + [len(record.shape.points)]
            rings = [[[round(x, 6), round(y, 6)]
                      for x, y in (transform.transform(*point)
                                   for point in record.shape.points[a:b])]
                     for a, b in zip(parts, parts[1:])]
            regions.append({'id': str(data['COD_REG']), 'name': data['DEN_REG'], 'rings': rings})
    assert len(regions) == 20
    result = {
        'source': 'Istat – Confini amministrativi generalizzati al 1 gennaio 2026',
        'url': 'https://www.istat.it/storage/cartografia/confini_amministrativi/generalizzati/2026/Limiti01012026_g.zip',
        'license': 'CC BY 4.0', 'crs': 'EPSG:4326', 'regions': regions,
    }
    args.output.write_text(json.dumps(result, ensure_ascii=False, separators=(',', ':')))


if __name__ == '__main__':
    main()
