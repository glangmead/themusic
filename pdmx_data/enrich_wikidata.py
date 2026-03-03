#!/usr/bin/env python3
"""
Enrichment: Use Wikidata SPARQL to get structured work metadata.

Wikidata properties used:
  P86   = composer
  P528  = catalog code (BWV, K, Op, etc.)
  P571  = inception (date composed)
  P577  = publication date
  P826  = tonality (key)
  P8625 = MuseScore ID
  P435  = MusicBrainz work ID
  P839  = IMSLP ID
  P2850 = Apple Music artist ID (composer-level)
  P12769 = Apple Music Classical work ID (work-level, if available)

Matching strategy (in order of confidence):
1. MuseScore ID match (P8625 vs musescore_url score ID)
2. Catalog number match (existing catalog_numbers dict)
3. Catalog number extracted from title text
4. Fuzzy title match: exact normalized, substring, token overlap

All API results are cached under wikidata_cache/ with a 7-day TTL.

Run locally (needs network access to en.wikipedia.org and query.wikidata.org).
"""

import json
import os
import re
import sys
import time
import urllib.error
import urllib.parse
import urllib.request
from pathlib import Path

PDMX_ROOT = Path(__file__).parent
OUTPUT_ROOT = PDMX_ROOT / "pdmx_composers"
CACHE_DIR = PDMX_ROOT / "wikidata_cache"
CACHE_TTL = 7 * 24 * 3600  # 7 days
RATE_LIMIT = 0.5
UA = "pdmx-enrichment/1.0 (glangmead@gmail.com)"

# ---------- Cache ----------

def cache_path(category, key):
    """Return path like wikidata_cache/qid/Ludwig_van_Beethoven.json."""
    safe_key = re.sub(r'[^a-zA-Z0-9_-]', '_', key)[:200]
    return CACHE_DIR / category / f"{safe_key}.json"


def load_cache(category, key):
    """Load cached JSON if it exists and is less than CACHE_TTL old."""
    path = cache_path(category, key)
    if not path.exists():
        return None
    age = time.time() - path.stat().st_mtime
    if age > CACHE_TTL:
        return None
    return json.loads(path.read_text())


def save_cache(category, key, data):
    """Write data to cache file, creating directories as needed."""
    path = cache_path(category, key)
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(json.dumps(data, ensure_ascii=False))


# ---------- API ----------

def api_get(url, headers=None):
    """Fetch URL with rate limiting."""
    time.sleep(RATE_LIMIT)
    hdrs = {"User-Agent": UA}
    if headers:
        hdrs.update(headers)
    try:
        req = urllib.request.Request(url, headers=hdrs)
        with urllib.request.urlopen(req, timeout=30) as resp:
            return json.loads(resp.read().decode("utf-8"))
    except Exception as e:
        print(f"    API error: {e}")
        return None


def get_wikidata_id(wiki_title):
    """Get Wikidata Q-ID from Wikipedia article title (cached)."""
    cached = load_cache("qid", wiki_title)
    if cached is not None:
        return cached.get("qid")

    params = {
        "action": "query",
        "titles": wiki_title,
        "prop": "pageprops",
        "ppprop": "wikibase_item",
        "format": "json",
        "formatversion": "2",
    }
    url = "https://en.wikipedia.org/w/api.php?" + urllib.parse.urlencode(params)
    data = api_get(url)
    qid = None
    if data and "query" in data:
        pages = data["query"].get("pages", [])
        if pages and not pages[0].get("missing"):
            qid = pages[0].get("pageprops", {}).get("wikibase_item")

    save_cache("qid", wiki_title, {"qid": qid})
    return qid


def sparql_query(query):
    """Run a SPARQL query against Wikidata."""
    url = "https://query.wikidata.org/sparql?" + urllib.parse.urlencode({
        "query": query, "format": "json"
    })
    data = api_get(url, headers={"Accept": "application/sparql-results+json"})
    if data and "results" in data:
        return data["results"].get("bindings", [])
    return []


def get_composer_apple_music_id(qid):
    """Get Apple Music artist ID (P2850) for a composer (cached)."""
    cached = load_cache("apple", qid)
    if cached is not None:
        return cached.get("apple_id", "")

    query = f"""
    SELECT ?appleId WHERE {{
      wd:{qid} wdt:P2850 ?appleId.
    }}
    """
    results = sparql_query(query)
    apple_id = ""
    if results:
        apple_id = results[0].get("appleId", {}).get("value", "")

    save_cache("apple", qid, {"apple_id": apple_id})
    return apple_id


def get_works_for_composer(qid):
    """
    Get all musical works for a composer from Wikidata (cached).

    Returns list of dicts with catalog info, year, key, wikidata_id, label,
    and various external IDs.
    """
    cached = load_cache("works", qid)
    if cached is not None:
        return cached

    query = f"""
    SELECT ?work ?workLabel ?catalogNum ?inception ?pubDate ?keyLabel
           ?musescoreId ?musicbrainzId ?imslpId ?appleClassicalId WHERE {{
      ?work wdt:P86 wd:{qid}.
      OPTIONAL {{ ?work wdt:P528 ?catalogNum. }}
      OPTIONAL {{ ?work wdt:P571 ?inception. }}
      OPTIONAL {{ ?work wdt:P577 ?pubDate. }}
      OPTIONAL {{ ?work wdt:P826 ?key. }}
      OPTIONAL {{ ?work wdt:P8625 ?musescoreId. }}
      OPTIONAL {{ ?work wdt:P435 ?musicbrainzId. }}
      OPTIONAL {{ ?work wdt:P839 ?imslpId. }}
      OPTIONAL {{ ?work wdt:P12769 ?appleClassicalId. }}
      SERVICE wikibase:label {{ bd:serviceParam wikibase:language "en". }}
    }}
    """
    results = sparql_query(query)
    if not results:
        save_cache("works", qid, [])
        return []

    works = []
    for r in results:
        entry = {}

        label = r.get("workLabel", {}).get("value", "")
        if label:
            entry["label"] = label

        work_uri = r.get("work", {}).get("value", "")
        if work_uri:
            entry["wikidata_id"] = work_uri.split("/")[-1]

        cat = r.get("catalogNum", {}).get("value", "")
        if cat:
            entry["catalog_raw"] = cat
            parsed = parse_catalog(cat)
            if parsed:
                entry["catalog_type"] = parsed[0]
                entry["catalog_num"] = parsed[1]

        inception = r.get("inception", {}).get("value", "")
        pub_date = r.get("pubDate", {}).get("value", "")
        date_str = inception or pub_date
        if date_str:
            m = re.match(r'(\d{4})', date_str)
            if m:
                entry["year"] = int(m.group(1))

        key_label = r.get("keyLabel", {}).get("value", "")
        if key_label and not key_label.startswith("Q"):
            entry["key"] = key_label

        msid = r.get("musescoreId", {}).get("value", "")
        if msid:
            entry["musescore_id"] = msid

        mbid = r.get("musicbrainzId", {}).get("value", "")
        if mbid:
            entry["musicbrainz_id"] = mbid

        imslp = r.get("imslpId", {}).get("value", "")
        if imslp:
            entry["imslp_id"] = imslp

        apple_cid = r.get("appleClassicalId", {}).get("value", "")
        if apple_cid:
            entry["apple_classical_id"] = apple_cid

        works.append(entry)

    save_cache("works", qid, works)
    return works


# ---------- Catalog parsing ----------

CATALOG_PATTERNS_ANCHORED = [
    (r'^BuxWV\s*(\d+)', "BuxWV"),
    (r'^BWV\s*(\d+[a-z]?(?:/\d+)?)', "BWV"),
    (r'^HWV\s*(\d+)', "HWV"),
    (r'^KV?\.?\s*(\d+[a-z]?)', "K"),
    (r'^Op\.?\s*(\d+)', "Op"),
    (r'^RV\s*(\d+)', "RV"),
    (r'^WAB\s*(\d+)', "WAB"),
    (r'^SWV\s*(\d+)', "SWV"),
    (r'^WWV\s*(\d+)', "WWV"),
    (r'^WoO\.?\s*(\d+)', "WoO"),
    (r'^TWV\s*(.+)', "TWV"),
    (r'^Wq\.?\s*(\d+)', "Wq"),
    (r'^Sz\.?\s*(\d+)', "Sz"),
    (r'^LWV\s*(\d+)', "LWV"),
    (r'^FWV\s*(.+)', "FWV"),
    (r'^SV\s*(\d+)', "SV"),
    (r'^JW\s*(.+)', "JW"),
    (r'^D\.?\s*(\d+[a-z]?)', "D"),
    (r'^Hob\.?\s*(.+)', "Hob"),
    (r'^S\.?\s*(\d+)', "S"),
    (r'^L\.?\s*(\d+)', "L"),
    (r'^Z\.?\s*(\d+)', "Z"),
]

# Non-anchored patterns for extracting from title text.
# Short/ambiguous prefixes require 2+ digit numbers.
CATALOG_PATTERNS_TITLE = [
    (r'\bBuxWV\s*(\d+)', "BuxWV"),
    (r'\bBWV\s*(\d+[a-z]?(?:/\d+)?)', "BWV"),
    (r'\bHWV\s*(\d+)', "HWV"),
    (r'\bKV\.?\s*(\d+[a-z]?)', "K"),
    (r'(?<!\w)K\.?\s*(\d+[a-z]?)', "K"),
    (r'\bOp\.?\s*(\d+)', "Op"),
    (r'\bRV\s*(\d+)', "RV"),
    (r'\bWAB\s*(\d+)', "WAB"),
    (r'\bSWV\s*(\d+)', "SWV"),
    (r'\bWWV\s*(\d+)', "WWV"),
    (r'\bWoO\.?\s*(\d+)', "WoO"),
    (r'\bTWV\s*([\d]+(?::[\w\d]+)?)', "TWV"),
    (r'\bWq\.?\s*(\d+)', "Wq"),
    (r'(?<!\w)Sz\.?\s*(\d+)', "Sz"),
    (r'\bLWV\s*(\d+)', "LWV"),
    (r'\bFWV\s*([A-Z]?\d+(?:/\d+)?)', "FWV"),
    (r'\bSV\s*(\d+)', "SV"),
    (r'\bJW\s*([\w/]+\d+)', "JW"),
    (r'(?<!\w)D\.?\s*(\d{2,}[a-z]?)', "D"),
    (r'\bHob\.?\s*(\w+(?:/\w+)*)', "Hob"),
    (r'(?<!\w)S\.?\s*(\d{2,})', "S"),
    (r'(?<!\w)L\.?\s*(\d{2,})', "L"),
    (r'(?<!\w)Z\.?\s*(\d{2,})', "Z"),
]


def parse_catalog(cat_str):
    """Parse a catalog string like 'BWV 792' into ('BWV', '792')."""
    for pattern, cat_type in CATALOG_PATTERNS_ANCHORED:
        m = re.match(pattern, cat_str.strip(), re.IGNORECASE)
        if m:
            return (cat_type, m.group(1).strip())
    return None


def extract_catalog_from_title(title):
    """Extract a catalog number from title text. Returns {type: number} or {}."""
    for pattern, cat_type in CATALOG_PATTERNS_TITLE:
        m = re.search(pattern, title, re.IGNORECASE)
        if m:
            return {cat_type: m.group(1).strip()}
    return {}


def cat_key(cat_type, cat_num):
    """Normalize catalog type+number for matching."""
    return (cat_type.upper(), re.sub(r'^0+', '', str(cat_num)).lower().strip())


def parse_catalog_range(raw, composer_cat_type=""):
    """
    Parse a catalog range like 'BWV 772–801' or bare '772-786'.
    Returns (cat_type, start, end) or None.
    """
    # Try prefixed: "BWV 772–801", "HWV 319–330"
    m = re.match(
        r'([A-Za-z]+\.?\s*)(\d+)\s*[-–—]\s*(\d+)', raw.strip())
    if m:
        prefix = m.group(1).strip().rstrip('.')
        parsed = parse_catalog(prefix + " 0")
        cat_type = parsed[0] if parsed else prefix.upper()
        return (cat_type, int(m.group(2)), int(m.group(3)))

    # Bare range: "772-786" — use composer's catalog type
    if composer_cat_type:
        m = re.match(r'^(\d+)\s*[-–—]\s*(\d+)$', raw.strip())
        if m:
            return (composer_cat_type, int(m.group(1)), int(m.group(2)))

    return None


# ---------- Fuzzy title matching ----------

GENERIC_TERMS = {
    "theme", "prelude", "preludio", "prélude", "minuet", "menuett", "menuet",
    "sonata", "sonatina", "nocturne", "gavotte", "waltz", "march", "marche",
    "scherzo", "ronde", "etude", "étude", "estudio", "andante", "allegro",
    "adagio", "fugue", "fuge", "kyrie", "romance", "rondo", "aria",
    "bagatelle", "ballade", "barcarolle", "berceuse", "bolero", "bourrée",
    "cantata", "capriccio", "cavatina", "chaconne", "concerto", "concertino",
    "courante", "divertimento", "fantasy", "fantasia", "fantaisie",
    "gigue", "humoresque", "impromptu", "intermezzo", "invention",
    "lied", "mazurka", "overture", "ouverture", "partita", "passacaglia",
    "pavane", "polonaise", "requiem", "rhapsody", "sarabande", "serenade",
    "sinfonia", "suite", "tarantella", "toccata", "trio", "variations",
    "gloria", "credo", "sanctus", "agnus dei", "benedictus", "magnificat",
    "missa", "stabat mater", "te deum", "vespers",
}

MIN_SUBSTRING_LEN = 8
MIN_JACCARD = 0.5


def is_word_substring(needle, haystack):
    """Check if needle appears in haystack with word boundaries."""
    pattern = r'\b' + re.escape(needle) + r'\b'
    return bool(re.search(pattern, haystack))


def normalize_for_matching(text, composer_name):
    """Normalize a title for fuzzy comparison."""
    if not text:
        return ""
    s = text
    # Replace underscores (filenames)
    s = s.replace('_', ' ')
    # Decode HTML entities
    s = s.replace('&amp;', '&').replace('&quot;', '"')
    s = s.replace('&#039;', "'").replace('&lt;', '<').replace('&gt;', '>')
    # Lowercase
    s = s.lower()
    # Remove composer name parts
    for part in composer_name.split():
        s = re.sub(r'\b' + re.escape(part.lower()) + r'\b', '', s)
    # Remove catalog number patterns
    for pattern, _ in CATALOG_PATTERNS_TITLE:
        s = re.sub(pattern, '', s, flags=re.IGNORECASE)
    # Normalize "No." / "Nr." but keep the number
    s = re.sub(r'\bno\.?\s+', '', s)
    s = re.sub(r'\bnr\.?\s+', '', s)
    # Also normalize "number" to nothing (keep digit)
    s = re.sub(r'\bnumber\s+', '', s)
    # Remove key signatures
    s = re.sub(
        r'\bin\s+[a-g][#♯♭b]?\s*[-]?\s*'
        r'(?:major|minor|dur|moll|flat|sharp)\b',
        '', s)
    s = re.sub(
        r'\b[a-g][#♯♭b]?\s*[-]?\s*'
        r'(?:major|minor|dur|moll)\b',
        '', s)
    # Remove community noise
    s = re.sub(r'\bby\b\s+\w+(?:\s+\w+)*', '', s)
    s = re.sub(r'\(wip\)', '', s)
    s = re.sub(r'\(updated!?\)', '', s)
    s = re.sub(r'\(complete\)', '', s)
    s = re.sub(r'\(arr\.?[^)]*\)', '', s)
    s = re.sub(r'\barr\.?\s+(?:for\s+)?[\w\s]+$', '', s)
    # Remove movement indicators
    s = re.sub(
        r'\b(?:\d+(?:st|nd|rd|th))?\s*'
        r'(?:movement|mvt|mov)\.?\s*\d*',
        '', s)
    # Remove roman numeral movement prefixes like "III.", "IV."
    s = re.sub(r'\b[ivxlc]+\.\s*', '', s)
    # Remove punctuation (keep spaces)
    s = re.sub(r'[^\w\s]', ' ', s)
    # Collapse whitespace
    s = re.sub(r'\s+', ' ', s).strip()
    # Strip articles
    s = re.sub(
        r'^(?:the|a|an|le|la|les|der|die|das|el|il|lo)\s+', '', s)
    s = re.sub(
        r'\s+(?:the|a|an|le|la|les|der|die|das|el|il|lo)$', '', s)
    return s


def tokenize(text):
    """Split normalized text into word tokens, filtering short ones."""
    if not text:
        return set()
    return {w for w in text.split() if len(w) > 2}


def jaccard(set_a, set_b):
    """Jaccard similarity between two sets."""
    if not set_a or not set_b:
        return 0.0
    return len(set_a & set_b) / len(set_a | set_b)


def get_candidate_names(work):
    """Return list of (text, source_label) for matching, in priority order."""
    candidates = []
    pwt = work.get("parent_work_title", "")
    if pwt:
        candidates.append((pwt, "parent"))
    title = work.get("title", "")
    if title:
        candidates.append((title, "title"))
    mt = work.get("movement_title", "")
    if mt:
        candidates.append((mt, "movement"))
    mxml = work.get("musicxml", "")
    if mxml:
        stem = os.path.splitext(os.path.basename(mxml))[0]
        candidates.append((stem, "filename"))
    return candidates


def fuzzy_match_works(pdmx_works, unmatched_indices, wd_works_deduped,
                      composer_name):
    """
    Attempt fuzzy title matching for unmatched PDMX works against Wikidata
    works. Returns dict: pdmx_index -> (wd_work, match_method).
    """
    matches = {}

    # Pre-normalize all Wikidata labels
    wd_normalized = []
    for w in wd_works_deduped:
        label = w.get("label", "")
        norm = normalize_for_matching(label, composer_name)
        tokens = tokenize(norm)
        wd_normalized.append((norm, tokens))

    for pdmx_idx in unmatched_indices:
        work = pdmx_works[pdmx_idx]
        candidates = get_candidate_names(work)
        best_match = None
        best_method = None
        best_score = 0.0

        for text, _source in candidates:
            pdmx_norm = normalize_for_matching(text, composer_name)
            if not pdmx_norm or pdmx_norm in GENERIC_TERMS:
                continue
            pdmx_tokens = tokenize(pdmx_norm)

            for wd_idx, (wd_norm, wd_tokens) in enumerate(wd_normalized):
                if not wd_norm:
                    continue

                # (a) Exact match
                if pdmx_norm == wd_norm:
                    best_match = wd_works_deduped[wd_idx]
                    best_method = "title_exact"
                    break

                # (b) Substring (word-boundary-aware)
                if (len(pdmx_norm) >= MIN_SUBSTRING_LEN
                        and len(wd_norm) >= MIN_SUBSTRING_LEN
                        and wd_norm not in GENERIC_TERMS):
                    if (is_word_substring(pdmx_norm, wd_norm)
                            or is_word_substring(wd_norm, pdmx_norm)):
                        if best_method not in ("title_exact",):
                            best_match = wd_works_deduped[wd_idx]
                            best_method = "title_substring"

                # (c) Token overlap
                if pdmx_tokens and wd_tokens:
                    j = jaccard(pdmx_tokens, wd_tokens)
                    if j >= MIN_JACCARD and j > best_score:
                        if best_method not in ("title_exact",
                                               "title_substring"):
                            best_match = wd_works_deduped[wd_idx]
                            best_method = "title_tokens"
                            best_score = j

            if best_method == "title_exact":
                break  # No need to try other candidate names

        if best_match:
            matches[pdmx_idx] = (best_match, best_method)

    return matches


# ---------- Apple Music ----------

def make_apple_music_classical_search_url(composer_name, work):
    """Build a classical.music.apple.com search URL as fallback."""
    parts = []
    name_parts = composer_name.split()
    if name_parts:
        parts.append(name_parts[-1])

    cats = work.get("catalog_numbers", {})
    for ct, cn in cats.items():
        parts.append(f"{ct} {cn}")
        break

    if not cats:
        title = work.get("title", "")
        title = re.sub(r'_', ' ', title)
        for p in name_parts:
            title = re.sub(re.escape(p), '', title, flags=re.IGNORECASE)
        title = re.sub(r'\s+', ' ', title).strip()
        if len(title) > 50:
            title = title[:50]
        parts.append(title)

    query = " ".join(parts).strip()
    if query:
        return ("https://classical.music.apple.com/us/search?q="
                + urllib.parse.quote(query))
    return ""


# ---------- Per-composer processing ----------

def apply_match(work, matched_wd, match_method, birth_year, death_year):
    """
    Apply a Wikidata match to a PDMX work. Sets metadata fields.
    Returns True if year_composed was set.
    """
    got_year = False

    year = matched_wd.get("year")
    if year:
        if birth_year and year < birth_year + 5:
            year = None
        elif death_year and year > death_year + 2:
            year = None
    if year:
        work["year_composed"] = year
        got_year = True

    wd_key = matched_wd.get("key")
    if wd_key and "key" not in work:
        work["key"] = wd_key

    if matched_wd.get("wikidata_id"):
        work["wikidata_id"] = matched_wd["wikidata_id"]
    if matched_wd.get("label"):
        work["wikidata_title"] = matched_wd["label"]
    if matched_wd.get("musicbrainz_id"):
        work["musicbrainz_id"] = matched_wd["musicbrainz_id"]
    if matched_wd.get("imslp_id"):
        work["imslp_id"] = matched_wd["imslp_id"]
    if matched_wd.get("musescore_id"):
        work["wikidata_musescore_id"] = matched_wd["musescore_id"]

    apple_cid = matched_wd.get("apple_classical_id")
    if apple_cid:
        work["apple_music_classical_url"] = (
            f"https://classical.music.apple.com/us/work/{apple_cid}")

    work["wikidata_match_method"] = match_method
    return got_year


def process_composer(slug, composer_dir):
    """Process one composer via Wikidata."""
    index_path = composer_dir / "index.json"
    if not index_path.exists():
        return None

    data = json.loads(index_path.read_text().strip())
    composer_name = data.get("composer_name", "")
    wiki_url = data.get("wiki_page", "")
    birth_year = data.get("birth_year")
    death_year = data.get("death_year")

    if not wiki_url or "/wiki/" not in wiki_url:
        return None

    wiki_title = urllib.parse.unquote(wiki_url.split("/wiki/")[-1])
    empty_result = {
        "slug": slug, "composer": composer_name, "qid": None,
        "apple_artist_id": None,
        "n_wd_works": 0, "n_linked": 0, "n_year": 0,
        "n_by_msid": 0, "n_by_cat": 0, "n_by_cat_ext": 0,
        "n_by_cat_range": 0,
        "n_by_title_exact": 0, "n_by_title_sub": 0, "n_by_title_tok": 0,
        "n_apple_direct": 0, "n_apple_search": 0,
        "n_works": len(data.get("works", [])),
    }

    # Step 1: Wikidata QID
    qid = get_wikidata_id(wiki_title)
    if not qid:
        return empty_result

    data["wikidata_id"] = qid

    # Step 2: Apple Music artist ID
    apple_artist_id = get_composer_apple_music_id(qid)
    if apple_artist_id:
        data["apple_music_artist_id"] = apple_artist_id
        data["apple_music_classical_url"] = (
            f"https://classical.music.apple.com/us/artist/{apple_artist_id}")
        print(f"  [{slug}] QID={qid}, Apple Music artist={apple_artist_id}")
    else:
        print(f"  [{slug}] QID={qid} (no Apple Music artist ID)")

    # Step 3: Wikidata works
    print(f"  [{slug}] fetching works...")
    wd_works = get_works_for_composer(qid)

    works = data.get("works", [])

    if not wd_works:
        # Generate search URLs even without Wikidata works
        n_search = 0
        for work in works:
            url = make_apple_music_classical_search_url(composer_name, work)
            if url:
                work["apple_music_classical_search_url"] = url
                n_search += 1
        data["works"] = works
        index_path.write_text(json.dumps(data, ensure_ascii=False) + "\n")
        result = dict(empty_result)
        result["qid"] = qid
        result["apple_artist_id"] = apple_artist_id or None
        result["n_apple_search"] = n_search
        return result

    # Deduplicate Wikidata works by wikidata_id
    by_wdid = {}
    for w in wd_works:
        wdid = w.get("wikidata_id", "")
        if wdid:
            if wdid not in by_wdid:
                by_wdid[wdid] = dict(w)
            else:
                for field in ("catalog_raw", "catalog_type", "catalog_num",
                              "year", "key", "musescore_id", "musicbrainz_id",
                              "imslp_id", "apple_classical_id"):
                    if field in w and field not in by_wdid[wdid]:
                        by_wdid[wdid][field] = w[field]

    wd_deduped = list(by_wdid.values())

    # Build indexes
    # Use composer's catalog_type for bare numbers from Wikidata
    composer_cat_type = data.get("catalog_type", "")

    wd_by_cat = {}
    for w in wd_deduped:
        ct = w.get("catalog_type")
        cn = w.get("catalog_num")
        if ct and cn:
            key = cat_key(ct, cn)
            if key not in wd_by_cat:
                wd_by_cat[key] = w
        elif not ct and composer_cat_type:
            # Bare number from Wikidata — try with composer's catalog type
            raw = w.get("catalog_raw", "")
            if raw and re.match(r'^\d+[a-z]?$', raw.strip()):
                key = cat_key(composer_cat_type, raw.strip())
                if key not in wd_by_cat:
                    wd_by_cat[key] = w

    # Build range index: list of (cat_type, start, end, wd_work)
    wd_cat_ranges = []
    for w in wd_deduped:
        raw = w.get("catalog_raw", "")
        if raw and re.search(r'\d+\s*[-–—]\s*\d+', raw):
            parsed = parse_catalog_range(raw, composer_cat_type)
            if parsed:
                wd_cat_ranges.append((*parsed, w))

    wd_by_msid = {}
    for w in wd_deduped:
        msid = w.get("musescore_id")
        if msid:
            wd_by_msid[str(msid)] = w

    n_wd_year = sum(1 for w in wd_deduped if "year" in w)
    n_wd_msid = len(wd_by_msid)
    n_wd_mb = sum(1 for w in wd_deduped if "musicbrainz_id" in w)
    n_wd_imslp = sum(1 for w in wd_deduped if "imslp_id" in w)
    n_wd_apple = sum(1 for w in wd_deduped if "apple_classical_id" in w)
    print(f"    {len(wd_deduped)} unique works ({n_wd_year} w/year, "
          f"{n_wd_msid} w/MuseScore, {n_wd_mb} w/MusicBrainz, "
          f"{n_wd_imslp} w/IMSLP, {n_wd_apple} w/AppleClassical)")

    # Step 4: Match PDMX works against Wikidata
    counters = {
        "linked": 0, "year": 0,
        "msid": 0, "cat": 0, "cat_ext": 0, "cat_range": 0,
        "title_exact": 0, "title_sub": 0, "title_tok": 0,
    }
    unmatched = []

    for idx, work in enumerate(works):
        matched_wd = None
        match_method = None

        # Method 1: MuseScore ID
        ms_url = work.get("pdmx", {}).get("musescore_url", "")
        if ms_url:
            m = re.search(r'/scores/(\d+)', ms_url)
            if m:
                score_id = m.group(1)
                if score_id in wd_by_msid:
                    matched_wd = wd_by_msid[score_id]
                    match_method = "musescore_id"

        # Method 2: Catalog number (existing)
        if not matched_wd:
            work_cats = work.get("catalog_numbers", {})
            for ct, cn in work_cats.items():
                key = cat_key(ct, cn)
                if key in wd_by_cat:
                    matched_wd = wd_by_cat[key]
                    match_method = "catalog"
                    break

        # Method 3: Catalog number (extracted from title)
        if not matched_wd:
            extracted = extract_catalog_from_title(work.get("title", ""))
            if extracted:
                for ct, cn in extracted.items():
                    key = cat_key(ct, cn)
                    if key in wd_by_cat:
                        matched_wd = wd_by_cat[key]
                        match_method = "catalog_extracted"
                        break

        # Method 3b: Catalog number falls within a Wikidata range
        if not matched_wd and wd_cat_ranges:
            all_cats = work.get("catalog_numbers", {})
            if not all_cats:
                all_cats = extract_catalog_from_title(work.get("title", ""))
            for ct, cn in all_cats.items():
                try:
                    num = int(re.match(r'(\d+)', str(cn)).group(1))
                except (ValueError, AttributeError):
                    continue
                ct_upper = ct.upper()
                for r_type, r_start, r_end, r_work in wd_cat_ranges:
                    if r_type.upper() == ct_upper and r_start <= num <= r_end:
                        matched_wd = r_work
                        match_method = "catalog_range"
                        break
                if matched_wd:
                    break

        if matched_wd:
            got_year = apply_match(work, matched_wd, match_method,
                                   birth_year, death_year)
            counters["linked"] += 1
            if got_year:
                counters["year"] += 1
            method_key = {
                "musescore_id": "msid",
                "catalog": "cat",
                "catalog_extracted": "cat_ext",
                "catalog_range": "cat_range",
            }[match_method]
            counters[method_key] += 1
        else:
            unmatched.append(idx)

    # Method 4: Fuzzy title matching for remaining works
    if unmatched and wd_deduped:
        fuzzy = fuzzy_match_works(works, unmatched, wd_deduped, composer_name)
        for pdmx_idx, (matched_wd, match_method) in fuzzy.items():
            work = works[pdmx_idx]
            got_year = apply_match(work, matched_wd, match_method,
                                   birth_year, death_year)
            counters["linked"] += 1
            if got_year:
                counters["year"] += 1
            method_key = {
                "title_exact": "title_exact",
                "title_substring": "title_sub",
                "title_tokens": "title_tok",
            }[match_method]
            counters[method_key] += 1

    # Apple Music search URLs for unlinked works
    for work in works:
        if "apple_music_classical_url" not in work:
            url = make_apple_music_classical_search_url(composer_name, work)
            if url:
                work["apple_music_classical_search_url"] = url

    data["works"] = works
    index_path.write_text(json.dumps(data, ensure_ascii=False) + "\n")

    n_apple_direct = sum(
        1 for w in works if w.get("apple_music_classical_url"))
    n_apple_search = sum(
        1 for w in works if w.get("apple_music_classical_search_url"))

    total_linked = counters["linked"]
    total_year = counters["year"]
    if total_linked > 0:
        methods = []
        for label, key in [("msid", "msid"), ("cat", "cat"),
                           ("cat_ext", "cat_ext"),
                           ("cat_range", "cat_range"),
                           ("title_exact", "title_exact"),
                           ("title_sub", "title_sub"),
                           ("title_tok", "title_tok")]:
            if counters[key]:
                methods.append(f"{label}={counters[key]}")
        print(f"    Linked {total_linked}/{len(works)} works "
              f"({', '.join(methods)}), "
              f"{total_year} with year_composed")

    return {
        "slug": slug, "composer": composer_name, "qid": qid,
        "apple_artist_id": apple_artist_id or None,
        "n_wd_works": len(wd_deduped),
        "n_linked": total_linked, "n_year": total_year,
        "n_by_msid": counters["msid"],
        "n_by_cat": counters["cat"],
        "n_by_cat_ext": counters["cat_ext"],
        "n_by_cat_range": counters["cat_range"],
        "n_by_title_exact": counters["title_exact"],
        "n_by_title_sub": counters["title_sub"],
        "n_by_title_tok": counters["title_tok"],
        "n_apple_direct": n_apple_direct,
        "n_apple_search": n_apple_search,
        "n_works": len(works),
    }


# ---------- Main ----------

def main():
    if len(sys.argv) > 1:
        output_root = Path(sys.argv[1])
    else:
        output_root = OUTPUT_ROOT

    manifest = json.load(open(output_root / "manifest.json"))
    composers = manifest["composers"]

    # Clear existing Wikidata-sourced fields
    wd_fields = [
        "year_composed", "wikidata_id", "wikidata_title",
        "musicbrainz_id", "imslp_id", "wikidata_musescore_id",
        "apple_music_classical_url", "apple_music_classical_search_url",
        "wikidata_match_method",
    ]
    print(f"Clearing existing Wikidata fields ({', '.join(wd_fields)})...")
    for c in composers:
        idx_path = output_root / c["slug"] / "index.json"
        if not idx_path.exists():
            continue
        d = json.loads(idx_path.read_text().strip())
        changed = False
        for w in d.get("works", []):
            for f in wd_fields:
                if f in w:
                    del w[f]
                    changed = True
        for cf in ["wikidata_id", "apple_music_artist_id",
                    "apple_music_classical_url"]:
            if cf in d:
                del d[cf]
                changed = True
        if changed:
            idx_path.write_text(json.dumps(d, ensure_ascii=False) + "\n")

    print(f"\nProcessing {len(composers)} composers via Wikidata SPARQL...")
    print("(3 API calls per composer, cached for 7 days)")
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

        if (i + 1) % 20 == 0:
            linked = sum(r["n_linked"] for r in results)
            year = sum(r["n_year"] for r in results)
            qids = sum(1 for r in results if r.get("qid"))
            print(f"\n  === Progress: {i+1}/{len(composers)}, "
                  f"{qids} QIDs, {linked} linked, {year} with year ===\n")

    # Summary
    print("\n" + "=" * 60)
    print("Wikidata SPARQL Enrichment Summary")
    print("=" * 60)
    total_linked = sum(r["n_linked"] for r in results)
    total_year = sum(r["n_year"] for r in results)
    total_works = sum(r["n_works"] for r in results)
    n_with_qid = sum(1 for r in results if r.get("qid"))
    n_with_wd = sum(1 for r in results if r.get("n_wd_works", 0) > 0)
    n_any_link = sum(1 for r in results if r["n_linked"] > 0)
    total_wd = sum(r.get("n_wd_works", 0) for r in results)

    by_msid = sum(r.get("n_by_msid", 0) for r in results)
    by_cat = sum(r.get("n_by_cat", 0) for r in results)
    by_cat_ext = sum(r.get("n_by_cat_ext", 0) for r in results)
    by_cat_range = sum(r.get("n_by_cat_range", 0) for r in results)
    by_te = sum(r.get("n_by_title_exact", 0) for r in results)
    by_ts = sum(r.get("n_by_title_sub", 0) for r in results)
    by_tt = sum(r.get("n_by_title_tok", 0) for r in results)

    print(f"Composers processed:        {len(results)}")
    print(f"With Wikidata QID:          {n_with_qid}")
    print(f"With works in Wikidata:     {n_with_wd}")
    print(f"Total Wikidata works found: {total_wd}")
    print(f"Composers with PDMX match:  {n_any_link}")
    print()
    print(f"Works linked to Wikidata:   {total_linked}/{total_works}")
    print(f"Works with year_composed:   {total_year}/{total_works}")
    print(f"  - by MuseScore ID:        {by_msid}")
    print(f"  - by catalog (existing):  {by_cat}")
    print(f"  - by catalog (extracted): {by_cat_ext}")
    print(f"  - by catalog (range):     {by_cat_range}")
    print(f"  - by title (exact):       {by_te}")
    print(f"  - by title (substring):   {by_ts}")
    print(f"  - by title (tokens):      {by_tt}")

    n_apple_artist = sum(1 for r in results if r.get("apple_artist_id"))
    n_apple_direct = sum(r.get("n_apple_direct", 0) for r in results)
    n_apple_search = sum(r.get("n_apple_search", 0) for r in results)
    print(f"\nApple Music Classical:")
    print(f"  Composers with artist ID: {n_apple_artist}")
    print(f"  Works with direct URL:    {n_apple_direct} (from Wikidata P12769)")
    print(f"  Works with search URL:    {n_apple_search} (fallback)")

    top = sorted(results, key=lambda r: r["n_linked"], reverse=True)[:20]
    print("\nTop composers by Wikidata links:")
    for r in top:
        if r["n_linked"] > 0:
            methods = []
            for label, key in [("msid", "n_by_msid"), ("cat", "n_by_cat"),
                               ("cat_ext", "n_by_cat_ext"),
                               ("cat_range", "n_by_cat_range"),
                               ("t_exact", "n_by_title_exact"),
                               ("t_sub", "n_by_title_sub"),
                               ("t_tok", "n_by_title_tok")]:
                if r.get(key, 0):
                    methods.append(f"{label}={r[key]}")
            print(f"  {r['composer']:40s}  {r['n_linked']:3d}/{r['n_works']:3d} "
                  f"linked ({r['n_year']} w/year, "
                  f"{r['n_wd_works']} in WD, {', '.join(methods)})")


if __name__ == "__main__":
    main()
