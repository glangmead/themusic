#!/usr/bin/env python3
"""
Phase 4: Deep enrichment from PDMX data/ JSON files.

For each work, re-reads the original data/ JSON to extract:
- Proper key name from key_signatures (fifths + mode)
- MIDI instrument names from track programs
- Actual tempo BPM
- Number of measures
- Duration in seconds (more accurate)
- Note density (notes per second)
"""

import csv
import json
import re
import sys
from pathlib import Path

PDMX_ROOT = Path(__file__).parent
OUTPUT_ROOT = PDMX_ROOT / "pdmx_composers"

# MIDI General MIDI program number -> instrument name
GM_INSTRUMENTS = {
    0: "Acoustic Grand Piano", 1: "Bright Acoustic Piano", 2: "Electric Grand Piano",
    3: "Honky-tonk Piano", 4: "Electric Piano 1", 5: "Electric Piano 2",
    6: "Harpsichord", 7: "Clavinet",
    8: "Celesta", 9: "Glockenspiel", 10: "Music Box", 11: "Vibraphone",
    12: "Marimba", 13: "Xylophone", 14: "Tubular Bells", 15: "Dulcimer",
    16: "Drawbar Organ", 17: "Percussive Organ", 18: "Rock Organ",
    19: "Church Organ", 20: "Reed Organ", 21: "Accordion",
    22: "Harmonica", 23: "Tango Accordion",
    24: "Acoustic Guitar (nylon)", 25: "Acoustic Guitar (steel)",
    26: "Electric Guitar (jazz)", 27: "Electric Guitar (clean)",
    28: "Electric Guitar (muted)", 29: "Overdriven Guitar",
    30: "Distortion Guitar", 31: "Guitar Harmonics",
    32: "Acoustic Bass", 33: "Electric Bass (finger)", 34: "Electric Bass (pick)",
    35: "Fretless Bass", 36: "Slap Bass 1", 37: "Slap Bass 2",
    38: "Synth Bass 1", 39: "Synth Bass 2",
    40: "Violin", 41: "Viola", 42: "Cello", 43: "Contrabass",
    44: "Tremolo Strings", 45: "Pizzicato Strings",
    46: "Orchestral Harp", 47: "Timpani",
    48: "String Ensemble 1", 49: "String Ensemble 2",
    50: "Synth Strings 1", 51: "Synth Strings 2",
    52: "Choir Aahs", 53: "Voice Oohs", 54: "Synth Choir", 55: "Orchestra Hit",
    56: "Trumpet", 57: "Trombone", 58: "Tuba", 59: "Muted Trumpet",
    60: "French Horn", 61: "Brass Section", 62: "Synth Brass 1", 63: "Synth Brass 2",
    64: "Soprano Sax", 65: "Alto Sax", 66: "Tenor Sax", 67: "Baritone Sax",
    68: "Oboe", 69: "English Horn", 70: "Bassoon", 71: "Clarinet",
    72: "Piccolo", 73: "Flute", 74: "Recorder", 75: "Pan Flute",
    76: "Blown Bottle", 77: "Shakuhachi", 78: "Whistle", 79: "Ocarina",
    80: "Lead 1 (square)", 81: "Lead 2 (sawtooth)", 82: "Lead 3 (calliope)",
    83: "Lead 4 (chiff)", 84: "Lead 5 (charang)", 85: "Lead 6 (voice)",
    86: "Lead 7 (fifths)", 87: "Lead 8 (bass + lead)",
    88: "Pad 1 (new age)", 89: "Pad 2 (warm)", 90: "Pad 3 (polysynth)",
    91: "Pad 4 (choir)", 92: "Pad 5 (bowed)", 93: "Pad 6 (metallic)",
    94: "Pad 7 (halo)", 95: "Pad 8 (sweep)",
    # Percussion
    113: "Tinkle Bell", 114: "Agogo", 115: "Steel Drums",
    116: "Woodblock", 117: "Taiko Drum", 118: "Melodic Tom",
    119: "Synth Drum",
}

# Key signature fifths -> key name
FIFTHS_TO_KEY = {
    -7: ("C♭", "A♭"), -6: ("G♭", "E♭"), -5: ("D♭", "B♭"),
    -4: ("A♭", "F"), -3: ("E♭", "C"), -2: ("B♭", "G"),
    -1: ("F", "D"), 0: ("C", "A"), 1: ("G", "E"),
    2: ("D", "B"), 3: ("A", "F♯"), 4: ("E", "C♯"),
    5: ("B", "G♯"), 6: ("F♯", "D♯"), 7: ("C♯", "A♯"),
}


def fifths_mode_to_key(fifths, mode):
    """Convert key signature fifths count and mode to key name."""
    if fifths is None:
        return None
    fifths = int(fifths)
    if fifths not in FIFTHS_TO_KEY:
        return None
    major, minor = FIFTHS_TO_KEY[fifths]
    if mode == "minor" or mode == 1:
        return f"{minor} minor"
    else:
        return f"{major} major"


def programs_to_instruments(tracks):
    """Extract unique instrument names from MIDI track programs."""
    instruments = []
    seen = set()
    for track in tracks:
        if track.get("is_drum"):
            if "Percussion" not in seen:
                instruments.append("Percussion")
                seen.add("Percussion")
            continue
        program = track.get("program")
        if program is not None and program in GM_INSTRUMENTS:
            name = GM_INSTRUMENTS[program]
            if name not in seen:
                instruments.append(name)
                seen.add(name)
    return instruments if instruments else None


def build_path_index():
    """Build index from PDMX.csv mapping mxl paths to data/ paths."""
    index = {}  # mxl_path -> data_path
    csv_path = PDMX_ROOT / "PDMX.csv"
    with open(csv_path) as f:
        reader = csv.DictReader(f)
        for row in reader:
            mxl = row.get("mxl", "")
            data = row.get("path", "")
            mid = row.get("mid", "")
            if mxl and data:
                # Normalize: strip ./
                mxl_clean = mxl.lstrip("./")
                data_clean = data.lstrip("./")
                mid_clean = mid.lstrip("./") if mid else ""
                index[mxl_clean] = data_clean
                if mid_clean:
                    index[mid_clean] = data_clean
    return index


def read_data_json(data_path):
    """Read a data/ JSON file and extract enrichment data."""
    full_path = PDMX_ROOT / data_path
    if not full_path.exists():
        return None

    try:
        with open(full_path) as f:
            data = json.load(f)
    except (json.JSONDecodeError, UnicodeDecodeError):
        return None

    result = {}

    # Key signature
    key_sigs = data.get("key_signatures", [])
    if key_sigs:
        first_ks = key_sigs[0]
        fifths = first_ks.get("fifths")
        mode = first_ks.get("mode")
        key = fifths_mode_to_key(fifths, mode)
        if key:
            result["key"] = key

        # If multiple key signatures, note the key changes
        if len(key_sigs) > 1:
            keys = []
            for ks in key_sigs:
                k = fifths_mode_to_key(ks.get("fifths"), ks.get("mode"))
                if k and k not in keys:
                    keys.append(k)
            if len(keys) > 1:
                result["key_changes"] = keys

    # Time signature
    time_sigs = data.get("time_signatures", [])
    if time_sigs:
        first_ts = time_sigs[0]
        num = first_ts.get("numerator")
        den = first_ts.get("denominator")
        if num and den:
            result["time_signature"] = f"{num}/{den}"

    # Tempo
    tempos = data.get("tempos", [])
    if tempos:
        first_tempo = tempos[0]
        qpm = first_tempo.get("qpm")
        if qpm:
            result["tempo_bpm"] = round(qpm)
            text = first_tempo.get("text", "")
            if text:
                result["tempo_marking"] = text

    # Instruments from tracks
    tracks = data.get("tracks", [])
    instruments = programs_to_instruments(tracks)
    if instruments:
        result["instruments_gm"] = instruments
    result["n_parts"] = len(tracks)

    # Barlines -> number of measures
    barlines = data.get("barlines", [])
    if barlines:
        measures = set()
        for bl in barlines:
            m = bl.get("measure")
            if m:
                measures.add(m)
        if measures:
            result["n_measures"] = max(measures)

    # Note count from tracks
    total_notes = 0
    for track in tracks:
        notes = track.get("notes", [])
        total_notes += len(notes)
    if total_notes > 0:
        result["n_notes"] = total_notes

    # Duration from song_length or last note
    song_length = data.get("song_length")
    if song_length:
        result["duration_ticks"] = song_length
        resolution = data.get("resolution", 480)
        if tempos and tempos[0].get("qpm"):
            # Approximate duration in seconds
            qpm = tempos[0]["qpm"]
            seconds = (song_length / resolution) * (60.0 / qpm)
            result["duration_seconds"] = round(seconds, 1)

    return result


def main():
    if len(sys.argv) > 1:
        output_root = Path(sys.argv[1])
    else:
        output_root = OUTPUT_ROOT

    manifest = json.load(open(output_root / "manifest.json"))

    print("Building MXL->data path index from PDMX.csv...")
    path_index = build_path_index()
    print(f"  Indexed {len(path_index)} paths")

    # We need to map each work's MXL file back to its PDMX path
    # The MXL filename in index.json is the renamed copy; we need the original PDMX path
    # The original path was stored... let me check if we saved it

    # Actually, let's build a different index: from the original mxl filename (the IPFS hash)
    # The build script renamed files, so we need to map back. Let's use the musescore_url
    # to find the metadata path, then the PDMX.csv row.

    # Better approach: index by musescore URL
    url_to_data = {}
    csv_path = PDMX_ROOT / "PDMX.csv"
    print("Building MuseScore URL -> data path index...")
    with open(csv_path) as f:
        reader = csv.DictReader(f)
        for row in reader:
            url = ""
            # The metadata JSON has the musescore URL; let's use the metadata path
            # Actually, let's just index by (composer_name, title)
            composer = row.get("composer_name", "").strip()
            title = row.get("title", "").strip()
            data_path = row.get("path", "").lstrip("./")
            if composer and title and data_path:
                key = (composer.lower(), title.lower())
                url_to_data[key] = data_path

    print(f"  Indexed {len(url_to_data)} (composer, title) pairs")

    # Also build by musescore URL from the metadata field in CSV
    # The CSV has a 'metadata' column with the metadata JSON path
    # and we stored musescore_url in the index.json
    url_to_data2 = {}
    with open(csv_path) as f:
        reader = csv.DictReader(f)
        for row in reader:
            # Extract score ID from metadata path like ./metadata/7/130028.json
            meta_path = row.get("metadata", "")
            data_path = row.get("path", "").lstrip("./")
            if meta_path and data_path:
                # Extract score ID
                m = re.search(r'/(\d+)\.json$', meta_path)
                if m:
                    score_id = m.group(1)
                    url_to_data2[score_id] = data_path

    print(f"  Indexed {len(url_to_data2)} score IDs")

    stats = {
        "keys_enriched": 0,
        "instruments_enriched": 0,
        "tempo_enriched": 0,
        "measures_added": 0,
        "total_works": 0,
        "matched": 0,
    }

    composers = manifest["composers"]
    for ci, c in enumerate(composers):
        slug = c["slug"]
        index_path = output_root / slug / "index.json"
        if not index_path.exists():
            continue

        data = json.loads(index_path.read_text().strip())
        composer_name = data.get("composer_name", "")

        for work in data.get("works", []):
            stats["total_works"] += 1

            # Try to find the data/ JSON path
            data_path = None

            # Method 1: Match by (composer, title) from the original PDMX title
            pdmx = work.get("pdmx", {})
            title = work.get("title", "")

            # Try exact match first
            key = (composer_name.lower(), title.lower())
            if key in url_to_data:
                data_path = url_to_data[key]

            # Method 2: Match by MuseScore URL -> score ID
            if not data_path:
                ms_url = pdmx.get("musescore_url", "")
                if ms_url:
                    m = re.search(r'/scores/(\d+)', ms_url)
                    if m:
                        score_id = m.group(1)
                        data_path = url_to_data2.get(score_id)

            if not data_path:
                continue

            # Read the data/ JSON
            enrichment = read_data_json(data_path)
            if not enrichment:
                continue

            stats["matched"] += 1

            # Apply enrichment
            if "key" in enrichment and "key" not in work:
                work["key"] = enrichment["key"]
                stats["keys_enriched"] += 1
            elif "key" in enrichment and work.get("key") != enrichment["key"]:
                # Keep the data/ JSON key as more authoritative
                work["key_from_data"] = enrichment["key"]

            if "key_changes" in enrichment:
                work["key_changes"] = enrichment["key_changes"]

            if "instruments_gm" in enrichment:
                work["instruments_gm"] = enrichment["instruments_gm"]
                stats["instruments_enriched"] += 1

            if "tempo_bpm" in enrichment:
                work["tempo_bpm"] = enrichment["tempo_bpm"]
                stats["tempo_enriched"] += 1

            if "n_measures" in enrichment:
                work["n_measures"] = enrichment["n_measures"]
                stats["measures_added"] += 1

            if "n_parts" in enrichment:
                work["n_parts"] = enrichment["n_parts"]

            if "n_notes" in enrichment:
                work["n_notes"] = enrichment["n_notes"]
                # Compute note density
                dur = pdmx.get("duration_seconds") or enrichment.get("duration_seconds")
                if dur and dur > 0:
                    work["notes_per_second"] = round(enrichment["n_notes"] / dur, 1)

        # Write back
        index_path.write_text(json.dumps(data, ensure_ascii=False) + "\n")

        if (ci + 1) % 50 == 0:
            print(f"  Progress: {ci+1}/{len(composers)}")

    print(f"\nPhase 4 Enrichment Complete")
    print(f"=" * 50)
    print(f"Total works:           {stats['total_works']}")
    print(f"Matched to data/ JSON: {stats['matched']}")
    print(f"Keys enriched:         {stats['keys_enriched']}")
    print(f"Instruments (GM):      {stats['instruments_enriched']}")
    print(f"Tempo BPM added:       {stats['tempo_enriched']}")
    print(f"Measure counts added:  {stats['measures_added']}")


if __name__ == "__main__":
    main()
