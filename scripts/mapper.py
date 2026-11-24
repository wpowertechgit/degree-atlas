"""Mapper pipeline: raw university course lists -> canonical subjects, degrees, domains.

Stages (run in order, each is resumable):
  python scripts/mapper.py cluster   # TF-IDF candidate groups across universities
  python scripts/mapper.py judge     # Sonnet decides which candidates are the same subject
  python scripts/mapper.py assemble  # write data/subjects, degrees, domains
  python scripts/mapper.py curriculum # refresh degree plans with the existing subject IDs
"""
import os
import json
import math
import re
import subprocess
import sys
from collections import Counter, defaultdict
from concurrent.futures import ThreadPoolExecutor
from pathlib import Path

repo = Path(__file__).resolve().parent.parent
root = Path(os.environ.get("DEGREE_ATLAS_PROFILE") or repo)  # profile folder holding data/, work/
work = root / "work"
work.mkdir(exist_ok=True)
THRESHOLD = 0.3
SAME_UNI_THRESHOLD = 0.55
BATCH = 12
JUDGE_REVISION = "curriculum-equivalence-v2"


def load(p):
    return json.loads(Path(p).read_text(encoding="utf-8"))


def save(p, o):
    Path(p).write_text(json.dumps(o, ensure_ascii=False, indent=1), encoding="utf-8")


def unis():
    result = [load(f) for f in sorted((root / "data/universities").glob("*.json"))]
    plans = curriculum_plans()
    for u in result:
        uid = u["university"].lower().split()[0]
        for d in u["degrees"]:
            plan = plans.get(degree_id(uid, d), {})
            codes = {c["code"] for c in d["courses"]}
            d["courses"].extend(c for c in plan.get("extra_courses", []) if c["code"] not in codes)
    return result


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


PROMPT = """You are the mapper for a university-subject network. Below are candidate groups of courses from different universities (any language). For each group, partition its members into sets that teach essentially the SAME subject content (same core topics at similar depth and scope). Members that teach something different must go in separate sets. A set may be a single course.
Shared words, titles, department, and theme are insufficient evidence. Keep introductory and advanced sequences, labs versus lectures, and generic thesis, seminar or project titles separate unless the catalog descriptions establish genuine equivalence. Split by default when evidence is thin. Course equivalence never changes which degree a course belongs to, its requirement category, or its semester.
Reply with ONLY a JSON object: {{"<group number>": [["uni:code","uni:code"],["uni:code"]], ...}} covering every member of every group exactly once.

{body}"""


def judge():
    cs = courses()
    groups = load(work / "clusters.json")["multi"]
    done_f = work / "judged.json"
    done = load(done_f) if done_f.exists() else {}
    gk = lambda i: judgment_key(groups[i])
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


def judgment_key(group):
    return JUDGE_REVISION + "|" + "|".join(sorted(group))


def degree_id(uid, degree):
    return f"{uid}-{degree['level'].lower()}-{slug(degree['name'])}"


def curriculum_plans():
    path = repo / "data/curricula.json"
    return load(path) if path.exists() else {}


def curriculum_entries(degree, plan, lookup):
    """Requirement types belong to a course in a specific degree, never to a cluster."""
    codes = {c["code"]: c for c in degree["courses"]}
    choice_by_code = {
        code: (group["name"], group.get("course_sources", {}).get(code, group.get("source", plan["source"])))
        for group in plan.get("choices", []) for code in group.get("courses", [])
    }
    required = plan.get("required", {})
    unknown_codes = (required.keys() | choice_by_code.keys()) - codes.keys()
    if unknown_codes:
        raise ValueError(f"{degree['name']}: review has unknown codes: {', '.join(sorted(unknown_codes))}")
    rank = {"mandatory": 2, "elective": 1, "unverified": 0}
    entries = {}
    for code, course in codes.items():
        sid = lookup(code)
        if sid is None:
            if code in required or code in choice_by_code or course.get("requirement"):
                raise ValueError(f"{degree['name']}: sourced course {code} is unmapped")
            continue
        entry = {"subject": sid, "semester": None, "kind": "unverified"}
        if code in required:
            entry.update(kind="mandatory", semester=required[code], source=plan["source"])
        elif code in choice_by_code:
            group, source = choice_by_code[code]
            entry.update(kind="elective", group=group, source=source)
        elif not plan and (requirement := course.get("requirement")) and requirement.get("source"):
            entry.update({k: v for k, v in requirement.items() if k != "quote"})  # the quote stays in the university file
            if entry["kind"] == "mandatory":
                entry["semester"] = course.get("semester")
        old = entries.get(sid)
        if old and old.get("source") and entry.get("source"):
            raise ValueError(f"{degree['name']}: distinct sourced courses share {sid}; review its aliases")
        if old is None or rank[entry["kind"]] > rank[old["kind"]]:
            entries[sid] = entry
    return sorted(entries.values(), key=lambda e: (-rank[e["kind"]], e["semester"] or 999, e["subject"]))


def degree_record(did, degree, entries, plan):
    record = {"id": did, "title": degree["name"], "level": degree["level"], "subjects": entries}
    source = plan.get("source") or degree.get("curriculum_source")
    choices = plan.get("choices", degree.get("choices", []))
    if source:
        record["curriculum_source"] = source
    if choices:
        record["choices"] = [{k: v for k, v in g.items() if k not in {"courses", "course_sources"}} for g in choices]
    return record


def suggest_semesters(entries, prereq, level):
    """Give every non-elective course without a plan semester a suggested one. Returns True if any was set.

    Courses go in prerequisite order (foundations first; among equals, courses that more others build on
    come earlier), spread evenly over the usual number of terms, and always after their own prerequisites.
    Semesters taken from an official plan are kept.
    """
    terms = 4 if level == "MSc" else 6
    core = [e for e in entries if e["kind"] != "elective"]
    ids = {e["subject"] for e in core}
    todo = [e for e in core if e.get("semester") is None]
    if not todo:
        return False
    memo = {}

    def depth(sid, seen=frozenset()):
        if sid not in memo:
            ps = [p for p in prereq.get(sid, ()) if p in ids and p not in seen]  # `seen` guards against cycles
            memo[sid] = 1 + max((depth(p, seen | {sid}) for p in ps), default=0)
        return memo[sid]

    dependents = Counter(p for sid in ids for p in prereq.get(sid, ()) if p in ids)
    todo.sort(key=lambda e: (depth(e["subject"]), -dependents[e["subject"]], e["subject"]))
    placed = {e["subject"]: e["semester"] for e in core if e.get("semester") is not None}
    per = math.ceil(len(todo) / terms)
    for i, e in enumerate(todo):
        after = max((placed.get(p) or 0 for p in prereq.get(e["subject"], ()) if p in ids), default=0)
        e["semester"] = min(terms, max(i // per + 1, after + 1))
        placed[e["subject"]] = e["semester"]
    return True


def curriculum():
    """Migrate degree metadata without rewriting course notes, aliases or prerequisites."""
    plans = curriculum_plans()
    subject_dir = root / "data/subjects"
    metas = {p.parent.name: load(p) for p in subject_dir.glob("*/meta.json")}
    alias_ids = {}
    for sid, meta in metas.items():
        for alias in meta["aliases"]:
            if alias.get("code"):
                alias_ids.setdefault((alias["university"].lower().split()[0], alias["code"]), sid)
    records, created, revised = {}, set(), set()
    universities = unis()
    for uni in universities:
        uid = uni["university"].lower().split()[0]
        for degree in uni["degrees"]:
            did = degree_id(uid, degree)
            plan = plans.get(did, {})
            assignments = plan.get("subject_assignments", {})
            extra_codes = {c["code"] for c in plan.get("extra_courses", [])}
            for course in (c for c in degree["courses"] if c["code"] in assignments or c["code"] in extra_codes):
                code = course["code"]
                key = (uid, code)
                prior = alias_ids.get(key)
                target = assignments.get(code)
                if prior is not None and (target is None or prior == target):
                    continue
                base = slug(course["title"])
                sid = target or (base if base not in metas else f"{base}-{uid}-{slug(code)}")
                if sid not in metas and (subject_dir / sid).exists():
                    raise ValueError(f"{sid}: resolve the new course ID before migrating")
                if prior is not None:
                    old = metas[prior]
                    aliases = [a for a in old["aliases"]
                               if (a["university"].lower().split()[0], a.get("code")) != key]
                    if not aliases:
                        raise ValueError(f"{prior}: preserve the existing ID for this single-course subject")
                    old["aliases"] = aliases
                    revised.add(prior)
                alias_ids[key] = sid
                alias = {"university": uni["university"], "code": code, "name": course["title"]}
                if sid in metas:
                    metas[sid]["aliases"].append(alias)
                    revised.add(sid)
                    continue
                metas[sid] = {
                    "id": sid, "title": course["title"], "summary": course["description"],
                    "aliases": [alias],
                    "prerequisites": [], "degrees": [],
                    "levels": {f"L{n}": {"state": "none"} for n in range(4)},
                }
                created.add(sid)
    for uni in universities:
        uid = uni["university"].lower().split()[0]
        for degree in uni["degrees"]:
            if not degree["courses"]:
                continue
            did = degree_id(uid, degree)
            plan = plans.get(did, {})
            entries = curriculum_entries(degree, plan, lambda code: alias_ids.get((uid, code)))
            records[did] = degree_record(did, degree, entries, plan)
    # Legacy demo and imported degree files may have no raw university record.
    for path in (root / "data/degrees").glob("*.json"):
        if path.stem in records:
            continue
        record = load(path)
        changed = False
        for entry in record["subjects"]:
            if not entry.get("source") and entry["kind"] != "unverified":
                entry["kind"] = "unverified"
                changed = True
        if changed:
            records[record["id"]] = record
    prereqs = {sid: meta["prerequisites"] for sid, meta in metas.items()}
    for path in (root / "data/degrees").glob("*.json"):
        if path.stem not in records and suggest_semesters((record := load(path))["subjects"], prereqs, record["level"]):
            records[record["id"]] = record
    for record in records.values():
        suggest_semesters(record["subjects"], prereqs, record["level"])
    membership = defaultdict(list)
    for did, record in records.items():
        for entry in record["subjects"]:
            membership[entry["subject"]].append({"degree": did, "kind": entry["kind"]})
    for sid, meta in metas.items():
        old = meta["degrees"]
        new = sorted([r for r in old if r["degree"] not in records] + membership[sid], key=lambda r: r["degree"])
        folder = subject_dir / sid
        if sid in created:
            (folder / "figures").mkdir(parents=True)
            save(folder / "sources.json", [])
        if sid in created or sid in revised or old != new:
            meta["degrees"] = new
            save(folder / "meta.json", meta)
    for did, record in records.items():
        save(root / "data/degrees" / f"{did}.json", record)
    print(f"{len(records)} degree plans updated, {len(created)} sourced subjects added, study notes preserved")


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
    plans = curriculum_plans()
    assignments = {
        f"{did.split('-')[0]}:{code}": sid
        for did, plan in plans.items()
        for code, sid in plan.get("subject_assignments", {}).items()
    }
    cl = load(work / "clusters.json")
    judged = load(work / "judged.json") if (work / "judged.json").exists() else {}
    sets = []
    used = set()
    for group in cl["multi"]:
        for part in judged.get(judgment_key(group), [[k] for k in group]):
            current = [k for k in dict.fromkeys(part) if k in cs and k not in used and k not in assignments]
            if current:
                sets.append(current)
                used.update(current)
    mapped = defaultdict(list)
    for key in cs.keys() - used:
        if key in assignments:
            mapped[assignments[key]].append(key)
        else:
            sets.append([key])
    sets.extend(mapped.values())
    # A reviewed partition must not be re-merged by title. Preserve IDs by exact
    # upstream aliases so a later split cannot rename or overwrite old notes.
    reserved = {p.parent.name: load(p) for p in (root / "data/subjects").glob("*/meta.json")}
    old_keys = defaultdict(set)
    for sid, meta in reserved.items():
        for alias in meta["aliases"]:
            if alias.get("code"):
                old_keys[f"{alias['university'].lower().split()[0]}:{alias['code']}"].add(sid)
    def overlap(group):
        return Counter(sid for key in group for sid in old_keys[key])
    sets.sort(key=lambda group: (-max(overlap(group).values(), default=0), sorted(group)))
    ids, key2id = {}, {}
    for s in sets:
        s.sort()
        base = slug(cs[s[0]]["title"])
        sid = assignments.get(s[0])
        if sid is None:
            choices = sorted(overlap(s).items(), key=lambda x: (-x[1], x[0]))
            sid = next((x for x, _ in choices if x not in ids and x not in assignments.values()), None)
        if sid is None:
            sid, n = base, 2
            while sid in ids or sid in reserved or sid in assignments.values():
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
    chosen_domain = {}  # degree id -> domain id classified by the agent in the university file
    for uid, u, d in degs:
        did = degree_id(uid, d)
        plan = plans.get(did, {})
        entries = curriculum_entries(d, plan, lambda code: key2id[f"{uid}:{code}"])
        deg_files[did] = degree_record(did, d, entries, plan)
        if d.get("domain"):
            chosen_domain[did] = d["domain"]
        for entry in entries:
            sdeg[entry["subject"]][did] = entry["kind"]
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
    cur_f = repo / "data/curated_prerequisites.json"  # hand/agent-curated links, {subject: [prerequisite ids]}
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
        save_meta = {
            "id": sid,
            "title": rep["title"],
            "aliases": new_aliases,
            "summary": rep["description"] or rep["title"],
            "prerequisites": sorted(prereq[sid]),
            "degrees": [r for r in old["degrees"] if r["degree"] not in deg_files] +
                       [{"degree": d, "kind": k} for d, k in sorted(sdeg[sid].items())] if old else
                       [{"degree": d, "kind": k} for d, k in sorted(sdeg[sid].items())],
            "levels": levels,
        }
        folder.mkdir(parents=True, exist_ok=True)
        (folder / "figures").mkdir(exist_ok=True)
        if not (folder / "sources.json").exists():
            (folder / "sources.json").write_text("[]\n")
        save(mf, save_meta)
    for sid in reserved.keys() - ids.keys():
        previous = reserved[sid]
        remaining = [r for r in previous["degrees"] if r["degree"] not in deg_files]
        if remaining != previous["degrees"]:
            previous["degrees"] = remaining
            save(root / "data/subjects" / sid / "meta.json", previous)
    # Plan semesters come from the study plan; the remaining courses get a suggested semester.
    dom = defaultdict(list)
    known_domains = {f.stem for f in (root / "data/domains").glob("*.json")}  # before this run writes anything
    for did, record in deg_files.items():
        suggest_semesters(record["subjects"], prereq, record["level"])
        save(root / "data/degrees" / f"{did}.json", record)
        dom[chosen_domain.get(did) or domain_of(record["title"])].append(did)  # the keyword guess is only the fallback for old data
    for dn, dl in dom.items():
        if root != repo and dn not in known_domains:
            continue  # a profile never invents domains; the check below reports it
        f = root / "data/domains" / f"{dn}.json"
        if root != repo and f.exists():  # a profile keeps the shipped domain lists and only adds its degrees
            dl = [*dl, *load(f).get("degrees", [])]
        save(f, {"id": dn, "title": dn.replace("-", " ").title(), "degrees": sorted(set(dl))})
    print(f"{len(ids)} subjects, {len(deg_files)} degrees, {len(dom)} domains")
    if root != repo:  # a personal profile must rest on verified plan evidence
        import check_plan

        problems = check_plan.check(strict=True)
        for did in deg_files:
            dn = chosen_domain.get(did)
            if dn not in known_domains:
                problems.append(f"{did}: set `domain` on the degree in the university file to one of: "
                                + ", ".join(sorted(known_domains)))
        for did, record in deg_files.items():
            if not any(e["kind"] == "mandatory" for e in record["subjects"]):
                problems.append(f"{did}: no mandatory subjects; every entry is unverified, so the atlas will not show it")
        if problems:
            print(chr(10).join(problems))
            sys.exit("Requirement evidence is missing or does not match the study-plan pages. See AGENTS.md (Verify the study plan first).")


if __name__ == "__main__":
    steps = {"cluster": cluster, "judge": judge, "assemble": assemble, "curriculum": curriculum}
    if len(sys.argv) != 2 or sys.argv[1] not in steps:
        sys.exit("usage: python scripts/mapper.py {" + "|".join(steps) + "}")
    steps[sys.argv[1]]()
