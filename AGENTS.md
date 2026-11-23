# Degree Atlas: agent workflow

Generates university-subject study material at four depth levels (L0-L3) from real course lists. Subjects are shared across degrees (a DAG). Output goes to `data/`; the Flutter app in `app/` only reads it. This file is the single source of rules for every agent (Claude Code, Codex); `CLAUDE.md` just points here.

## Levels

| Level | Goal |
| --- | --- |
| L0 ELI5 | concept, main methods, lessons (about one page) |
| L1 Basics | main ideas and key terms |
| L2 Master crash course | methods, derivations, typical problems |
| L3 Research frontier | state of the field, open directions (dated, regenerable) |

A level is written only if the previous one exists for that subject. Length, sources and ending of each level are in **Level specs** below.

## Pipeline and data

scout -> mapper -> writer, with an optional verifier pass. Agent definitions live in `.claude/agents/`; use the strongest model you have for L3 and for verification.

```
data/universities/<uni>.json   raw course lists (scout)
data/domains/<domain>.json     groups of degrees
data/degrees/<degree>.json     sourced requirements, choice groups and nullable semesters
data/subjects/<id>/            meta.json, L0.md..L3.md, exercises.json, figures/, sources.json
materials/<course>/            the user's own course files plus index.json (profile root, private)
```

Schemas are in `schemas/`. After every write run `python scripts/validate.py`.

Expansion order: the curriculum decides, not interest. The user gives a degree and a target level; fill gaps: L0 of every mandatory subject, then L1 in semester order after prerequisites, then L2, L3. Electives only on request.

## Setup after clone

If the user asks you to set up this repository (for example "clone this and set it up"): clone it, `cd` into it and run `python scripts/setup.py` (add `--install-flutter` when no Flutter SDK is installed, `--no-app` when only the agent workflow is needed). It installs the Python requirements, builds the Flutter app, creates `work/` and `profiles/` and validates. Fix every item under "Needs attention", rerun until it prints "Setup complete", then tell the user how to start the app (`launch.bat` on Windows). Then continue with Bootstrap below only if they want the full university data set; for a personal topic, a profile and a learning request are enough.

## Bootstrap (empty checkout)

The repo ships no scraped or generated data (licensing). Build it locally:

1. Pick universities from `catalogs.json` (MIT, ETH Zurich and NUS are examples; add your own). Check each site's terms first.
2. Per university and degree, run the scout (`.claude/agents/scout.md`). Read the official study plan or degree chart and the course catalog. Write `data/universities/<id>.json` per `schemas/university.schema.json`. Record the plan URL, requirement evidence, and course URL.
3. `python scripts/mapper.py cluster`, `judge`, `assemble`: merges equivalent courses into subjects, builds `data/subjects/`, `data/degrees/`, links prerequisites. `data/domains/`, `data/curricula.json` and `data/curated_prerequisites.json` are committed and reused. For a requirements-only correction, run `python scripts/mapper.py curriculum` to rebuild degree memberships without rebuilding subject clusters or notes.
4. `python scripts/validate.py` must print `OK`.
5. Generate levels with the loop below, starting at L0.

Everything under `data/subjects/`, `data/degrees/` and `data/universities/` is gitignored; do not commit it.

## Profiles

A profile is a separate data set in `profiles/<name>/` with its own `data/`, `work/`, `progress.json` and `settings.json`. The app creates one with the domain files only. When the environment variable `DEGREE_ATLAS_PROFILE` is set, every `data/`, `work/` and `progress.json` path in this file, and every script in `scripts/`, refers to that folder instead of the repository root. Shared reference files (`schemas/`, `data/curricula.json`, `data/curated_prerequisites.json`, `catalogs.json`) always come from the repository. Never write outside the active profile.

## Learning request

When the user says what they want to learn (for example "I want to learn material science") in an empty or partial profile:

1. Pick the matching domain in `data/domains/` and 1-3 degree programs from the universities in `catalogs.json` whose study plans cover the topic (use web search to find them; prefer a bachelor and, if the topic is advanced, a master).
2. Get the course lists for those degrees only. If the repository's own `data/universities/<uni>.json` exists (local, gitignored), copy that file into the profile's `data/universities/` keeping its structure and `university` name but only the needed degrees (on Windows set `PYTHONUTF8=1` when reading these files from Python); otherwise run the scout (`.claude/agents/scout.md`). Then run `mapper.py cluster`, `judge` and `assemble` and `validate.py` as in Bootstrap. Never hand-write degree, subject or domain files for catalog degrees; the mapper builds them. `validate.py` must print `OK`; if it reports a prerequisite that does not exist in this profile, remove that id from the subject's `prerequisites` and validate again. The app picks up new files on its own.
3. Write L0 for every mandatory subject of the new degrees (`next.py L0 --degree <id> -n 10`, in batches), then tell the user what exists and offer L1.
4. Do not narrate or report progress. When everything is written, answer with one short line saying what now exists.

## Own course materials

The user can import their own course files (lecture notes, slides, problem sets, past exams) into the active profile. The app copies the folder to `materials/<course>/` and asks you to ingest it. If the user instead gives you a folder or file path in chat, copy it there yourself first (never work on the original). These files are private and local: never upload or publish them, and never modify them. Write the subject so the user is introduced from the ground up and then prepared well for their own course.

1. **Read everything.** Run `python scripts/extract.py materials/<course>` (the path is relative to the profile): it writes text of docx, pptx, xlsx, odt, md, txt, tex and html files (and PDFs when `pdftotext` exists) to `work/materials/<course>/`. Files it lists as "read directly" (PDFs, scans, images, handwriting) you read yourself with your file reader, up to about 20 pages at a time. Skim nothing: the topic list is only as good as your reading.
2. **Index.** Write `materials/<course>/index.json` (`schemas/materials-index.schema.json`): every file with its `kind` (slides, notes, textbook, problem-set, exam, other), and the course topics in the order the materials teach them, each with the files that cover it. Set `subject` to the subject id once it exists. `covered` stays empty until levels are written.
3. **Subject, degree and domain.** One subject per course (several if the folder clearly holds separate courses), id `own-<slug>`. Check the profile's own `data/subjects/` for an existing equivalent subject and reuse it if the scope matches (never reuse subjects of the repository's default data). Otherwise create `data/subjects/<id>/meta.json` with a one-sentence `summary` of the course, alias university `own`, empty `prerequisites` unless the user names some, and all four `levels` keys (`L0`-`L3`, `"state":"none"` until written, then date and model as usual) and a personal degree `data/degrees/own-<programme>.json`. The degree is the programme or specialization the course belongs to (for example "Computational Materials Science"), so name it that way, and reuse an existing `own-` degree when the course fits the same programme. Set `level` to BSc or MSc as the course suggests, the subject as `mandatory`, `source` to `materials/<course>`. Add the degree id to the best-fitting file in `data/domains/` so the atlas shows it (`validate.py` requires every `own-` degree to be listed in a domain). Run `validate.py`.
4. **L0 and L1: an elementary introduction.** Assume the reader knows only the prerequisites. Explain from the ground up with intuition and small examples, in the order of the user's course so the pieces later connect. The materials decide scope, order and notation; do not copy their terseness, and fill gaps with web search.
5. **L2: mastery of the user's course.** Follow the materials: their structure, notation, theorems, derivations and typical problem types, so the user can work through their own notes afterwards. Cite them in `sources.json` as `{"level":"L2","title":"...","file":"materials/<course>/<file>","pages":"12-18"}` (`file` replaces `url`; `pages` is free text, so a page range or a section name both work) and use the same inline `[n]` numbering as for web sources. Check the materials' own problems and statements before relying on them: if a question or solution is wrong or misleading, say so in the worked solution instead of copying the error. Use the web only to repair gaps or errors in the materials, and say so in the text.
6. **Exercises.** Build them from the problem sets and past exams: the same style, difficulty and mix of types, with fully worked solutions. Change the numbers and wording so the user practises the method and not the memorised answer. Put the topic names in `concepts`.
7. **Coverage.** In `index.json` fill each topic's `covered` with the levels that teach it. Every topic must be covered once L2 exists; `validate.py` checks this. End `L2.md` with one line naming topics that the materials mention but do not explain.

## Degree plans and clustering

- Verify membership for the exact institution, credential, major or track, and cohort. Build from the published requirements first. Use catalog descriptions afterward to identify and describe the courses. Retrieve both teaching terms if the catalog is split by term.
- A mandatory subject is a named course that every student on the stated plan takes. A required number of credits, a pick-one option, a specialization, free electives, and university-wide categories belong in named choice groups. An eligible course is an option even if the catalog marks it compulsory within one optional track.
- Put the official requirement URL in `course.requirement.source` and use `course.requirement.kind` and `group` where applicable. Set `semester` only when the official study plan places the named course in that semester. Fall or spring availability, course numbers and prerequisite depth do not determine a semester. Leave it null when the plan is flexible.
- Preserve named choice rules such as “pick one” or “pick two tracks” and any unit limits. Do not turn an entire department catalog or a broad eligibility rule into a degree list. Keep unmatched legacy entries unverified until a source resolves them.
- Cluster equivalent course content only when scope, depth and outcomes match. Titles, similar topics and cross-listings alone do not justify a merge. Keep generic theses, seminars, introductory sequences and advanced variants separate unless there is evidence of equivalent content. Clusters never carry membership, requirement status or semester from one degree to another.
- Review the output by listing the first term, counting the named mandatory subjects, and checking the biggest choice group against the source. If a term or named core is missing, flag the gap and leave it unverified until there is evidence.

Everything here works the same in Codex and Claude Code.

## The loop

Levels start at L0 (`next.py L0`; one page from the subject summary and the course descriptions in `data/universities/`, no sources needed). Given a target (for example "L1 for `mit-bsc-computer-science`" or just "L2"):

1. `python scripts/next.py <level> [--degree <id>] -n 10` prints subjects in dependency order. Degree mode starts with sourced named requirements and may include their actual prerequisites. Pass `--include-electives` only when the user asks for choices. Take only `READY` ones.
2. For each subject, read `data/subjects/<id>/meta.json`, its `L<n-1>.md`, and the `L<n>.md` of each prerequisite (concept closure: use only what they introduced).
3. Gather sources with the web tools you have (see the table), reading pages before citing them.
4. Write `data/subjects/<id>/L<n>.md` and merge the sources into `sources.json`.
5. Self-check against the level spec (table below). Fix, then set `levels.L<n>` in `meta.json` to `{"state":"done","date":"<today>","model":"<your model id>"}`.
6. `python scripts/validate.py` must print `OK`.
7. Optional verification pass, ideally by a different model or a fresh context: `python scripts/next.py <level> --verify`, check each file against its sources, fix small errors in place, then set the state to `verified`.
8. Repeat from step 1 until `next.py` reports nothing left. A level that already exists is rewritten only when the user asks to regenerate or fix it (see below).

Work in batches of about 5-10 subjects, validating after each batch. Independent subjects may be written in parallel by subagents; keep `meta.json` writes per subject to avoid collisions.

## Languages

English `L<n>.md` is canonical: sources, `meta.json` state and concept closure refer to it. A translation is a separate file `L<n>.<lang>.md` (ISO 639-1 code, e.g. `L1.hu.md`) written from the existing English text. Keep headings, structure, LaTeX, citation numbers `[1]` and the check/solved/open sections identical; translate the prose and technical terms naturally. Do not touch `sources.json` or `meta.json` for a translation. When the user asks for content in a language, write the English level first if it is missing, then the translation.

## Regenerate and fix

The app can ask for a level to be regenerated or fixed. Do it only on such an explicit request.
- Regenerate: write the level again as a new one (same rules and tools), replace that level's entries in `sources.json`, validate, then re-translate every existing `L<n>.<lang>.md` from the new English text.
- Fix: the user describes a problem. Edit the existing file minimally, scan the rest of the file for the same kind of problem, apply the same fix to the other language versions, validate.

## Exercises

Practice problems are structured data the app runs and grades. They are the practice material; the levels themselves are reading text.

- List the work with `python scripts/next.py --exercises [--degree <id>] -n 10` (prints `subject<TAB>levels that still have no exercises`).
- File: `data/subjects/<id>/exercises.json`, a JSON array validated by `schemas/exercises.schema.json`. Aim for 8-12 exercises per written level L1-L3 (fewer is fine for a short course). When the user asks for more, append new ones with new ids and keep the existing ones.
- Fields: `id` (kebab-case, unique per subject), `level` (1-3), `type`, `prompt` (markdown with LaTeX), `solution` (worked explanation, always present), optional `hints` (progressive, 1-3), `difficulty` (1 easy, 2 medium, 3 hard), `concepts`.
- Types and their `answer`:
  - `mcq`: `choices` (3-5) and `answer` as a list of correct indexes, normally one. Several indexes mean "select all that apply" and the prompt must say so.
  - `numeric`: `answer` a number, `tolerance` a relative fraction (0.01 = 1 percent; absolute when the answer is 0), `unit` for display. Ask for a stated unit and precision in the prompt.
  - `short`: `answer` a list of accepted strings (lower-case compared, case and trailing dot ignored); an entry starting with `re:` is a regular expression. Use only when the answer is a single term or short phrase.
  - `open`: derivations and proofs. No `answer`; the `solution` is the reference.
- Mix: L1 mostly `mcq` and `short`, some `numeric`; L2 `numeric` and `open` with real calculations; L3 `open` and `mcq` about methods and the state of the field. Difficulty should rise within a level.
- Every exercise must be answerable from that level's text and the prerequisites' same level (concept closure) and must be self-contained: no figures, no "see above".
- Correctness first. Work out each solution before writing the answer, compute every `numeric` answer by running code (Python) instead of by hand, and make wrong `mcq` choices plausible but clearly wrong. A wrong key is worse than a missing exercise.
- Languages: `exercises.<lang>.json` holds the same exercises translated (prompt, choices, hints, solution, short answers). Keep `id`, `level`, `type`, and for `mcq` and `numeric` the `answer`, `tolerance` and `unit` identical; `validate.py` checks this.
- Run `python scripts/validate.py` after each batch. Exercises may exist only for levels that are written.

## Level specs

| Level | Length | Sources and tools | Ends with |
| --- | --- | --- | --- |
| L0 ELI5 | ~1 page | Subject summary and course descriptions only, no web needed | nothing (no practice) |
| L1 Basics | about 3-4 pages (roughly 900-1400 words) | Open lecture notes, MIT OCW, open textbooks, Wikipedia only as last resort. Search the web, then fetch and read the pages before citing them. | optional short `## Check questions`, no answers (real practice is in exercises) |
| L2 Master crash course | one lecture-note, roughly 2000-3500 words | Textbooks and full lecture notes. Derive the key results, not just state them. Search the web, then fetch and read the pages. | optional `## Solved problems` with full solutions (more practice is in exercises) |
| L3 Research frontier | variable, roughly 1500-3000 words | Use your own web search and page fetching, no special services: search for recent reviews and papers (journal and publisher pages, arXiv, conference proceedings) and for existing tools and systems (project pages, repositories), then read each page before citing it. Prefer reviews and the last 3-5 years. | `## Open questions`, and a line `Generated: <date>` under the title |

Rules for every level:
- List the sources you actually read in `sources.json` (`{"level","title","url"}`) and cite them inline as `[1]`, numbered like that level's entries, for non-obvious claims, numbers and quotes. No invented sources or URLs; if you found no good source, say so in the text instead of inventing one.
- L3: list at least 4 sources in `sources.json` (reviews, papers, project pages), each with a title and an http(s) URL; `validate.py` checks this. Cache the pages you fetch as text in `work/pages/` so regenerating or fixing a level does not refetch them. Write L3 with the strongest model available (Opus in Claude Code): it depends entirely on built-in web search quality.
- Formulas are LaTeX (`$...$` inline, `$$...$$` display on its own lines). The viewer renders them with a KaTeX-like engine: prefer `aligned`, `cases`, `matrix` and `array` environments, use `\text{...}` for words inside formulas, and avoid `align`/`eqnarray`, `\label`, `\tag`, `\newcommand` and packages. Figures are optional SVG files in `figures/`.
- Heading is `# <title> (L<n>)`.
- Concept closure: no concept beyond the prerequisites' levels. Define anything new.
- Do not modify other levels, `aliases`, `summary`, `degrees` or `prerequisites` (prerequisite links are curated separately in `data/curated_prerequisites.json`).

## Models (Claude Code)

Use the strongest model available, at least for L3 and verification. The in-app agent runs on the model chosen in its dropdown; the agent definitions in `.claude/agents/` pin cheaper models only as a default for bulk work.
