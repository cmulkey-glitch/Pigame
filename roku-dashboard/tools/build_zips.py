"""Build data/zip/NNN.csv (ZIP -> lat/lon) from the Census ZCTA gazetteer (public domain).

    curl -O https://www2.census.gov/geo/docs/maps-data/data/gazetteer/2023_Gazetteer/2023_Gaz_zcta_national.zip
    unzip 2023_Gaz_zcta_national.zip
    python3 tools/build_zips.py 2023_Gaz_zcta_national.txt

One file per 3-digit prefix keeps each lookup to a few KB on the Roku. Lines are
"LL,lat,lon" (last two ZIP digits); 3 decimals is ~100 m, plenty for a forecast grid.
"""
import csv
import os
import sys
from collections import defaultdict

out_dir = os.path.join(os.path.dirname(os.path.abspath(__file__)), '..', 'data', 'zip')
groups = defaultdict(list)
with open(sys.argv[1], newline='') as f:
    rows = csv.reader(f, delimiter='\t')
    header = [h.strip() for h in next(rows)]
    zi, la, lo = header.index('GEOID'), header.index('INTPTLAT'), header.index('INTPTLONG')
    for r in rows:
        z = r[zi].strip()
        groups[z[:3]].append(f'{z[3:]},{float(r[la]):.3f},{float(r[lo]):.3f}')

os.makedirs(out_dir, exist_ok=True)
for name in os.listdir(out_dir):
    if name.endswith('.csv'):
        os.remove(os.path.join(out_dir, name))
for prefix, lines in sorted(groups.items()):
    with open(os.path.join(out_dir, prefix + '.csv'), 'w') as f:
        f.write('\n'.join(sorted(lines)) + '\n')
print(f'{sum(len(v) for v in groups.values())} ZIPs in {len(groups)} files')
