#!/usr/bin/env python3
"""
Enrichment: Extract metadata from .mxl MusicXML files and metadata/ JSON.

From MusicXML inside .mxl files:
  - <work-title>: parent work title (e.g. "6 Partitas")
  - <work-number>: catalog number (e.g. "BWV 825-830")
  - <movement-title>: specific movement name
  - <part-name>: actual instrument names (much better than GM program guesses)
  - <creator type="composer">: composer attribution
  - <creator type="arranger">: arranger if applicable

From metadata/ JSON (MuseScore metadata):
  - score.title: MuseScore's title (sometimes more structured)

These are joined to index.json works via PDMX.csv which maps
(composer_name, title) -> mxl path and metadata path.
"""

import csv
import json
import re
import sys
import zipfile
from pathlib import Path

PDMX_ROOT = Path(__file__).parent
OUTPUT_ROOT = PDMX_ROOT / "pdmx_composers"


def extract_mxl_metadata(mxl_path):
    """Extract metadata from MusicXML inside an .mxl file."""
    result = {}
    full_path = PDMX_ROOT / mxl_path
    if not full_path.exists():
        return result

    try:
        with zipfile.ZipFile(full_path) as z:
            # Find the score XML file (not container.xml)
            score_file = None
            for name in z.namelist():
                if not name.startswith('META-INF') and (
                    name.endswith('.xml') or name.endswith('.musicxml')
                ):
                    score_file = name
                    break
            if not score_file:
                return result

            with z.open(score_file) as xf:
                content = xf.read().decode('utf-8', errors='replace')[:15000]

                # <work-title>
                m = re.search(r'<work-title>(.*?)</work-title>', content)
                if m and m.group(1).strip():
                    result['work_title'] = m.group(1).strip()

                # <work-number>
                m = re.search(r'<work-number>(.*?)</work-number>', content)
                if m and m.group(1).strip():
                    result['work_number'] = m.group(1).strip()

                # <movement-title>
                m = re.search(r'<movement-title>(.*?)</movement-title>', content)
                if m and m.group(1).strip():
                    result['movement_title'] = m.group(1).strip()

                # <movement-number>
                m = re.search(r'<movement-number>(.*?)</movement-number>', content)
                if m and m.group(1).strip():
                    result['movement_number'] = m.group(1).strip()

                # <creator type="composer">
                m = re.search(r'<creator[^>]*type="composer"[^>]*>(.*?)</creator>', content)
                if m and m.group(1).strip():
                    result['mxl_composer'] = m.group(1).strip()

                # <creator type="arranger">
                m = re.search(r'<creator[^>]*type="arranger"[^>]*>(.*?)</creator>', content)
                if m and m.group(1).strip():
                    result['arranger'] = m.group(1).strip()

                # <creator type="lyricist">
                m = re.search(r'<creator[^>]*type="lyricist"[^>]*>(.*?)</creator>', content)
                if m and m.group(1).strip():
                    result['lyricist'] = m.group(1).strip()

                # <part-name> elements (actual instrument names)
                part_names = []
                for pm in re.finditer(r'<part-name>(.*?)</part-name>', content):
                    name = pm.group(1).strip()
                    if name and name.lower() not in ('', 'na', 'n/a'):
                        part_names.append(name)
                if part_names:
                    result['part_names'] = part_names

    except (zipfile.BadZipFile, OSError, UnicodeDecodeError):
        pass

    return result


def extract_catalog_from_work_number(work_number):
    """Parse catalog numbers from <work-number> field."""
    if not work_number:
        return {}

    cats = {}
    patterns = [
        (r'\bBWV\s*(\d+[a-z]?(?:[–\-]\d+)?)', "BWV"),
        (r'\bKV?\.?\s*(\d+[a-z]?)', "K"),
        (r'\bOp\.?\s*(\d+)', "Op"),
        (r'\bD\.?\s*(\d+)', "D"),
        (r'\bHob\.?\s*(\S+)', "Hob"),
        (r'\bRV\s*(\d+)', "RV"),
        (r'\bHWV\s*(\d+)', "HWV"),
        (r'\bS\.?\s*(\d+)', "S"),
        (r'\bL\.?\s*(\d+)', "L"),
        (r'\bWoO\.?\s*(\d+)', "WoO"),
        (r'\bSWV\s*(\d+)', "SWV"),
        (r'\bWAB\s*(\d+)', "WAB"),
        (r'\bBuxWV\s*(\d+)', "BuxWV"),
        (r'\bWq\.?\s*(\d+)', "Wq"),
        (r'\bSz\.?\s*(\d+)', "Sz"),
        (r'\bWWV\s*(\d+)', "WWV"),
        (r'\bZ\.?\s*(\d+)', "Z"),
        (r'\bTWV\s*(\S+)', "TWV"),
    ]
    for pattern, cat_type in patterns:
        m = re.search(pattern, work_number, re.IGNORECASE)
        if m:
            cats[cat_type] = m.group(1)
    return cats


def dedupe_parts(part_names):
    """Deduplicate and clean part names."""
    if not part_names:
        return None
    seen = set()
    clean = []
    for p in part_names:
        # Normalize: strip numbers like "Violin I", "Violin II" -> keep both
        p = p.strip()
        p_lower = p.lower()
        if p_lower and p_lower not in seen and p_lower not in ('', 'na', 'n/a', 'instrument'):
            seen.add(p_lower)
            clean.append(p)
    return clean if clean else None


def main():
    if len(sys.argv) > 1:
        output_root = Path(sys.argv[1])
    else:
        output_root = OUTPUT_ROOT

    manifest = json.load(open(output_root / "manifest.json"))

    # Build index: (composer_name_lower, title_lower) -> {mxl_path, metadata_path}
    # Also by musescore score_id -> paths
    print("Building CSV index...")
    csv_index = {}  # (composer, title) -> row data
    score_id_index = {}  # score_id -> row data

    with open(PDMX_ROOT / "PDMX.csv") as f:
        reader = csv.DictReader(f)
        for row in reader:
            composer = row.get("composer_name", "").strip().lower()
            title = row.get("title", "").strip().lower()
            mxl = row.get("mxl", "").lstrip("./")
            meta = row.get("metadata", "").lstrip("./")

            if composer and title:
                csv_index[(composer, title)] = {"mxl": mxl, "metadata": meta}

            if meta:
                m = re.search(r'/(\d+)\.json$', meta)
                if m:
                    score_id_index[m.group(1)] = {"mxl": mxl, "metadata": meta}

    print(f"  {len(csv_index)} (composer,title) entries, {len(score_id_index)} score IDs")

    stats = {
        "total_works": 0,
        "mxl_found": 0,
        "work_title_added": 0,
        "work_number_added": 0,
        "movement_title_added": 0,
        "parts_added": 0,
        "catalog_enriched": 0,
        "arranger_added": 0,
    }

    composers = manifest["composers"]
    for ci, c in enumerate(composers):
        slug = c["slug"]
        index_path = output_root / slug / "index.json"
        if not index_path.exists():
            continue

        data = json.loads(index_path.read_text().strip())
        composer_name = data.get("composer_name", "")
        changed = False

        for work in data.get("works", []):
            stats["total_works"] += 1

            # Find the MXL path via CSV index
            title = work.get("title", "")
            pdmx = work.get("pdmx", {})

            paths = None

            # Method 1: by (composer, title)
            key = (composer_name.lower(), title.lower())
            if key in csv_index:
                paths = csv_index[key]

            # Method 2: by MuseScore score ID
            if not paths:
                ms_url = pdmx.get("musescore_url", "")
                if ms_url:
                    m = re.search(r'/scores/(\d+)', ms_url)
                    if m:
                        paths = score_id_index.get(m.group(1))

            if not paths or not paths.get("mxl"):
                continue

            stats["mxl_found"] += 1

            # Extract MXL metadata
            mxl_meta = extract_mxl_metadata(paths["mxl"])

            if not mxl_meta:
                continue

            # Apply enrichments
            if "work_title" in mxl_meta:
                wt = mxl_meta["work_title"]
                # Only add if it's different from the existing title and seems meaningful
                if wt.lower() != title.lower() and len(wt) > 2:
                    work["parent_work_title"] = wt
                    stats["work_title_added"] += 1
                    changed = True

            if "work_number" in mxl_meta:
                work["work_number_raw"] = mxl_meta["work_number"]
                stats["work_number_added"] += 1
                changed = True

                # Try to extract catalog numbers from work-number
                cats = extract_catalog_from_work_number(mxl_meta["work_number"])
                for cat_type, cat_num in cats.items():
                    if cat_type not in work.get("catalog_numbers", {}):
                        work.setdefault("catalog_numbers", {})[cat_type] = cat_num
                        stats["catalog_enriched"] += 1

            if "movement_title" in mxl_meta:
                work["movement_title"] = mxl_meta["movement_title"]
                stats["movement_title_added"] += 1
                changed = True

            if "movement_number" in mxl_meta:
                work["movement_number"] = mxl_meta["movement_number"]
                changed = True

            if "part_names" in mxl_meta:
                parts = dedupe_parts(mxl_meta["part_names"])
                if parts:
                    work["instruments"] = parts  # Override GM instruments with real names
                    stats["parts_added"] += 1
                    changed = True

            if "arranger" in mxl_meta:
                work["arranger"] = mxl_meta["arranger"]
                stats["arranger_added"] += 1
                changed = True

            if "lyricist" in mxl_meta:
                work["lyricist"] = mxl_meta["lyricist"]
                changed = True

        if changed:
            index_path.write_text(json.dumps(data, ensure_ascii=False) + "\n")

        if (ci + 1) % 50 == 0:
            print(f"  Progress: {ci+1}/{len(composers)}")

    print(f"\nMXL Metadata Enrichment Complete")
    print(f"=" * 50)
    print(f"Total works:            {stats['total_works']}")
    print(f"MXL files found:        {stats['mxl_found']}")
    print(f"Parent work titles:     {stats['work_title_added']}")
    print(f"Work numbers (raw):     {stats['work_number_added']}")
    print(f"Movement titles:        {stats['movement_title_added']}")
    print(f"Part names (instruments): {stats['parts_added']}")
    print(f"Catalog numbers added:  {stats['catalog_enriched']}")
    print(f"Arrangers:              {stats['arranger_added']}")


if __name__ == "__main__":
    main()
