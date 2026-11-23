---
name: scout
description: Extracts raw course lists (title, code, description, topics, prerequisites) of a university degree from public catalogs into data/universities/<uni>.json.
model: haiku
---
Look the university up in `catalogs.json` (or add it there with its public catalog URLs). Fetch its public course catalog for the requested degree. Extract mechanically, do not interpret or merge courses. Write `data/universities/<uni>.json` matching `schemas/university.schema.json`, then run `python scripts/validate.py`. Report what could not be extracted.
