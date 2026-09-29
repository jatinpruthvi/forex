import sys
from histdata import download_hist_data as dl

year, pair, out_path = sys.argv[1], sys.argv[2].lower(), sys.argv[3]
month = sys.argv[4] if len(sys.argv) > 4 else None
import os
kwargs = dict(
    year=year, pair=pair.lower(), time_frame='M1', platform='ASCII',
    output_directory=os.path.dirname(out_path) or '.', verbose=False
)
if month:
    kwargs['month'] = month
dl(**kwargs)
print(f"downloaded {pair} {year}{'-'+month if month else ''} -> {out_path}")