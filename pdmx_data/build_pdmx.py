#!/usr/bin/env python3
"""
Build pdmx_composers directory from PDMX dataset filtered by composer list.

This script:
1. Parses Greg's composer HTML table
2. Matches composers against PDMX.csv (license_conflict=False)
3. Creates per-composer directories with musicxml/ and midi/ subdirectories
4. Copies MXL and MID files
5. Analyzes MusicXML for multi-movement structure using data/ JSON
6. Generates index.json (JSONL, one line per composer)
"""

import csv
import json
import os
import re
import shutil
import sys
import unicodedata
import zipfile
from html.parser import HTMLParser
from pathlib import Path

# ──────────────────────────────────────────────
# Configuration
# ──────────────────────────────────────────────
if len(sys.argv) > 1:
    PDMX_ROOT = Path(sys.argv[1])
else:
    PDMX_ROOT = Path(__file__).parent

OUTPUT_ROOT = PDMX_ROOT / "pdmx_composers"
HTML_FILE = PDMX_ROOT / "2025-10-10-classical-composers.html"
CSV_FILE = PDMX_ROOT / "PDMX.csv"

# Movement detection patterns in tempo text or annotations
MOVEMENT_KEYWORDS = re.compile(
    r'\b(allegro|andante|adagio|largo|presto|vivace|moderato|lento|grave|'
    r'scherzo|minuet|menuet|menuetto|trio|rondo|finale|overture|prelude|'
    r'fugue|fuga|gavotte|bourr[eé]e|sarabande|courante|gigue|allemande|'
    r'aria|recitative|march|siciliano|intermezzo|romanze|cavatina|'
    r'maestoso|con\s+moto|molto|poco|non\s+troppo)\b',
    re.IGNORECASE
)

# ──────────────────────────────────────────────
# HTML Parsing
# ──────────────────────────────────────────────
class TableParser(HTMLParser):
    def __init__(self):
        super().__init__()
        self.in_table = False; self.in_td = False; self.in_a = False
        self.current_href = ''; self.current_cell = ''; self.current_row = []
        self.rows = []; self.in_thead = False; self.in_th = False; self.headers = []

    def handle_starttag(self, tag, attrs):
        ad = dict(attrs)
        if tag == 'table': self.in_table = True
        elif tag == 'thead': self.in_thead = True
        elif tag == 'tr': self.current_row = []
        elif tag == 'th' and self.in_thead: self.in_th = True; self.current_cell = ''
        elif tag == 'td' and self.in_table: self.in_td = True; self.current_cell = ''; self.current_href = ''
        elif tag == 'a' and (self.in_td or self.in_th): self.in_a = True; self.current_href = ad.get('href','')

    def handle_endtag(self, tag):
        if tag == 'th': self.in_th = False; self.headers.append(self.current_cell.strip())
        elif tag == 'td': self.in_td = False; self.current_row.append({'text': self.current_cell.strip(), 'href': self.current_href})
        elif tag == 'tr' and self.current_row: self.rows.append(self.current_row)
        elif tag == 'thead': self.in_thead = False
        elif tag == 'table': self.in_table = False
        elif tag == 'a': self.in_a = False

    def handle_data(self, data):
        if self.in_td or self.in_th: self.current_cell += data


def parse_composers(html_path):
    with open(html_path) as f:
        html = f.read()
    parser = TableParser()
    parser.feed(html)
    composers = []
    for row in parser.rows:
        if len(row) >= 8:
            composers.append({
                'name_lf': row[0]['text'],
                'name_fl': row[1]['text'],
                'wiki_url': row[2]['href'],
                'apple_music_url': row[3]['href'],
                'great': row[4]['text'].strip(),
                'dates': row[5]['text'],
                'nationality': row[6]['text'],
                'period': row[7]['text'],
            })
    return composers


# ──────────────────────────────────────────────
# Name normalization & matching
# ──────────────────────────────────────────────
def strip_accents(s):
    return ''.join(c for c in unicodedata.normalize('NFD', s) if unicodedata.category(c) != 'Mn')


def normalize_tokens(name):
    n = strip_accents(name.lower().strip())
    return set(re.sub(r'[^a-z0-9 ]', ' ', n).split())


COMMON_LAST_NAMES = frozenset({
    'smith', 'lang', 'martin', 'adams', 'field', 'bach', 'williams', 'brown',
    'young', 'jones', 'white', 'king', 'moore', 'hall', 'carter', 'price',
    'glass', 'wolf', 'cage', 'bridge', 'monk', 'bell', 'arnold', 'gould',
    'weber', 'riley', 'foss', 'nono', 'rorem', 'wolfe', 'reich', 'part',
    'orff', 'weill', 'cui', 'lalo', 'bax',
})


def build_composer_patterns(composers):
    patterns = []
    for c in composers:
        tokens = normalize_tokens(c['name_fl'])
        last_raw = c['name_lf'].split(',')[0].strip()
        last_tokens = normalize_tokens(last_raw)
        patterns.append({
            'composer': c,
            'all_tokens': tokens,
            'last_tokens': last_tokens,
        })
    return patterns


def score_match(pdmx_tokens, pattern):
    all_t = pattern['all_tokens']
    last_t = pattern['last_tokens']

    if not last_t.issubset(pdmx_tokens):
        return 0

    matched = all_t.intersection(pdmx_tokens)
    n_matched = len(matched)
    n_total = len(all_t)

    if n_total <= 2:
        if n_matched == n_total:
            return 100
        elif n_matched == n_total - 1 and last_t.issubset(matched):
            last_str = ' '.join(sorted(last_t))
            if last_str in COMMON_LAST_NAMES:
                return 0
            if len(last_str) >= 6:
                return 75
            return 0
        return 0
    else:
        ratio = n_matched / n_total
        if ratio >= 0.6 and n_matched >= 2:
            return int(60 + ratio * 40)
        return 0


# Special-case matchers for names that don't follow normal patterns
SPECIAL_MATCHERS = {
    'Amy Marcy Cheney Beach': lambda c: 'amy beach' in strip_accents(c).lower(),
    'Ignacy Jan Paderewski': lambda c: 'paderewski' in strip_accents(c).lower(),
    'Gilles de Bins dit Binchois': lambda c: 'binchois' in strip_accents(c).lower(),
    'Leoš Janáček': lambda c: 'janacek' in strip_accents(c).lower(),
    'Bohuslav Martinů': lambda c: 'martinu' in strip_accents(c).lower(),
    'Fanny Mendelssohn-Hensel': lambda c: 'fanny' in c.lower() and ('mendelssohn' in strip_accents(c).lower() or 'hensel' in c.lower()),
    'Clara Wieck Schumann': lambda c: 'clara' in c.lower() and 'schumann' in strip_accents(c).lower(),
    'Marchetto Cara': lambda c: 'marchetto cara' in strip_accents(c).lower(),
}


# ──────────────────────────────────────────────
# Directory slug generation
# ──────────────────────────────────────────────
def _make_prefixed_slug(name_fl, name_lf):
    """Generate a prefixed slug like 'js_bach' or 'cpe_bach'."""
    last = name_lf.split(',')[0].strip()
    base = strip_accents(last).lower()
    base = re.sub(r'[^a-z]', '_', base).strip('_')
    base = re.sub(r'_+', '_', base)

    parts = name_fl.split()
    last_parts = last.split()
    first_parts = [p for p in parts if p not in last_parts]
    if first_parts:
        initials = '_'.join(strip_accents(p[0]).lower() for p in first_parts if p)
        prefixed = f"{initials}_{base}"
        prefixed = re.sub(r'[^a-z_]', '', prefixed)
        return prefixed

    # Fallback: full name
    full_slug = strip_accents(name_fl).lower()
    full_slug = re.sub(r'[^a-z]', '_', full_slug).strip('_')
    return re.sub(r'_+', '_', full_slug)


def assign_all_slugs(matched_names, composer_by_name, matches_ref=None):
    """Assign slugs, giving the plain last name to the most prominent composer in each group."""
    from collections import defaultdict
    groups = defaultdict(list)
    for name_fl in matched_names:
        c = composer_by_name[name_fl]
        last = c['name_lf'].split(',')[0].strip()
        base = strip_accents(last).lower()
        base = re.sub(r'[^a-z]', '_', base).strip('_')
        base = re.sub(r'_+', '_', base)
        groups[base].append(name_fl)

    slugs = {}
    for base, names in groups.items():
        if len(names) == 1:
            slugs[names[0]] = base
        else:
            # Pick the most prominent: marked as "great" (⭐️), or most works, or alphabetically first
            def prominence(name_fl):
                c = composer_by_name[name_fl]
                is_great = 1 if c.get('great') == '⭐️' else 0
                # Use n_works from matches as a tiebreaker (more works = more prominent)
                n_works = len(matches_ref.get(name_fl, [])) if matches_ref else 0
                return (-is_great, -n_works, name_fl)

            ranked = sorted(names, key=prominence)
            # The most prominent gets the plain slug
            slugs[ranked[0]] = base
            for name_fl in ranked[1:]:
                c = composer_by_name[name_fl]
                slugs[name_fl] = _make_prefixed_slug(c['name_fl'], c['name_lf'])

    return slugs


# ──────────────────────────────────────────────
# MusicXML / Data JSON analysis
# ──────────────────────────────────────────────
def analyze_data_json(data_path):
    """Analyze the data/ JSON file for movement structure, key, tempo, etc."""
    full_path = PDMX_ROOT / data_path.lstrip('./')
    if not full_path.exists():
        return None

    try:
        with open(full_path) as f:
            d = json.load(f)
    except (json.JSONDecodeError, UnicodeDecodeError):
        return None

    info = {
        'title': d.get('metadata', {}).get('title'),
        'creators': d.get('metadata', {}).get('creators', []),
    }

    # Key signatures
    ks_list = d.get('key_signatures', [])
    if ks_list:
        primary_ks = ks_list[0]
        root = primary_ks.get('root_str', '')
        mode = primary_ks.get('mode', '')
        if root and root != 'None':
            info['key'] = f"{root} {mode}" if mode and mode != 'None' else root
    info['all_key_signatures'] = [
        {'measure': ks.get('measure'), 'key': f"{ks.get('root_str','')} {ks.get('mode','')}", 'fifths': ks.get('fifths')}
        for ks in ks_list if ks.get('root_str') and ks.get('root_str') != 'None'
    ]

    # Time signatures
    ts_list = d.get('time_signatures', [])
    if ts_list:
        primary_ts = ts_list[0]
        info['time_signature'] = f"{primary_ts.get('numerator','')}/{primary_ts.get('denominator','')}"
    info['all_time_signatures'] = [
        {'measure': ts.get('measure'), 'time_sig': f"{ts.get('numerator','')}/{ts.get('denominator','')}"}
        for ts in ts_list
    ]

    # Tempos
    tempos = d.get('tempos', [])
    info['tempos'] = []
    for t in tempos:
        text = t.get('text', '')
        # Strip HTML tags
        clean_text = re.sub(r'<[^>]+>', '', text).strip()
        info['tempos'].append({
            'measure': t.get('measure'),
            'qpm': t.get('qpm'),
            'marking': clean_text if clean_text else None,
        })

    # Detect movements from tempo markings and structural cues
    movements = detect_movements(d)
    if movements:
        info['detected_movements'] = movements
        info['is_multi_movement'] = len(movements) > 1
    else:
        info['is_multi_movement'] = False

    # Track info
    tracks = d.get('tracks', [])
    info['n_tracks'] = len(tracks)
    info['instruments'] = [t.get('name', '') for t in tracks if t.get('name')]

    # Song length
    sl = d.get('song_length', {})
    if isinstance(sl, dict):
        info['n_bars'] = sl.get('bars')
        info['n_beats'] = sl.get('beats')

    return info


def detect_movements(data):
    """Detect movement boundaries from tempo markings and time sig changes."""
    tempos = data.get('tempos', [])
    ts_changes = data.get('time_signatures', [])

    movements = []
    for t in tempos:
        text = re.sub(r'<[^>]+>', '', t.get('text', '')).strip()
        if text and MOVEMENT_KEYWORDS.search(text):
            movements.append({
                'start_measure': t.get('measure'),
                'tempo_marking': text,
                'qpm': t.get('qpm'),
            })

    # If no movements detected from tempo, check for significant time sig changes
    if len(movements) <= 1 and len(ts_changes) > 1:
        # Time sig changes at measure 1 don't count
        sig_changes = [ts for ts in ts_changes if ts.get('measure', 1) > 1]
        # Only consider if there are also key sig changes at similar points
        ks_changes = data.get('key_signatures', [])
        ks_measures = set(ks.get('measure') for ks in ks_changes if ks.get('measure', 1) > 1)

        for ts in sig_changes:
            m = ts.get('measure')
            if m in ks_measures:
                movements.append({
                    'start_measure': m,
                    'time_signature': f"{ts.get('numerator','')}/{ts.get('denominator','')}",
                })

    # Sort by measure number
    movements.sort(key=lambda x: x.get('start_measure', 0))

    # Deduplicate movements at same measure
    seen = set()
    unique = []
    for m in movements:
        sm = m.get('start_measure')
        if sm not in seen:
            seen.add(sm)
            unique.append(m)

    return unique


def extract_mxl_title(mxl_path):
    """Try to extract title and movement info from MXL file."""
    full_path = PDMX_ROOT / mxl_path.lstrip('./')
    if not full_path.exists():
        return None

    try:
        with zipfile.ZipFile(full_path) as z:
            for name in z.namelist():
                if name.endswith('.xml') and 'container' not in name.lower():
                    content = z.read(name).decode('utf-8', errors='replace')
                    info = {}

                    # Extract movement-title
                    mt = re.search(r'<movement-title>(.*?)</movement-title>', content, re.DOTALL)
                    if mt:
                        info['movement_title'] = mt.group(1).strip()

                    # Extract work-title
                    wt = re.search(r'<work-title>(.*?)</work-title>', content, re.DOTALL)
                    if wt:
                        info['work_title'] = wt.group(1).strip()

                    # Count <score-part> elements (instruments)
                    parts = re.findall(r'<score-part\s+id="([^"]*)"', content)
                    info['n_parts'] = len(parts)

                    return info if info else None
    except (zipfile.BadZipFile, KeyError, UnicodeDecodeError):
        return None

    return None


# ──────────────────────────────────────────────
# Metadata enrichment
# ──────────────────────────────────────────────
def extract_work_name(row, data_info, mxl_info):
    """Extract the best work name from available sources."""
    candidates = []

    # From PDMX CSV
    if row.get('song_name') and row['song_name'] != 'NA':
        candidates.append(row['song_name'])
    if row.get('title'):
        candidates.append(row['title'])

    # From data JSON
    if data_info and data_info.get('title'):
        candidates.append(data_info['title'])

    # From MXL
    if mxl_info:
        if mxl_info.get('work_title'):
            candidates.append(mxl_info['work_title'])
        if mxl_info.get('movement_title'):
            candidates.append(mxl_info['movement_title'])

    # Pick the best (longest non-empty, strip composer name prefixes)
    best = ''
    for c in candidates:
        c = c.strip()
        if len(c) > len(best):
            best = c

    return best or 'Unknown'


def classify_form(title, data_info):
    """Try to classify the musical form from title and tempo markings."""
    title_lower = title.lower() if title else ''

    form_patterns = [
        (r'\bsonata\b', 'Sonata'),
        (r'\bconcerto\b', 'Concerto'),
        (r'\bsymphony\b', 'Symphony'),
        (r'\bsuite\b', 'Suite'),
        (r'\bpartita\b', 'Partita'),
        (r'\bfugue?\b', 'Fugue'),
        (r'\bprelude\b', 'Prelude'),
        (r'\bnocturne\b', 'Nocturne'),
        (r'\betude\b', 'Étude'),
        (r'\bwaltz\b', 'Waltz'),
        (r'\bmazurka\b', 'Mazurka'),
        (r'\bpolonaise\b', 'Polonaise'),
        (r'\bballade\b', 'Ballade'),
        (r'\bscherzo\b', 'Scherzo'),
        (r'\bimpromtu\b', 'Impromptu'),
        (r'\brondo\b', 'Rondo'),
        (r'\boverture\b', 'Overture'),
        (r'\bmass\b', 'Mass'),
        (r'\brequiem\b', 'Requiem'),
        (r'\bmagnificat\b', 'Magnificat'),
        (r'\bmotet\b', 'Motet'),
        (r'\bcantata\b', 'Cantata'),
        (r'\boratorio\b', 'Oratorio'),
        (r'\bopera\b', 'Opera'),
        (r'\baria\b', 'Aria'),
        (r'\blied\b', 'Lied'),
        (r'\bsong\b', 'Song'),
        (r'\bchoral[e]?\b', 'Chorale'),
        (r'\bhymn\b', 'Hymn'),
        (r'\bpsalm\b', 'Psalm'),
        (r'\bcanon\b', 'Canon'),
        (r'\binvention\b', 'Invention'),
        (r'\btoccata\b', 'Toccata'),
        (r'\bfantasia\b', 'Fantasia'),
        (r'\brhapsod', 'Rhapsody'),
        (r'\bvariation', 'Variations'),
        (r'\bmarch\b', 'March'),
        (r'\bminuet\b', 'Minuet'),
        (r'\bgavotte\b', 'Gavotte'),
        (r'\bsarabande\b', 'Sarabande'),
        (r'\bbourr[eé]e\b', 'Bourrée'),
        (r'\bgigue\b', 'Gigue'),
        (r'\ballemande\b', 'Allemande'),
        (r'\bcourante\b', 'Courante'),
        (r'\bsicilian[oa]\b', 'Siciliana'),
        (r'\bbarcarol', 'Barcarolle'),
        (r'\bberceuse\b', 'Berceuse'),
        (r'\btarantell', 'Tarantella'),
        (r'\bserenade\b', 'Serenade'),
        (r'\bdivertimento\b', 'Divertimento'),
        (r'\bquartet\b', 'Quartet'),
        (r'\btrio\b', 'Trio'),
        (r'\bquintet\b', 'Quintet'),
        (r'\bduet\b', 'Duet'),
        (r'\bmadrigal\b', 'Madrigal'),
        (r'\bchanson\b', 'Chanson'),
        (r'\bpassacagli', 'Passacaglia'),
        (r'\bchaconne\b', 'Chaconne'),
    ]

    for pattern, form_name in form_patterns:
        if re.search(pattern, title_lower):
            return form_name

    return None


def extract_catalog_number(title):
    """Extract BWV, K., Op., etc. from title."""
    patterns = [
        (r'\bBWV\s*(\d+[a-z]?)\b', 'BWV'),
        (r'\bK\.?\s*(\d+[a-z]?)\b', 'K'),
        (r'\bKV\.?\s*(\d+[a-z]?)\b', 'KV'),
        (r'\bOp\.?\s*(\d+)\b', 'Op'),
        (r'\bHob\.?\s*([IVXLC]+[:/]\d+)\b', 'Hob'),
        (r'\bD\.?\s*(\d{3,})\b', 'D'),  # Schubert
        (r'\bWoO\.?\s*(\d+)\b', 'WoO'),
        (r'\bRV\.?\s*(\d+)\b', 'RV'),
        (r'\bHWV\.?\s*(\d+)\b', 'HWV'),
        (r'\bS\.?\s*(\d{3,})\b', 'S'),  # Liszt
    ]
    catalogs = {}
    for pattern, prefix in patterns:
        m = re.search(pattern, title, re.IGNORECASE)
        if m:
            catalogs[prefix] = m.group(1)
    return catalogs if catalogs else None


# ──────────────────────────────────────────────
# Main build logic
# ──────────────────────────────────────────────
def main():
    print("=" * 60)
    print("Building pdmx_composers")
    print("=" * 60)

    # 1. Parse composers
    print("\n[1/5] Parsing composer list...")
    composers = parse_composers(HTML_FILE)
    print(f"  Found {len(composers)} composers")

    # 2. Build matching patterns
    print("\n[2/5] Matching composers against PDMX.csv...")
    patterns = build_composer_patterns(composers)
    composer_by_name = {c['name_fl']: c for c in composers}

    # Scan CSV and match
    matches = {}  # name_fl -> list of CSV rows
    row_count = 0

    with open(CSV_FILE) as f:
        reader = csv.DictReader(f)
        for row in reader:
            if row['license_conflict'] != 'False':
                continue
            row_count += 1
            comp = row['composer_name'].strip()
            if not comp:
                continue

            pdmx_tokens = normalize_tokens(comp)

            # Check special matchers first
            matched = False
            for name, matcher in SPECIAL_MATCHERS.items():
                if name in composer_by_name and matcher(comp):
                    if name not in matches:
                        matches[name] = []
                    matches[name].append(row)
                    matched = True
                    break

            if matched:
                continue

            # Normal token matching
            best_match = None
            best_score = 0
            for p in patterns:
                s = score_match(pdmx_tokens, p)
                if s > best_score:
                    best_score = s
                    best_match = p['composer']

            if best_match and best_score >= 70:
                key = best_match['name_fl']
                if key not in matches:
                    matches[key] = []
                matches[key].append(row)

    print(f"  Scanned {row_count} rows")
    print(f"  Matched {len(matches)} composers, {sum(len(v) for v in matches.values())} works")

    # 3. Create directory structure
    print("\n[3/5] Creating directory structure...")
    OUTPUT_ROOT.mkdir(parents=True, exist_ok=True)

    composer_slugs = assign_all_slugs(sorted(matches.keys()), composer_by_name, matches_ref=matches)

    # 4. Process each composer
    print("\n[4/5] Processing composers...")
    total_composers = len(matches)
    total_works_copied = 0
    total_mxl_copied = 0
    total_mid_copied = 0

    for idx, (name_fl, rows) in enumerate(sorted(matches.items()), 1):
        c = composer_by_name[name_fl]
        slug = composer_slugs[name_fl]

        composer_dir = OUTPUT_ROOT / slug
        musicxml_dir = composer_dir / "musicxml"
        midi_dir = composer_dir / "midi"

        composer_dir.mkdir(parents=True, exist_ok=True)
        musicxml_dir.mkdir(exist_ok=True)
        midi_dir.mkdir(exist_ok=True)

        works = []
        for row in rows:
            work = process_work(row, musicxml_dir, midi_dir, c)
            if work:
                works.append(work)
                total_works_copied += 1
                if work.get('musicxml'):
                    total_mxl_copied += 1
                if work.get('midi'):
                    total_mid_copied += 1

        # Build composer JSONL entry
        composer_entry = {
            'composer_name': c['name_fl'],
            'name_last_first': c['name_lf'],
            'slug': slug,
            'wiki_page': c['wiki_url'],
            'apple_music_playlist': c['apple_music_url'],
            'era': c['period'],
            'dates': c['dates'],
            'nationality': c['nationality'],
            'notable': c['great'] == '⭐️',
            'works': works,
        }

        # Write index.json (single JSONL line)
        index_path = composer_dir / "index.json"
        with open(index_path, 'w') as f:
            f.write(json.dumps(composer_entry, ensure_ascii=False))
            f.write('\n')

        if idx % 20 == 0 or idx == total_composers:
            print(f"  [{idx}/{total_composers}] {name_fl} ({slug}): {len(works)} works")

    # 5. Summary
    print("\n[5/5] Summary")
    print(f"  Composers processed: {total_composers}")
    print(f"  Works total: {total_works_copied}")
    print(f"  MusicXML files copied: {total_mxl_copied}")
    print(f"  MIDI files copied: {total_mid_copied}")
    print(f"  Output: {OUTPUT_ROOT}")

    # Write a root-level manifest
    manifest = {
        'total_composers': total_composers,
        'total_works': total_works_copied,
        'total_mxl': total_mxl_copied,
        'total_mid': total_mid_copied,
        'composers': [
            {'name': name_fl, 'slug': composer_slugs[name_fl], 'n_works': len(matches[name_fl])}
            for name_fl in sorted(matches.keys())
        ],
    }
    with open(OUTPUT_ROOT / 'manifest.json', 'w') as f:
        json.dump(manifest, f, indent=2, ensure_ascii=False)

    print("\nDone!")


def process_work(row, musicxml_dir, midi_dir, composer):
    """Process a single work: copy files, analyze structure, build metadata."""
    title = row.get('title', '') or row.get('song_name', '') or 'Unknown'

    # Paths from CSV
    mxl_rel = row.get('mxl', '')
    mid_rel = row.get('mid', '')
    data_rel = row.get('path', '')
    metadata_rel = row.get('metadata', '')

    # Generate a safe filename base from the title
    safe_title = strip_accents(title)[:80]
    safe_title = re.sub(r'[^\w\s\-]', '', safe_title).strip()
    safe_title = re.sub(r'\s+', '_', safe_title)
    if not safe_title:
        safe_title = 'untitled'

    # Deduplicate filename if needed
    mxl_dest = None
    mid_dest = None

    if mxl_rel and mxl_rel != 'NA':
        src = PDMX_ROOT / mxl_rel.lstrip('./')
        if src.exists():
            dest_name = f"{safe_title}.mxl"
            dest = musicxml_dir / dest_name
            # Handle duplicates
            counter = 1
            while dest.exists():
                dest_name = f"{safe_title}_{counter}.mxl"
                dest = musicxml_dir / dest_name
                counter += 1
            try:
                shutil.copy2(src, dest)
                mxl_dest = f"musicxml/{dest_name}"
            except (OSError, shutil.Error) as e:
                print(f"    Warning: Could not copy MXL {src}: {e}")

    if mid_rel and mid_rel != 'NA':
        src = PDMX_ROOT / mid_rel.lstrip('./')
        if src.exists():
            dest_name = f"{safe_title}.mid"
            dest = midi_dir / dest_name
            counter = 1
            while dest.exists():
                dest_name = f"{safe_title}_{counter}.mid"
                dest = midi_dir / dest_name
                counter += 1
            try:
                shutil.copy2(src, dest)
                mid_dest = f"midi/{dest_name}"
            except (OSError, shutil.Error) as e:
                print(f"    Warning: Could not copy MID {src}: {e}")

    # Analyze data JSON
    data_info = analyze_data_json(data_rel) if data_rel else None

    # Analyze MXL file
    mxl_info = extract_mxl_title(mxl_rel) if mxl_rel and mxl_rel != 'NA' else None

    # Build work name
    work_name = extract_work_name(row, data_info, mxl_info)

    # Build work metadata
    work = {
        'title': work_name,
        'musicxml': mxl_dest,
        'midi': mid_dest,
    }

    # Add catalog number if found
    catalog = extract_catalog_number(work_name)
    if catalog:
        work['catalog_numbers'] = catalog

    # Add form
    form = classify_form(work_name, data_info)
    if form:
        work['form'] = form

    # Add key
    if data_info and data_info.get('key'):
        work['key'] = data_info['key']

    # Add time signature
    if data_info and data_info.get('time_signature'):
        work['time_signature'] = data_info['time_signature']

    # Add instruments
    if data_info and data_info.get('instruments'):
        work['instruments'] = data_info['instruments']

    # Add n_bars
    if data_info and data_info.get('n_bars'):
        work['n_bars'] = data_info['n_bars']

    # Add tempo markings
    if data_info and data_info.get('tempos'):
        tempo_markings = [t['marking'] for t in data_info['tempos'] if t.get('marking')]
        if tempo_markings:
            work['tempo_markings'] = tempo_markings

    # Movement detection
    if data_info and data_info.get('is_multi_movement') and data_info.get('detected_movements'):
        movements = []
        for m in data_info['detected_movements']:
            mov = {'start_measure': m.get('start_measure')}
            if m.get('tempo_marking'):
                mov['tempo_marking'] = m['tempo_marking']
            if m.get('time_signature'):
                mov['time_signature'] = m['time_signature']
            movements.append(mov)
        work['movements'] = movements
        work['is_multi_movement'] = True
    else:
        work['is_multi_movement'] = False

    # PDMX metadata
    work['pdmx'] = {
        'rating': float(row.get('rating', 0) or 0),
        'n_favorites': int(row.get('n_favorites', 0) or 0),
        'n_views': int(row.get('n_views', 0) or 0),
        'duration_seconds': float(row.get('song_length.seconds', 0) or 0),
        'n_notes': int(row.get('n_notes', 0) or 0),
        'complexity': row.get('complexity', ''),
        'is_original': row.get('is_original') == 'True',
        'is_best_arrangement': row.get('is_best_arrangement') == 'True',
        'genres': row.get('genres', ''),
        'tags': row.get('tags', ''),
        'musescore_url': '',  # Will be populated from metadata JSON
    }

    # Try to get MuseScore URL from metadata JSON
    if metadata_rel and metadata_rel != 'NA':
        meta_path = PDMX_ROOT / metadata_rel.lstrip('./')
        if meta_path.exists():
            try:
                with open(meta_path) as f:
                    meta = json.load(f)
                score_data = meta.get('data', {}).get('score', {})
                work['pdmx']['musescore_url'] = score_data.get('url', '')
                if score_data.get('duration'):
                    work['pdmx']['musescore_duration'] = score_data['duration']
            except (json.JSONDecodeError, KeyError):
                pass

    return work


if __name__ == '__main__':
    main()
