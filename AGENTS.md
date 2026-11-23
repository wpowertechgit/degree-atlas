# Degree Atlas: agent workflow

## Bootstrap (empty checkout)

The repo ships no scraped or generated data (licensing; generated text is unreviewed). Build it locally:

1. Pick universities from `catalogs.json` (MIT, ETH Zurich and NUS are examples; add your own). Check each site's terms first.
2. Per university and degree, run the scout (`.claude/agents/scout.md`): fetch the catalog pages and write `data/universities/<id>.json` per `schemas/university.schema.json`. Extract mechanically; keep the course URL.
3. `python scripts/mapper.py cluster`, `judge`, `assemble`: merges equivalent courses into subjects, builds `data/subjects/`, `data/degrees/`, links prerequisites. `data/domains/` and `data/curated_prerequisites.json` are committed and reused.
4. `python scripts/validate.py` must print `OK`.
5. Generate levels with the loop below, starting at L0.

Everything under `data/subjects/`, `data/degrees/` and `data/universities/` is gitignored; do not commit it.


Works the same in Codex and Claude Code. Read `CLAUDE.md` first for the level definitions and rules. This file is the setup and the loop for writing levels. 

## The loop

Levels start at L0 (`next.py L0`; one page from the subject summary and the course descriptions in `data/universities/`, no sources needed). Given a target (for example "L1 for `mit-bsc-computer-science`" or just "L2"):

1. `python scripts/next.py <level> [--degree <id>] -n 10` prints subjects in dependency order. Take only `READY` ones.
2. For each subject, read `data/subjects/<id>/meta.json`, its `L<n-1>.md`, and the `L<n>.md` of each prerequisite (concept closure: use only what they introduced).
3. Gather sources with the web tools you have (see the table), reading pages before citing them.
4. Write `data/subjects/<id>/L<n>.md` and merge the sources into `sources.json`.
5. Self-check against the level spec (table below). Fix, then set `levels.L<n>` in `meta.json` to `{"state":"done","date":"<today>","model":"<your model id>"}`.
6. `python scripts/validate.py` must print `OK`.
7. Verification is a separate pass, ideally by a different model or a fresh context: `python scripts/next.py <level> --verify`, check each file against its sources, fix small errors in place, then set the state to `verified`. On substantive problems leave it `done` and rewrite.
8. Repeat from step 1 until `next.py` reports nothing left. Never rewrite a subject whose level is already `done` or `verified`.

Work in batches of about 5-10 subjects, validating after each batch. Independent subjects may be written in parallel by subagents; keep `meta.json` writes per subject to avoid collisions.

## Level specs

| Level | Length | Sources and tools | Ends with |
| --- | --- | --- | --- |
| L0 ELI5 | ~1 page | Subject summary and course descriptions only, no web needed | nothing (no practice) |
| L1 Basics | 3-4 pages (900-1400 words) | Open lecture notes, MIT OCW, open textbooks, Wikipedia only as last resort. Search, then scrape/read the pages (emaf `scrape` works). | `## Check questions`, 4-6, no answers |
| L2 Master crash course | one lecture-note, 2000-3500 words | Textbooks and full lecture notes. Derive the key results, not just state them. Search, then scrape/read. | `## Solved problems`, 3-5, full solutions |
| L3 Research frontier | variable, 1500-3000 words | **Use emaf**: `research` for recent papers and reviews, `prior_art` for existing tools and systems, `scrape` to read the sources. Prefer reviews and the last 3-5 years. | `## Open questions`, and a line `Generated: <date>` under the title |

Rules for every level:
- Every factual claim cites a source read in this session, inline as `[1]`; the numbering matches the entries for that level in `sources.json` (`{"level","title","url"}`). No invented sources or URLs. If no real source is found, do not write the level for that subject.
- L3: arXiv/bioRxiv/medRxiv and other unreviewed items get `"preprint": true` in `sources.json` and "(preprint, not peer reviewed)" at the first mention in the text.
- Formulas are LaTeX (`$...$`, `$$...$$`). Figures are optional SVG files in `figures/`.
- Heading is `# <title> (L<n>)`.
- Concept closure: no concept beyond the prerequisites' levels. Define anything new.
- Do not modify other levels, `aliases`, `summary`, `degrees` or `prerequisites` (prerequisite links are curated separately in `data/curated_prerequisites.json`).

## Models (Claude Code)

L1 Haiku, L2 Sonnet, L3 Opus, verifier Opus (agent definitions in `.claude/agents/`). In Codex use your strongest available model for L3 and verification.
