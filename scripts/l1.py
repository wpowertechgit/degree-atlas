"""Generate L1 (sourced) for subjects that have L0 but no L1. Haiku + web tools, one subject per call.

  python scripts/l1.py [limit] [--ids a,b,c]   # default order: mandatory subjects first
"""
import json
import re
import subprocess
import sys
from concurrent.futures import ThreadPoolExecutor
from datetime import date
from pathlib import Path

root = Path(__file__).resolve().parent.parent
TOOLS = "WebSearch,mcp__claude_ai_emaf__scrape"
PROMPT = """You write L1 ("Basics") study notes for the university subject below.

Subject: {title}
Also known as: {aliases}
Summary: {summary}
Existing L0 (for consistency, do not copy):
{l0}

Steps: use WebSearch to find 2-4 reliable open sources (MIT OpenCourseWare, university lecture notes, open textbooks, Wikipedia only as a last resort), read the best ones with the emaf scrape tool, then write the notes.

Requirements for the notes: Markdown, 3-4 pages (about 900-1400 words), "# {title} (L1)" heading, the main ideas explained coherently with the key terms in bold, formulas in LaTeX ($...$), then a "## Check questions" section with 4-6 questions (no answers needed). Every factual claim must be supported by the sources you actually read; cite them inline as [1], [2]. Do not invent sources or URLs. If you could not find real sources, say so.

Reply with ONLY a JSON object: {{"markdown": "...", "sources": [{{"title": "...", "url": "..."}}]}}"""


def run(meta):
    sid = meta["id"]
    d = root / "data/subjects" / sid
    l0 = (d / "L0.md").read_text(encoding="utf-8")
    prompt = PROMPT.format(
        title=meta["title"],
        aliases="; ".join(f"{a['name']} ({a['university']} {a.get('code', '')})" for a in meta["aliases"][:6]),
        summary=meta["summary"], l0=l0)
    for _ in range(2):
        r = subprocess.run(["claude", "-p", "--model", "haiku", "--allowedTools", TOOLS, "--output-format", "json",
                            "--no-session-persistence"], input=prompt, capture_output=True, text=True, encoding="utf-8")
        try:
            env = json.loads(r.stdout)
            res = json.loads(re.search(r"\{.*\}", env["result"], re.S).group(0))
            md, src = res["markdown"].strip(), res["sources"]
            if len(md) < 1500 or not src or not all(s.get("url", "").startswith("http") for s in src):
                continue
        except Exception:
            continue
        (d / "L1.md").write_text(md + "\n", encoding="utf-8")
        sf = d / "sources.json"
        old = [s for s in json.loads(sf.read_text(encoding="utf-8")) if s["level"] != "L1"]
        sf.write_text(json.dumps(old + [{"level": "L1", "title": s["title"], "url": s["url"]} for s in src],
                                 ensure_ascii=False, indent=1), encoding="utf-8")
        meta["levels"]["L1"] = {"state": "done", "date": date.today().isoformat(), "model": "claude-haiku-5-5"}
        (d / "meta.json").write_text(json.dumps(meta, ensure_ascii=False, indent=1), encoding="utf-8")
        return env.get("total_cost_usd", 0)
    return None


def main():
    args = sys.argv[1:]
    ids = None
    if "--ids" in args:
        i = args.index("--ids")
        ids = args[i + 1].split(",")
        del args[i:i + 2]
    metas = [json.loads(p.read_text(encoding="utf-8")) for p in sorted((root / "data/subjects").glob("*/meta.json"))]
    todo = [m for m in metas if m["levels"]["L0"]["state"] != "none" and m["levels"]["L1"]["state"] == "none"
            and (ids is None or m["id"] in ids)]
    todo.sort(key=lambda m: -sum(d["kind"] == "mandatory" for d in m["degrees"]))
    if args:
        todo = todo[:int(args[0])]
    ok = cost = 0
    with ThreadPoolExecutor(4) as ex:
        for m, c in zip(todo, ex.map(run, todo)):
            ok += c is not None
            cost += c or 0
            print(f"{m['id']}: {'ok' if c is not None else 'FAILED'} (${c or 0:.3f})  total ok {ok}/{len(todo)} ${cost:.2f}", flush=True)


if __name__ == "__main__":
    main()
