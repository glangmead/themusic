#!/usr/bin/env python3
"""Convert SHARC Timbre Dataset JSON files into a single compact JSON for app bundling.
Also generates vowel formant instruments from Ladefoged & Johnson (2011) data
and piano harmonic profiles from the AMY synthesizer project's heterodyne analysis
of University of Iowa Steinway recordings.

Usage:
    python3 bin/preprocess_sharc.py /path/to/sharc/repo Orbital/Resources/sharc_instruments.json [amy-piano-json]

Requires the SHARC repo: https://github.com/gregsandell/sharc
Optional: AMY piano-params.json from https://github.com/shorepine/amy
"""

import json
import math
import sys
import os

NOTE_TO_SEMITONE = {
    "c": 0, "cs": 1, "d": 2, "ds": 3, "e": 4, "f": 5,
    "fs": 6, "g": 7, "gs": 8, "a": 9, "as": 10, "b": 11,
}

DISPLAY_NAMES = {
    "alto_trombone": "Alto Trombone",
    "altoflute_vibrato": "Alto Flute",
    "Bach_trumpet": "Bach Trumpet",
    "bass_clarinet": "Bass Clarinet",
    "bass_trombone": "Bass Trombone",
    "bassflute_vibrato": "Bass Flute",
    "bassoon": "Bassoon",
    "Bb_clarinet": "B-flat Clarinet",
    "C_trumpet": "C Trumpet",
    "C_trumpet_muted": "C Trumpet (muted)",
    "CB": "Contrabass",
    "CB_martele": "Contrabass (martele)",
    "CB_muted": "Contrabass (muted)",
    "CB_pizz": "Contrabass (pizz)",
    "cello_martele": "Cello (martele)",
    "cello_muted_vibrato": "Cello (muted)",
    "cello_pizzicato": "Cello (pizz)",
    "cello_vibrato": "Cello",
    "contrabass_clarinet": "Contrabass Clarinet",
    "contrabassoon": "Contrabassoon",
    "Eb_clarinet": "E-flat Clarinet",
    "English_horn": "English Horn",
    "flute_vibrato": "Flute",
    "French_horn": "French Horn",
    "French_horn_muted": "French Horn (muted)",
    "oboe": "Oboe",
    "piccolo": "Piccolo",
    "trombone": "Trombone",
    "trombone_muted": "Trombone (muted)",
    "tuba": "Tuba",
    "viola_martele": "Viola (martele)",
    "viola_muted_vibrato": "Viola (muted)",
    "viola_pizzicato": "Viola (pizz)",
    "viola_vibrato": "Viola",
    "violin_martele": "Violin (martele)",
    "violin_muted_vibrato": "Violin (muted)",
    "violin_pizzicato": "Violin (pizz)",
    "violin_vibrato": "Violin",
    "violinensemb": "Violin Ensemble",
}


def note_name_to_midi(name: str) -> int:
    """Convert SHARC note name (e.g. 'as3', 'cs5') to MIDI note number."""
    name = name.replace("#", "s")
    for length in (2, 1):
        prefix = name[:length]
        if prefix in NOTE_TO_SEMITONE:
            octave = int(name[length:])
            return 12 * (octave + 1) + NOTE_TO_SEMITONE[prefix]
    raise ValueError(f"Unknown note: {name}")


def load_amy_piano(amy_path: str) -> list:
    """Load AMY heterodyne piano analysis and convert to SHARC-compatible format.

    AMY stores frequencies as centinotes (MIDI note * 100) and magnitudes as
    dB on a 0-100 scale with 20 time-sample snapshots per partial. We take the
    mf velocity (index 1) and use peak magnitude over time for each partial,
    then convert to linear amplitude normalized to [0, 1].
    """
    with open(amy_path) as f:
        amy = json.load(f)

    notes_midi = amy["notes"]           # 21 MIDI pitches
    velocities = amy["velocities"]      # [40, 80, 120]
    num_harmonics = amy["num_harmonics"]  # 63 entries (21 notes * 3 velocities)
    harmonics_mags = amy["harmonics_mags"]  # flat list of time-series arrays

    vel_idx = 1  # mf (velocity 80)
    sharc_notes = []

    for note_idx, midi_note in enumerate(notes_midi):
        combo = note_idx * len(velocities) + vel_idx
        nh = num_harmonics[combo]
        offset = sum(num_harmonics[:combo])

        # Peak magnitude over 20 time samples for each partial, dB scale 0-100
        peak_db = [max(harmonics_mags[offset + i]) for i in range(nh)]

        # Convert dB (0-100, where 100 = loudest) to linear amplitude
        linear = [10.0 ** ((db - 100.0) / 20.0) for db in peak_db]

        # Normalize to max = 1
        mx = max(linear) if linear else 1.0
        normalized = [round(a / mx, 6) for a in linear]

        sharc_notes.append({"midiNote": midi_note, "harmonics": normalized})

    return [{
        "id": "amy_piano_steinway",
        "displayName": "Piano (Steinway)",
        "notes": sharc_notes,
    }]


def build_vowel_instruments():
    """Generate vowel formant instruments from Ladefoged & Johnson (2011), figure 2.4."""
    VOWELS = [
        {"id": "vowel_ee",  "displayName": "Vowel: ee (heed)",  "formants": [(280, 80), (2250, 120), (2890, 150)]},
        {"id": "vowel_ih",  "displayName": "Vowel: ih (hid)",   "formants": [(400, 80), (1920, 120), (2560, 150)]},
        {"id": "vowel_eh",  "displayName": "Vowel: eh (head)",  "formants": [(550, 80), (1770, 120), (2490, 150)]},
        {"id": "vowel_aah", "displayName": "Vowel: aah (had)",  "formants": [(690, 80), (1660, 120), (2490, 150)]},
        {"id": "vowel_ah",  "displayName": "Vowel: ah (hod)",   "formants": [(710, 80), (1100, 120), (2540, 150)]},
        {"id": "vowel_aw",  "displayName": "Vowel: aw (hawed)", "formants": [(590, 80), (880,  120), (2540, 150)]},
        {"id": "vowel_uh",  "displayName": "Vowel: uh (hood)",  "formants": [(450, 80), (1030, 120), (2380, 150)]},
        {"id": "vowel_ooh", "displayName": "Vowel: ooh (who'd)","formants": [(310, 80), (870,  120), (2250, 150)]},
    ]

    def lorentzian(f, f_center, bandwidth):
        half_bw = bandwidth / 2.0
        return 1.0 / (1.0 + ((f - f_center) / half_bw) ** 2)

    def vowel_harmonics(f0, formants, max_freq=10000.0):
        harmonics = []
        n = 1
        while n * f0 < max_freq:
            freq = n * f0
            amp = sum(lorentzian(freq, fc, bw) for fc, bw in formants)
            harmonics.append(amp)
            n += 1
        if not harmonics:
            return [1.0]
        peak = max(harmonics)
        if peak > 0:
            harmonics = [round(a / peak, 6) for a in harmonics]
        return harmonics

    instruments = []
    for vowel in VOWELS:
        notes = []
        for midi in range(36, 97):  # C2 to C7
            f0 = 440.0 * (2.0 ** ((midi - 69) / 12.0))
            harms = vowel_harmonics(f0, vowel["formants"])
            notes.append({"midiNote": midi, "harmonics": harms})
        instruments.append({
            "id": vowel["id"],
            "displayName": vowel["displayName"],
            "notes": notes,
        })
    return instruments


def build_sharc_instruments(sharc_dir):
    """Load SHARC instrument data from the repo checkout."""
    metadata_path = os.path.join(sharc_dir, "json", "metadata.json")
    with open(metadata_path) as f:
        metadata = json.load(f)

    instruments = []
    for inst in metadata:
        inst_id = inst["instname"]
        notes = []
        for note_entry in inst["notes"]:
            filepath = os.path.join(sharc_dir, note_entry["file"])
            with open(filepath) as f:
                data = json.load(f)
            midi = note_name_to_midi(data["note"])
            amps = [h["amp"] for h in data["harmonics"]]
            max_amp = max(amps) if amps else 1.0
            normalized = [round(a / max_amp, 6) for a in amps]
            notes.append({"midiNote": midi, "harmonics": normalized})
        notes.sort(key=lambda n: n["midiNote"])
        instruments.append({
            "id": inst_id,
            "displayName": DISPLAY_NAMES.get(inst_id, inst_id),
            "notes": notes,
        })
    return instruments


def write_output(instruments, output_path):
    instruments.sort(key=lambda i: i["displayName"])
    output = {"instruments": instruments}
    with open(output_path, "w") as f:
        json.dump(output, f, separators=(",", ":"))
    size_kb = os.path.getsize(output_path) / 1024
    print(
        f"Wrote {len(instruments)} instruments, "
        f"{sum(len(i['notes']) for i in instruments)} notes "
        f"({size_kb:.0f} KB) to {output_path}"
    )


def main():
    # Mode 1: --add-amy <amy-json> <existing-output-json>
    #   Merges AMY instruments into an existing sharc_instruments.json
    if len(sys.argv) >= 2 and sys.argv[1] == "--add-amy":
        if len(sys.argv) != 4:
            print(f"Usage: {sys.argv[0]} --add-amy <amy-piano-json> <output-json-path>")
            sys.exit(1)
        amy_path = sys.argv[2]
        output_path = sys.argv[3]

        with open(output_path) as f:
            existing = json.load(f)
        instruments = existing["instruments"]

        # Remove any previous AMY entries
        instruments = [i for i in instruments if not i["id"].startswith("amy_")]

        instruments.extend(load_amy_piano(amy_path))
        write_output(instruments, output_path)
        return

    # Mode 2: full rebuild from SHARC repo
    if len(sys.argv) < 3:
        print(f"Usage: {sys.argv[0]} <sharc-repo-path> <output-json-path> [amy-piano-json]")
        print(f"       {sys.argv[0]} --add-amy <amy-piano-json> <output-json-path>")
        sys.exit(1)

    sharc_dir = sys.argv[1]
    output_path = sys.argv[2]

    instruments = build_sharc_instruments(sharc_dir)
    instruments.extend(build_vowel_instruments())

    amy_path = sys.argv[3] if len(sys.argv) > 3 else None
    if amy_path and os.path.isfile(amy_path):
        instruments.extend(load_amy_piano(amy_path))
    elif amy_path:
        print(f"Warning: AMY piano file not found: {amy_path}", file=sys.stderr)

    write_output(instruments, output_path)


if __name__ == "__main__":
    main()
