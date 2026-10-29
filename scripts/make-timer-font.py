#!/usr/bin/env python3
import pathlib
import sys

from fontTools import subset
from fontTools.ttLib import TTFont

FONTS = pathlib.Path(__file__).resolve().parent.parent / "App" / "Resources" / "Fonts"
SOURCE = FONTS / "FacultyGlyphic-Regular.ttf"
TARGET = FONTS / "FacultyGlyphicTimer-Regular.ttf"
NAMES = {1: "Faculty Glyphic Timer", 3: "FacultyGlyphicTimer-Regular", 4: "Faculty Glyphic Timer Regular",
         6: "FacultyGlyphicTimer-Regular", 16: "Faculty Glyphic Timer"}


def features(font: TTFont) -> set[str]:
    return {record.FeatureTag for table in ("GSUB", "GPOS") if table in font for record in font[table].table.FeatureList.FeatureRecord}


def main() -> int:
    font = TTFont(SOURCE)
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
    for record in font["name"].names:
        if record.nameID in NAMES:
            record.string = NAMES[record.nameID]
    font.save(TARGET)
    print(TARGET.name, sorted(features(font)))
    return 0


if __name__ == "__main__":
    sys.exit(main())
