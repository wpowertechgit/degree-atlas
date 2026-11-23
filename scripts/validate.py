"""Validate data/ against schemas/ plus cross-references. Exit 1 on any error."""
import json
import sys
from pathlib import Path

from jsonschema import Draft202012Validator

root = Path(__file__).resolve().parent.parent
rules = [
    ("data/universities/*.json", "university"),
    ("data/domains/*.json", "domain"),
    ("data/degrees/*.json", "degree"),
    ("data/subjects/*/meta.json", "meta"),
    ("data/subjects/*/sources.json", "sources"),
]
errors = []


def load(p):
    return json.loads(p.read_text(encoding="utf-8"))


for pattern, name in rules:
    v = Draft202012Validator(load(root / f"schemas/{name}.schema.json"))
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
    for s in load(f).get("subjects", []):
        if s["subject"] not in metas:
            errors.append(f"{f.name}: unknown subject '{s['subject']}'")

cur = root / "data/curated_prerequisites.json"
if cur.exists():
    for sid, ps in load(cur).items():
        for x in [sid, *ps]:
            if x not in metas:
                errors.append(f"curated_prerequisites.json: unknown subject '{x}'")
        if sid in ps:
            errors.append(f"curated_prerequisites.json: '{sid}' lists itself")

print("\n".join(errors) or "OK")
sys.exit(bool(errors))
