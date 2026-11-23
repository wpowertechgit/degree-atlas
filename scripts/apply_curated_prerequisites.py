"""Apply curated prerequisite links from the resumable curation file."""
import json
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent


def load(path):
    return json.loads(path.read_text(encoding="utf-8"))


def main():
    curated_path = ROOT / "data/curated_prerequisites.json"
    curated = load(curated_path) if curated_path.exists() else {}
    metas = {p.parent.name: load(p) for p in (ROOT / "data/subjects").glob("*/meta.json")}
    for sid, prereqs in curated.items():
        if sid not in metas:
            raise SystemExit(f"unknown subject: {sid}")
        unknown = set(prereqs) - metas.keys()
        if unknown:
            raise SystemExit(f"unknown prerequisites for {sid}: {sorted(unknown)}")
        if sid in prereqs:
            raise SystemExit(f"self prerequisite: {sid}")

    # Validate the combined graph before writing any metadata.
    graph = {sid: set(meta.get("prerequisites", [])) | set(curated.get(sid, []))
             for sid, meta in metas.items()}
    state = {}

    def visit(sid):
        if state.get(sid) == 1:
            raise SystemExit(f"prerequisite cycle through {sid}")
        if state.get(sid) == 2:
            return
        state[sid] = 1
        for prerequisite in graph[sid]:
            visit(prerequisite)
        state[sid] = 2

    for sid in graph:
        visit(sid)

    reduced = {}
    for sid, prerequisites in graph.items():
        direct = set()
        for candidate in sorted(prerequisites):
            pending = list(prerequisites - {candidate})
            seen = set()
            redundant = False
            while pending:
                current = pending.pop()
                if current == candidate:
                    redundant = True
                    break
                if current not in seen:
                    seen.add(current)
                    pending.extend(graph[current])
            if not redundant:
                direct.add(candidate)
        if len(direct) > 5:
            raise SystemExit(f"more than five direct prerequisites for {sid}")
        reduced[sid] = sorted(direct)

    for sid, prerequisites in reduced.items():
        path = ROOT / "data/subjects" / sid / "meta.json"
        meta = metas[sid]
        meta["prerequisites"] = prerequisites
        path.write_text(json.dumps(meta, ensure_ascii=False, indent=1) + "\n", encoding="utf-8")


if __name__ == "__main__":
    main()
