"""Check that requirement claims in data/universities/*.json are backed by study-plan pages the agent really fetched.

  python scripts/check_plan.py

Workflow it enforces (offline, no network): the agent saves each study-plan page it read as text in
work/pages/<name>.txt, first line `URL: <the page url>`, then the page text. Every course with a
`requirement` must carry `requirement.quote`, the exact text of the plan that names the course, and:
  - `requirement.source` equals the URL of a cached page,
  - the quote occurs in that page's text (whitespace and case ignored),
  - the course code or title occurs in the quote.
In a profile (DEGREE_ATLAS_PROFILE set) a requirement without a quote is an error; in the repository's own
data set old entries without a quote are tolerated. Exit 1 on any error.
"""
import json
import os
import re
import sys
from pathlib import Path

repo = Path(__file__).resolve().parent.parent
root = Path(os.environ.get("DEGREE_ATLAS_PROFILE") or repo)


def norm(s: str) -> str:
    return re.sub(r"\s+", " ", s.replace(" ", " ").replace("​", "")).strip().casefold()


def cached_pages() -> dict[str, str]:
    pages = {}
    for f in (root / "work" / "pages").glob("*.txt"):
        head, _, body = f.read_text(encoding="utf-8", errors="replace").partition("\n")
        if head.startswith("URL:"):
            url = head[4:].strip()
            pages[url] = pages.get(url, "") + " " + norm(body)
    return pages


def check(strict: bool) -> list[str]:
    errors, pages = [], cached_pages()
    for f in sorted((root / "data" / "universities").glob("*.json")):
        uni = json.loads(f.read_text(encoding="utf-8"))
        for degree in uni.get("degrees", []):
            for c in degree.get("courses", []):
                req = c.get("requirement")
                if not req:
                    continue
                where = f"{f.name}: {degree['name']}: {c.get('code')}"
                quote = req.get("quote")
                if not quote:
                    if strict:
                        errors.append(f"{where}: requirement needs a quote copied from the study plan")
                    continue
                text = pages.get(req["source"])
                if text is None:
                    errors.append(f"{where}: no cached page for {req['source']} (save it as work/pages/<name>.txt with first line 'URL: ...')")
                elif norm(quote) not in text:
                    errors.append(f"{where}: quote not found in the cached plan page")
                if norm(str(c.get("code", ""))) not in norm(quote) and norm(c.get("title", "")) not in norm(quote):
                    errors.append(f"{where}: quote names neither the course code nor its title")
    return errors


if __name__ == "__main__":
    problems = check(strict=root != repo)
    print("\n".join(problems) or "OK")
    sys.exit(bool(problems))
