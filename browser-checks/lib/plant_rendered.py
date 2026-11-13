"""
The rendered check's fixture pages (#597), planted into a course and taken
out again.

    python3 browser-checks/lib/plant_rendered.py plant  <course folder>
    python3 browser-checks/lib/plant_rendered.py remove <course folder>

`plant` copies every page in browser-checks/fixtures/rendered/ into
`<course>/Rendered Check/`, makes the three files the pages show (a GeoGebra
sketch, a one-page PDF and a small picture: the repository ships recipes,
not binaries), and adds `Rendered Check` to the course's shared folders, so
the pages and the files beside them reach every section's site. `remove`
takes all of it out again: the folder only when it carries this script's
marker, and the course's settings put back as they were when nothing else
has changed them since (otherwise only the one entry is taken out, and it
says so).

verify.sh plants into EXC2O (6h, the rendered check) and verify-deploy.sh
into the course it publishes (#597's second half), so the local check and
the deployed one read the same pages. Prints one line; no names, no paths
outside the course.
"""
from __future__ import annotations

import base64
import json
import shutil
import struct
import sys
import zipfile
import zlib
from pathlib import Path

FOLDER = "Rendered Check"
MARKER = ".plantoir-rendered-check"
PAGES = Path(__file__).resolve().parent.parent / "fixtures" / "rendered"

SKETCH_NAME = "Rendered Check Sketch.ggb"
PDF_NAME = "Rendered Check Handout.pdf"
PICTURE_NAME = "Rendered Check Picture.png"

# The sketch: two points and the segment between them, the shape
# verify.sh's GeoGebra fixture has used since #578 (GeoGebra opens it, and
# point A is what the drag and the reset rows move).
SKETCH_XML = """<?xml version="1.0" encoding="utf-8"?>
<geogebra format="5.0" version="5.4.933.1" app="classic" platform="w" id="plantoir-rendered-check-597">
<gui><font size="16"/></gui>
<euclidianView>
\t<size  width="640" height="360"/>
\t<coordSystem xZero="320" yZero="180" scale="40" yscale="40"/>
\t<evSettings axes="true" grid="true" gridIsBold="false" pointCapturing="3" rightAngleStyle="1" checkboxSize="26" gridType="3"/>
</euclidianView>
<kernel><continuous val="false"/><decimals val="2"/><angleUnit val="degree"/><coordStyle val="0"/></kernel>
<construction title="plantoir-rendered-check-sketch" author="" date="">
<element type="point" label="A"><show object="true" label="true"/><coords x="-3" y="-1" z="1"/></element>
<element type="point" label="B"><show object="true" label="true"/><coords x="3" y="2" z="1"/></element>
<command name="Segment"><input a0="A" a1="B"/><output a0="f"/></command>
<element type="segment" label="f"><show object="true" label="false"/></element>
</construction>
</geogebra>
"""

PDF_BYTES = (b"%PDF-1.4\n1 0 obj<</Type/Catalog/Pages 2 0 R>>endobj\n"
             b"2 0 obj<</Type/Pages/Kids[3 0 R]/Count 1>>endobj\n"
             b"3 0 obj<</Type/Page/Parent 2 0 R/MediaBox[0 0 612 792]>>endobj\n"
             b"trailer<</Root 1 0 R>>\n%EOF\n")


def png(width: int, height: int, colour: bytes = b"\x2e\x7d\x32") -> bytes:
    rows = b"".join(b"\x00" + colour * width for _ in range(height))

    def chunk(kind: bytes, data: bytes) -> bytes:
        return struct.pack(">I", len(data)) + kind + data + struct.pack(">I", zlib.crc32(kind + data) & 0xffffffff)

    return (b"\x89PNG\r\n\x1a\n" + chunk(b"IHDR", struct.pack(">IIBBBBB", width, height, 8, 2, 0, 0, 0))
            + chunk(b"IDAT", zlib.compress(rows, 9)) + chunk(b"IEND", b""))


def plant(course: Path) -> int:
    target = course / FOLDER
    config_path = course / "course_config.json"
    if not config_path.is_file():
        print(f"plant_rendered: {course} has no course_config.json")
        return 1
    if target.exists():
        if not (target / MARKER).is_file():
            print(f"plant_rendered: {target} already exists and is not the check's own; left alone")
            return 1
        shutil.rmtree(target)
    target.mkdir()
    pages = sorted(PAGES.glob("*.md"))
    for page in pages:
        shutil.copyfile(page, target / page.name)
    with zipfile.ZipFile(target / SKETCH_NAME, "w", zipfile.ZIP_DEFLATED) as sketch:
        sketch.writestr("geogebra.xml", SKETCH_XML)
        sketch.writestr("geogebra_thumbnail.png", png(64, 36, b"\xff\xff\xff"))
    (target / PDF_NAME).write_bytes(PDF_BYTES)
    (target / PICTURE_NAME).write_bytes(png(120, 60))
    before = config_path.read_bytes()
    config = json.loads(before.decode("utf-8"))
    shared = config.setdefault("shared_folders", [])
    added = FOLDER not in shared
    if added:
        shared.append(FOLDER)
        config_path.write_text(json.dumps(config, indent=2, ensure_ascii=False) + "\n", encoding="utf-8")
    after = config_path.read_bytes()
    (target / MARKER).write_text(json.dumps({
        "added": added,
        "configBefore": base64.b64encode(before).decode("ascii"),
        "configAfter": base64.b64encode(after).decode("ascii"),
    }), encoding="utf-8")
    print(f"plant_rendered: planted {len(pages)} pages and 3 files in {FOLDER}/"
          + (", and shared the folder" if added else ", the folder already shared"))
    return 0


def remove(course: Path) -> int:
    target = course / FOLDER
    marker = target / MARKER
    if not marker.is_file():
        print(f"plant_rendered: nothing of the check's in {FOLDER}/")
        return 0
    record = json.loads(marker.read_text(encoding="utf-8"))
    shutil.rmtree(target)
    config_path = course / "course_config.json"
    said = "settings unchanged"
    if record.get("added") and config_path.is_file():
        now = config_path.read_bytes()
        if now == base64.b64decode(record["configAfter"]):
            config_path.write_bytes(base64.b64decode(record["configBefore"]))
            said = "settings put back as they were"
        else:
            config = json.loads(now.decode("utf-8"))
            shared = config.get("shared_folders", [])
            if FOLDER in shared:
                shared.remove(FOLDER)
                config_path.write_text(json.dumps(config, indent=2, ensure_ascii=False) + "\n", encoding="utf-8")
            said = "settings changed since, so only the folder's entry was taken out"
    print(f"plant_rendered: removed {FOLDER}/ ({said})")
    return 0


def main(arguments: list[str]) -> int:
    if len(arguments) != 2 or arguments[0] not in ("plant", "remove"):
        print("usage: plant_rendered.py plant|remove <course folder>")
        return 2
    course = Path(arguments[1])
    return plant(course) if arguments[0] == "plant" else remove(course)


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
