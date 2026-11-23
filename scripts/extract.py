"""Extract plain text from course materials so an agent can read them without special tools.

  python scripts/extract.py materials/<course>

Writes one UTF-8 text file per source file to work/materials/<course>/ (inside the active profile).
Handles docx, pptx, xlsx, odt, odp (standard library only), md, txt, tex, csv and html. PDFs use
`pdftotext` when it is installed; otherwise they are listed so the agent reads them directly
(PDF and image files can be read page by page with the agent's own file reader).
"""
import os
import re
import shutil
import subprocess
import sys
import zipfile
from html.parser import HTMLParser
from pathlib import Path
from xml.etree import ElementTree as ET

repo = Path(__file__).resolve().parent.parent
root = Path(os.environ.get("DEGREE_ATLAS_PROFILE") or repo)

PLAIN = {".md", ".txt", ".tex", ".csv", ".json", ".py", ".c", ".cpp", ".java", ".m"}


def xml_text(data: bytes, para_tags: tuple[str, ...]) -> str:
    """Text of all <...:t> runs, with a line break after each paragraph-like element."""
    out = []
    for _, el in ET.iterparse(__import__("io").BytesIO(data)):
        tag = el.tag.rsplit("}", 1)[-1]
        if tag in ("t", "text"):
            out.append(el.text or "")
        elif tag in para_tags:
            out.append("\n")
    return re.sub(r"\n{3,}", "\n\n", "".join(out))


def office(path: Path) -> str:
    ext = path.suffix.lower()
    with zipfile.ZipFile(path) as z:
        names = z.namelist()
        if ext == ".docx":
            return xml_text(z.read("word/document.xml"), ("p", "br"))
        if ext == ".pptx":
            slides = sorted((n for n in names if re.fullmatch(r"ppt/slides/slide\d+\.xml", n)), key=lambda n: int(re.findall(r"\d+", n)[-1]))
            return "\n".join(f"--- slide {i} ---\n" + xml_text(z.read(n), ("p",)) for i, n in enumerate(slides, 1))
        if ext == ".xlsx":
            strings = []
            if "xl/sharedStrings.xml" in names:
                strings = [t for t in xml_text(z.read("xl/sharedStrings.xml"), ("si",)).split("\n") if t]
            return "\n".join(strings)
        if ext in (".odt", ".odp"):
            return xml_text(z.read("content.xml"), ("p", "h"))
    return ""


class _Html(HTMLParser):
    def __init__(self):
        super().__init__()
        self.parts, self.skip = [], 0

    def handle_starttag(self, tag, attrs):
        self.skip += tag in ("script", "style")
        if tag in ("p", "br", "li", "h1", "h2", "h3", "tr"):
            self.parts.append("\n")

    def handle_endtag(self, tag):
        self.skip -= tag in ("script", "style")

    def handle_data(self, data):
        if not self.skip:
            self.parts.append(data)


def html(path: Path) -> str:
    p = _Html()
    p.feed(path.read_text(encoding="utf-8", errors="replace"))
    return re.sub(r"\n{3,}", "\n\n", "".join(p.parts))


def extract(path: Path) -> str | None:
    ext = path.suffix.lower()
    if ext in PLAIN:
        return path.read_text(encoding="utf-8", errors="replace")
    if ext in (".docx", ".pptx", ".xlsx", ".odt", ".odp"):
        return office(path)
    if ext in (".html", ".htm"):
        return html(path)
    if ext == ".pdf" and shutil.which("pdftotext"):
        r = subprocess.run(["pdftotext", "-layout", str(path), "-"], capture_output=True, text=True, encoding="utf-8", errors="replace")
        return r.stdout if r.returncode == 0 and r.stdout.strip() else None  # empty means a scanned PDF
    return None


def main():
    if len(sys.argv) != 2:
        sys.exit(__doc__)
    src = (root / sys.argv[1]).resolve()
    if not src.is_dir() or root.resolve() not in src.parents:
        sys.exit(f"{sys.argv[1]} is not a folder inside {root}")
    out_dir = root / "work" / "materials" / src.name
    out_dir.mkdir(parents=True, exist_ok=True)
    unread = []
    for f in sorted(p for p in src.rglob("*") if p.is_file() and p.name != "index.json"):
        rel = f.relative_to(src)
        try:
            text = extract(f)
        except (zipfile.BadZipFile, ET.ParseError, KeyError) as e:
            text = None
        if text and text.strip():
            target = out_dir / (str(rel).replace(os.sep, "__") + ".txt")
            target.write_text(text, encoding="utf-8")
            print(f"text  {rel} -> {target.relative_to(root)} ({len(text.split())} words)")
        else:
            unread.append(str(rel))
    for r in unread:
        print(f"read directly  {r}")


if __name__ == "__main__":
    main()
