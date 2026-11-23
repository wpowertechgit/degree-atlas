"""Export launcher icons from the ΔA SVG. Requires Inkscape and Pillow."""

from pathlib import Path
from shutil import which
import subprocess
import tempfile
import xml.etree.ElementTree as ET

from PIL import Image


APP = Path(__file__).resolve().parents[1] / "app"
BRAND = APP / "assets" / "brand"
ANDROID = APP / "android" / "app" / "src" / "main" / "res"
BINDER = "#732F36"
PAPER = "#FFFBF0"
DENSITIES = {"mdpi": 48, "hdpi": 72, "xhdpi": 96, "xxhdpi": 144, "xxxhdpi": 192}
ICO_SIZES = (16, 20, 24, 32, 40, 48, 64, 128, 256)
ANDROID_NS = "http://schemas.android.com/apk/res/android"
SVG_NS = "http://www.w3.org/2000/svg"


def make_launcher_svg(paths):
    outlines = "\n".join(f'    <path fill-rule="evenodd" d="{d}"/>' for d in paths)
    return f"""<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 128 128">
  <title>Degree Atlas launcher icon</title>
  <rect x="2" y="2" width="124" height="124" rx="27" fill="{BINDER}"/>
  <g transform="translate(18 27) scale(.64)" fill="{PAPER}">
{outlines}
  </g>
</svg>
"""


def write_adaptive_icon(paths):
    drawable = ANDROID / "drawable" / "ic_launcher_foreground.xml"
    outlines = "\n".join(
        f'        <path android:fillColor="{PAPER}" android:fillType="evenOdd"\n'
        f'            android:pathData="{d}" />'
        for d in paths
    )
    drawable.write_text(
        f"""<?xml version="1.0" encoding="utf-8"?>
<vector xmlns:android="{ANDROID_NS}"
    android:width="108dp" android:height="108dp"
    android:viewportWidth="108" android:viewportHeight="108">
    <group android:scaleX="0.42" android:scaleY="0.42"
        android:translateX="24" android:translateY="30">
{outlines}
    </group>
</vector>
""",
        encoding="utf-8",
    )
    values = ANDROID / "values" / "launcher_colors.xml"
    values.write_text(
        f"""<?xml version="1.0" encoding="utf-8"?>
<resources>
    <color name="launcher_background">{BINDER}</color>
</resources>
""",
        encoding="utf-8",
    )
    adaptive = ANDROID / "mipmap-anydpi-v26"
    adaptive.mkdir(exist_ok=True)
    (adaptive / "ic_launcher.xml").write_text(
        f"""<?xml version="1.0" encoding="utf-8"?>
<adaptive-icon xmlns:android="{ANDROID_NS}">
    <background android:drawable="@color/launcher_background" />
    <foreground android:drawable="@drawable/ic_launcher_foreground" />
</adaptive-icon>
""",
        encoding="utf-8",
    )


def main():
    inkscape = which("inkscape.com") or which("inkscape")
    if inkscape is None:
        raise SystemExit("Install Inkscape and put it on PATH to export launcher icons.")
    mark = ET.parse(BRAND / "degree-atlas.svg")
    paths = [path.attrib["d"] for path in mark.findall(f".//{{{SVG_NS}}}path")]
    if not paths:
        raise SystemExit("The ΔA SVG must contain outline paths.")
    source = BRAND / "launcher.svg"
    source.write_text(make_launcher_svg(paths), encoding="utf-8")
    with tempfile.TemporaryDirectory() as scratch:
        render = Path(scratch) / "launcher.png"
        subprocess.run(
            [inkscape, str(source), "--export-width=512", f"--export-filename={render}"],
            check=True,
        )
        with Image.open(render) as png:
            icon = png.convert("RGBA")
            icon.save(
                APP / "windows" / "runner" / "resources" / "app_icon.ico",
                sizes=[(size, size) for size in ICO_SIZES],
            )
            for density, size in DENSITIES.items():
                icon.resize((size, size), Image.Resampling.LANCZOS).save(
                    ANDROID / f"mipmap-{density}" / "ic_launcher.png"
                )
    write_adaptive_icon(paths)


if __name__ == "__main__":
    main()
