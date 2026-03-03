#!/usr/bin/env python3
"""
Phase 2: Wikipedia enrichment for pdmx_composers.

For each composer with a wiki_page URL:
1. Fetch their Wikipedia article via the MediaWiki API
2. Extract structured data: birth/death years, bio summary, work catalog info
3. Try to match PDMX works against Wikipedia work lists using catalog numbers + titles
4. Update index.json with enriched fields:
   - wikipedia_extract: short bio paragraph
   - birth_year / death_year (integers)
   - catalog_type: e.g. "BWV", "K", "Op"
   - For each work: year_composed, standard_title, wikipedia_work_url (if found)
"""

import json
import os
import re
import sys
import time
import urllib.request
import urllib.parse
import urllib.error
from pathlib import Path

# ──────────────────────────────────────────────
# Configuration
# ──────────────────────────────────────────────
PDMX_ROOT = Path(__file__).parent
OUTPUT_ROOT = PDMX_ROOT / "pdmx_composers"
RATE_LIMIT_SECONDS = 0.2  # be polite to Wikipedia API

# Known catalog type mappings per composer (common ones)
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
}


def wiki_api_query(title, prop="extracts|revisions", extra_params=None):
    """Query the Wikipedia API for a given article title."""
    params = {
        "action": "query",
        "titles": title,
        "format": "json",
        "formatversion": "2",
    }
    if "extracts" in prop:
        params["prop"] = "extracts"
        params["exintro"] = "1"
        params["explaintext"] = "1"
        params["exsectionformat"] = "plain"
    if extra_params:
        params.update(extra_params)

    url = "https://en.wikipedia.org/w/api.php?" + urllib.parse.urlencode(params)
    try:
        req = urllib.request.Request(url, headers={
            "User-Agent": "pdmx-greg-enrichment/1.0 (glangmead@gmail.com)"
        })
        with urllib.request.urlopen(req, timeout=15) as resp:
            return json.loads(resp.read().decode("utf-8"))
    except (urllib.error.URLError, urllib.error.HTTPError, json.JSONDecodeError) as e:
        print(f"  API error: {e}")
        return None


def wiki_get_wikitext(title):
    """Get raw wikitext for a Wikipedia article."""
    params = {
        "action": "parse",
        "page": title,
        "format": "json",
        "formatversion": "2",
        "prop": "wikitext",
    }
    url = "https://en.wikipedia.org/w/api.php?" + urllib.parse.urlencode(params)
    try:
        req = urllib.request.Request(url, headers={
            "User-Agent": "pdmx-greg-enrichment/1.0 (glangmead@gmail.com)"
        })
        with urllib.request.urlopen(req, timeout=15) as resp:
            data = json.loads(resp.read().decode("utf-8"))
            if "parse" in data and "wikitext" in data["parse"]:
                return data["parse"]["wikitext"]
            return None
    except Exception as e:
        print(f"  Wikitext error: {e}")
        return None


def wiki_get_sections(title):
    """Get section list for a Wikipedia article."""
    params = {
        "action": "parse",
        "page": title,
        "format": "json",
        "formatversion": "2",
        "prop": "sections",
    }
    url = "https://en.wikipedia.org/w/api.php?" + urllib.parse.urlencode(params)
    try:
        req = urllib.request.Request(url, headers={
            "User-Agent": "pdmx-greg-enrichment/1.0 (glangmead@gmail.com)"
        })
        with urllib.request.urlopen(req, timeout=15) as resp:
            data = json.loads(resp.read().decode("utf-8"))
            if "parse" in data:
                return data["parse"].get("sections", [])
            return []
    except Exception as e:
        print(f"  Sections error: {e}")
        return []


def wiki_get_section_text(title, section_index):
    """Get plaintext of a specific section."""
    params = {
        "action": "parse",
        "page": title,
        "format": "json",
        "formatversion": "2",
        "prop": "wikitext",
        "section": str(section_index),
    }
    url = "https://en.wikipedia.org/w/api.php?" + urllib.parse.urlencode(params)
    try:
        req = urllib.request.Request(url, headers={
            "User-Agent": "pdmx-greg-enrichment/1.0 (glangmead@gmail.com)"
        })
        with urllib.request.urlopen(req, timeout=15) as resp:
            data = json.loads(resp.read().decode("utf-8"))
            if "parse" in data and "wikitext" in data["parse"]:
                return data["parse"]["wikitext"]
            return None
    except Exception as e:
        print(f"  Section text error: {e}")
        return None


def extract_years_from_dates(dates_str):
    """Extract birth and death years from dates string like '1685 – 1750'."""
    if not dates_str:
        return None, None
    years = re.findall(r'\b(\d{3,4})\b', dates_str)
    birth = int(years[0]) if len(years) >= 1 else None
    death = int(years[1]) if len(years) >= 2 else None
    return birth, death


def extract_bio_summary(extract_text):
    """Clean up Wikipedia extract to a concise bio."""
    if not extract_text:
        return None
    # Take first 2-3 sentences max
    sentences = re.split(r'(?<=[.!?])\s+', extract_text.strip())
    bio = " ".join(sentences[:3])
    if len(bio) > 500:
        bio = bio[:497] + "..."
    return bio


def find_works_sections(sections):
    """Find section indices related to works/compositions."""
    works_keywords = [
        "works", "compositions", "selected works", "notable works",
        "list of compositions", "major works", "musical works",
        "selected compositions", "catalogue", "catalog",
        "operas", "symphonies", "concertos", "sonatas", "chamber music",
        "piano works", "orchestral works", "choral works", "vocal works",
    ]
    found = []
    for s in sections:
        title_lower = s.get("line", "").lower().strip()
        for kw in works_keywords:
            if kw in title_lower:
                found.append(s)
                break
    return found


def parse_work_entries_from_wikitext(wikitext):
    """
    Parse work entries from wikitext. Look for patterns like:
    - [[Symphony No. 5 (Beethoven)|Symphony No. 5]] in C minor, Op. 67 (1808)
    - * Sonata No. 14 in C-sharp minor, Op. 27, No. 2 ("Moonlight") (1801)
    - Bullets with work titles, catalog numbers, years
    """
    if not wikitext:
        return []

    entries = []
    lines = wikitext.split("\n")

    for line in lines:
        line = line.strip()
        if not line:
            continue
        # Skip headers
        if line.startswith("="):
            continue
        # Look for bullet items or numbered items
        if not (line.startswith("*") or line.startswith("#") or line.startswith(":")):
            continue

        # Clean up wiki markup
        clean = re.sub(r'\[\[([^|\]]*\|)?([^\]]*)\]\]', r'\2', line)  # [[link|text]] -> text
        clean = re.sub(r"'{2,}", "", clean)  # bold/italic
        clean = re.sub(r'<ref[^>]*>.*?</ref>', '', clean)  # refs
        clean = re.sub(r'<[^>]+>', '', clean)  # HTML tags
        clean = re.sub(r'\{\{[^}]*\}\}', '', clean)  # templates
        clean = clean.lstrip("*#: ").strip()

        if len(clean) < 5:
            continue

        entry = {"raw": clean}

        # Extract year
        year_match = re.search(r'\((\d{4})\)', clean)
        if year_match:
            entry["year"] = int(year_match.group(1))

        # Extract catalog numbers
        catalog_patterns = [
            (r'\bBWV\s*(\d+[a-z]?)', "BWV"),
            (r'\bK\.?\s*(\d+[a-z]?)', "K"),
            (r'\bKV\.?\s*(\d+[a-z]?)', "K"),
            (r'\bOp\.?\s*(\d+)', "Op"),
            (r'\bD\.?\s*(\d+)', "D"),
            (r'\bHob\.?\s*([IVXLC]+[:/]\d+)', "Hob"),
            (r'\bRV\s*(\d+)', "RV"),
            (r'\bHWV\s*(\d+)', "HWV"),
            (r'\bS\.?\s*(\d+)', "S"),
            (r'\bL\.?\s*(\d+)', "L"),
            (r'\bWoO\s*(\d+)', "WoO"),
            (r'\bTWV\s*(\S+)', "TWV"),
            (r'\bZ\.?\s*(\d+)', "Z"),
            (r'\bFWV\s*(\S+)', "FWV"),
            (r'\bRCT\s*(\d+)', "RCT"),
        ]
        for pattern, cat_type in catalog_patterns:
            m = re.search(pattern, clean, re.IGNORECASE)
            if m:
                entry.setdefault("catalog_numbers", {})[cat_type] = m.group(1)

        # Extract key
        key_match = re.search(
            r'in\s+([A-G][-♯♭#b]?\s*(?:major|minor|Major|Minor))',
            clean
        )
        if key_match:
            entry["key"] = key_match.group(1).strip()

        # Use beginning of text as title (before parenthetical year/catalog)
        title_part = re.split(r'\s*[\(,]\s*(?:Op\.|BWV|K\.|D\.|RV|HWV|\d{4})', clean)[0].strip()
        if title_part:
            entry["title"] = title_part

        entries.append(entry)

    return entries


def normalize_for_matching(s):
    """Normalize a string for fuzzy matching."""
    if not s:
        return ""
    import unicodedata
    # NFD decompose, strip accents
    s = unicodedata.normalize("NFD", s)
    s = "".join(c for c in s if unicodedata.category(c) != "Mn")
    s = s.lower()
    # Remove punctuation
    s = re.sub(r'[^\w\s]', ' ', s)
    s = re.sub(r'\s+', ' ', s).strip()
    return s


def match_work_to_wiki(work, wiki_entries):
    """
    Try to match a PDMX work to a Wikipedia entry.
    Returns the best matching entry or None.
    """
    best_match = None
    best_score = 0

    work_cats = work.get("catalog_numbers", {})
    work_title_norm = normalize_for_matching(work.get("title", ""))

    for entry in wiki_entries:
        score = 0
        entry_cats = entry.get("catalog_numbers", {})

        # Catalog number match is strongest signal
        for cat_type, cat_num in work_cats.items():
            if cat_type in entry_cats:
                entry_num = entry_cats[cat_type]
                # Normalize: strip leading zeros, lowercase
                if re.sub(r'^0+', '', str(cat_num)).lower() == re.sub(r'^0+', '', str(entry_num)).lower():
                    score += 10
                elif str(cat_num).lower() in str(entry_num).lower() or str(entry_num).lower() in str(cat_num).lower():
                    score += 5

        # Title similarity as secondary signal
        entry_title_norm = normalize_for_matching(entry.get("title", ""))
        if entry_title_norm and work_title_norm:
            # Check for significant word overlap
            work_words = set(work_title_norm.split()) - {"in", "the", "a", "of", "no", "for", "and", "minor", "major"}
            entry_words = set(entry_title_norm.split()) - {"in", "the", "a", "of", "no", "for", "and", "minor", "major"}
            if work_words and entry_words:
                overlap = len(work_words & entry_words) / max(len(work_words), len(entry_words))
                score += overlap * 3

        if score > best_score and score >= 5:  # Require at least catalog match
            best_score = score
            best_match = entry

    return best_match


def process_composer(slug, composer_dir):
    """Process one composer: fetch Wikipedia data, match works, update index.json."""
    index_path = composer_dir / "index.json"
    if not index_path.exists():
        return None

    with open(index_path) as f:
        data = json.loads(f.read().strip())

    wiki_url = data.get("wiki_page", "")
    if not wiki_url:
        return None

    # Extract article title from URL
    wiki_title = urllib.parse.unquote(wiki_url.split("/wiki/")[-1]) if "/wiki/" in wiki_url else None
    if not wiki_title:
        return None

    composer_name = data.get("composer_name", slug)
    print(f"  [{slug}] Fetching Wikipedia for {composer_name}...")

    changes = {}

    # 1. Get intro extract (bio summary)
    time.sleep(RATE_LIMIT_SECONDS)
    result = wiki_api_query(wiki_title)
    if result and "query" in result:
        pages = result["query"].get("pages", [])
        if pages and not pages[0].get("missing"):
            extract = pages[0].get("extract", "")
            bio = extract_bio_summary(extract)
            if bio:
                changes["wikipedia_extract"] = bio

    # 2. Extract birth/death years (from dates string or Wikipedia)
    birth, death = extract_years_from_dates(data.get("dates", ""))
    if birth:
        changes["birth_year"] = birth
    if death:
        changes["death_year"] = death

    # 3. Set catalog type
    if composer_name in CATALOG_TYPES:
        changes["catalog_type"] = CATALOG_TYPES[composer_name]

    # 4. Get sections to find works lists
    time.sleep(RATE_LIMIT_SECONDS)
    sections = wiki_get_sections(wiki_title)
    works_sections = find_works_sections(sections)

    # 5. Parse work entries from works sections
    all_wiki_entries = []
    for ws in works_sections[:5]:  # Limit to first 5 relevant sections
        time.sleep(RATE_LIMIT_SECONDS)
        section_text = wiki_get_section_text(wiki_title, ws["index"])
        if section_text:
            entries = parse_work_entries_from_wikitext(section_text)
            all_wiki_entries.extend(entries)

    # 6. Match PDMX works against Wikipedia entries
    n_matched = 0
    works = data.get("works", [])
    for work in works:
        match = match_work_to_wiki(work, all_wiki_entries)
        if match:
            n_matched += 1
            if "year" in match:
                work["year_composed"] = match["year"]
            if "key" in match and "key" not in work:
                work["key"] = match["key"]
            # Merge catalog numbers from Wikipedia
            for cat_type, cat_num in match.get("catalog_numbers", {}).items():
                work.setdefault("catalog_numbers", {})[cat_type] = cat_num

    # 7. Build the "list of compositions" Wikipedia URL if relevant
    # Many major composers have a separate "List of compositions by X" article
    compositions_article = f"List of compositions by {composer_name}"
    time.sleep(RATE_LIMIT_SECONDS)
    check = wiki_api_query(compositions_article, prop="extracts")
    if check and "query" in check:
        pages = check["query"].get("pages", [])
        if pages and not pages[0].get("missing"):
            changes["wikipedia_compositions_url"] = (
                "https://en.wikipedia.org/wiki/" +
                urllib.parse.quote(compositions_article.replace(" ", "_"))
            )

    # Apply changes to data
    data.update(changes)
    data["works"] = works

    # Write updated index.json
    with open(index_path, "w") as f:
        f.write(json.dumps(data, ensure_ascii=False))
        f.write("\n")

    return {
        "slug": slug,
        "composer": composer_name,
        "has_bio": "wikipedia_extract" in changes,
        "has_years": "birth_year" in changes,
        "n_wiki_entries": len(all_wiki_entries),
        "n_works_matched": n_matched,
        "n_works_total": len(works),
        "has_compositions_url": "wikipedia_compositions_url" in changes,
    }


def main():
    if len(sys.argv) > 1:
        output_root = Path(sys.argv[1])
    else:
        output_root = OUTPUT_ROOT

    if not output_root.exists():
        print(f"Output directory not found: {output_root}")
        sys.exit(1)

    # Read manifest to get composer list
    manifest_path = output_root / "manifest.json"
    if not manifest_path.exists():
        print("manifest.json not found")
        sys.exit(1)

    with open(manifest_path) as f:
        manifest = json.load(f)

    composers = manifest.get("composers", [])
    print(f"Processing {len(composers)} composers for Wikipedia enrichment...")
    print()

    results = []
    for i, c in enumerate(composers):
        slug = c["slug"]
        composer_dir = output_root / slug
        if not composer_dir.exists():
            continue

        result = process_composer(slug, composer_dir)
        if result:
            results.append(result)

        if (i + 1) % 10 == 0:
            print(f"\n  Progress: {i+1}/{len(composers)} composers processed\n")

    # Summary
    print("\n" + "=" * 60)
    print("Wikipedia Enrichment Summary")
    print("=" * 60)
    n_bio = sum(1 for r in results if r["has_bio"])
    n_years = sum(1 for r in results if r["has_years"])
    n_with_wiki = sum(1 for r in results if r["n_wiki_entries"] > 0)
    n_any_match = sum(1 for r in results if r["n_works_matched"] > 0)
    total_matched = sum(r["n_works_matched"] for r in results)
    total_works = sum(r["n_works_total"] for r in results)
    n_comp_url = sum(1 for r in results if r["has_compositions_url"])

    print(f"Composers processed:        {len(results)}")
    print(f"With bio summary:           {n_bio}")
    print(f"With birth/death years:     {n_years}")
    print(f"With Wikipedia work lists:  {n_with_wiki}")
    print(f"With compositions URL:      {n_comp_url}")
    print(f"Works matched to Wikipedia: {total_matched}/{total_works}")
    print(f"Composers with any match:   {n_any_match}")

    # Show top matches
    top = sorted(results, key=lambda r: r["n_works_matched"], reverse=True)[:15]
    print("\nTop composers by Wikipedia work matches:")
    for r in top:
        if r["n_works_matched"] > 0:
            print(f"  {r['composer']:40s}  {r['n_works_matched']:3d}/{r['n_works_total']:3d} works matched, {r['n_wiki_entries']:3d} wiki entries")

    # Show unmatched
    unmatched = [r for r in results if r["n_works_matched"] == 0 and r["n_wiki_entries"] > 0]
    if unmatched:
        print(f"\nComposers with wiki entries but no work matches ({len(unmatched)}):")
        for r in unmatched[:10]:
            print(f"  {r['composer']:40s}  {r['n_wiki_entries']:3d} wiki entries, 0 matches")


if __name__ == "__main__":
    main()
