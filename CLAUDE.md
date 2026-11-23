# Degree Atlas

Generates university-subject study material at four depth levels (L0-L3) from real course lists. Subjects are shared across degrees (DAG). Output goes to `data/`; a Flutter app (later phase) only reads it.

## Levels
A level is generated only if the previous one exists for that subject.

| Level | Goal | Length | Sources | Practice |
| --- | --- | --- | --- | --- |
| L0 ELI5 | concept, main methods, lessons | ~1 page | course description, notes | none |
| L1 Basics | main ideas, key terms | 3-4 pages | lecture notes, OCW | check questions |
| L2 Master crash course | methods, derivations, typical problems | one lecture-note | notes, textbooks | solved problems |
| L3 Research frontier | state of the field, open directions | variable | recent reviews, arXiv, conferences | open questions |

Rules:
- From L1 up every claim has a source listed in `sources.json`. In L3 mark preprints as not peer reviewed.
- Formulas are LaTeX.
- Concept closure: a level may only use concepts introduced by the prerequisite subjects at that level. The verifier checks this.
- L0-L2 are stable. L3 is dated and regenerable.

## Pipeline
scout -> mapper -> writer -> verifier (on failure the writer rewrites). Only accepted material is written to `data/`. Agents live in `.claude/agents/`.

Models: scout Haiku; mapper Sonnet; writer Haiku for L0/L1, Sonnet for L2, Opus for L3 (override the model when invoking); verifier Opus.

## Expansion order
Curriculum decides, not interest. User gives degree + target level; fill gaps:
1. L0 of every mandatory subject. 2. Then L1 in semester order, after prerequisites. 3. Same for L2, L3. 4. Electives only on request. 5. Never regenerate a finished subject.

## Data
```
data/universities/<uni>.json   raw course lists (scout)
data/domains/<domain>.json     groups of degrees
data/degrees/<degree>.json     level + subjects in semester order
data/subjects/<id>/            meta.json, L0.md..L3.md, figures/, sources.json
```
Schemas are in `schemas/`. After every write run `python scripts/validate.py`.

## Writing L1-L3
The agent loop (`scripts/next.py`, level specs, tools per level, verification pass) is in `AGENTS.md`. L3 uses emaf (`research`, `prior_art`, `scrape`).
