#!/usr/bin/env python3
"""Download the bundled fonts (google/fonts, OFL) and build the icon assets from the free Hugeicons package
(@hugeicons/core-free-icons on npm, MIT) into the app.

Idempotent: fonts already present are kept; the icon catalogue is rewritten from the pinned package. Standard library only.
"""
import base64
import hashlib
import io
import json
import pathlib
import re
import shutil
import sys
import tarfile
import urllib.parse
import urllib.request

ROOT = pathlib.Path(__file__).resolve().parent.parent
FONTS = ROOT / "App" / "Resources" / "Fonts"
LICENSES = ROOT / "App" / "Resources" / "Licenses"
ICON_TABLE = ROOT / "Shared" / "Icons.swift"
CATALOG = ROOT / "Shared" / "Icons.xcassets"
ICONS = CATALOG / "Hugeicons"
CACHE = ROOT / "build"

FONT_FILES = {
    "DMSans.ttf": "ofl/dmsans/DMSans[opsz,wght].ttf",
}
FONT_LICENSES = {"OFL-DMSans.txt": "ofl/dmsans/OFL.txt"}

HUGEICONS_VERSION = "4.4.0"
HUGEICONS_INTEGRITY = "sha512-7Mz8bmGoY6tZ6l3C2TXwNMLVSr0I8HPwjjFIERAuJFj3rWwLxdF2ZLkDqdrVuEE1dx5b/VXyIsP4WoSU6Q40KQ=="
HUGEICONS_TARBALL = f"https://registry.npmjs.org/@hugeicons/core-free-icons/-/core-free-icons-{HUGEICONS_VERSION}.tgz"

STROKES = {"": "1.5", "-bold": "2"}
FILLED = {"star", "star-half"}

ELEMENT = re.compile(r'\[\s*"(\w+)",\s*\{([^}]*)\}\s*\]')
ATTRIBUTE = re.compile(r'(\w+):\s*"([^"]*)"')


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


def hugeicons_package() -> tarfile.TarFile:
    """The pinned npm tarball, checked against its registry integrity and cached under build/."""
    tarball = CACHE / f"hugeicons-core-free-icons-{HUGEICONS_VERSION}.tgz"
    data = tarball.read_bytes() if tarball.exists() else fetch(HUGEICONS_TARBALL)
    digest = "sha512-" + base64.b64encode(hashlib.sha512(data).digest()).decode()
    if digest != HUGEICONS_INTEGRITY:
        tarball.unlink(missing_ok=True)
        raise SystemExit(f"{HUGEICONS_TARBALL}: integrity mismatch")
    if not tarball.exists():
        CACHE.mkdir(exist_ok=True)
        tarball.write_bytes(data)
    return tarfile.open(fileobj=io.BytesIO(data))


def icon_names() -> list[str]:
    """The kebab-case Hugeicons names in the raw values of `IconName`."""
    return re.findall(r'^\s*case \w+ = "([a-z0-9-]+)"', ICON_TABLE.read_text(), re.MULTILINE)


def elements(package: tarfile.TarFile, name: str) -> list[tuple[str, dict[str, str]]]:
    """The SVG elements of a free icon, from `dist/esm/<Name>Icon.js` (`[["path", { d: "…", strokeWidth: "1.5", … }], …]`)."""
    component = "".join(part.capitalize() for part in name.split("-")) + "Icon"
    try:
        source = package.extractfile(f"package/dist/esm/{component}.js").read().decode()
    except KeyError:
        raise SystemExit(f"{component} is not in @hugeicons/core-free-icons {HUGEICONS_VERSION}")
    found = []
    for tag, attributes in ELEMENT.findall(source):
        pairs = {re.sub(r"[A-Z]", lambda m: "-" + m.group().lower(), key): value for key, value in ATTRIBUTE.findall(attributes) if key != "key"}
        found.append((tag, {key: "#000000" if value == "currentColor" else value for key, value in pairs.items()}))
    if not found:
        raise SystemExit(f"{component}: no SVG elements found")
    return found


def svg(shapes: list[tuple[str, dict[str, str]]], stroke: str) -> str:
    body = "".join(
        f"<{tag} " + " ".join(f'{key}="{stroke if key == "stroke-width" else value}"' for key, value in attributes.items()) + "/>"
        for tag, attributes in shapes
    )
    return f'<svg xmlns="http://www.w3.org/2000/svg" width="24" height="24" viewBox="0 0 24 24" fill="none">{body}</svg>\n'


def filled(package: tarfile.TarFile, name: str) -> list[tuple[str, dict[str, str]]]:
    """The star outline filled whole, or on its left half for `star-half` (the star path from its bottom point round the left side to its top)."""
    (tag, star), = elements(package, "star")
    if name == "star":
        return [(tag, {**star, "fill": "#000000"})]
    bottom, top = "11.9993 18.7917", "11.9999 2.5"
    path = star["d"]
    left = "M" + bottom + path[path.index(bottom) + len(bottom):path.index(top) + len(top)] + "Z"
    return [(tag, {"d": left, "fill": "#000000"}), *elements(package, "star-half")]


def write_imageset(name: str, content: str) -> None:
    imageset = ICONS / f"{name}.imageset"
    imageset.mkdir(parents=True, exist_ok=True)
    (imageset / f"{name}.svg").write_text(content)
    (imageset / "Contents.json").write_text(json.dumps({
        "images": [{"filename": f"{name}.svg", "idiom": "universal"}],
        "info": {"author": "xcode", "version": 1},
        "properties": {"preserves-vector-representation": True, "template-rendering-intent": "template"},
    }, indent=2) + "\n")


def build_icons() -> None:
    package = hugeicons_package()
    names = icon_names()
    if not names:
        raise SystemExit(f"no icon names in {ICON_TABLE.relative_to(ROOT)}")
    wanted = set()
    for name in names:
        shapes = elements(package, name)
        for suffix, stroke in STROKES.items():
            write_imageset(name + suffix, svg(shapes, stroke))
            wanted.add(name + suffix)
        if name in FILLED:
            write_imageset(name + "-fill", svg(filled(package, name), STROKES[""]))
            wanted.add(name + "-fill")
    for stale in ICONS.glob("*.imageset"):
        if stale.name.removesuffix(".imageset") not in wanted:
            shutil.rmtree(stale)
    (ICONS / "Contents.json").write_text(json.dumps({"info": {"author": "xcode", "version": 1}, "properties": {"provides-namespace": True}}, indent=2) + "\n")
    (CATALOG / "Contents.json").write_text(json.dumps({"info": {"author": "xcode", "version": 1}}, indent=2) + "\n")
    (LICENSES / "Hugeicons-LICENSE.txt").write_bytes(package.extractfile("package/LICENSE.md").read())


def main() -> int:
    for name, path in FONT_FILES.items():
        save(FONTS / name, google(path))
    for name, path in FONT_LICENSES.items():
        save(LICENSES / name, google(path))
    build_icons()
    return 0


if __name__ == "__main__":
    sys.exit(main())
