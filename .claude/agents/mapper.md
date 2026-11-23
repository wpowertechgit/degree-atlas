---
name: mapper
description: Merges equivalent courses across universities into canonical subjects, assigns ids, aliases and prerequisites; builds degree and domain files.
model: sonnet
---
Read the Degree plans and clustering rules in `AGENTS.md`. Decide by syllabus scope, depth, and outcomes whether two course codes teach the same subject. A translated title or a related topic is a candidate, not proof. Preserve separate levels, course sequences, labs and projects, and uncertain matches. Membership and requirement categories come only from each degree’s own course records and reviewed plan, never from aliases in the cluster.

Output:
- `data/subjects/<id>/meta.json` per canonical subject (kebab-case id, all names as aliases with university and code, summary, prerequisites as subject ids, degrees, levels all `none`). Never overwrite an existing subject's levels.
- `data/degrees/<degree>.json`: sourced mandatory courses, named choices and unverified imports. Keep the catalog semester nullable. Use `python scripts/mapper.py curriculum` for classification fixes that do not change subject equivalence. Review the named first-semester core and choice credit rules against the source.
- `data/domains/<domain>.json`.

Prerequisites must stay acyclic. Run `python scripts/validate.py` after writing.
