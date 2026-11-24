"""One-shot setup after `git clone`: Python deps, Flutter app build, local folders, validation.

  python scripts/setup.py                     # everything; on Windows downloads the prebuilt app
  python scripts/setup.py --no-app            # skip the app (agent workflow only)
  python scripts/setup.py --build-app         # build the app from source (Flutter + Visual Studio C++ on Windows)
  python scripts/setup.py --build-app --install-flutter   # also clone the Flutter SDK into ~/flutter if none is found
"""
import argparse
import os
import platform
import shutil
import json
import subprocess
import sys
import urllib.request
import zipfile
from pathlib import Path

repo = Path(__file__).resolve().parent.parent
ap = argparse.ArgumentParser()
ap.add_argument("--no-app", action="store_true")
ap.add_argument("--install-flutter", action="store_true")
ap.add_argument("--build-app", action="store_true", help="build the app from source instead of downloading the Windows release")
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

def download_release():
    """Fetch the prebuilt Windows app from the latest GitHub release. Returns True on success."""
    api = "https://api.github.com/repos/wpowertechgit/degree-atlas/releases/latest"
    try:
        with urllib.request.urlopen(api, timeout=30) as r:
            assets = json.load(r)["assets"]
        url = next(a["browser_download_url"] for a in assets if a["name"] == "degree-atlas-windows.zip")
        out = repo / "app/build/windows/x64/runner/Release"
        out.mkdir(parents=True, exist_ok=True)
        zpath = out / "_download.zip"
        print("downloading", url)
        try:
            urllib.request.urlretrieve(url, zpath)
            with zipfile.ZipFile(zpath) as z:
                z.extractall(out)
        finally:
            zpath.unlink(missing_ok=True)
        return (out / "degree_atlas.exe").exists()
    except PermissionError:
        print("a file is in use: close Degree Atlas and rerun setup")
        return False
    except Exception as e:  # network, no release yet, bad zip
        print("release download failed:", e)
        return False


if not args.no_app and windows and not args.build_app:
    step("Prebuilt app")
    if download_release():
        print("app ready (prebuilt release)")
    else:
        problems.append("could not download the prebuilt app; get it from https://github.com/wpowertechgit/degree-atlas/releases or rerun with --build-app (needs Flutter and Visual Studio C++)")
elif not args.no_app:
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
