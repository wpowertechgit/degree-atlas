"""Validate data/ against schemas/ plus cross-references. Exit 1 on any error."""
import os
import json
import sys
from pathlib import Path

from jsonschema import Draft202012Validator

repo = Path(__file__).resolve().parent.parent
root = Path(os.environ.get("DEGREE_ATLAS_PROFILE") or repo)  # profile folder holding data/, work/
rules = [
    ("data/universities/*.json", "university"),
    ("data/domains/*.json", "domain"),
    ("data/degrees/*.json", "degree"),
    ("data/subjects/*/meta.json", "meta"),
    ("data/subjects/*/sources.json", "sources"),
    ("data/subjects/*/exercises*.json", "exercises"),
    ("materials/*/index.json", "materials-index"),
]
errors = []


def load(p):
    return json.loads(p.read_text(encoding="utf-8"))


for pattern, name in rules:
    v = Draft202012Validator(load(repo / f"schemas/{name}.schema.json"))
    for f in root.glob(pattern):
        for e in v.iter_errors(load(f)):
            errors.append(f"{f.relative_to(root)}: {'/'.join(map(str, e.path))}: {e.message}")

# cross-references: folder == id, prerequisites exist, a non-empty level needs
# its file and a non-empty previous level
metas = {p.parent.name: load(p) for p in root.glob("data/subjects/*/meta.json")}
for sid, m in metas.items():
    if m.get("id") != sid:
        errors.append(f"subjects/{sid}: id '{m.get('id')}' != folder name")
    for p in m.get("prerequisites", []):
        if p not in metas:
            errors.append(f"subjects/{sid}: unknown prerequisite '{p}'")
    prev = True
    for n in range(4):
        st = m.get("levels", {}).get(f"L{n}", {}).get("state", "none")
        if st != "none":
            if not prev:
                errors.append(f"subjects/{sid}: L{n} exists without L{n - 1}")
            if not (root / f"data/subjects/{sid}/L{n}.md").exists():
                errors.append(f"subjects/{sid}: L{n}.md missing")
        prev = st != "none"

# personal degrees (own-*) must be listed in a domain, or the atlas never shows them
listed = {d for f in root.glob("data/domains/*.json") for d in load(f).get("degrees", [])}
for f in root.glob("data/degrees/own-*.json"):
    if f.stem not in listed:
        errors.append(f"degrees/{f.name}: not listed in any data/domains/*.json")

# own course materials: listed files exist; once the subject has L2, every topic is covered by some level
for idx in sorted(root.glob("materials/*/index.json")):
    ix = load(idx)
    if not isinstance(ix, dict):
        continue
    for f in ix.get("files", []):
        if not (idx.parent / f.get("path", "")).exists():
            errors.append(f"{idx.relative_to(root)}: file '{f.get('path')}' does not exist")
    sid = ix.get("subject")
    if sid:
        if sid not in metas:
            errors.append(f"{idx.relative_to(root)}: unknown subject '{sid}'")
        elif metas[sid].get("levels", {}).get("L2", {}).get("state", "none") != "none":
            for t in ix.get("topics", []):
                if not t.get("covered"):
                    errors.append(f"{idx.relative_to(root)}: topic '{t.get('name')}' is not covered by any level")

# L3 needs real, readable sources: at least 4 entries with a title and an http(s) URL
for sid, m in metas.items():
    if m.get("levels", {}).get("L3", {}).get("state", "none") == "none":
        continue
    sf = root / f"data/subjects/{sid}/sources.json"
    l3 = [s for s in (load(sf) if sf.exists() else []) if isinstance(s, dict) and s.get("level") == "L3"]
    if len(l3) < 4:
        errors.append(f"subjects/{sid}: L3 needs at least 4 sources in sources.json (has {len(l3)})")
    for s in l3:
        if not str(s.get("title", "")).strip() or not str(s.get("url", "")).startswith(("http://", "https://")):
            errors.append(f"subjects/{sid}: L3 source needs a title and an http(s) URL: {s}")

# exercises: only for written levels, answers consistent with the type, translations keep the answer key
import re

for d in sorted(root.glob("data/subjects/*")):
    files = {f.name: f for f in d.glob("exercises*.json")}
    english = load(files["exercises.json"]) if "exercises.json" in files else []
    en_by_id = {e["id"]: e for e in english if isinstance(e, dict) and "id" in e}
    for name, f in files.items():
        if not re.fullmatch(r"exercises(\.[a-z]{2})?\.json", name):
            errors.append(f"subjects/{d.name}/{name}: file name must be exercises.json or exercises.<lang>.json")
            continue
        items = load(f)
        if not isinstance(items, list):
            continue
        ids = set()
        for e in items:
            if not isinstance(e, dict) or "id" not in e:
                continue
            where = f"subjects/{d.name}/{name}: '{e['id']}'"
            if e["id"] in ids:
                errors.append(f"{where}: duplicate id")
            ids.add(e["id"])
            lv = metas.get(d.name, {}).get("levels", {}).get(f"L{e.get('level')}", {}).get("state", "none")
            if lv == "none":
                errors.append(f"{where}: level L{e.get('level')} is not written")
            if e.get("type") == "mcq" and isinstance(e.get("answer"), list) and isinstance(e.get("choices"), list):
                if any(i >= len(e["choices"]) for i in e["answer"]):
                    errors.append(f"{where}: answer index outside choices")
            if e.get("type") == "numeric" and isinstance(e.get("answer"), (int, float)) and e.get("answer") != 0 and "tolerance" not in e:
                errors.append(f"{where}: numeric exercise needs a tolerance")
            if name != "exercises.json":
                src = en_by_id.get(e["id"])
                if src is None:
                    errors.append(f"{where}: no English exercise with this id")
                elif src.get("type") != e.get("type") or src.get("level") != e.get("level") or (
                    e.get("type") in ("mcq", "numeric") and src.get("answer") != e.get("answer")
                ):
                    errors.append(f"{where}: type, level and answer key must match the English exercise")

seen = set()


def visit(s, stack=()):
    if s in stack:
        errors.append("prerequisite cycle: " + " -> ".join(stack + (s,)))
    elif s not in seen:
        seen.add(s)
        for p in metas.get(s, {}).get("prerequisites", []):
            visit(p, stack + (s,))


for s in metas:
    visit(s)

for f in root.glob("data/degrees/*.json"):
    degree = load(f)
    ids = set()
    for s in degree.get("subjects", []):
        sid = s["subject"]
        kind = s["kind"]
        if sid not in metas:
            errors.append(f"{f.name}: unknown subject '{sid}'")
        if sid in ids:
            errors.append(f"{f.name}: duplicate membership '{sid}'")
        ids.add(sid)
        if kind in ("mandatory", "elective") and not s.get("source"):
            errors.append(f"{f.name}: '{sid}' needs requirement evidence")
        if kind != "mandatory" and s.get("semester") is not None:
            errors.append(f"{f.name}: '{sid}' is outside the required semester sequence")
        if sid in metas and {"degree": degree["id"], "kind": kind} not in metas[sid]["degrees"]:
            errors.append(f"{f.name}: '{sid}' membership disagrees with subject metadata")

cur = repo / "data/curated_prerequisites.json"  # shared reference, only checked for the main data set
if cur.exists() and root == repo:
    for sid, ps in load(cur).items():
        for x in [sid, *ps]:
            if x not in metas:
                errors.append(f"curated_prerequisites.json: unknown subject '{x}'")
        if sid in ps:
            errors.append(f"curated_prerequisites.json: '{sid}' lists itself")

print("\n".join(errors) or "OK")
sys.exit(bool(errors))
