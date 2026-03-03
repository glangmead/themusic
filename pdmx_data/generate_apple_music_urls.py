#!/usr/bin/env python3
"""
Generate Apple Music search URLs for each work.

This creates searchable URLs using catalog numbers and titles.
Can be extended later to use the iTunes Search API:
  https://itunes.apple.com/search?term={query}&media=music&entity=song&limit=5

Or the Apple Music API (requires auth):
  https://api.music.apple.com/v1/catalog/us/search?term={query}&types=songs

For now, stores search_query in each work for future use.
"""

import json
import re
import sys
import urllib.parse
from pathlib import Path

OUTPUT_ROOT = Path(__file__).parent / "pdmx_composers"


def build_search_query(composer_name, work):
    """Build an Apple Music search query for a work."""
    title = work.get("title", "")
    catalog_numbers = work.get("catalog_numbers", {})

    # Build search terms
    parts = []

    # Add composer last name
    name_parts = composer_name.split()
    if name_parts:
        parts.append(name_parts[-1])  # Last name

    # Add catalog number if available (most specific identifier)
    for cat_type, cat_num in catalog_numbers.items():
        parts.append(f"{cat_type} {cat_num}")
        break  # Use first catalog number only

    # Add key if available
    key = work.get("key", "")
    if key and "minor" in key.lower():
        parts.append(key.split()[0] + " minor")
    elif key and "major" in key.lower():
        parts.append(key.split()[0] + " major")

    # If no catalog number, use cleaned title
    if not catalog_numbers:
        # Clean title: remove file-name artifacts
        clean = re.sub(r'_', ' ', title)
        clean = re.sub(r'\s+', ' ', clean).strip()
        # Truncate to first meaningful part
        if len(clean) > 50:
            clean = clean[:50]
        parts.append(clean)

    query = " ".join(parts)
    return query


def main():
    if len(sys.argv) > 1:
        output_root = Path(sys.argv[1])
    else:
        output_root = OUTPUT_ROOT

    manifest = json.load(open(output_root / "manifest.json"))
    total_queries = 0

    for c in manifest["composers"]:
        slug = c["slug"]
        index_path = output_root / slug / "index.json"
        if not index_path.exists():
            continue

        data = json.loads(index_path.read_text().strip())
        composer_name = data.get("composer_name", "")

        for work in data.get("works", []):
            query = build_search_query(composer_name, work)
            work["apple_music_search_query"] = query
            total_queries += 1

        index_path.write_text(json.dumps(data, ensure_ascii=False) + "\n")

    print(f"Generated {total_queries} Apple Music search queries")
    print(f"To use with iTunes Search API:")
    print(f"  https://itunes.apple.com/search?term={{query}}&media=music&entity=song&limit=5")
    print(f"\nExample queries:")

    # Show some examples
    for slug in ["bach", "mozart", "chopin", "debussy"]:
        data = json.loads((output_root / slug / "index.json").read_text().strip())
        for w in data["works"][:2]:
            q = w.get("apple_music_search_query", "")
            print(f"  {slug}: {q}")


if __name__ == "__main__":
    main()
