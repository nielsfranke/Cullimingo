#!/usr/bin/env bash
# Builds the offline reverse-geocoding gazetteer asset from GeoNames
# (https://www.geonames.org, CC-BY 4.0 — keep the attribution in README.md).
#
# Downloads cities1000 (every place with population ≥ 1000, ~140k rows) plus
# the admin1 (state/province) and country name tables, joins them, and writes
# the compact asset the app ships:
#
#   assets/geo/cities.tsv.gz   lat <TAB> lon <TAB> city <TAB> state <TAB>
#                              country <TAB> ISO-3166-1 alpha-2
#
# Re-run to refresh the data; commit the regenerated asset.
set -euo pipefail

cd "$(dirname "$0")/.."
workdir=$(mktemp -d)
trap 'rm -rf "$workdir"' EXIT

echo "Downloading GeoNames dumps…"
curl -fsSL -o "$workdir/cities1000.zip" \
  https://download.geonames.org/export/dump/cities1000.zip
curl -fsSL -o "$workdir/admin1.txt" \
  https://download.geonames.org/export/dump/admin1CodesASCII.txt
curl -fsSL -o "$workdir/countryInfo.txt" \
  https://download.geonames.org/export/dump/countryInfo.txt
unzip -q -o "$workdir/cities1000.zip" -d "$workdir"

echo "Joining and compacting…"
mkdir -p assets/geo
python3 - "$workdir" <<'PY'
import csv, gzip, sys

work = sys.argv[1]

admin1 = {}
with open(f"{work}/admin1.txt", encoding="utf-8") as f:
    for row in csv.reader(f, delimiter="\t"):
        if len(row) >= 2:
            admin1[row[0]] = row[1]  # "CC.CODE" -> name

countries = {}
with open(f"{work}/countryInfo.txt", encoding="utf-8") as f:
    for line in f:
        if line.startswith("#"):
            continue
        cols = line.rstrip("\n").split("\t")
        if len(cols) >= 5:
            countries[cols[0]] = cols[4]  # ISO -> country name

# Sections of a bigger place (PPLX — city districts/neighbourhoods) and mere
# localities (PPLL) would win nearest-neighbour inside big cities, but IPTC
# City wants the city itself; historical/abandoned places would caption
# things that no longer exist.
SKIP_FEATURES = {"PPLX", "PPLL", "PPLH", "PPLQ", "PPLW"}

rows = 0
with open(f"{work}/cities1000.txt", encoding="utf-8") as src, \
     gzip.open("assets/geo/cities.tsv.gz", "wt", encoding="utf-8") as out:
    for cols in csv.reader(src, delimiter="\t", quoting=csv.QUOTE_NONE):
        # GeoNames columns: 1 name, 4 lat, 5 lon, 7 feature code,
        # 8 country code, 10 admin1.
        if cols[7] in SKIP_FEATURES:
            continue
        name, lat, lon, cc, a1 = cols[1], cols[4], cols[5], cols[8], cols[10]
        state = admin1.get(f"{cc}.{a1}", "")
        country = countries.get(cc, "")
        out.write(f"{lat}\t{lon}\t{name}\t{state}\t{country}\t{cc}\n")
        rows += 1
print(f"Wrote assets/geo/cities.tsv.gz ({rows} places)")
PY

ls -lh assets/geo/cities.tsv.gz
