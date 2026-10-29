#!/usr/bin/env python3
"""Download the bundled fonts (google/fonts, OFL) and Phosphor icons (phosphor-icons/core, MIT) into the app.

Idempotent: files already present are kept. Standard library only.
"""
import json
import pathlib
import sys
import urllib.parse
import urllib.request

ROOT = pathlib.Path(__file__).resolve().parent.parent
FONTS = ROOT / "App" / "Resources" / "Fonts"
ICONS = ROOT / "App" / "Resources" / "Assets.xcassets" / "Phosphor"
LICENSES = ROOT / "App" / "Resources" / "Licenses"

FONT_FILES = {
    "FacultyGlyphic-Regular.ttf": "ofl/facultyglyphic/FacultyGlyphic-Regular.ttf",
    "DMSans.ttf": "ofl/dmsans/DMSans[opsz,wght].ttf",
    "AzeretMono.ttf": "ofl/azeretmono/AzeretMono[wght].ttf",
}
FONT_LICENSES = {"OFL-FacultyGlyphic.txt": "ofl/facultyglyphic/OFL.txt", "OFL-DMSans.txt": "ofl/dmsans/OFL.txt", "OFL-AzeretMono.txt": "ofl/azeretmono/OFL.txt"}

# Phosphor names used by the web app, with the weights it draws them in.
ICON_WEIGHTS = {
    "house": ["light"], "person-simple-bike": ["light", "bold"], "star-four": ["light", "bold"], "map-pin": ["light"],
    "user-circle": ["light"], "sign-out": ["light", "regular"], "arrow-clockwise": ["light"], "warning-circle": ["light"],
    "x": ["light", "bold"], "lightning": ["light", "bold"], "letter-circle-p": ["light"], "caret-right": ["light", "bold"],
    "caret-down": ["light", "bold"], "magnifying-glass": ["light"], "navigation-arrow": ["light"], "timer": ["light"],
    "star": ["light", "fill"], "star-half": ["fill"], "ticket": ["bold"], "trend-up": ["bold"], "arrow-right": ["bold"],
    "arrow-up-right": ["bold"], "arrow-left": ["light"], "check": ["bold"], "spinner-gap": ["regular"], "copy": ["light"],
    "thumbs-up": ["light", "bold", "fill"], "thumbs-down": ["light"], "battery-empty": ["light"], "battery-full": ["light"],
    "battery-high": ["light"], "battery-low": ["light"], "battery-medium": ["light"], "warning": ["bold", "fill"],
    "clock": ["bold"], "lock-open": ["light", "bold"], "download-simple": ["light"], "envelope-simple": ["light"],
}


def fetch(url: str) -> bytes:
    request = urllib.request.Request(url, headers={"User-Agent": "velov-ios-assets"})
    with urllib.request.urlopen(request, timeout=60) as response:
        return response.read()


def save(path: pathlib.Path, url: str) -> None:
    if path.exists() and path.stat().st_size > 0:
        return
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_bytes(fetch(url))
    print(f"fetched {path.relative_to(ROOT)}")


def google(path: str) -> str:
    return "https://raw.githubusercontent.com/google/fonts/main/" + urllib.parse.quote(path)


def main() -> int:
    for name, path in FONT_FILES.items():
        save(FONTS / name, google(path))
    for name, path in FONT_LICENSES.items():
        save(LICENSES / name, google(path))
    save(LICENSES / "Phosphor-LICENSE.txt", "https://raw.githubusercontent.com/phosphor-icons/core/main/LICENSE")

    ICONS.mkdir(parents=True, exist_ok=True)
    (ICONS / "Contents.json").write_text(json.dumps({"info": {"author": "xcode", "version": 1}, "properties": {"provides-namespace": True}}, indent=2))
    for icon, weights in ICON_WEIGHTS.items():
        for weight in weights:
            file = f"{icon}.svg" if weight == "regular" else f"{icon}-{weight}.svg"
            imageset = ICONS / f"{icon}-{weight}.imageset"
            save(imageset / file, f"https://raw.githubusercontent.com/phosphor-icons/core/main/assets/{weight}/{file}")
            (imageset / "Contents.json").write_text(json.dumps({
                "images": [{"filename": file, "idiom": "universal"}],
                "info": {"author": "xcode", "version": 1},
                "properties": {"preserves-vector-representation": True, "template-rendering-intent": "template"},
            }, indent=2))
    catalog = ICONS.parent / "Contents.json"
    if not catalog.exists():
        catalog.write_text(json.dumps({"info": {"author": "xcode", "version": 1}}, indent=2))
    return 0


if __name__ == "__main__":
    sys.exit(main())
