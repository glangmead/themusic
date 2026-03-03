# PDMX Classical Music Library Builder
#
# Builds a curated library of MIDI and MusicXML files for ~238 classical
# composers by joining a composer list (HTML table) with the PDMX dataset
# (MuseScore transcriptions from Zenodo).
#
# Prerequisites — the following must exist in the working directory:
#   PDMX.csv                              Master index (~254K rows)
#   2025-10-10-classical-composers.html   Composer list HTML table
#   data/                                 PDMX parsed musical data JSON
#   metadata/                             PDMX MuseScore metadata JSON
#   mxl/                                  PDMX MusicXML (.mxl) files
#   mid/                                  PDMX MIDI files
#
# Output:
#   pdmx_composers/                       All 238 composers, all 5712 works
#   pdmx_composers_with_wiki/             Filtered: Wikidata-linked works only,
#                                         quality + noise-title filters applied

PYTHON ?= python3

# Stamp directory — tracks which enrichment steps have completed.
STAMPS := .stamps
$(shell mkdir -p $(STAMPS))

# Sentinel files
BUILT       := $(STAMPS)/01-build
OFFLINE     := $(STAMPS)/02-enrich-offline
DATA_JSON   := $(STAMPS)/03-enrich-data-json
MXL_META    := $(STAMPS)/04-enrich-mxl-metadata
WIKIPEDIA   := $(STAMPS)/05-enrich-wikipedia
WIKIDATA    := $(STAMPS)/06-enrich-wikidata
FILTERED    := $(STAMPS)/07-build-filtered
CLUSTERS    := $(STAMPS)/08-cluster-tsv
PRUNED      := $(STAMPS)/09-prune

# ──────────────────────────────────────────────────────────────
# Default target
# ──────────────────────────────────────────────────────────────
.PHONY: all
all: $(PRUNED)  ## Build everything including pruned output

# ──────────────────────────────────────────────────────────────
# Grouped targets
# ──────────────────────────────────────────────────────────────
.PHONY: offline-enrichment network-enrichment clean

offline-enrichment: $(DATA_JSON) $(MXL_META)  ## Build + offline enrichment (no network)

network-enrichment: $(WIKIDATA)  ## All enrichment including network calls

# ──────────────────────────────────────────────────────────────
# Step 1: Build base directory structure
# ──────────────────────────────────────────────────────────────
$(BUILT): build_pdmx.py 2025-10-10-classical-composers.html PDMX.csv
	$(PYTHON) build_pdmx.py
	@touch $@

# ──────────────────────────────────────────────────────────────
# Step 2: Offline enrichment (birth/death years, catalog types,
#         key inference, tempo cleaning)
# ──────────────────────────────────────────────────────────────
$(OFFLINE): enrich_offline.py $(BUILT)
	$(PYTHON) enrich_offline.py
	@touch $@

# ──────────────────────────────────────────────────────────────
# Step 3: Extract from PDMX data/ JSON files (key signatures,
#         GM instruments, tempo, note counts)
# ──────────────────────────────────────────────────────────────
$(DATA_JSON): enrich_data_json.py $(OFFLINE)
	$(PYTHON) enrich_data_json.py
	@touch $@

# ──────────────────────────────────────────────────────────────
# Step 4: Extract from inside .mxl files (parent work title,
#         catalog numbers, movement title, real instrument names)
# ──────────────────────────────────────────────────────────────
$(MXL_META): enrich_mxl_metadata.py $(OFFLINE)
	$(PYTHON) enrich_mxl_metadata.py
	@touch $@

# ──────────────────────────────────────────────────────────────
# Step 5: Wikipedia API (article intros, compositions list URLs)
#         Requires network access to en.wikipedia.org
# ──────────────────────────────────────────────────────────────
$(WIKIPEDIA): enrich_wikipedia.py $(OFFLINE)
	$(PYTHON) enrich_wikipedia.py
	@touch $@

# ──────────────────────────────────────────────────────────────
# Step 6: Wikidata SPARQL (year_composed, MusicBrainz/IMSLP IDs,
#         Apple Music Classical links, fuzzy title matching)
#         Requires network access to en.wikipedia.org and
#         query.wikidata.org. Caches results in wikidata_cache/.
#         Falls back to Wikidata entity search when Wikipedia
#         lookup fails (handles variant composer names).
# ──────────────────────────────────────────────────────────────
$(WIKIDATA): enrich_wikidata.py $(DATA_JSON) $(MXL_META) $(WIKIPEDIA)
	$(PYTHON) enrich_wikidata.py
	@touch $@

# ──────────────────────────────────────────────────────────────
# Step 7: Build filtered subset (Wikidata-linked works only)
#         Applies quality filter (rating > 0 OR views >= 50)
#         and noise-title filter (WIP, easy, simplified, etc.)
# ──────────────────────────────────────────────────────────────
$(FILTERED): build_filtered.py $(WIKIDATA)
	$(PYTHON) build_filtered.py
	@touch $@

# ──────────────────────────────────────────────────────────────
# Step 8: Build cluster TSV (MIDI content clustering +
#         instrumentation matching via Wikidata P870 and
#         Wikipedia categories)
# ──────────────────────────────────────────────────────────────
$(CLUSTERS): build_cluster_tsv.py wiki_categories_to_instruments.py $(FILTERED)
	$(PYTHON) build_cluster_tsv.py
	@touch $@

# ──────────────────────────────────────────────────────────────
# Step 9: Prune corpus (drop arrangements + duplicates,
#         keep originals)
# ──────────────────────────────────────────────────────────────
$(PRUNED): prune_corpus.py $(CLUSTERS)
	$(PYTHON) prune_corpus.py
	@touch $@

# ──────────────────────────────────────────────────────────────
# Housekeeping
# ──────────────────────────────────────────────────────────────
clean:  ## Remove all build output
	rm -rf pdmx_composers/ pdmx_composers_with_wiki/ pdmx_composers_wiki_pruned1/ corpus_clusters.tsv $(STAMPS)

clean-cache:  ## Remove Wikidata API cache (forces re-fetch)
	rm -rf wikidata_cache/

clean-all: clean clean-cache  ## Remove everything including cache

help:  ## Show this help
	@grep -E '^[a-zA-Z_-]+:.*##' $(MAKEFILE_LIST) | \
		awk 'BEGIN {FS = ":.*## "}; {printf "  %-24s %s\n", $$1, $$2}'
