"""Mapper pipeline: raw university course lists -> canonical subjects, degrees, domains.

Stages (run in order, each is resumable):
  python scripts/mapper.py cluster   # TF-IDF candidate groups across universities
  python scripts/mapper.py judge     # Sonnet decides which candidates are the same subject
  python scripts/mapper.py assemble  # write data/subjects, degrees, domains
"""
import json
import math
import re
import subprocess
import sys
from collections import Counter, defaultdict
from concurrent.futures import ThreadPoolExecutor
from pathlib import Path

root = Path(__file__).resolve().parent.parent
work = root / "work"
work.mkdir(exist_ok=True)
THRESHOLD = 0.3
SAME_UNI_THRESHOLD = 0.55
BATCH = 12


def load(p):
    return json.loads(Path(p).read_text(encoding="utf-8"))


def save(p, o):
    Path(p).write_text(json.dumps(o, ensure_ascii=False, indent=1), encoding="utf-8")


def unis():
    return [load(f) for f in sorted((root / "data/universities").glob("*.json"))]


def courses():
    """Unique courses keyed 'uni:code'."""
    out = {}
    for u in unis():
        uid = u["university"].lower().split()[0]
        for d in u["degrees"]:
            for c in d["courses"]:
                k = f"{uid}:{c['code']}"
                if k not in out:
                    out[k] = {**c, "uni": u["university"], "key": k}
    return out


def tokens(c):
    t = f"{c['title']} {c['title']} {c['description']} {' '.join(c.get('topics', []))}"
    return [w for w in re.findall(r"[a-z]{3,}", t.lower())]


def cluster():
    cs = courses()
    docs = {k: Counter(tokens(c)) for k, c in cs.items()}
    df = Counter(w for d in docs.values() for w in d)
    n = len(docs)
    idf = {w: math.log(n / v) for w, v in df.items()}
    vec = {}
    for k, d in docs.items():
        v = {w: (1 + math.log(f)) * idf[w] for w, f in d.items() if df[w] < n * 0.2}
        norm = math.sqrt(sum(x * x for x in v.values())) or 1
        vec[k] = {w: x / norm for w, x in v.items()}
    inv = defaultdict(list)
    for k, v in vec.items():
        for w in v:
            inv[w].append(k)
    parent = {k: k for k in cs}

    def find(x):
        while parent[x] != x:
            parent[x] = parent[parent[x]]
            x = parent[x]
        return x

    pairs = 0
    for k, v in vec.items():
        score = Counter()
        for w, x in v.items():
            for o in inv[w]:
                if o > k:
                    score[o] += x * vec[o][w]
        for o, s in score.items():
            if s >= (THRESHOLD if cs[o]["uni"] != cs[k]["uni"] else SAME_UNI_THRESHOLD):
                parent[find(o)] = find(k)
                pairs += 1
    groups = defaultdict(list)
    for k in cs:
        groups[find(k)].append(k)
    multi = [g for g in groups.values() if len(g) > 1]
    save(work / "clusters.json", {"multi": multi, "single": [g[0] for g in groups.values() if len(g) == 1]})
    print(f"{n} courses, {pairs} candidate pairs, {len(multi)} candidate groups, "
          f"{n - sum(map(len, multi))} singletons")


PROMPT = """You are the mapper for a university-subject network. Below are candidate groups of courses from different universities (any language). For each group, partition its members into sets that teach essentially the SAME subject content (same core topics at similar depth). Members that teach something different must go in separate sets. A set may be a single course.
Reply with ONLY a JSON object: {{"<group number>": [["uni:code","uni:code"],["uni:code"]], ...}} covering every member of every group exactly once.

{body}"""


def judge():
    cs = courses()
    groups = load(work / "clusters.json")["multi"]
    done_f = work / "judged.json"
    done = load(done_f) if done_f.exists() else {}
    gk = lambda i: "|".join(sorted(groups[i]))  # key by members: stable across re-clustering
    todo = [i for i in range(len(groups)) if gk(i) not in done]
    batches = [todo[i:i + BATCH] for i in range(0, len(todo), BATCH)]

    def run(batch):
        body = "\n\n".join(
            f"### Group {i}\n" + "\n".join(
                f"- {k} | {cs[k]['title']} | {cs[k]['description'][:300]}" for k in groups[i]) for i in batch)
        for _ in range(2):
            r = subprocess.run(["claude", "-p", "--model", "sonnet", "--tools", "", "--no-session-persistence"],
                               input=PROMPT.format(body=body), capture_output=True, text=True, encoding="utf-8")
            m = re.search(r"\{.*\}", r.stdout, re.S)
            try:
                res = json.loads(m.group(0))
                if all(str(i) in res and sorted(sum(res[str(i)], [])) == sorted(groups[i]) for i in batch):
                    return {gk(i): res[str(i)] for i in batch}
            except Exception:
                pass
        return {gk(i): [[k] for k in groups[i]] for i in batch}  # fail safe: keep separate

    with ThreadPoolExecutor(6) as ex:
        for res in ex.map(run, batches):
            done.update(res)
            save(done_f, done)
            print(f"judged {len(done)}/{len(groups)}", flush=True)


def slug(s):
    s = re.sub(r"[^a-z0-9]+", "-", s.lower()).strip("-")
    return s[:60].strip("-") or "subject"


DOMAINS = [
    ("computing", r"comput|data science|cyber|informatics|artificial intel|robotic"),
    ("engineering", r"engineering|architecture|aerospace|materials|mechanic|electr|nuclear|space|process"),
    ("natural-science", r"physics|chemi|biolog|earth|climate|environment|geo|agricultur|astronom|neuro|brain|pharma|health|medic|food"),
    ("mathematics", r"math|statistic"),
    ("social-science", r"econom|financ|management|manage|polic|politic|business|planning|anthropolog|global|public|studies"),
    ("humanities", r".*"),
]


def domain_of(title):
    t = title.lower()
    return next(d for d, rx in DOMAINS if re.search(rx, t))


def assemble():
    cs = courses()
    cl = load(work / "clusters.json")
    judged = load(work / "judged.json") if (work / "judged.json").exists() else {}
    sets = [s for g in cl["multi"] for s in judged.get("|".join(sorted(g)), [[k] for k in g])]
    sets += [[k] for k in cl["single"]]
    # same title = same subject at L0 granularity (joint listings, per-degree variants, generic studios/theses)
    by_title = {}
    merged = []
    for s in sets:
        nt = re.sub(r"[^a-z0-9]+", " ", cs[s[0]]["title"].lower()).strip()
        if nt in by_title:
            by_title[nt].extend(s)
        else:
            by_title[nt] = s
            merged.append(s)
    sets = merged
    # prefer the first listed university's title as the canonical one
    ids, key2id = {}, {}
    for s in sets:
        s.sort()
        base = slug(cs[s[0]]["title"])
        sid, n = base, 2
        while sid in ids:
            sid, n = f"{base}-{n}", n + 1
        ids[sid] = s
        for k in s:
            key2id[k] = sid
    # prerequisites: resolve codes of the same university to subject ids
    code2key = defaultdict(dict)
    for k, c in cs.items():
        code2key[c["uni"]][c["code"]] = k
    degs = []
    for u in unis():
        uid = u["university"].lower().split()[0]
        for d in u["degrees"]:
            if d["courses"]:
                degs.append((uid, u, d))
    sdeg = defaultdict(dict)  # subject -> degree id -> kind
    deg_files = {}
    for uid, u, d in degs:
        did = f"{uid}-{d['level'].lower()}-{slug(d['name'])}"
        subs = {}
        for c in d["courses"]:
            sid = key2id[f"{uid}:{c['code']}"]
            kind = "mandatory" if c.get("mandatory") else "elective"
            if subs.get(sid, {}).get("kind") != "mandatory":
                subs[sid] = {"kind": kind, "semester": c.get("semester")}
        deg_files[did] = (d, subs)
        for sid, v in subs.items():
            if sdeg[sid].get(did) != "mandatory":
                sdeg[sid][did] = v["kind"]
    prereq = defaultdict(set)
    for k, c in cs.items():
        for p in c.get("prerequisites", []):
            pk = code2key[c["uni"]].get(p)
            if pk and key2id[pk] != key2id[k]:
                prereq[key2id[k]].add(key2id[pk])
    llm_f = work / "prereq_llm.json"  # free-text prerequisites resolved by scripts/prereqs.py
    for k, ps in (load(llm_f) if llm_f.exists() else {}).items():
        for pk in ps:
            if k in key2id and pk in key2id and key2id[pk] != key2id[k]:
                prereq[key2id[k]].add(key2id[pk])
    cur_f = root / "data/curated_prerequisites.json"  # hand/agent-curated links, {subject: [prerequisite ids]}
    for sid, ps in (load(cur_f) if cur_f.exists() else {}).items():
        if sid in ids:
            prereq[sid].update(x for x in ps if x in ids and x != sid)
    # break cycles: drop back-edges found by DFS
    state = {}

    def dfs(s):
        state[s] = 1
        for p in sorted(prereq[s]):
            if state.get(p) == 1:
                prereq[s].discard(p)
            elif p not in state:
                dfs(p)
        state[s] = 2

    sys.setrecursionlimit(10000)
    for s in ids:
        if s not in state:
            dfs(s)
    # Keep only direct dependencies. If another prerequisite path already
    # connects a subject to a candidate, the direct edge adds no information.
    reduced = defaultdict(set)
    for sid in ids:
        for candidate in sorted(prereq[sid]):
            pending = [p for p in prereq[sid] if p != candidate]
            seen = set()
            redundant = False
            while pending:
                current = pending.pop()
                if current == candidate:
                    redundant = True
                    break
                if current not in seen:
                    seen.add(current)
                    pending.extend(prereq[current])
            if not redundant:
                reduced[sid].add(candidate)
    prereq = reduced
    for sid, members in ids.items():
        folder = root / "data/subjects" / sid
        mf = folder / "meta.json"
        old = load(mf) if mf.exists() else None
        levels = old["levels"] if old else {f"L{n}": {"state": "none"} for n in range(4)}
        rep = cs[members[0]]
        new_aliases = [{"name": cs[k]["title"], "university": cs[k]["uni"], "code": cs[k]["code"]} for k in members]
        if old and old["aliases"] != new_aliases and levels["L0"]["state"] == "done":
            levels["L0"] = {"state": "none"}  # members changed: rewrite L0 from all of them
            (root / "data/subjects" / sid / "L0.md").unlink(missing_ok=True)
        save_meta = {
            "id": sid,
            "title": rep["title"],
            "aliases": new_aliases,
            "summary": rep["description"] or rep["title"],
            "prerequisites": sorted(prereq[sid]),
            "degrees": [{"degree": d, "kind": k} for d, k in sorted(sdeg[sid].items())],
            "levels": levels,
        }
        folder.mkdir(parents=True, exist_ok=True)
        (folder / "figures").mkdir(exist_ok=True)
        if not (folder / "sources.json").exists():
            (folder / "sources.json").write_text("[]\n")
        save(mf, save_meta)
    orphans = work / "orphans"
    for d in (root / "data/subjects").iterdir():
        if d.is_dir() and d.name not in ids and d.name != "control-theory":
            orphans.mkdir(exist_ok=True)
            d.rename(orphans / d.name)
    # degrees (semester: given, else depth in the prerequisite graph restricted to the degree)
    dom = defaultdict(list)
    for did, (d, subs) in deg_files.items():
        depth = {}

        def dp(s, seen=()):
            if s in depth:
                return depth[s]
            r = 1 + max((dp(p, seen + (s,)) for p in prereq[s] if p in subs and p not in seen), default=0)
            depth[s] = r
            return r

        entries = [{"subject": s, "semester": v["semester"] or dp(s), "kind": v["kind"]}
                   for s, v in sorted(subs.items())]
        lvl = d["level"]
        save(root / "data/degrees" / f"{did}.json", {"id": did, "title": d["name"], "level": lvl, "subjects": entries})
        dom[domain_of(d["name"])].append(did)
    for dn, dl in dom.items():
        save(root / "data/domains" / f"{dn}.json", {"id": dn, "title": dn.replace("-", " ").title(), "degrees": sorted(dl)})
    print(f"{len(ids)} subjects, {len(deg_files)} degrees, {len(dom)} domains")


if __name__ == "__main__":
    {"cluster": cluster, "judge": judge, "assemble": assemble}[sys.argv[1]]()
