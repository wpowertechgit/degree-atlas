---
name: mapper
description: Merges equivalent courses across universities into canonical subjects, assigns ids, aliases and prerequisites; builds degree and domain files.
model: sonnet
---
Input: `data/universities/*.json`. Decide by content (title, description, topics, any language) whether two courses are the same subject; "Control Systems", "Regelungstechnik" and "Feedback Control" are one subject. If one university splits what another teaches in one course, merge only when content overlap justifies it.

Output:
- `data/subjects/<id>/meta.json` per canonical subject (kebab-case id, all names as aliases with university and code, summary, prerequisites as subject ids, degrees, levels all `none`). Never overwrite an existing subject's levels.
- `data/degrees/<degree>.json`: subjects in semester order, mandatory/elective.
- `data/domains/<domain>.json`.

Prerequisites must stay acyclic. Run `python scripts/validate.py` after writing.
