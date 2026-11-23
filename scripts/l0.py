"""Generate L0 for every subject that lacks it (Haiku, batched, resumable).

  python scripts/l0.py [limit]
"""
import json
import re
import subprocess
import sys
from concurrent.futures import ThreadPoolExecutor
from datetime import date
from pathlib import Path

root = Path(__file__).resolve().parent.parent
BATCH, WORKERS = 6, 6
PROMPT = """You write L0 ("explain like I'm five") study notes for university subjects.
For EACH subject below write about one page (150-250 words) of Markdown: the concept, the main methods, and the lessons, in plain language a curious outsider understands. Start with a "# <title> (L0)" heading. Use only what the course descriptions support; do not invent specifics. LaTeX ($...$) only if a formula really helps. No practice questions.
Reply with ONLY a JSON object mapping subject id to its Markdown string.

{body}"""


def run(batch):
    body = "\n\n".join(
        f"### {m['id']}\nTitle: {m['title']}\nDescriptions:\n" +
        "\n".join(f"- ({a['university']} {a.get('code', '')}) {a['name']}" for a in m["aliases"]) +
        f"\nSummary: {m['summary']}" for m in batch)
    for _ in range(2):
        r = subprocess.run(["claude", "-p", "--model", "haiku", "--tools", "", "--no-session-persistence"],
                           input=PROMPT.format(body=body), capture_output=True, text=True, encoding="utf-8")
        try:
            res = json.loads(re.search(r"\{.*\}", r.stdout, re.S).group(0))
        except Exception:
            continue
        ok = 0
        for m in batch:
            md = res.get(m["id"])
            if not isinstance(md, str) or len(md) < 200:
                continue
            d = root / "data/subjects" / m["id"]
            (d / "L0.md").write_text(md.strip() + "\n", encoding="utf-8")
            m["levels"]["L0"] = {"state": "done", "date": date.today().isoformat(), "model": "claude-haiku-5-5"}
            (d / "meta.json").write_text(json.dumps(m, ensure_ascii=False, indent=1), encoding="utf-8")
            ok += 1
        if ok:
            return ok
    return 0


def main():
    metas = [json.loads(p.read_text(encoding="utf-8")) for p in sorted((root / "data/subjects").glob("*/meta.json"))]
    todo = [m for m in metas if m["levels"]["L0"]["state"] == "none"]
    if len(sys.argv) > 1:
        todo = todo[:int(sys.argv[1])]
    batches = [todo[i:i + BATCH] for i in range(0, len(todo), BATCH)]
    total = 0
    with ThreadPoolExecutor(WORKERS) as ex:
        for n in ex.map(run, batches):
            total += n
            print(f"L0 written: {total}/{len(todo)}", flush=True)


if __name__ == "__main__":
    main()
