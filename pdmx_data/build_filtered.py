#!/usr/bin/env python3
"""
Build a filtered subset of pdmx_composers containing only works with
Wikidata links, passing quality, noise-title, and match-validity filters.

Filters applied:
1. Work must have a wikidata_id (from enrich_wikidata.py)
2. Quality: rating > 0 OR n_views >= 50
3. Noise title: excludes works with WIP, easy, simplified, beginner,
   single line, cover, remix, my version, practice in the title
4. Match validation: title_tokens matches are checked for number/opus/key
   conflicts between PDMX title and Wikidata title; conflicts are dropped

After filtering, wikidata_title is promoted to display_title.

Input:  pdmx_composers/
Output: pdmx_composers_with_wiki/
"""

import json
import re
import shutil
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

# ---------- title_tokens match validation ----------

# Extract opus numbers: Op. N, op N, Opus N
_OP_RE = re.compile(r'\bop(?:us)?\.?\s*(\d+)', re.IGNORECASE)

# Extract "No." style numbers: No. N, Nr. N, # N, Nº N, N.8, n1
_NO_RE = re.compile(r'(?:\bno\.?\s*|#\s*|\bNº\s*|\bnr\.?\s*|\bn\.?\s*(?=\d))(\d+)',
                     re.IGNORECASE)

# Extract ordinals: 5th, 2nd, 1st, 3rd
_ORD_RE = re.compile(r'\b(\d+)(?:st|nd|rd|th)\b', re.IGNORECASE)

# Extract catalog numbers: K N, KV N, BWV N, D N, RV N, K160, etc.
_CAT_RE = re.compile(
    r'\b(K|KV|BWV|RV|D|HWV|Hob|WoO|SWV|SV|L)\.?\s*(\d+)',
    re.IGNORECASE)

# Extract key signatures: "in C major", "in D minor", "in La minore", etc.
_KEY_RE = re.compile(
    r'\bin\s+('
    r'[A-G](?:[#b\u266f\u266d-]?(?:\s*flat|\s*sharp)?)\s*'
    r'(?:major|minor|dur|moll)'
    r'|'
    r'(?:do|re|mi|fa|sol|la|si)(?:\s*(?:diesis|bemolle))?\s*'
    r'(?:maggiore|minore)'
    r')',
    re.IGNORECASE)

# French numeric ordinals: 1er, 1ère, 1ére, 2e, 3ème, etc.
_FR_ORD_NUM_RE = re.compile(
    r'\b(\d+)\s*(?:[e\xe8\xe9]re|[e\xe8\xe9]me|er|re|e)\b', re.IGNORECASE)

# French ordinal words: premier, deuxième, troisième, etc.
_FR_ORD_MAP = {
    'premier': '1', 'premi\xe8re': '1', 'premiere': '1',
    'deuxi\xe8me': '2', 'deuxieme': '2', 'second': '2', 'seconde': '2',
    'troisi\xe8me': '3', 'troisieme': '3',
    'quatri\xe8me': '4', 'quatrieme': '4',
    'cinqui\xe8me': '5', 'cinquieme': '5',
    'sixi\xe8me': '6', 'sixieme': '6',
}
_FR_ORD_WORD_RE = re.compile(
    r'\b(' + '|'.join(re.escape(k) for k in _FR_ORD_MAP) + r')\b',
    re.IGNORECASE)

# Bare number after a musical form word: "Mazurka 23", "Concerto 2", etc.
_FORM_NUM_RE = re.compile(
    r'\b(?:psalm|mazurka|gnossienne|gymnop[e\xe9]die|symphony|concerto|'
    r'sonata|sonatina|etude|\xe9tude|prelude|pr\xe9lude|waltz|valse|'
    r'impromptu|nocturne|rhapsody|ballade|serenade|bagatelle|intermezzo|'
    r'scherzo|arabesque|barcarolle|berceuse)\s+(\d+)\b',
    re.IGNORECASE)

# Italian-to-English note map for key normalization
_IT_NOTE_MAP = {
    'do': 'c', 're': 'd', 'mi': 'e', 'fa': 'f',
    'sol': 'g', 'la': 'a', 'si': 'b',
}


def _normalize_key(raw):
    """Normalize an extracted key string for comparison."""
    raw = raw.lower().strip()
    for it_note, en_note in sorted(_IT_NOTE_MAP.items(),
                                   key=lambda x: -len(x[0])):
        if raw.startswith(it_note) and (
                len(raw) == len(it_note) or not raw[len(it_note)].isalpha()):
            raw = en_note + raw[len(it_note):]
            break
    raw = (raw.replace('maggiore', 'major').replace('minore', 'minor')
              .replace('dur', 'major').replace('moll', 'minor')
              .replace('diesis', 'sharp').replace('bemolle', 'flat'))
    return re.sub(r'\s+', ' ', raw).strip()


def _extract_signals(title):
    """Extract numbers and key from a title for conflict detection."""
    ops = set(_OP_RE.findall(title))
    nos = set(_NO_RE.findall(title))

    ords = set(_ORD_RE.findall(title))

    # French ordinals (merge into ords)
    for m in _FR_ORD_NUM_RE.findall(title):
        ords.add(m)
    for m in _FR_ORD_WORD_RE.findall(title):
        num = _FR_ORD_MAP.get(m.lower())
        if num:
            ords.add(num)

    cats = {}
    for prefix, num in _CAT_RE.findall(title):
        cats.setdefault(prefix.upper(), set()).add(num)

    key_m = _KEY_RE.search(title)
    key = _normalize_key(key_m.group(1)) if key_m else None

    # Bare numbers after musical form words
    bare = set(_FORM_NUM_RE.findall(title))

    return ops, nos, ords, cats, key, bare


def validate_title_tokens_match(pdmx_title, wd_title):
    """Return True if the title_tokens match looks plausible.

    Rejects when there is a clear number, opus, catalog, or key conflict.
    """
    p_ops, p_nos, p_ords, p_cats, p_key, p_bare = _extract_signals(pdmx_title)
    w_ops, w_nos, w_ords, w_cats, w_key, w_bare = _extract_signals(wd_title)

    # Opus conflict
    if p_ops and w_ops and not p_ops & w_ops:
        return False

    # "No." conflict
    if p_nos and w_nos and not p_nos & w_nos:
        return False

    # Ordinal vs "No." conflict (e.g., "5th Symphony" vs "Symphony No. 9")
    if p_ords and w_nos and not p_ords & w_nos:
        return False
    if p_nos and w_ords and not p_nos & w_ords:
        return False

    # Bare number vs "No." or ordinal conflict
    # e.g., "Mazurka 23" vs "Mazurka no. 3", "Concerto 2" vs "No. 1"
    w_all_nums = w_nos | w_ords | w_bare
    p_all_nums = p_nos | p_ords | p_bare
    if p_bare and w_all_nums and not p_bare & w_all_nums:
        return False
    if w_bare and p_all_nums and not w_bare & p_all_nums:
        return False

    # Catalog number conflict (same prefix, different number)
    for prefix in set(p_cats) & set(w_cats):
        if not p_cats[prefix] & w_cats[prefix]:
            return False

    # Key conflict
    if p_key and w_key and p_key != w_key:
        return False

    return True


# ---------- main ----------

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
    dropped_bad_match = 0

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
            # Validate title_tokens matches
            if w.get("wikidata_match_method") == "title_tokens":
                wd_title = w.get("wikidata_title", "")
                if not validate_title_tokens_match(w["title"], wd_title):
                    dropped_bad_match += 1
                    continue
            # Promote wikidata_title to display_title
            w["display_title"] = w.get("wikidata_title", w["title"])
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
    print("  Dropped: %d no Wikidata, %d low quality, %d noise title, "
          "%d bad title_tokens match" % (
              dropped_no_wd, dropped_quality, dropped_noise,
              dropped_bad_match))


if __name__ == "__main__":
    main()
