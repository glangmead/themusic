#!/usr/bin/env python3
"""
romantext_to_orbital.py

Convert a RomanText (.txt) harmonic analysis file into an Orbital scoreTracks JSON.

Usage:
    python3 romantext_to_orbital.py INPUT.txt [OPTIONS]

Options:
    --out FILE          Output JSON file (default: INPUT_orbital.json)
    --bpm N             Tempo in BPM (default: 72)
    --preset NAME       Instrument preset for chord track (default: warm_analog_pad)
    --bass-preset NAME  Instrument preset for bass track
    --bass              Add a bass track (organ_baroque_positive preset)
    --octave N          Chord voicing octave (default: 3)
    --no-loop           Do not loop the pattern (default: loops)
    --min-duration N    Drop chord events shorter than N beats (default: 0.25)
    --measures A-B      Only include measures A through B (e.g. --measures 1-16)
    --section NAME      Only include the named Form section (e.g. "Verse")
    --voices N          Number of voices per chord track (default: 6)
    --sustain F         Sustain fraction 0-1 (default: 0.85)

Example:
    python3 romantext_to_orbital.py riemenschneider181.txt --bpm 80 --bass
"""

import argparse
import json
import os
import re
import sys
from dataclasses import dataclass
from typing import Optional


# ---------------------------------------------------------------------------
# Pitch helpers
# ---------------------------------------------------------------------------

PC_TO_SEMI = {'C': 0, 'D': 2, 'E': 4, 'F': 5, 'G': 7, 'A': 9, 'B': 11}
MAJOR_INTERVALS = [0, 2, 4, 5, 7, 9, 11]
MINOR_INTERVALS = [0, 2, 3, 5, 7, 8, 10]
# Prefer flat names to match Orbital's Tonic library conventions
SEMI_TO_PC = ['C', 'Db', 'D', 'Eb', 'E', 'F', 'F#', 'G', 'Ab', 'A', 'Bb', 'B']

NUMERAL_TO_DEGREE = {'I': 0, 'II': 1, 'III': 2, 'IV': 3, 'V': 4, 'VI': 5, 'VII': 6}


def parse_pitch_class(s: str) -> Optional[int]:
    s = s.strip()
    if not s or s[0].upper() not in PC_TO_SEMI:
        return None
    semi = PC_TO_SEMI[s[0].upper()]
    for ch in s[1:]:
        if ch == '#':
            semi += 1
        elif ch == 'b':
            semi -= 1
    return semi % 12


def scale_semitones(root_semi: int, scale: str) -> list:
    intervals = MAJOR_INTERVALS if scale == 'major' else MINOR_INTERVALS
    return [(root_semi + i) % 12 for i in intervals]


# ---------------------------------------------------------------------------
# Data types
# ---------------------------------------------------------------------------

@dataclass
class KeyState:
    root: str   # e.g. 'C', 'Bb', 'F#'
    scale: str  # 'major' or 'minor'

    def semitone(self) -> int:
        return parse_pitch_class(self.root)

    def __eq__(self, other):
        return self.root == other.root and self.scale == other.scale


@dataclass
class RawEvent:
    """A single parsed chord event from the body of a RomanText file."""
    beat: float         # absolute 0-indexed quarter-note beat
    measure: int        # original measure number
    roman: str          # chord symbol as written (e.g. "V7/V", "ii6/5")
    key: KeyState       # key context at this chord


# ---------------------------------------------------------------------------
# RomanText parser
# ---------------------------------------------------------------------------

BEAT_RE = re.compile(r'^b(\d+(?:\.\d+)?)$')
KEY_PREFIX_RE = re.compile(r'^([A-Ga-g][b#]*):\s*(.*)$')


def parse_key_str(s: str) -> Optional[KeyState]:
    """Parse a RomanText key token like 'C', 'Bb', 'f#' → KeyState."""
    s = s.strip()
    if not s or s[0].upper() not in PC_TO_SEMI:
        return None
    scale = 'major' if s[0].isupper() else 'minor'
    root = s[0].upper() + s[1:]
    return KeyState(root=root, scale=scale)


def parse_time_sig(s: str) -> tuple:
    m = re.match(r'(\d+)/(\d+)', s.strip())
    return (int(m.group(1)), int(m.group(2))) if m else (4, 4)


def beats_per_measure(num: int, den: int) -> float:
    """Quarter-note beats per measure for a time signature num/den."""
    return num * (4.0 / den)


def rt_beat_to_abs(rt_beat: float, measure: int, beats_pm: float, ts_num: int) -> float:
    """Convert 1-indexed RomanText beat to absolute 0-indexed quarter-note beat."""
    beat_dur = beats_pm / ts_num  # quarter notes per RT beat unit
    return (measure - 1) * beats_pm + (rt_beat - 1.0) * beat_dur


def looks_like_chord(token: str) -> bool:
    if not token:
        return False
    # Named special chords
    if token in ('N', 'N6', 'It6', 'Ger6/5', 'Ger7', 'Fr4/3', 'Fr6', 'vo', 'vo6'):
        return True
    # Roman numerals or chromatic prefix
    return token[0] in ('I', 'i', 'V', 'v', 'b', '#')


def tokenise_measure(body: str) -> list:
    """Split a measure body string into typed tokens:
    ('beat', float), ('key', KeyState), ('chord', str), ('bar', None)."""
    tokens = []
    parts = body.split()
    i = 0
    while i < len(parts):
        token = parts[i]
        if token == '||':
            tokens.append(('bar', None))
        elif BEAT_RE.match(token):
            tokens.append(('beat', float(BEAT_RE.match(token).group(1))))
        else:
            km = KEY_PREFIX_RE.match(token)
            if km:
                key = parse_key_str(km.group(1))
                tokens.append(('key', key))
                # Remainder (e.g. 'C:I' → 'I') gets re-inserted
                rem = km.group(2).strip()
                if rem:
                    parts.insert(i + 1, rem)
            elif looks_like_chord(token):
                tokens.append(('chord', token))
        i += 1
    return tokens


def expand_repeats(lines: list) -> list:
    """Expand mN = mP and mN-M = mP-Q repeat directives."""
    # Collect all primary measure content
    measure_content: dict = {}
    for line in lines:
        stripped = line.strip()
        # Skip repeat directives themselves
        if re.match(r'^m\d+(?:-\d+)?\s*=\s*m\d+', stripped):
            continue
        m = re.match(r'^m(\d+)(?:-(\d+))?\s+(.*)', stripped)
        if m:
            ms = int(m.group(1))
            me = int(m.group(2)) if m.group(2) else ms
            content = m.group(3)
            for mn in range(ms, me + 1):
                measure_content[mn] = content

    expanded = []
    for line in lines:
        stripped = line.strip()
        m = re.match(r'^m(\d+)(?:-(\d+))?\s*=\s*m(\d+)(?:-(\d+))?$', stripped)
        if m:
            dst_start = int(m.group(1))
            dst_end = int(m.group(2)) if m.group(2) else dst_start
            src_start = int(m.group(3))
            for offset in range(dst_end - dst_start + 1):
                dst_mn = dst_start + offset
                src_mn = src_start + offset
                if src_mn in measure_content:
                    expanded.append(f'm{dst_mn} {measure_content[src_mn]}\n')
        else:
            expanded.append(line)
    return expanded


def parse_romantext_file(path: str):
    """Parse a RomanText file.

    Returns:
        title (str), initial_key (KeyState), events (list[RawEvent]),
        total_beats (float), form_sections (dict: name → list of measure nums)
    """
    with open(path, 'r', encoding='utf-8') as f:
        raw_lines = f.readlines()

    # Split header / body at the first blank line
    body_start = 0
    header_lines = []
    for i, line in enumerate(raw_lines):
        if line.strip() == '' or line.strip() == ' ':
            body_start = i + 1
            break
        header_lines.append(line)

    # Parse header
    header: dict = {}
    for line in header_lines:
        m = re.match(r'^([A-Za-z ]+):\s*(.*)', line.strip())
        if m:
            header.setdefault(m.group(1).strip(), []).append(m.group(2).strip())

    composer = header.get('Composer', [''])[0]
    artist = header.get('Artist', [''])[0]
    piece = (header.get('Piece') or header.get('BWV') or [''])[0]
    title_h = header.get('Title', [''])[0]
    name_parts = [x for x in [composer or artist, piece or title_h] if x]
    title = ' – '.join(name_parts) if name_parts else os.path.splitext(os.path.basename(path))[0]

    ts_str = (header.get('Time Signature') or ['4/4'])[0]
    ts_num, ts_den = parse_time_sig(ts_str)

    body_lines = raw_lines[body_start:]
    body_lines = expand_repeats(body_lines)

    # Walk the body
    current_key: Optional[KeyState] = None
    current_ts_num: int = ts_num
    current_ts_den: int = ts_den
    current_beats_pm: float = beats_per_measure(ts_num, ts_den)
    # Track measure→beats_pm in case time sig changes mid-piece
    measure_beats_pm: dict = {}  # measure_num → beats_pm at that point

    events: list = []
    form_sections: dict = {}  # name → [measure_num, ...]
    current_section: Optional[str] = None
    max_measure: int = 0

    for line in body_lines:
        stripped = line.strip()
        if not stripped:
            continue

        # Note / comment
        if stripped.startswith('Note:'):
            continue

        # Form marker
        fm = re.match(r'^Form:\s*(.+)', stripped)
        if fm:
            current_section = fm.group(1).strip()
            form_sections.setdefault(current_section, [])
            continue

        # Time signature change in body
        ts_m = re.match(r'^Time Signature:\s*(\d+)/(\d+)', stripped)
        if ts_m:
            current_ts_num = int(ts_m.group(1))
            current_ts_den = int(ts_m.group(2))
            current_beats_pm = beats_per_measure(current_ts_num, current_ts_den)
            continue

        # Pedal marker (ignore)
        if stripped.startswith('Pedal:'):
            continue

        # Measure line (including ranges and variants)
        # mN, mN-M, mNvarM — variant lines are ignored (use primary reading)
        mline = re.match(r'^m(\d+)(?:-(\d+))?(var\d+)?\s+(.*)', stripped)
        if not mline:
            continue
        if mline.group(3):
            continue  # skip variant measures

        mstart = int(mline.group(1))
        mend = int(mline.group(2)) if mline.group(2) else mstart
        body_str = mline.group(4).strip()

        if mend > max_measure:
            max_measure = mend

        # Record beats_pm for each measure in this range
        for mn in range(mstart, mend + 1):
            measure_beats_pm[mn] = current_beats_pm
            if current_section is not None:
                form_sections[current_section].append(mn)

        # Tokenise the measure body
        tokens = tokenise_measure(body_str)

        # Walk tokens for each measure in the range
        rt_beat = 1.0
        key_here = current_key  # local key cursor

        for kind, val in tokens:
            if kind == 'beat':
                rt_beat = val
            elif kind == 'key':
                key_here = val
            elif kind == 'bar':
                pass  # phrase marker, skip
            elif kind == 'chord':
                if key_here is None:
                    continue
                # For measure ranges, the same chord pattern applies to each measure
                for mn in range(mstart, mend + 1):
                    bpm_here = measure_beats_pm.get(mn, current_beats_pm)
                    abs_beat = rt_beat_to_abs(rt_beat, mn, bpm_here, current_ts_num)
                    events.append(RawEvent(
                        beat=abs_beat,
                        measure=mn,
                        roman=val,
                        key=key_here,
                    ))

        # Update running key from last key seen in this line
        for kind, val in reversed(tokens):
            if kind == 'key':
                current_key = val
                break

        # Set initial_key if not yet determined
        if current_key is not None and events:
            pass  # initial_key set from first event's key below

    events.sort(key=lambda e: e.beat)

    # Initial key: the key of the very first chord event
    initial_key = events[0].key if events else KeyState(root='C', scale='major')

    # Total beats: start of (max_measure + 1)
    total_beats = max_measure * measure_beats_pm.get(max_measure, current_beats_pm)

    return title, initial_key, events, total_beats, form_sections


# ---------------------------------------------------------------------------
# Applied chord resolution
# ---------------------------------------------------------------------------

def is_supported_roman(s: str) -> bool:
    """Return True if the chord symbol can be expressed via setRoman."""
    if not s:
        return False
    # Strip bracket annotations (e.g. "V9[b9]" → "V9")
    if '[' in s:
        s = s[:s.index('[')].strip()
    if not s:
        return False
    # Neapolitan: N and N6 are supported; N7, N9, etc. are not
    if s.startswith('N'):
        return s in ('N', 'N6')
    # Augmented sixths: recognized variants are supported
    if s.startswith('It') or s.startswith('Ger') or s.startswith('Fr'):
        return s in ('It6', 'Ger6/5', 'Ger7', 'Fr4/3', 'Fr6')
    # Flat/sharp-prefixed chords (bII, bVII, #IV, etc.)
    if s[0] in ('b', '#'):
        return len(s) > 1 and s[1].upper() in ('I', 'V')
    # Standard Roman numeral chords (I, i, V, v, plus vo, vo6 etc.)
    return s[0] in ('I', 'i', 'V', 'v')


def _skip_reason(s: str) -> str:
    """Human-readable reason why a chord symbol is unsupported."""
    if s.startswith('N') and s not in ('N', 'N6'):
        return f'extended Neapolitan {s!r} (only N and N6 are supported)'
    if (s.startswith('It') or s.startswith('Ger') or s.startswith('Fr')) and \
            s not in ('It6', 'Ger6/5', 'Ger7', 'Fr4/3', 'Fr6'):
        return f'unrecognized augmented-sixth variant {s!r}'
    return f'unrecognized chord symbol {s!r}'


def tonicize(key: KeyState, target_roman: str) -> KeyState:
    """Compute the tonicized key for an applied chord target (e.g. 'V' → G major in C).
    Supports b/# prefix on the target (e.g. 'bIII' → Eb major in C)."""
    target = target_roman
    semitone_offset = 0
    # Strip b/# prefix; offset applied to final pitch class
    if target.startswith('b'):
        semitone_offset = -1
        target = target[1:]
    elif target.startswith('#'):
        semitone_offset = 1
        target = target[1:]
    if not target:
        return key
    # Scale type determined by case of numeral (not the b/# prefix character)
    target_scale = 'major' if target[0].isupper() else 'minor'
    # Extract pure Roman numeral characters (I and V cover all numerals)
    numeral = ''
    for c in target.upper():
        if c in ('I', 'V'):
            numeral += c
        else:
            break
    degree_idx = NUMERAL_TO_DEGREE.get(numeral)
    if degree_idx is None:
        return key
    semis = scale_semitones(key.semitone(), key.scale)
    if degree_idx >= len(semis):
        return key
    target_semi = (semis[degree_idx] + semitone_offset) % 12
    target_root = SEMI_TO_PC[target_semi]
    return KeyState(root=target_root, scale=target_scale)


def resolve_applied(roman: str, key: KeyState) -> tuple:
    """For an applied chord (e.g. 'V7/V', 'V/bIII'), return (chord_part, resolved_key).
    For non-applied chords, returns (roman, key)."""
    # Find the rightmost '/' followed by a Roman numeral letter or b/# prefix
    idx = None
    for pos in range(len(roman) - 1, 0, -1):
        if roman[pos] == '/' and pos + 1 < len(roman):
            after = roman[pos + 1]
            if after in ('I', 'i', 'V', 'v', 'b', '#'):
                idx = pos
                break
    if idx is None:
        return roman, key
    chord_part = roman[:idx]
    target_part = roman[idx + 1:]
    new_key = tonicize(key, target_part)
    return chord_part, new_key


# ---------------------------------------------------------------------------
# Build Orbital JSON
# ---------------------------------------------------------------------------

def build_orbital_json(
    title: str,
    initial_key: KeyState,
    events: list,           # list[RawEvent]
    total_beats: float,
    bpm: float,
    loop: bool,
    preset: str,
    bass_preset: Optional[str],
    octave: int,
    voices: int,
    sustain: float,
    min_duration: float,
) -> dict:

    if not events:
        return _empty_json(title, initial_key, bpm, loop, preset, bass_preset,
                           octave, voices, sustain, total_beats)

    # --- Deduplicate events at the same beat (pivot chord: keep last) ---
    deduped: list = []
    for ev in events:
        if deduped and abs(deduped[-1].beat - ev.beat) < 1e-9:
            deduped[-1] = ev
        else:
            deduped.append(ev)

    # --- Shift so first event is at beat 0 ---
    shift = deduped[0].beat
    if abs(shift) > 1e-9:
        deduped = [RawEvent(beat=e.beat - shift, measure=e.measure,
                            roman=e.roman, key=e.key) for e in deduped]
        total_beats -= shift

    total_beats = max(total_beats, 1.0)

    # --- Filter unsupported chord types, warning for each ---
    supported = []
    for e in deduped:
        if is_supported_roman(e.roman):
            supported.append(e)
        else:
            print(f'  Warning: m{e.measure}: skipping "{e.roman}" — {_skip_reason(e.roman)}',
                  file=sys.stderr)
    deduped = supported
    if not deduped:
        return _empty_json(title, initial_key, bpm, loop, preset, bass_preset,
                           octave, voices, sustain, total_beats)

    # --- Filter short chord events ---
    if min_duration > 0 and len(deduped) > 1:
        filtered = [deduped[0]]
        for i in range(1, len(deduped)):
            ev = deduped[i]
            next_beat = deduped[i + 1].beat if i + 1 < len(deduped) else total_beats
            duration = next_beat - ev.beat
            if duration >= min_duration:
                filtered.append(ev)
        deduped = filtered

    # --- Emit chordEvents ---
    chord_events_json = []
    prev_key = initial_key

    for ev in deduped:
        beat = round(ev.beat, 6)
        # Remove trailing ".0" integer beats for cleanliness
        beat_val = int(beat) if beat == int(beat) else beat

        roman = ev.roman
        key = ev.key

        # Resolve applied chords
        chord_roman, resolved_key = resolve_applied(roman, key)

        # Emit setKey if the key has changed
        if resolved_key != prev_key:
            chord_events_json.append({
                'beat': beat_val,
                'op': 'setKey',
                'root': resolved_key.root,
                'scale': resolved_key.scale,
            })
            prev_key = resolved_key

        chord_events_json.append({
            'beat': beat_val,
            'op': 'setRoman',
            'roman': chord_roman,
        })

    # --- Build note durations for the tracks ---
    event_beats = sorted(set(round(e.beat, 6) for e in deduped))
    event_beats.append(round(total_beats, 6))
    event_beats = sorted(set(event_beats))

    note_durations = []
    for i in range(len(event_beats) - 1):
        dur = round(event_beats[i + 1] - event_beats[i], 6)
        if dur > 0:
            # Emit as int if whole number
            note_durations.append(int(dur) if dur == int(dur) else dur)

    if not note_durations:
        note_durations = [round(total_beats, 6)]

    # --- Build tracks ---
    tracks = []

    chord_notes = [{'type': 'currentChord', 'durationBeats': d} for d in note_durations]
    tracks.append({
        'name': 'Chords',
        'presetFilename': preset,
        'numVoices': voices,
        'octave': octave,
        'voicing': 'open',
        'sustainFraction': sustain,
        'notes': chord_notes,
    })

    if bass_preset:
        bass_notes = [{'type': 'chordTone', 'index': 0, 'durationBeats': d}
                      for d in note_durations]
        tracks.append({
            'name': 'Bass',
            'presetFilename': bass_preset,
            'numVoices': 2,
            'octave': octave - 1,
            'voicing': 'closed',
            'sustainFraction': 0.7,
            'notes': bass_notes,
        })

    total_beats_val = round(total_beats, 6)
    total_beats_val = int(total_beats_val) if total_beats_val == int(total_beats_val) else total_beats_val

    return {
        'name': title,
        'scoreTracks': {
            'bpm': bpm,
            'totalBeats': total_beats_val,
            'loop': loop,
            'key': {'root': initial_key.root, 'scale': initial_key.scale},
            'chordEvents': chord_events_json,
            'tracks': tracks,
        }
    }


def _empty_json(title, initial_key, bpm, loop, preset, bass_preset,
                octave, voices, sustain, total_beats):
    return {
        'name': title,
        'scoreTracks': {
            'bpm': bpm,
            'totalBeats': max(round(total_beats, 1), 4.0),
            'loop': loop,
            'key': {'root': initial_key.root, 'scale': initial_key.scale},
            'chordEvents': [{'beat': 0, 'op': 'setChord', 'degrees': [0, 2, 4], 'inversion': 0}],
            'tracks': [],
        }
    }


# ---------------------------------------------------------------------------
# Filter helpers
# ---------------------------------------------------------------------------

def filter_by_measures(events: list, start_m: int, end_m: int,
                       total_beats: float, form_sections: dict) -> tuple:
    """Filter events to the given measure range. Returns (filtered_events, new_total_beats)."""
    filtered = [e for e in events if start_m <= e.measure <= end_m]
    if not filtered:
        return events, total_beats
    # total_beats for the clipped range
    clip_start = filtered[0].beat
    clip_end = filtered[-1].beat  # last chord's start; we need to add its duration
    # Estimate: find the beat that would be after the last measure
    # Use the gap between the last two events as a proxy for one chord's duration
    if len(filtered) >= 2:
        last_dur = filtered[-1].beat - filtered[-2].beat
    else:
        # Can't tell — use original beats_pm estimate
        last_dur = 4.0
    new_total = clip_end + last_dur - clip_start
    return filtered, new_total


def filter_by_section(events: list, section_name: str,
                      form_sections: dict, total_beats: float) -> tuple:
    """Filter events to the named form section."""
    # Case-insensitive match
    matched = None
    for k in form_sections:
        if k.lower() == section_name.lower():
            matched = k
            break
    if matched is None:
        return events, total_beats
    measures = set(form_sections[matched])
    filtered = [e for e in events if e.measure in measures]
    if not filtered:
        return events, total_beats
    clip_start = filtered[0].beat
    clip_end = filtered[-1].beat
    last_dur = (filtered[-1].beat - filtered[-2].beat) if len(filtered) >= 2 else 4.0
    new_total = clip_end + last_dur - clip_start
    return filtered, new_total


# ---------------------------------------------------------------------------
# CLI
# ---------------------------------------------------------------------------

def main():
    p = argparse.ArgumentParser(
        description='Convert a RomanText .txt file to an Orbital scoreTracks JSON.',
        formatter_class=argparse.RawDescriptionHelpFormatter,
        epilog=__doc__,
    )
    p.add_argument('input', help='Path to the RomanText .txt file')
    p.add_argument('--out', help='Output JSON file path')
    p.add_argument('--bpm', type=float, default=72, help='Tempo in BPM (default: 72)')
    p.add_argument('--preset', default='warm_analog_pad',
                   help='Chord instrument preset (default: warm_analog_pad)')
    p.add_argument('--bass-preset', default=None,
                   help='Bass instrument preset (enables bass track)')
    p.add_argument('--bass', action='store_true',
                   help='Add bass track (organ_baroque_positive)')
    p.add_argument('--octave', type=int, default=3, help='Chord octave (default: 3)')
    p.add_argument('--no-loop', action='store_true', help='Do not loop the pattern')
    p.add_argument('--min-duration', type=float, default=0.25,
                   help='Drop chord events shorter than N beats (default: 0.25)')
    p.add_argument('--measures', help='Measure range A-B (e.g. --measures 1-16)')
    p.add_argument('--section', help='Form section name to extract (e.g. "Verse")')
    p.add_argument('--voices', type=int, default=6, help='Number of chord voices (default: 6)')
    p.add_argument('--sustain', type=float, default=0.85, help='Sustain fraction (default: 0.85)')

    args = p.parse_args()

    loop = not args.no_loop

    bass_preset = None
    if args.bass and not args.bass_preset:
        bass_preset = 'organ_baroque_positive'
    elif args.bass_preset:
        bass_preset = args.bass_preset

    out_path = args.out or (os.path.splitext(args.input)[0] + '_orbital.json')

    print(f'Parsing {args.input}…', file=sys.stderr)
    title, initial_key, events, total_beats, form_sections = parse_romantext_file(args.input)
    print(f'  Title: {title}', file=sys.stderr)
    print(f'  Initial key: {initial_key.root} {initial_key.scale}', file=sys.stderr)
    print(f'  Chord events: {len(events)}', file=sys.stderr)
    print(f'  Total beats: {total_beats:.1f}', file=sys.stderr)
    if form_sections:
        print(f'  Form sections: {list(form_sections.keys())}', file=sys.stderr)

    # Apply filters
    if args.section:
        events, total_beats = filter_by_section(events, args.section, form_sections, total_beats)
        print(f'  After section filter "{args.section}": {len(events)} events', file=sys.stderr)

    if args.measures:
        m = re.match(r'(\d+)-(\d+)', args.measures)
        if m:
            events, total_beats = filter_by_measures(
                events, int(m.group(1)), int(m.group(2)), total_beats, form_sections)
            print(f'  After measure filter {args.measures}: {len(events)} events', file=sys.stderr)
        else:
            print(f'Warning: could not parse --measures "{args.measures}", ignoring.',
                  file=sys.stderr)

    result = build_orbital_json(
        title=title,
        initial_key=initial_key,
        events=events,
        total_beats=total_beats,
        bpm=args.bpm,
        loop=loop,
        preset=args.preset,
        bass_preset=bass_preset,
        octave=args.octave,
        voices=args.voices,
        sustain=args.sustain,
        min_duration=args.min_duration,
    )

    with open(out_path, 'w', encoding='utf-8') as f:
        json.dump(result, f, indent=2)

    print(f'Wrote {out_path}', file=sys.stderr)
    score = result['scoreTracks']
    print(f'  chordEvents: {len(score["chordEvents"])}', file=sys.stderr)
    print(f'  tracks: {len(score["tracks"])}', file=sys.stderr)
    print(f'  totalBeats: {score["totalBeats"]}', file=sys.stderr)


if __name__ == '__main__':
    main()
