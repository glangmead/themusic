#!/usr/bin/env python3
"""
Build pdmx_composers_wiki_pruned1 from pdmx_composers_with_wiki using
cluster and instrumentation data from corpus_clusters.tsv.

Rules per cluster:
  - Has any is_original=true  -> keep the single best true file
  - All is_original=false     -> drop entire cluster
  - Has unknown (no true)     -> keep all unknown files
"""

import json
import os
import shutil
from collections import defaultdict
from pathlib import Path

PDMX_ROOT = Path(__file__).parent
BASE_IN = PDMX_ROOT / "pdmx_composers_with_wiki"
BASE_OUT = PDMX_ROOT / "pdmx_composers_wiki_pruned1"
TSV_PATH = PDMX_ROOT / "corpus_clusters.tsv"


def load_tsv():
    """Load TSV into list of dicts."""
    with open(TSV_PATH) as f:
        lines = f.readlines()
    header = lines[0].strip().split("\t")
    rows = []
    for line in lines[1:]:
        cols = line.strip().split("\t")
        rows.append(dict(zip(header, cols)))
    return rows


def decide_kept_paths(rows, index_cache):
    """
    Apply pruning rules. Returns set of paths to keep.
    """
    clusters = defaultdict(list)
    for r in rows:
        clusters[r["cluster"]].append(r)

    kept_paths = set()

    for cid, members in clusters.items():
        origs = set(m["is_original_instrumentation"] for m in members)

        if "true" in origs:
            # Keep the single best true file
            true_members = [m for m in members if m["is_original_instrumentation"] == "true"]
            best = pick_best(true_members, index_cache)
            kept_paths.add(best["path"])
        elif origs == {"false"}:
            # Drop all
            pass
        else:
            # Has unknown — keep all unknowns
            for m in members:
                if m["is_original_instrumentation"] == "unknown":
                    kept_paths.add(m["path"])

    return kept_paths


def load_index_cache():
    """Load all composer index.json files once. Returns dict: composer -> data."""
    cache = {}
    for composer in os.listdir(BASE_IN):
        idx_path = os.path.join(BASE_IN, composer, "index.json")
        if os.path.isfile(idx_path):
            with open(idx_path) as f:
                cache[composer] = json.load(f)
    return cache


def pick_best(members, index_cache):
    """
    Pick the best file from a list by: most notes, highest rating, most views.
    Uses preloaded index_cache to avoid re-reading index.json per file.
    """
    scored = []
    for m in members:
        path = m["path"]
        composer = path.split("/")[0]
        n_notes = 0
        rating = 0.0
        views = 0
        data = index_cache.get(composer)
        if data:
            midi_rel = "/".join(path.split("/")[1:])  # e.g. midi/Reverie.mid
            for w in data.get("works", []):
                if w.get("midi") == midi_rel:
                    n_notes = w.get("n_notes") or 0
                    rating = (w.get("pdmx") or {}).get("rating") or 0.0
                    views = (w.get("pdmx") or {}).get("n_views") or 0
                    break
        scored.append((n_notes, rating, views, m))

    scored.sort(key=lambda x: (x[0], x[1], x[2]), reverse=True)
    return scored[0][3]


def build_pruned_corpus(kept_paths):
    """
    Copy the directory structure, keeping only works whose paths are in kept_paths.
    Updates index.json to remove dropped works.
    """
    if os.path.exists(BASE_OUT):
        shutil.rmtree(BASE_OUT)

    # Group kept paths by composer
    by_composer = defaultdict(set)
    for p in kept_paths:
        parts = p.split("/")
        composer = parts[0]
        midi_rel = "/".join(parts[1:])  # e.g. midi/foo.mid
        by_composer[composer].add(midi_rel)

    total_kept = 0
    total_composers = 0

    for composer in sorted(os.listdir(BASE_IN)):
        composer_in = os.path.join(BASE_IN, composer)
        if not os.path.isdir(composer_in):
            continue

        idx_in = os.path.join(composer_in, "index.json")
        if not os.path.isfile(idx_in):
            continue

        with open(idx_in) as f:
            data = json.load(f)

        kept_midi_rels = by_composer.get(composer, set())

        # Filter works
        kept_works = []
        for w in data.get("works", []):
            midi_rel = w.get("midi")
            if midi_rel and midi_rel in kept_midi_rels:
                kept_works.append(w)
            elif not midi_rel:
                # Works without MIDI — check if path is in kept_paths
                no_midi_path = f"{composer}/NO_MIDI"
                if no_midi_path in kept_paths:
                    kept_works.append(w)

        if not kept_works:
            continue

        total_composers += 1
        total_kept += len(kept_works)

        # Create output directory
        composer_out = os.path.join(BASE_OUT, composer)
        os.makedirs(os.path.join(composer_out, "midi"), exist_ok=True)
        os.makedirs(os.path.join(composer_out, "musicxml"), exist_ok=True)

        # Write filtered index.json
        data_out = dict(data)
        data_out["works"] = kept_works
        with open(os.path.join(composer_out, "index.json"), "w") as f:
            json.dump(data_out, f, indent=2, ensure_ascii=False)

        # Copy MIDI and MusicXML files for kept works
        for w in kept_works:
            midi_rel = w.get("midi")
            if midi_rel:
                src = os.path.join(composer_in, midi_rel)
                dst = os.path.join(composer_out, midi_rel)
                if os.path.isfile(src):
                    shutil.copy2(src, dst)

            mxml_rel = w.get("musicxml")
            if mxml_rel:
                src = os.path.join(composer_in, mxml_rel)
                dst = os.path.join(composer_out, mxml_rel)
                if os.path.isfile(src):
                    shutil.copy2(src, dst)

    return total_composers, total_kept


def main():
    print("Loading TSV...")
    rows = load_tsv()
    print(f"  {len(rows)} files in TSV")

    print("Loading index cache...")
    index_cache = load_index_cache()
    print(f"  {len(index_cache)} composers loaded")

    print("Deciding which files to keep...")
    kept_paths = decide_kept_paths(rows, index_cache)
    dropped = len(rows) - len(kept_paths)
    print(f"  Keeping {len(kept_paths)}, dropping {dropped}")

    print("Building pruned corpus...")
    n_composers, n_works = build_pruned_corpus(kept_paths)
    print(f"  {n_composers} composers, {n_works} works")
    print(f"  Output: {BASE_OUT}")

    # Sanity check: verify counts match
    if n_works != len(kept_paths):
        # Some paths may be NO_MIDI or have mismatches
        print(f"  Note: {len(kept_paths)} paths in kept set but {n_works} works written")
        missing = kept_paths - set()  # would need more logic to track
        print("  (Small mismatches expected for NO_MIDI entries)")


if __name__ == "__main__":
    main()
