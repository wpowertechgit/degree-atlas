"""List the subjects an agent should write next, in a valid order.

  python scripts/next.py L0..L3 [--degree ID] [-n 10]     # to write: previous level present, prerequisites at this level
  python scripts/next.py L1 --verify [--degree ID]    # written (state done) but not yet verified
  python scripts/next.py --exercises [--degree ID] [-n 10] # subjects with a written level L1-L3 that has no exercises yet
  python scripts/next.py L0 --degree ID --include-electives # also write confirmed options

Without --degree the order is global: subjects that are mandatory in the most degrees first.
Prerequisites of the chosen subjects that still lack the level are pulled in, so the output is
a dependency order. Only entries marked READY may be written now; BLOCKED ones show what is missing.
"""
import os
import argparse
import json
from pathlib import Path

repo = Path(__file__).resolve().parent.parent
root = Path(os.environ.get("DEGREE_ATLAS_PROFILE") or repo)  # profile folder holding data/, work/
ap = argparse.ArgumentParser()
ap.add_argument("level", nargs="?", choices=["L0", "L1", "L2", "L3"])
ap.add_argument("--exercises", action="store_true")
ap.add_argument("--degree")
ap.add_argument("--include-electives", action="store_true")
ap.add_argument("-n", type=int, default=10)
ap.add_argument("--verify", action="store_true")
a = ap.parse_args()

metas = {p.parent.name: json.loads(p.read_text(encoding="utf-8")) for p in root.glob("data/subjects/*/meta.json")}
if not a.level and not a.exercises:
    ap.error("give a level or --exercises")
n = int(a.level[1]) if a.level else 0
prev = f"L{n - 1}"


def state(sid, lvl):
    return metas[sid]["levels"].get(lvl, {}).get("state", "none")


# candidate pool and priority
if a.degree:
    d = json.loads((root / f"data/degrees/{a.degree}.json").read_text(encoding="utf-8"))
    allowed = {"mandatory", "elective"} if a.include_electives else {"mandatory"}
    order = {e["subject"]: (e["kind"] != "mandatory", e.get("semester") or 99)
             for e in d["subjects"] if e["kind"] in allowed and e.get("source")}
else:
    order = {}
    for sid, m in metas.items():
        mand = sum(x["kind"] == "mandatory" for x in m["degrees"])
        order[sid] = (-mand, 0)

if a.exercises:
    todo = []
    for s in order:
        if s not in metas:
            continue
        f = root / f"data/subjects/{s}/exercises.json"
        have = {e.get("level") for e in json.loads(f.read_text(encoding="utf-8"))} if f.exists() else set()
        missing = [f"L{k}" for k in (1, 2, 3) if state(s, f"L{k}") != "none" and k not in have]
        if missing:
            todo.append(f"{s}	{','.join(missing)}")
    print(chr(10).join(todo[: a.n]) or "nothing left")
    raise SystemExit

if a.verify:
    todo = [s for s in order if s in metas and state(s, a.level) == "done"]
    print("\n".join(todo[: a.n]) or "nothing to verify")
    raise SystemExit

if a.degree and not order:
    print("No sourced courses in this scope. Review the degree plan before generating it.")
    raise SystemExit

# pull in prerequisites that lack the level
pool = {s for s in order if s in metas and state(s, a.level) == "none"}
stack = list(pool)
while stack:
    for p in metas[stack.pop()]["prerequisites"]:
        if p in metas and state(p, a.level) == "none" and p not in pool:
            pool.add(p)
            stack.append(p)

seen, out = set(), []


def visit(s):
    if s in seen:
        return
    seen.add(s)
    for p in metas[s]["prerequisites"]:
        if p in pool:
            visit(p)
    out.append(s)


for s in sorted(pool, key=lambda s: (*order.get(s, (9, 99)), s)):
    visit(s)

rows = []
for s in out:
    miss_prev = n > 0 and state(s, prev) == "none"
    miss_pre = [p for p in metas[s]["prerequisites"] if p in metas and state(p, a.level) == "none"]
    if miss_prev or miss_pre:
        status = "BLOCKED " + ("needs " + prev + " " if miss_prev else "") + ("needs " + a.level + " of " + ",".join(miss_pre) if miss_pre else "")
    else:
        status = "READY"
    rows.append((status != "READY", s, status))
for _, s, status in sorted(rows, key=lambda r: r[0])[: a.n]:  # READY first, order otherwise kept
    print(f"{s}\t{status}")
if not out:
    print("nothing left")
