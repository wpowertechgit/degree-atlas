"""One-shot setup after `git clone`: Python deps, Flutter app build, local folders, validation.

  python scripts/setup.py                     # everything
  python scripts/setup.py --no-app            # skip the Flutter build (agent workflow only)
  python scripts/setup.py --install-flutter   # clone the Flutter stable SDK into ~/flutter if none is found
"""
import argparse
import os
import platform
import shutil
import subprocess
import sys
from pathlib import Path

repo = Path(__file__).resolve().parent.parent
ap = argparse.ArgumentParser()
ap.add_argument("--no-app", action="store_true")
ap.add_argument("--install-flutter", action="store_true")
args = ap.parse_args()
windows = platform.system() == "Windows"
problems = []


def step(msg):
    print(f"\n== {msg}")


def run(cmd, cwd=repo, **kw):
    print("$", " ".join(map(str, cmd)))
    return subprocess.run(cmd, cwd=cwd, shell=windows and cmd[0] == "flutter", **kw).returncode == 0


def find_flutter():
    found = shutil.which("flutter")
    if found:
        return found
    exe = "flutter.bat" if windows else "flutter"
    for base in [Path("C:/src/flutter"), Path.home() / "flutter", Path.home() / "development/flutter", Path("/opt/flutter")]:
        if (base / "bin" / exe).exists():
            return str(base / "bin" / exe)
    return None


step("Python dependencies")
if sys.version_info < (3, 10):
    problems.append("Python 3.10 or newer is required")
elif not run([sys.executable, "-m", "pip", "install", "-q", "-r", "requirements.txt"]):
    problems.append("pip install failed")

step("Agent CLI")
agents = [n for n in ("claude", "codex") if shutil.which(n) or (n == "claude" and (Path.home() / ".local/bin" / ("claude.exe" if windows else "claude")).exists())]
print("found:", ", ".join(agents) or "none")
if not agents:
    problems.append("install Claude Code (https://claude.com/claude-code) or Codex; the in-app agent panel needs `claude`")

step("Local folders")
for d in ("work", "profiles"):
    (repo / d).mkdir(exist_ok=True)
print("work/ and profiles/ ready")

if not args.no_app:
    step("Flutter app")
    flutter = find_flutter()
    if not flutter and args.install_flutter and shutil.which("git"):
        target = Path.home() / "flutter"
        if run(["git", "clone", "--depth", "1", "-b", "stable", "https://github.com/flutter/flutter.git", str(target)]):
            flutter = find_flutter()
    if not flutter:
        problems.append("Flutter SDK not found. Install it (https://docs.flutter.dev/get-started/install) or rerun with --install-flutter")
    else:
        os.environ["PATH"] = str(Path(flutter).parent) + os.pathsep + os.environ["PATH"]
        target = {"Windows": "windows", "Darwin": "macos"}.get(platform.system(), "linux")
        app = repo / "app"
        if run(["flutter", "pub", "get"], cwd=app) and run(["flutter", "build", target, "--release"], cwd=app):
            print(f"built app/build/{target}")
        else:
            problems.append(f"Flutter build failed. Run `flutter doctor -v` in app/ and fix what it reports (on Windows: Visual Studio with the C++ desktop workload)")

step("Validate data")
if not run([sys.executable, "scripts/validate.py"]):
    problems.append("validate.py reported errors")

print("\n== Result")
if problems:
    print("Needs attention:")
    for p in problems:
        print(" -", p)
    sys.exit(1)
print("Setup complete. Start the app with launch.bat (Windows) or the built binary under app/build/.")
print("In the app: create an empty profile from the folder menu, open the Agent panel and say what you want to learn.")
