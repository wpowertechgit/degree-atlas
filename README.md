<p align="center">
  <picture>
    <source media="(prefers-color-scheme: dark)" srcset="app/assets/brand/degree-atlas-wordmark-light.svg">
    <img src="app/assets/brand/degree-atlas-wordmark.svg" alt="Degree Atlas" width="420">
  </picture>
</p>

<p align="center">
  <b>Don't have 3-4 years to waste on a degree just to get into a topic? np bro, gotchu.</b>
</p>

<p align="center">
  <a href="LICENSE"><img alt="License: MIT" src="https://img.shields.io/badge/license-MIT-blue"></a>
  <img alt="Built with Flutter" src="https://img.shields.io/badge/built%20with-Flutter-02569B">
  <img alt="Agents: Claude Code and Codex" src="https://img.shields.io/badge/agents-Claude%20Code%20%7C%20Codex-8A63D2">
</p>

<!-- Add a screenshot of the atlas here: ![Degree Atlas](docs/atlas.png) -->

Degree Atlas is for the people who want to actually learn a field but are way too lazy to sit down and grind through 800 pages of PDFs. Yeah, same bro. You tell your AI agent what you want to learn (or throw your own course files at it), it figures out what a real degree would teach you and in what order, writes it up at the depth you pick, and gives you a map to browse it on. You read, you practise, you move on.

## Why this exists

Every university publishes what it teaches: study plans, course lists, descriptions, sometimes whole lecture notes. Lay a few of those side by side and you can see what a field is really made of, what comes first, and what builds on what. The problem is it's all scattered across catalogs, written for students who already enrolled, and nobody is going to read it as a whole.

Teaching yourself is the other half of the pain. A search gives you a hundred explanations at random depth. A textbook assumes you finished the previous one. Nothing tells you what to learn first or whether you're ready for the next thing. And if you're already in a course, your own notes are a pile of PDFs with no order and no practice problems.

So this does two things. It reads real degree programs, merges the courses they share into single subjects, and lays everything out as a map with prerequisites. Then your agent writes each subject at the depth you need, and the app lets you read it, practise it and watch the progress ring fill up. Pick a field, follow the map, go deeper when you feel ready.

## How it helps

- **You want to learn a field, not enrol in it.** Say "I want to learn chemical engineering". The agent finds real programs that teach it, builds the subjects in the order a degree would, and starts with a one-page explanation of each, so you see the whole landscape before you commit to any details.
- **You're in a course and drowning in your own material.** Import the folder with your slides, notes and past exams. You get a gentle intro from the ground up, then a deeper level that follows your course's own structure and notation, plus practice problems in the style of your exams.
- **You want to go deep.** Every subject has four levels, from an explanation anyone can follow up to the open questions researchers are chewing on right now.

Quick honesty check: the material is only as good as the agent and the sources it reads. It's written to cite what it actually read, and every level has a "report a problem" button that sends the fix back to the agent. Treat it like a smart study buddy, not like a textbook.

No API keys, no accounts, no hosted service. It drives a coding agent you already use (Claude Code or Codex). Your data, progress and imported files live only on your machine; the agent you pick reads them the way it reads any file you give it.

## What's in it

| Level                            | Goal                                                    |
| -------------------------------- | ------------------------------------------------------- |
| **L0** ELI5                | the concept, main methods and lessons in about one page |
| **L1** Basics              | main ideas and key terms, a few pages                   |
| **L2** Master crash course | methods, derivations, solved problems                   |
| **L3** Research frontier   | state of the field and open questions, dated            |

- **A radial atlas.** You in the middle, then domains, degrees and subjects. Courses shared by several degrees or universities are one subject, so everything forms a prerequisite graph.
- **Practice.** Graded exercises per subject: multiple choice, numeric, short answer and open problems. Your results are tracked.
- **Your own course materials.** Import a folder of notes, slides, problem sets and past exams. You get an elementary intro (L0, L1), a mastery level (L2) that follows your course, and exercises in the style of your exams.
- **Profiles.** Start empty (only the domains), say "I want to learn material science", and the agent builds it. Profiles can be renamed, deleted, exported and imported.
- **Languages.** Read and generate in 13 languages, and have the agent translate what already exists.
- **In-app agent.** A chat panel hooked to a Claude Code session, with a window to check and sign in to your Claude connection.

## Quick start

**Windows:** download `DegreeAtlas-Setup-<version>.exe` from the latest [release](https://github.com/wpowertechgit/degree-atlas/releases) and run it. It installs per user (no admin rights) into `%LOCALAPPDATA%\Programs\DegreeAtlas`, together with the scripts and agent instructions, and adds a Start menu entry. You also need Python 3.10+ and Claude Code for the writing agent. The installer is unsigned, so SmartScreen shows "unknown publisher" (More info, Run anyway). Uninstalling keeps your profiles.

**From source** (any platform, or to work on the repository):

```bash
git clone https://github.com/wpowertechgit/degree-atlas.git
cd degree-atlas
python scripts/setup.py          # Python deps, prebuilt Windows app, local folders, validation
```

Or just open the repo in Claude Code and say "set this up" (see **Setup after clone** in [AGENTS.md](AGENTS.md)). Then start the viewer with `launch.bat` on Windows.

You need Python 3.10+ and Claude Code or Codex for the writing. On Windows, `setup.py` downloads the prebuilt app from the latest [release](https://github.com/wpowertechgit/degree-atlas/releases), so no Flutter or Visual Studio is needed. The app is unsigned, so a zip downloaded manually in a browser triggers the same SmartScreen prompt.

To build from source instead (macOS, Linux, or app development), run `python scripts/setup.py --build-app`. That needs the Flutter SDK (add `--install-flutter` to fetch it) and, on Windows, Visual Studio with the C++ desktop workload.

**First run:** open the profile menu, create an empty profile, open the Agent panel and tell it what you want to learn. Or go **Data → Import course materials…** and start from your own files.

## How it works

```
scout  ->  mapper  ->  writer  (-> optional verifier)
```

1. The **scout** reads a degree's public study plan and course catalog.
2. The **mapper** merges equivalent courses into subjects and builds degrees, domains and prerequisite links.
3. The **writer** produces L0 to L3 and the exercises, citing the sources it actually read.

Everything an agent needs to know is in [AGENTS.md](AGENTS.md): the workflow, level specs, languages, exercises and the rules for your own materials. `python scripts/validate.py` checks all the data against the schemas in `schemas/`.

## What's in this repo

```
AGENTS.md          the agent workflow and rules (Claude Code and Codex)
app/               Flutter desktop viewer
scripts/           mapper, validator, work queue, setup
schemas/           JSON Schemas for the data files
.claude/agents/    scout, mapper, writer, verifier definitions
catalogs.json      example catalog sources (MIT, ETH Zurich, NUS)
data/domains/      domain groupings (committed)
data/              universities/, degrees/, subjects/ are generated locally and gitignored
profiles/          your personal data sets (gitignored)
```

The repo deliberately has **no scraped catalog data and no generated study text**. You build those locally from public catalogs, which keeps the licensing clean. Your own materials stay on your machine too.

## The viewer in detail

- **Atlas:** colours follow the domain, a BSc/MSc toggle switches the level, and clicking a subject opens its brief. Marking a level as read feeds the animated progress, stored in `progress.json` (personal, gitignored).
- **Reading overlay:** L0 to L3 tabs plus Practice, a report-a-problem button, regenerate, and translate buttons that hand the request to the agent.
- **Data menu:** exports everything under `data/` plus your progress into a single-line JSON file (the data is LZW-compressed and base64-encoded in its `payload` field), and imports one. Same-path files get overwritten, progress is merged. Imported course materials are not part of the export.
- **Design:** the reader has a handwritten course-binder look, see [DESIGN.md](DESIGN.md).

## Contributing

Issues and pull requests are welcome, see [CONTRIBUTING.md](CONTRIBUTING.md). Found something security-related, including how the in-app agent is permissioned? Open an issue, and read [SECURITY.md](SECURITY.md) first.

## License

MIT, see [LICENSE](LICENSE). The bundled Kalam font keeps its own license in `app/assets/fonts/`. Generated study material and any catalog data you build locally are yours to handle under the terms of their sources.
