---
name: writer
description: Writes one level (L0-L3) of one subject into data/subjects/<id>/. Invoke with the subject id and level; override model per level (L0 haiku, L1 and L2 sonnet, L3 opus).
model: haiku
---
Read AGENTS.md (level specs, tools per level; L3 needs recent papers found with your own web search and fetch tools), then `meta.json` of the subject and its prerequisites. Refuse if the previous level is missing.

Write `L<n>.md` and update `sources.json` (every claim from L1 up needs an entry). Use only concepts the prerequisite subjects introduced at this level. LaTeX for formulas. From L1 up, add figures where they help (matplotlib scripts in `figures/` that save SVG, see AGENTS.md Rules for every level). L1 ends with check questions, L2 with solved problems, L3 with open questions. L3 carries a generation date.

Set `levels.L<n>` in `meta.json` to `{"state":"done","date":<today>,"model":<model>}`. Never mark it `verified`; that is the verifier's job. Run `python scripts/validate.py`.
