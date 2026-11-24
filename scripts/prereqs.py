"""Resolve free-text prerequisites (ETH) to course keys with Haiku. Output: work/prereq_llm.json
  { "eth:<code>": ["eth:<code>", ...] }   (consumed by mapper.py assemble)
"""
import json
import re
import subprocess
import sys
from collections import defaultdict
from concurrent.futures import ThreadPoolExecutor
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
import mapper  # noqa: E402

out_f = mapper.work / "prereq_llm.json"
STOP = {"and", "the", "for", "with", "basic", "knowledge", "introduction", "course", "advanced", "lecture", "theory", "systems", "methods"}
BATCH = 10
PROMPT = """For each course below, its free-text prerequisite statement is given with candidate courses (same university). Decide which candidates the statement explicitly names or clearly requires (e.g. "Analysis I and II" -> both Analysis courses). Vague statements like "basic knowledge of chemistry" -> none. Never add candidates that are not clearly required.
Reply with ONLY JSON: {{"<course key>": ["<candidate key>", ...], ...}} including every course key (empty list if none).

{body}"""


def words(s):
    return {w for w in re.findall(r"[a-z]{4,}", s.lower()) if w not in STOP}


def main():
    mapper.migrate_uni_ids()
    cs = mapper.courses()
    done = mapper.load(out_f) if out_f.exists() else {}
    bytitle = defaultdict(list)
    for k, c in cs.items():
        for w in words(c["title"]):
            bytitle[w].append(k)
    items = []
    for k, c in cs.items():
        txt = " ".join(c.get("prerequisites") or []) if not c["uni"].startswith("MIT") else ""
        if not txt or k in done or c["uni"].startswith("National"):
            continue
        # NUS/MIT already carry course codes; only treat entries that are not codes
        if re.fullmatch(r"[A-Z0-9.\-\[\]]+", txt.strip()):
            continue
        score = defaultdict(int)
        for w in words(txt):
            for o in bytitle.get(w, []):
                if o != k and cs[o]["uid"] == c["uid"]:
                    score[o] += 1
        cand = [o for o, _ in sorted(score.items(), key=lambda x: -x[1])[:10]]
        if cand:
            items.append((k, txt[:300], cand))
        else:
            done[k] = []
    batches = [items[i:i + BATCH] for i in range(0, len(items), BATCH)]

    def run(batch):
        body = "\n\n".join(
            f"### {k}\nPrerequisites: {txt}\nCandidates:\n" + "\n".join(f"- {o} | {cs[o]['title']}" for o in cand)
            for k, txt, cand in batch)
        for _ in range(2):
            r = subprocess.run(["claude", "-p", "--model", "haiku", "--tools", "", "--no-session-persistence"],
                               input=PROMPT.format(body=body), capture_output=True, text=True, encoding="utf-8")
            try:
                res = json.loads(re.search(r"\{.*\}", r.stdout, re.S).group(0))
                return {k: [o for o in res.get(k, []) if o in cand] for k, _, cand in batch}
            except Exception:
                continue
        return {k: [] for k, _, _ in batch}

    with ThreadPoolExecutor(4) as ex:
        for res in ex.map(run, batches):
            done.update(res)
            mapper.save(out_f, done)
            print(f"resolved {len(done)}", flush=True)
    print("links:", sum(len(v) for v in done.values()))


if __name__ == "__main__":
    main()
