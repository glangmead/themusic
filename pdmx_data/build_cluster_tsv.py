#!/usr/bin/env python3
"""
Build a TSV of all works in the PDMX corpus with cluster assignments and
instrumentation match info.

Columns:
  path              - e.g. debussy/midi/Reverie_Debussy_fix.mid
  wikidata_qid      - e.g. Q1851122
  cluster           - integer cluster ID (same-cluster = musically identical)
  instruments       - instruments listed in the MIDI/index.json
  canonical_instruments - canonical instrumentation from Wikidata P870 or Wikipedia categories
  is_original_instrumentation - true/false/unknown
"""

import json
import os
import subprocess
import sys
import time
import urllib.parse
import urllib.request
from collections import defaultdict
from itertools import combinations
from pathlib import Path

from wiki_categories_to_instruments import categories_to_instruments

PDMX_ROOT = Path(__file__).parent
BASE = PDMX_ROOT / "pdmx_composers_with_wiki"
TSV_OUT = PDMX_ROOT / "corpus_clusters.tsv"
MIDICSV = "/opt/homebrew/bin/midicsv"

# --- Instrument normalization ---

INSTRUMENT_CANONICAL = {
    "piano": "piano",
    "acoustic grand piano": "piano",
    "bright acoustic piano": "piano",
    "sähköpiano": "electric piano",
    "electric piano": "electric piano",
    "klavier": "piano",
    "harpsichord": "harpsichord",
    "clavichord": "harpsichord",
    "keyboard instrument": "keyboard",
    "organ": "organ",
    "church organ": "organ",
    "pipe organ": "organ",
    "violin": "violin",
    "violino": "violin",
    "viola": "viola",
    "violoncello": "cello",
    "cello": "cello",
    "contrabass": "double bass",
    "double bass": "double bass",
    "flute": "flute",
    "oboe": "oboe",
    "english horn": "english horn",
    "clarinet": "clarinet",
    "bassoon": "bassoon",
    "horn": "horn",
    "horn in f": "horn",
    "french horn": "horn",
    "trumpet": "trumpet",
    "trombone": "trombone",
    "tuba": "tuba",
    "harp": "harpsichord",  # MuseScore uses "Harp" for harpsichord (GM program 46 workaround)
    "guitar": "guitar",
    "classical guitar": "guitar",
    "voice": "voice",
    "soprano": "voice",
    "alto": "voice",
    "tenor": "voice",
    "bass": "voice",
    "baritone": "voice",
    "mixed choir": "choir",
    "satb choir": "choir",
    "choir": "choir",
    "string orchestra": "string orchestra",
    "string quartet": "string quartet",
    "orchestra": "orchestra",
    "continuo group": "continuo",
    "recorder": "recorder",
    "alttosaksofoni": "saxophone",
    "alto saxophone": "saxophone",
    "rumpusetti": "drums",
    "drum set": "drums",
    "akustinen basso": "bass guitar",
    # SATB voice parts from choral scores
    "s": "voice",
    "a": "voice",
    "t": "voice",
    "b": "voice",
    "cantus": "voice",
    "altus": "voice",
    "bassus": "voice",
    # Japanese/Korean/Chinese instrument names from MuseScore
    "ハープシーコード": "harpsichord",
    "ハープ": "harpsichord",  # Same MuseScore uploader using Japanese "harp" for harpsichord
    "ピアノ": "piano",
    "피아노": "piano",
    "鋼琴": "piano",
    "바이올린": "violin",
    "플루트": "flute",
    # Norwegian/Finnish/Spanish instrument names
    "fiolin": "violin",
    "flauta": "flute",
    "fagot": "bassoon",
    "corno en re": "horn",
    "corno en la": "horn",
    "clarinete en la": "clarinet",
    "clarinete en si♭": "clarinet",
    "clarinette en si♭": "clarinet",
    "violines": "violin",
    "violas": "viola",
    "violonchelos": "cello",
    "violonchelo": "cello",
    "contrabajos": "double bass",
    "violín": "violin",
    "klassieke gitaar": "guitar",
    "orgue": "organ",
    "grand piano": "piano",
    # Abbreviations
    "fl.": "flute",
    # Instrument parts (e.g. "Harpsichord 1")
    "harpsichord 1": "harpsichord",
    "harpsichord 2": "harpsichord",
    "harpsichord 3": "harpsichord",
    "harpsichord 4": "harpsichord",
    "violin 1": "violin",
    "violin 2": "violin",
    "violin i": "violin",
    "violin ii": "violin",
    "violin iii": "violin",
    "viola 1": "viola",
    "viola 2": "viola",
    "flute 1": "flute",
    "flute 2": "flute",
    "flute i": "flute",
    "flute ii": "flute",
    "bassoon 1": "bassoon",
    "bassoon 2": "bassoon",
    "horn in f 1": "horn",
    "horn in f 2": "horn",
    "p1": "piano",
    "p2": "piano",
    # German instrument names
    "posaunen": "trombone",
    "posaune": "trombone",
    "kontrabässe": "double bass",
    "kontrabass": "double bass",
    "violoncelli": "cello",
    "flöten": "flute",
    "flöte": "flute",
    "flöjte.": "flute",
    "klarinetten": "clarinet",
    "klarinette": "clarinet",
    "fagotten": "bassoon",
    "fagott": "bassoon",
    "fagotti.": "bassoon",
    "singstimme": "voice",
    "violen": "viola",
    # With flat/sharp symbols
    "clarinets in b♭": "clarinet",
    "clarinet in b♭": "clarinet",
    "trumpets in b♭": "trumpet",
    "trumpet in b♭": "trumpet",
    "clarinets in a": "clarinet",
    "clarinet in a": "clarinet",
    "b♭ clarinet": "clarinet",
    "a clarinet": "clarinet",
    "horn in e♭": "horn",
    "horn in b♭": "horn",
    "horn in e": "horn",
    "horn in d": "horn",
    # French
    "hautbois": "oboe",
    "flûte": "flute",
    # Spanish
    "trompette en do": "trumpet",
    # Other
    "piccolo": "piccolo",
    "glockenspiel": "percussion",
    "harfe": "harp",
    "timpani": "timpani",
    "percussion": "percussion",
    # Wikidata values that need normalization
    "player piano": "piano",
    "piano four hands": "piano",
    "musical duo": "duo",
    "thoroughbass": "continuo",
    "string section": "string orchestra",
    "theorbo": "continuo",
    "chalumeau": "clarinet",
}


def normalize_instrument(name):
    if not name:
        return "unknown"
    raw = name.lower().strip()
    # Direct lookup first
    if raw in INSTRUMENT_CANONICAL:
        return INSTRUMENT_CANONICAL[raw]
    # Strip leading numbers and punctuation: "2 oboes" -> "oboes"
    import re
    stripped = re.sub(r"^\d+\s+", "", raw)
    if stripped in INSTRUMENT_CANONICAL:
        return INSTRUMENT_CANONICAL[stripped]
    # Strip trailing numbers/dots/spaces: "trombone 1. 2." -> "trombone"
    stripped2 = re.sub(r"[\s\d.]+$", "", raw)
    if stripped2 in INSTRUMENT_CANONICAL:
        return INSTRUMENT_CANONICAL[stripped2]
    # Strip both: "2 clarinets in b♭" -> "clarinets in b♭"
    stripped3 = re.sub(r"[\s\d.]+$", "", stripped)
    if stripped3 in INSTRUMENT_CANONICAL:
        return INSTRUMENT_CANONICAL[stripped3]
    # Try depluralization: "oboes" -> "oboe", "violins" -> "violin"
    for suffix_from, suffix_to in [("s", ""), ("es", ""), ("i", "")]:
        if stripped3.endswith(suffix_from):
            singular = stripped3[: -len(suffix_from)] + suffix_to
            if singular in INSTRUMENT_CANONICAL:
                return INSTRUMENT_CANONICAL[singular]
    # Also try just the base word
    base = re.sub(r"\s+(in\s+\w+|i+|solo)$", "", stripped3)
    if base in INSTRUMENT_CANONICAL:
        return INSTRUMENT_CANONICAL[base]
    # Depluralize the base
    for suffix_from, suffix_to in [("s", ""), ("es", ""), ("i", "")]:
        if base.endswith(suffix_from):
            singular = base[: -len(suffix_from)] + suffix_to
            if singular in INSTRUMENT_CANONICAL:
                return INSTRUMENT_CANONICAL[singular]
    return raw


def normalize_instrument_set(instruments):
    if not instruments:
        return frozenset()
    return frozenset(normalize_instrument(i) for i in instruments)


def fetch_all_canonical_instruments(qids):
    """
    Batch-query Wikidata for P870 (instrumentation) for all QIDs.
    Returns dict: qid -> frozenset of normalized instrument names.
    """
    result = {}
    qid_list = list(qids)
    total = len(qid_list)
    for i in range(0, total, 50):
        batch = qid_list[i: i + 50]
        values = " ".join(f"wd:{q}" for q in batch)
        query = f"""
        SELECT ?work ?instrumentLabel WHERE {{
          VALUES ?work {{ {values} }}
          ?work wdt:P870 ?instrument.
          SERVICE wikibase:label {{ bd:serviceParam wikibase:language "en". }}
        }}
        """
        url = "https://query.wikidata.org/sparql?" + urllib.parse.urlencode(
            {"query": query, "format": "json"}
        )
        req = urllib.request.Request(url, headers={"User-Agent": "PDMXDedup/1.0"})
        try:
            resp = urllib.request.urlopen(req)
            data = json.loads(resp.read())
            for r in data["results"]["bindings"]:
                qid = r["work"]["value"].split("/")[-1]
                inst = normalize_instrument(r["instrumentLabel"]["value"])
                result.setdefault(qid, set()).add(inst)
        except Exception as e:
            print(f"  SPARQL error on batch {i}-{i + len(batch)}: {e}", file=sys.stderr)
        if i + 50 < total:
            time.sleep(0.5)
        done = min(i + 50, total)
        print(f"  P870 query: {done}/{total} QIDs...", end="\r", file=sys.stderr)

    print(file=sys.stderr)
    return {qid: frozenset(insts) for qid, insts in result.items()}


def fetch_wikipedia_titles(qids):
    """
    Batch-query SPARQL for en.wikipedia sitelinks.
    Returns dict: qid -> Wikipedia page title (with underscores).
    """
    headers = {"User-Agent": "PDMXCorpusDedup/1.0 (glangmead@gmail.com)"}
    result = {}
    qid_list = list(qids)
    total = len(qid_list)
    for i in range(0, total, 50):
        batch = qid_list[i: i + 50]
        values = " ".join(f"wd:{q}" for q in batch)
        query = f"""
        SELECT ?work ?article WHERE {{
          VALUES ?work {{ {values} }}
          ?article schema:about ?work ;
                   schema:isPartOf <https://en.wikipedia.org/> .
        }}
        """
        url = "https://query.wikidata.org/sparql?" + urllib.parse.urlencode(
            {"query": query, "format": "json"}
        )
        req = urllib.request.Request(url, headers=headers)
        try:
            data = json.loads(urllib.request.urlopen(req).read())
            for r in data["results"]["bindings"]:
                qid = r["work"]["value"].split("/")[-1]
                article = r["article"]["value"]
                title = urllib.parse.unquote(article.split("/wiki/")[-1])
                result[qid] = title
        except Exception as e:
            print(f"  Sitelink SPARQL error on batch {i}: {e}", file=sys.stderr)
        if i + 50 < total:
            time.sleep(0.5)
        done = min(i + 50, total)
        print(f"  Wikipedia titles: {done}/{total} QIDs...", end="\r", file=sys.stderr)

    print(file=sys.stderr)
    return result


def fetch_wikipedia_categories(qid_to_title):
    """
    Batch-fetch Wikipedia categories for all pages.
    Returns dict: qid -> list of category names (without 'Category:' prefix).
    """
    headers = {"User-Agent": "PDMXCorpusDedup/1.0 (glangmead@gmail.com)"}
    # Invert: title -> qid (handle spaces vs underscores)
    title_to_qid = {}
    for qid, title in qid_to_title.items():
        title_to_qid[title] = qid
        title_to_qid[title.replace("_", " ")] = qid

    titles = list(qid_to_title.values())
    result = {}
    total = len(titles)
    for i in range(0, total, 50):
        batch = titles[i: i + 50]
        params = {
            "action": "query",
            "titles": "|".join(batch),
            "prop": "categories",
            "cllimit": "500",
            "format": "json",
        }
        url = "https://en.wikipedia.org/w/api.php?" + urllib.parse.urlencode(params)
        req = urllib.request.Request(url, headers=headers)
        try:
            data = json.loads(urllib.request.urlopen(req).read())
            for page_id, page in data["query"]["pages"].items():
                title = page.get("title", "")
                cats = [
                    c["title"].replace("Category:", "")
                    for c in page.get("categories", [])
                ]
                qid = title_to_qid.get(title)
                if not qid:
                    qid = title_to_qid.get(title.replace(" ", "_"))
                if qid:
                    result[qid] = cats
        except Exception as e:
            print(f"  Wikipedia categories error on batch {i}: {e}", file=sys.stderr)
        if i + 50 < total:
            time.sleep(0.3)
        done = min(i + 50, total)
        print(
            f"  Wikipedia categories: {done}/{total} pages...",
            end="\r",
            file=sys.stderr,
        )

    print(file=sys.stderr)
    return result


def midicsv_note_set(midi_path):
    """Extract canonical note set from MIDI: set of (beat_pos_in_64ths, pitch)."""
    result = subprocess.run(
        [MIDICSV, os.path.basename(midi_path)],
        capture_output=True,
        cwd=os.path.dirname(midi_path),
    )
    if result.returncode != 0:
        return None
    stdout = result.stdout.decode("utf-8", errors="replace")
    tpq = 480
    notes = set()
    for line in stdout.strip().split("\n"):
        parts = [p.strip() for p in line.split(",")]
        if len(parts) >= 4 and parts[2] == "Header":
            tpq = int(parts[5])
        if len(parts) >= 6 and parts[2] == "Note_on_c":
            vel = int(parts[5])
            if vel > 0:
                tick = int(parts[1])
                pitch = int(parts[4])
                tick_per_64th = tpq / 16
                beat_pos = round(tick / tick_per_64th)
                notes.add((beat_pos, pitch))
    return notes


def jaccard(a, b):
    if not a and not b:
        return 1.0
    if not a or not b:
        return 0.0
    return len(a & b) / len(a | b)


def classify_instrumentation(file_instruments, wd_instruments):
    """
    Determine if a file's instrumentation matches the Wikidata canonical.
    Returns: "true", "false", or "unknown"
    """
    if not wd_instruments:
        return "unknown"
    if not file_instruments:
        # No instrument data in the file — can't tell.
        # But if wikidata says piano/keyboard and we have no info, mark unknown
        return "unknown"

    # For keyboard works, wikidata might say "keyboard" generically
    # while file says "piano" or "harpsichord" — both are valid originals
    keyboard_family = {"piano", "harpsichord", "organ", "keyboard", "clavichord"}

    # Vocal/choral equivalence: SATB voices = choir
    vocal_family = {"voice", "choir"}

    # Orchestral: if canonical says "orchestra" or "string orchestra", a file
    # listing individual orchestral parts (strings, winds, brass, percussion)
    # IS the original — it's just spelled out rather than summarized.
    orchestral_indicators = {
        "violin", "viola", "cello", "double bass", "contrabass",
        "flute", "oboe", "clarinet", "bassoon",
        "horn", "trumpet", "trombone", "tuba",
        "timpani", "percussion", "harp",
        "piccolo",
    }
    string_indicators = {"violin", "viola", "cello", "double bass", "contrabass"}

    # Expand wikidata set: if it contains "keyboard", accept any keyboard instrument
    wd_expanded = set(wd_instruments)
    if wd_expanded & keyboard_family:
        wd_expanded |= keyboard_family
    if wd_expanded & vocal_family:
        wd_expanded |= vocal_family

    # Expand file set similarly for comparison
    file_expanded = set(file_instruments)
    if file_expanded & keyboard_family:
        file_expanded |= keyboard_family
    if file_expanded & vocal_family:
        file_expanded |= vocal_family

    # Orchestral expansion: if canonical says "orchestra" and the file lists
    # multiple orchestral instrument families, treat it as matching.
    if "orchestra" in wd_expanded or "chamber orchestra" in wd_expanded:
        # Count how many orchestral families are represented in the file
        known_file = file_expanded & orchestral_indicators
        # If file has instruments from at least 2 orchestral families
        # (strings + winds, or strings + brass, etc.), it's orchestral
        has_strings = bool(known_file & string_indicators)
        has_winds = bool(known_file & {"flute", "oboe", "clarinet", "bassoon", "piccolo"})
        has_brass = bool(known_file & {"horn", "trumpet", "trombone", "tuba"})
        n_families = sum([has_strings, has_winds, has_brass])
        if n_families >= 2:
            return "true"
    if "string orchestra" in wd_expanded:
        known_file = file_expanded & string_indicators
        if len(known_file) >= 2:
            return "true"

    # Check: is the file's instrumentation a reasonable match?
    # Exact match
    if file_expanded == wd_expanded:
        return "true"

    # File instruments are a subset of (expanded) wikidata instruments
    # e.g. file has {piano} and wikidata has {piano, voice}
    if file_expanded <= wd_expanded:
        return "true"

    # Wikidata is a subset of file instruments
    # e.g. wikidata says {choir} and file has {voice, organ} — organ is accompaniment
    if wd_expanded <= file_expanded:
        return "true"

    # File instruments overlap substantially with wikidata
    if file_expanded & wd_expanded:
        overlap = len(file_expanded & wd_expanded)
        total = len(file_expanded | wd_expanded)
        if overlap / total >= 0.5:
            return "true"

    # No overlap at all — clearly an arrangement
    if not (file_expanded & wd_expanded):
        return "false"

    return "false"


def main():
    # 1. Load all works
    print("Loading corpus...", file=sys.stderr)
    all_works = []
    by_qid = defaultdict(list)
    for composer in sorted(os.listdir(BASE)):
        idx_path = os.path.join(BASE, composer, "index.json")
        if not os.path.isfile(idx_path):
            continue
        with open(idx_path) as f:
            data = json.load(f)
        for w in data.get("works", []):
            w["_composer_slug"] = composer
            qid = w.get("wikidata_id")
            if qid:
                by_qid[qid].append(w)
                all_works.append(w)

    print(f"  {len(all_works)} works, {len(by_qid)} unique QIDs", file=sys.stderr)

    # 2. Fetch Wikidata P870 for ALL qids
    print("Fetching Wikidata instrumentation (P870)...", file=sys.stderr)
    all_qids = set(by_qid.keys())
    wd_instruments = fetch_all_canonical_instruments(all_qids)
    n_with_p870 = sum(1 for q in all_qids if q in wd_instruments)
    print(f"  {n_with_p870}/{len(all_qids)} QIDs have P870 data", file=sys.stderr)

    # 2b. For QIDs missing P870, fall back to Wikipedia categories
    missing_p870 = all_qids - set(wd_instruments.keys())
    if missing_p870:
        print("Fetching Wikipedia titles for P870-missing QIDs...", file=sys.stderr)
        wiki_titles = fetch_wikipedia_titles(missing_p870)
        print(
            f"  {len(wiki_titles)}/{len(missing_p870)} have en.wikipedia pages",
            file=sys.stderr,
        )

        print("Fetching Wikipedia categories...", file=sys.stderr)
        wiki_cats = fetch_wikipedia_categories(wiki_titles)
        print(f"  Got categories for {len(wiki_cats)} pages", file=sys.stderr)

        # Extract instruments from categories
        n_from_wiki = 0
        for qid, cats in wiki_cats.items():
            inst = categories_to_instruments(cats)
            if inst:
                wd_instruments[qid] = inst
                n_from_wiki += 1
        n_total = sum(1 for q in all_qids if q in wd_instruments)
        print(
            f"  Wikipedia categories added {n_from_wiki} more -> {n_total}/{len(all_qids)} QIDs with instrumentation",
            file=sys.stderr,
        )

    # 3. Build MIDI clusters within each QID group
    print("Building MIDI clusters...", file=sys.stderr)
    cluster_id = 0
    # Maps (composer_slug, midi_path) -> cluster_id
    work_cluster = {}

    for qid_idx, qid in enumerate(sorted(by_qid.keys())):
        works = by_qid[qid]
        if (qid_idx + 1) % 50 == 0:
            print(
                f"  Clustering: {qid_idx + 1}/{len(by_qid)} QIDs...",
                end="\r",
                file=sys.stderr,
            )

        if len(works) == 1:
            # Singleton — its own cluster
            w = works[0]
            midi_rel = w.get("midi")
            path = f"{w['_composer_slug']}/{midi_rel}" if midi_rel else f"{w['_composer_slug']}/NO_MIDI"
            work_cluster[path] = cluster_id
            cluster_id += 1
            continue

        # Multi-file group — compute MIDI note sets and cluster
        note_sets = {}
        for w in works:
            midi_rel = w.get("midi")
            if not midi_rel:
                continue
            midi_path = os.path.join(BASE, w["_composer_slug"], midi_rel)
            if os.path.isfile(midi_path):
                ns = midicsv_note_set(midi_path)
                if ns is not None:
                    path = f"{w['_composer_slug']}/{midi_rel}"
                    note_sets[path] = ns

        # Union-find
        paths = [
            f"{w['_composer_slug']}/{w.get('midi', 'NO_MIDI')}" for w in works
        ]
        parent = {p: p for p in paths}

        def find(x):
            while parent[x] != x:
                parent[x] = parent[parent[x]]
                x = parent[x]
            return x

        def union(x, y):
            px, py = find(x), find(y)
            if px != py:
                parent[px] = py

        for a, b in combinations(paths, 2):
            if a in note_sets and b in note_sets:
                j = jaccard(note_sets[a], note_sets[b])
                if j > 0.95:
                    union(a, b)

        # Assign cluster IDs
        root_to_cluster = {}
        for p in paths:
            root = find(p)
            if root not in root_to_cluster:
                root_to_cluster[root] = cluster_id
                cluster_id += 1
            work_cluster[p] = root_to_cluster[root]

    print(f"\n  {cluster_id} total clusters", file=sys.stderr)

    # 4. Build TSV rows
    print("Building TSV...", file=sys.stderr)
    rows = []
    for w in all_works:
        midi_rel = w.get("midi")
        qid = w.get("wikidata_id", "")
        composer = w["_composer_slug"]
        path = f"{composer}/{midi_rel}" if midi_rel else f"{composer}/NO_MIDI"

        instruments_raw = w.get("instruments") or []
        instruments_str = "; ".join(instruments_raw) if instruments_raw else ""

        wd_inst = wd_instruments.get(qid)
        wd_inst_str = "; ".join(sorted(wd_inst)) if wd_inst else ""

        file_inst_set = normalize_instrument_set(instruments_raw)
        is_original = classify_instrumentation(file_inst_set, wd_inst)

        cid = work_cluster.get(path, -1)

        rows.append({
            "path": path,
            "wikidata_qid": qid,
            "cluster": cid,
            "instruments": instruments_str,
            "canonical_instruments": wd_inst_str,
            "is_original_instrumentation": is_original,
        })

    # Sort by cluster, then path
    rows.sort(key=lambda r: (r["cluster"], r["path"]))

    # 5. Write TSV
    out_path = TSV_OUT
    columns = [
        "path",
        "wikidata_qid",
        "cluster",
        "instruments",
        "canonical_instruments",
        "is_original_instrumentation",
    ]
    with open(out_path, "w") as f:
        f.write("\t".join(columns) + "\n")
        for r in rows:
            f.write("\t".join(str(r[c]) for c in columns) + "\n")

    print(f"\nWrote {len(rows)} rows to {out_path}", file=sys.stderr)

    # Stats
    n_true = sum(1 for r in rows if r["is_original_instrumentation"] == "true")
    n_false = sum(1 for r in rows if r["is_original_instrumentation"] == "false")
    n_unknown = sum(1 for r in rows if r["is_original_instrumentation"] == "unknown")
    print(f"  is_original: true={n_true}, false={n_false}, unknown={n_unknown}", file=sys.stderr)


if __name__ == "__main__":
    main()
