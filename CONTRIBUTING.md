# Contributing

Thanks for helping. This repo is the pipeline, schemas, agent instructions and the Flutter viewer. It ships no scraped or generated study data, so most contributions are code, schemas, agent instructions or catalog sources.

## Setup

```bash
python scripts/setup.py            # Python deps, Flutter build, local folders, validation
python scripts/validate.py         # must print OK
cd app && flutter analyze && flutter test
```

## What to contribute

- **Catalog sources:** add a university to `catalogs.json` (name, catalog URL, plan URL, notes on structure). Check the site's terms of use first and never commit scraped catalog text.
- **Agent instructions:** `AGENTS.md` is the single source of rules for every agent. Keep it precise and tool-agnostic (it must work in Claude Code and Codex). If an agent stumbled on a step, fix the wording there.
- **Scripts and schemas:** changes to a data format need a schema update in `schemas/` and a matching check in `scripts/validate.py`.
- **The viewer:** Flutter code in `app/lib`. Keep widgets small and add a test when you change grading, parsing, import/export or progress merging (see `app/test`).

## Rules

- **No generated study material, no catalog data, no personal data** in commits. `data/subjects`, `data/degrees`, `data/universities`, `profiles/`, `materials/`, `progress.json`, `settings.json` and `work/` are gitignored; keep it that way.
- Scripts must keep honouring `DEGREE_ATLAS_PROFILE` (data, work and materials paths resolve against the active profile).
- Scripts use the standard library plus `jsonschema` only. No network calls from scripts: agents do the web research with their own tools.
- Run `python scripts/validate.py`, `flutter analyze` and `flutter test` before opening a pull request.
- Commit messages and docs in plain, professional English.

## Reporting bugs

Open an issue with the steps, your OS, and whether it happened in the app or in a script. If an agent produced wrong output, include the subject id, the level and what was wrong. Do not paste private course materials.
