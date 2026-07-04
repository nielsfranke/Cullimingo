#!/usr/bin/env bash
# Builds the IPTC Media Topics vocabulary asset from the official NewsCodes
# server (https://cv.iptc.org, CC-BY 4.0 — keep the attribution in README.md).
#
# Downloads the full mediatopic concept set (EN) and writes the compact asset
# the app ships, one topic per line, retired concepts dropped:
#
#   assets/iptc/mediatopics.tsv.gz   qcode <TAB> label <TAB> parent label
#
# Re-run to refresh the data; commit the regenerated asset.
set -euo pipefail

cd "$(dirname "$0")/.."
workdir=$(mktemp -d)
trap 'rm -rf "$workdir"' EXIT

echo "Downloading IPTC Media Topics…"
curl -fsSL -o "$workdir/mediatopics.json" \
  "https://cv.iptc.org/newscodes/mediatopic/?format=json&lang=en"

echo "Compacting…"
mkdir -p assets/iptc
python3 - "$workdir" <<'PY'
import gzip, json, sys

work = sys.argv[1]
doc = json.load(open(f"{work}/mediatopics.json", encoding="utf-8"))
concepts = doc["conceptSet"]

def label(concept):
    pref = concept.get("prefLabel") or {}
    # The EN scheme labels come as en-GB; take any en-* as fallback.
    for key in ("en-GB", "en-US", "en"):
        if key in pref:
            return pref[key]
    return next(iter(pref.values()), "")

by_qcode = {c["qcode"]: c for c in concepts if "qcode" in c}

rows = 0
with gzip.open("assets/iptc/mediatopics.tsv.gz", "wt", encoding="utf-8") as out:
    for c in concepts:
        qcode = c.get("qcode", "")
        name = label(c)
        if not qcode or not name or c.get("retired"):
            continue
        parents = c.get("broader") or []
        parent = by_qcode.get(parents[0]) if parents else None
        parent_label = label(parent) if parent else ""
        out.write(f"{qcode}\t{name}\t{parent_label}\n")
        rows += 1
print(f"Wrote assets/iptc/mediatopics.tsv.gz ({rows} topics)")
PY

ls -lh assets/iptc/mediatopics.tsv.gz
