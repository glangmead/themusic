#!/usr/bin/env python3
"""
Offline enrichment: extract birth/death years, set catalog types,
clean up instrument lists, normalize catalog numbers.
No network access needed.
"""

import json
import re
import sys
from pathlib import Path

OUTPUT_ROOT = Path(__file__).parent / "pdmx_composers"

# Known catalog type mappings
CATALOG_TYPES = {
    "Johann Sebastian Bach": "BWV",
    "Wolfgang Amadeus Mozart": "K",
    "Ludwig van Beethoven": "Op",
    "Franz Schubert": "D",
    "Joseph Haydn": "Hob",
    "Frédéric Chopin": "Op",
    "Antonio Vivaldi": "RV",
    "George Frideric Handel": "HWV",
    "Domenico Scarlatti": "K",
    "Franz Liszt": "S",
    "Robert Schumann": "Op",
    "Johannes Brahms": "Op",
    "Sergei Rachmaninoff": "Op",
    "Pyotr Ilyich Tchaikovsky": "Op",
    "Claude Debussy": "L",
    "Antonín Dvořák": "Op",
    "Edvard Grieg": "Op",
    "Felix Mendelssohn": "Op",
    "Camille Saint-Saëns": "Op",
    "Alexander Scriabin": "Op",
    "Sergei Prokofiev": "Op",
    "Dmitri Shostakovich": "Op",
    "Jean-Philippe Rameau": "RCT",
    "Georg Philipp Telemann": "TWV",
    "Arcangelo Corelli": "Op",
    "Henry Purcell": "Z",
    "Richard Strauss": "Op",
    "Gabriel Fauré": "Op",
    "César Franck": "FWV",
    "Max Reger": "Op",
    "Carl Maria von Weber": "Op",
    "Hector Berlioz": "Op",
    "Erik Satie": "",
    "Maurice Ravel": "M",
    "Jean Sibelius": "Op",
    "Giacomo Puccini": "",
    "Giuseppe Verdi": "",
    "Richard Wagner": "WWV",
    "Gustav Mahler": "",
    "Anton Bruckner": "WAB",
    "Bedřich Smetana": "JB",
    "Modest Mussorgsky": "",
    "Nikolai Rimsky-Korsakov": "Op",
    "Mikhail Glinka": "",
    "Mily Balakirev": "",
    "Carl Philipp Emanuel Bach": "Wq",
    "Johann Christian Bach": "W",
    "Dietrich Buxtehude": "BuxWV",
    "François Couperin": "",
    "Jean-Baptiste Lully": "LWV",
    "Claudio Monteverdi": "SV",
    "Giovanni Pierluigi da Palestrina": "",
    "Orlando di Lasso": "",
    "William Byrd": "",
    "Thomas Tallis": "",
    "Tomás Luis de Victoria": "",
    "Josquin des Prez": "",
    "Guillaume de Machaut": "",
    "Hildegard von Bingen": "",
    "Giovanni Gabrieli": "",
    "Andrea Gabrieli": "",
    "Heinrich Schütz": "SWV",
    "Samuel Barber": "Op",
    "Leonard Bernstein": "",
    "Edward Elgar": "Op",
    "Benjamin Britten": "Op",
    "Ralph Vaughan Williams": "",
    "Gustav Holst": "Op",
    "Percy Grainger": "",
    "Amy Beach": "Op",
    "Charles Ives": "",
    "Scott Joplin": "",
    "Isaac Albéniz": "Op",
    "Enrique Granados": "Op",
    "Manuel de Falla": "",
    "Béla Bartók": "Sz",
    "Zoltán Kodály": "Op",
    "Leoš Janáček": "JW",
    "Nikolai Medtner": "Op",
    "Alexander Glazunov": "Op",
    "Aram Khachaturian": "",
    "Reinhold Glière": "Op",
}


def extract_years(dates_str):
    """Extract birth and death years from dates string."""
    if not dates_str:
        return None, None
    # Handle various formats: "1685 – 1750", "c. 1325 – 1397", "1098–1179"
    years = re.findall(r'(\d{3,4})', dates_str)
    birth = int(years[0]) if len(years) >= 1 else None
    death = int(years[1]) if len(years) >= 2 else None
    return birth, death


def clean_instruments(instruments):
    """Deduplicate and clean instrument lists."""
    if not instruments:
        return None
    # Deduplicate while preserving order
    seen = set()
    clean = []
    for inst in instruments:
        inst_lower = inst.strip().lower()
        if inst_lower and inst_lower not in seen and inst_lower != "na":
            seen.add(inst_lower)
            # Capitalize properly
            clean.append(inst.strip())
    return clean if clean else None


def clean_tempo_markings(tempos):
    """Deduplicate and clean tempo markings, remove MuseScore internal ones."""
    if not tempos:
        return None
    seen = set()
    clean = []
    for t in tempos:
        t = t.strip()
        # Skip MuseScore internal metronome marks
        if re.match(r'^metNote\w+\s*=\s*[\d.]+$', t):
            continue
        if re.match(r'^unicodeNote\w+\s*=\s*[\d.]+$', t):
            continue
        if re.match(r'^[\ue000-\uf8ff]', t):  # Private use area chars (MuseScore glyphs)
            continue
        # Convert unicode note names to readable form
        t = re.sub(r'unicodeNoteQuarterUp', '♩', t)
        t = re.sub(r'unicodeNoteHalfUp', '𝅗𝅥', t)
        t = re.sub(r'unicodeNoteEighthUp', '♪', t)
        t_lower = t.lower()
        if t_lower and t_lower not in seen:
            seen.add(t_lower)
            clean.append(t)
    return clean if clean else None


def infer_key_from_title(title):
    """Try to extract key from work title."""
    m = re.search(
        r'in\s+([A-G][-♯♭#b]?\s*(?:major|minor|Major|Minor|maj|min|moll|dur))',
        title, re.IGNORECASE
    )
    if m:
        key = m.group(1).strip()
        # Normalize
        key = key.replace('#', '♯').replace('b', '♭') if len(key) > 2 else key
        return key

    # Also check for standalone key patterns like "C-sharp minor"
    m = re.search(
        r'([A-G][-]?(?:sharp|flat)?\s*(?:major|minor))',
        title, re.IGNORECASE
    )
    if m:
        return m.group(1).strip()
    return None


def main():
    if len(sys.argv) > 1:
        output_root = Path(sys.argv[1])
    else:
        output_root = OUTPUT_ROOT

    manifest = json.load(open(output_root / "manifest.json"))
    composers = manifest["composers"]

    stats = {
        "years_added": 0,
        "catalog_type_set": 0,
        "instruments_cleaned": 0,
        "tempos_cleaned": 0,
        "keys_inferred": 0,
        "total_works": 0,
    }

    for i, c in enumerate(composers):
        slug = c["slug"]
        index_path = output_root / slug / "index.json"
        if not index_path.exists():
            continue

        data = json.loads(index_path.read_text().strip())

        # 1. Birth/death years
        birth, death = extract_years(data.get("dates", ""))
        if birth and "birth_year" not in data:
            data["birth_year"] = birth
            stats["years_added"] += 1
        if death and "death_year" not in data:
            data["death_year"] = death

        # 2. Catalog type
        name = data.get("composer_name", "")
        if name in CATALOG_TYPES and CATALOG_TYPES[name]:
            data["catalog_type"] = CATALOG_TYPES[name]
            stats["catalog_type_set"] += 1

        # 3. Clean up each work
        for work in data.get("works", []):
            stats["total_works"] += 1

            # Clean instruments
            if "instruments" in work:
                cleaned = clean_instruments(work["instruments"])
                if cleaned != work["instruments"]:
                    stats["instruments_cleaned"] += 1
                if cleaned:
                    work["instruments"] = cleaned
                else:
                    del work["instruments"]

            # Clean tempo markings
            if "tempo_markings" in work:
                cleaned = clean_tempo_markings(work["tempo_markings"])
                if cleaned != work["tempo_markings"]:
                    stats["tempos_cleaned"] += 1
                if cleaned:
                    work["tempo_markings"] = cleaned
                else:
                    del work["tempo_markings"]

            # Infer key from title if missing
            if "key" not in work and work.get("title"):
                key = infer_key_from_title(work["title"])
                if key:
                    work["key"] = key
                    stats["keys_inferred"] += 1

        # Write back
        index_path.write_text(json.dumps(data, ensure_ascii=False) + "\n")

        if (i + 1) % 50 == 0:
            print(f"  Progress: {i+1}/{len(composers)}")

    print(f"\nOffline Enrichment Complete")
    print(f"=" * 50)
    print(f"Composers processed:    {len(composers)}")
    print(f"Birth/death years added: {stats['years_added']}")
    print(f"Catalog types set:       {stats['catalog_type_set']}")
    print(f"Instruments cleaned:     {stats['instruments_cleaned']}")
    print(f"Tempos cleaned:          {stats['tempos_cleaned']}")
    print(f"Keys inferred from title: {stats['keys_inferred']}")
    print(f"Total works processed:   {stats['total_works']}")


if __name__ == "__main__":
    main()
