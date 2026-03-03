#!/usr/bin/env python3
"""
Build a filtered subset of pdmx_composers containing only works with
Wikidata links, passing quality and noise-title filters.

Filters applied:
1. Work must have a wikidata_id (from enrich_wikidata.py)
2. Quality: rating > 0 OR n_views >= 50
3. Noise title: excludes works with WIP, easy, simplified, beginner,
   single line, cover, remix, my version, practice in the title

Input:  pdmx_composers/
Output: pdmx_composers_with_wiki/
"""

import json
import re
import shutil
import sys
from pathlib import Path

PDMX_ROOT = Path(__file__).parent
SRC = PDMX_ROOT / "pdmx_composers"
DST = PDMX_ROOT / "pdmx_composers_with_wiki"

MIN_VIEWS = 50

NOISE_RE = re.compile(
    r'\bsingle\s*line\b'
    r'|\bsimplified\b'
    r'|\beasy\b'
    r'|\bbeginner\b'
    r'|\bmy version\b'
    r'|\bcover\b'
    r'|\bremix\b'
    r'|\bpractice\b'
    r'|\bWIP\b',
    re.IGNORECASE
)


def main():
    if DST.exists():
        shutil.rmtree(DST)

    with open(SRC / "manifest.json") as f:
        manifest = json.load(f)

    new_composers = []
    total_works = 0
    total_mxl = 0
    total_mid = 0
    dropped_no_wd = 0
    dropped_quality = 0
    dropped_noise = 0

    for c in manifest["composers"]:
        slug = c["slug"]
        src_idx = SRC / slug / "index.json"
        if not src_idx.exists():
            continue

        with open(src_idx) as f:
            data = json.loads(f.readline())

        kept = []
        for w in data.get("works", []):
            if "wikidata_id" not in w:
                dropped_no_wd += 1
                continue
            pdmx = w.get("pdmx", {})
            rating = pdmx.get("rating", 0)
            views = pdmx.get("n_views", 0)
            if not (rating > 0 or views >= MIN_VIEWS):
                dropped_quality += 1
                continue
            if NOISE_RE.search(w["title"]):
                dropped_noise += 1
                continue
            kept.append(w)

        if not kept:
            continue

        dst_dir = DST / slug
        dst_mxl = dst_dir / "musicxml"
        dst_mid = dst_dir / "midi"
        dst_mxl.mkdir(parents=True, exist_ok=True)
        dst_mid.mkdir(parents=True, exist_ok=True)

        n_mxl = 0
        n_mid = 0
        for w in kept:
            mxl_rel = w.get("musicxml")
            mid_rel = w.get("midi")
            if mxl_rel:
                mxl_src = SRC / slug / mxl_rel
                if mxl_src.exists():
                    shutil.copy2(mxl_src, dst_mxl / mxl_src.name)
                    n_mxl += 1
            if mid_rel:
                mid_src = SRC / slug / mid_rel
                if mid_src.exists():
                    shutil.copy2(mid_src, dst_mid / mid_src.name)
                    n_mid += 1

        data["works"] = kept
        with open(dst_dir / "index.json", "w") as f:
            f.write(json.dumps(data, ensure_ascii=False) + "\n")

        new_composers.append({"slug": slug, "n_works": len(kept)})
        total_works += len(kept)
        total_mxl += n_mxl
        total_mid += n_mid

    new_manifest = {
        "total_composers": len(new_composers),
        "total_works": total_works,
        "total_mxl": total_mxl,
        "total_mid": total_mid,
        "composers": new_composers,
    }
    with open(DST / "manifest.json", "w") as f:
        json.dump(new_manifest, f, indent=2)

    total_input = sum(
        c.get("n_works", 0) for c in manifest["composers"])
    print("Filtered %d -> %d works (%d composers)" % (
        total_input, total_works, len(new_composers)))
    print("  Dropped: %d no Wikidata, %d low quality, %d noise title" % (
        dropped_no_wd, dropped_quality, dropped_noise))


if __name__ == "__main__":
    main()
