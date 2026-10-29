#!/usr/bin/env python3
import hashlib
import io
import pathlib
import sys
import urllib.request

from fontTools import subset
from fontTools.ttLib import TTFont
from fontTools.ttLib.tables._g_l_y_f import Glyph

ROOT = pathlib.Path(__file__).resolve().parent.parent
FONTS = ROOT / "App" / "Resources" / "Fonts"
TARGET = FONTS / "VelovGlyphic-Regular.ttf"
TIMER = FONTS / "VelovGlyphicTimer-Regular.ttf"
LICENSE = ROOT / "App" / "Resources" / "Licenses" / "OFL-VelovGlyphic.txt"
SOURCE = "https://raw.githubusercontent.com/google/fonts/9a17b498ba9b7ec6220b1b9fe0bb07c0a25ac22c/ofl/facultyglyphic/"
FILES = {
    "FacultyGlyphic-Regular.ttf": "27010aebf4430da073b75b8877bc3d3e35bd24d2e4f9403d34418abe94c3d31f",
    "OFL.txt": "5a6185c9e0232792afbef890406b569471ceda95e59d1999b602a8047d54be64",
}
NAMES = {1: "Velov Glyphic", 3: "1.004;NONE;VelovGlyphic-Regular", 4: "Velov Glyphic Regular", 6: "VelovGlyphic-Regular"}
TIMER_NAMES = {1: "Velov Glyphic Timer", 3: "1.004;NONE;VelovGlyphicTimer-Regular", 4: "Velov Glyphic Timer Regular",
               6: "VelovGlyphicTimer-Regular"}
NARROW_SPACES = {0x202F: "uni202F", 0x00A0: "uni00A0"}
NARROW_SPACE_WIDTH = 0.26
NOTICE = ("Velov Glyphic is a modified version of Faculty Glyphic: the tabular one keeps the proportional one's spacing "
          "and a narrow no-break space (U+202F) is added. It is not the Original Version and does not use its name.\n\n")


def fetch(name: str) -> bytes:
    request = urllib.request.Request(SOURCE + name, headers={"User-Agent": "velov-ios-assets"})
    with urllib.request.urlopen(request, timeout=60) as response:
        data = response.read()
    if hashlib.sha256(data).hexdigest() != FILES[name]:
        raise SystemExit(f"{name}: checksum mismatch")
    return data


def tighten_tabular_one(font: TTFont) -> None:
    for component in font["glyf"]["one.tf"].components:
        component.x = 0
    font["hmtx"]["one.tf"] = font["hmtx"]["one"]


def add_narrow_spaces(font: TTFont) -> None:
    width = round(NARROW_SPACE_WIDTH * font["head"].unitsPerEm)
    for codepoint, name in NARROW_SPACES.items():
        if codepoint in font.getBestCmap():
            continue
        order = font.getGlyphOrder()
        font["glyf"][name] = Glyph()
        font["hmtx"][name] = (width, 0)
        if name not in order:
            font.setGlyphOrder(order + [name])
        for table in font["cmap"].tables:
            if table.isUnicode():
                table.cmap[codepoint] = name


def rename(font: TTFont, names: dict[int, str]) -> None:
    for record in font["name"].names:
        if record.nameID in names:
            record.string = names[record.nameID]


def derive(source: bytes) -> TTFont:
    font = TTFont(io.BytesIO(source), recalcTimestamp=False)
    tighten_tabular_one(font)
    add_narrow_spaces(font)
    rename(font, NAMES)
    return font


def features(font: TTFont) -> set[str]:
    return {record.FeatureTag for table in ("GSUB", "GPOS") if table in font for record in font[table].table.FeatureList.FeatureRecord}


def without_tabular_figures(font: TTFont) -> TTFont:
    options = subset.Options()
    options.glyph_names = True
    options.name_IDs = ["*"]
    options.name_languages = ["*"]
    options.name_legacy = True
    options.notdef_outline = True
    options.layout_features = sorted(features(font) - {"tnum"})
    subsetter = subset.Subsetter(options)
    subsetter.populate(glyphs=font.getGlyphOrder())
    subsetter.subset(font)
    rename(font, TIMER_NAMES)
    return font


def main() -> int:
    FONTS.mkdir(parents=True, exist_ok=True)
    LICENSE.parent.mkdir(parents=True, exist_ok=True)
    source = fetch("FacultyGlyphic-Regular.ttf")
    derive(source).save(TARGET)
    without_tabular_figures(derive(source)).save(TIMER)
    LICENSE.write_text(NOTICE + fetch("OFL.txt").decode())
    for path in (TARGET, TIMER, LICENSE):
        print(path.relative_to(ROOT))
    return 0


if __name__ == "__main__":
    sys.exit(main())
