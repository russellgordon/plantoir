#!/usr/bin/env python3
"""
The picture-size reader, run against Pillow (#612).

NOT named `test_*.py` on purpose, like `check_figure_rules_against_the_site.py`:
it needs the image's Node and Pillow, so it can only run inside the
container (Windows' `PythonToolchainTests` discovers every
`scripts/test_*.py`). `verify.sh` runs it in the image, with the corpus
mounted beside it.

`support/quartz/plugins/transformers/pictureSizes.js` - the file the site's
transformer imports - reads every picture in `scripts/fixtures/picture-sizes/`
in Node, and:

1. every picture Pillow can open is answered with exactly Pillow's
   `ImageOps.exif_transpose(picture).size` (the size a browser draws, EXIF
   orientation applied), and every file Pillow cannot decode with null;
2. the files named `named-*` - SVGs, which Pillow cannot read, and the
   pictures where the engines disagree, so the reader must say null even
   though Pillow has an answer - are answered exactly as NAMED says;
3. every answer is the same when the first read is only 16 bytes, so the
   build's read-the-start-first shortcut can never change a size;
4. every `sizedAttributes` case in ATTRIBUTE_CASES - the attribute rule,
   including a raw <img> the build must leave alone (review S1);
5. the transformer itself (plantoirPictureSizes.ts, bundled with Quartz's
   esbuild) over a page of three pictures, with the reader replaced by one
   that THROWS for one of them: the page is still transformed, that picture
   is left exactly as Quartz wrote it, and the other two are sized
   (implementation review F1 - a size is an improvement, never a reason for
   a build to fail).

The corpus is committed (scripts/fixtures/make_picture_sizes_corpus.py is
how it was drawn). The count of each kind is printed and checked against a
floor, so an empty or half-mounted corpus cannot pass.
"""
import json
import math
import shutil
import subprocess
import sys
import tempfile
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))

import toolchain_paths  # noqa: E402
from PIL import Image, ImageOps  # noqa: E402

READER_JS = toolchain_paths.SUPPORT_DIR / "quartz" / "plugins" / "transformers" / "pictureSizes.js"
TRANSFORMER_TS = toolchain_paths.SUPPORT_DIR / "quartz" / "plugins" / "transformers" / "plantoirPictureSizes.ts"
QUARTZ_PATH_TS = toolchain_paths.QUARTZ_DIR / "quartz" / "util" / "path.ts"
NODE_MODULES = toolchain_paths.QUARTZ_DIR / "node_modules"
CORPUS = Path(__file__).resolve().parent / "fixtures" / "picture-sizes"

# Asked of nobody but this list: [width, height], {"ratio": height / width},
# or None (leave the tag as Quartz wrote it).
NAMED = {
    "named-webp-exif-o6.webp": None,        # WebKit rotates it, Chromium does not (review S2)
    "named-gif-frame-smaller.gif": None,    # the engines draw it at different sizes (review N2)
    "named-tiff.tif": None,                 # Chromium cannot draw a TIFF
    "named-svg-px.svg": [300, 150],
    "named-svg-unitless.svg": [320, 160],
    "named-svg-cm.svg": [8 * 96 / 2.54, 4 * 96 / 2.54],
    "named-svg-inch-and-pt.svg": [192, 96],
    "named-svg-fraction.svg": [300.6, 150.4],
    "named-svg-viewbox-only.svg": {"ratio": 2},
    "named-svg-percent.svg": None,
    "named-svg-em.svg": None,
    "named-svg-width-only.svg": None,
    "named-svg-comment-first.svg": [300, 150],  # not the <svg> inside the comment (review S4)
    "named-svg-upper-case.svg": {"ratio": 1},   # WIDTH/HEIGHT are not width/height to a browser (S4)
    "named-svg-prolog-doctype.svg": [300, 150],
    "named-svg-bom.svg": [300, 150],
    "named-svg-prefixed.svg": [300, 150],
    "named-svg-single-quotes.svg": [200, 50],
    "named-svg-not-svg.svg": None,
}

# The attribute rule (pictureSizes.js sizedAttributes): hast properties as
# Quartz or rehype-raw leaves them, a size as the reader answers, and what
# the build writes (None: nothing).
WIDE = {"width": 900, "height": 300}
ATTRIBUTE_CASES = [
    ({"width": "auto", "height": "auto"}, WIDE, {"width": 900, "height": 300}),
    ({}, WIDE, {"width": 900, "height": 300}),
    ({"width": "600", "height": "auto"}, WIDE, {"width": 600, "height": 200}),
    ({"width": 600}, WIDE, {"width": 600, "height": 200}),
    ({"width": "520", "height": "auto"}, {"width": 1400, "height": 1580}, {"width": 520, "height": 587}),
    ({"width": "600", "height": "400"}, WIDE, None),                 # a typed |600x400 stays (Q1)
    ({"width": 600, "height": 400}, WIDE, None),
    ({"height": 100}, WIDE, None),
    ({"width": "50%"}, WIDE, None),                                  # review S1
    ({"width": "300px"}, WIDE, None),
    ({"style": "height:100px"}, WIDE, None),
    ({"style": "max-height:100px"}, WIDE, None),
    ({"style": "width:50%"}, WIDE, None),
    ({"width": "0"}, WIDE, None),
    ({"width": "auto", "height": "auto"}, {"ratio": 1.5}, None),     # a bare viewBox-only SVG
    ({"width": "200", "height": "auto"}, {"ratio": 1.5}, {"width": 200, "height": 300}),
    ({"width": "auto", "height": "auto"}, {"width": 8 * 96 / 2.54, "height": 4 * 96 / 2.54},
     {"width": 302, "height": 151}),
    ({"width": "auto", "height": "auto"}, None, None),
    ({"width": "10", "height": "auto"}, {"width": 4000, "height": 1}, {"width": 10, "height": 1}),
]

PILLOW_FLOOR = 35
NAMED_FLOOR = len(NAMED)

RUNNER = r"""
import { readFileSync } from "fs"
import { pathToFileURL } from "url"
const reader = await import(pathToFileURL(process.argv[2]).href)
const job = JSON.parse(readFileSync(process.argv[3], "utf-8"))
const answers = {}
for (const path of job.files) {
  answers[path] = { whole: reader.pictureSizeOfFile(path), start: reader.pictureSizeOfFile(path, 16) }
}
const attributes = []
for (const [properties, size] of job.attributeCases) {
  attributes.push(reader.sizedAttributes(properties, size))
}
console.log(JSON.stringify({ answers, attributes }))
"""


# Bundles the transformer with esbuild's own API (from Quartz's node_modules).
# Its reader is swapped for STUB_JS, which throws for one picture and asks
# the real reader about the rest; Quartz's path helpers come from Quartz.
BUILD = r"""
import { createRequire } from "module"
const require = createRequire("NODE_MODULES/")
const { build } = require("esbuild")
await build({
  entryPoints: [process.argv[2]], outfile: process.argv[3], bundle: true, platform: "node", format: "esm",
  logLevel: "error", nodePaths: ["NODE_MODULES"],
  plugins: [{ name: "swap", setup(builder) {
    builder.onResolve({ filter: /^\.\/pictureSizes\.js$/ }, () => ({ path: "STUB_JS" }))
    builder.onResolve({ filter: /^\.\.\/\.\.\/util\/path$/ }, () => ({ path: "QUARTZ_PATH_TS" }))
    builder.onResolve({ filter: /^\.\.\/types$/ }, () => ({ path: "types", namespace: "empty" }))
    builder.onLoad({ filter: /.*/, namespace: "empty" }, () => ({ contents: "export {}", loader: "js" }))
  } }],
})
"""

STUB_JS = r"""
import * as real from "READER_JS"
export function pictureSizeOfFile(path, firstRead) {
  return real.pictureSizeOfFile(path, firstRead)
}
export function sizedAttributes(properties, size) {
  if (String(properties.src).includes("throws")) throw new Error("a reader that fails on this picture")
  return real.sizedAttributes(properties, size)
}
"""

TRANSFORMER_RUNNER = r"""
import { PlantoirPictureSizes } from "TRANSFORMER_TS"
const [directory] = process.argv.slice(2)
const files = ["Media/wide.png", "Media/throws.png", "Media/tall.png"]
const ctx = { allFiles: files, allSlugs: files, argv: { directory } }
function picture(src, width) {
  return { type: "element", tagName: "img", properties: { src, width, height: "auto", alt: "" }, children: [] }
}
const tree = { type: "root", children: [
  picture("./Media/wide.png", "600"), picture("./Media/throws.png", "auto"), picture("./Media/tall.png", "auto"),
] }
let threw = null
try {
  for (const make of PlantoirPictureSizes().htmlPlugins(ctx)) make()(tree, { data: { slug: "page" } })
} catch (error) {
  threw = String(error)
}
const after = []
for (const node of tree.children) after.push(node.properties)
console.log(JSON.stringify({ threw, after }))
"""


def transformer_failures(work: Path) -> list:
    """Section 5: one picture's failure leaves that picture alone."""
    failures = []
    site = work / "content"
    (site / "Media").mkdir(parents=True)
    shutil.copyfile(CORPUS / "png-rgb.png", site / "Media" / "wide.png")      # 120 x 40
    shutil.copyfile(CORPUS / "png-rgb.png", site / "Media" / "throws.png")
    shutil.copyfile(CORPUS / "png-grey.png", site / "Media" / "tall.png")     # 30 x 90
    (work / "stub.mjs").write_text(STUB_JS.replace("READER_JS", str(work / "pictureSizes.js")), encoding="utf-8")
    (work / "build.mjs").write_text(BUILD.replace("NODE_MODULES", str(NODE_MODULES)).replace(
        "STUB_JS", str(work / "stub.mjs")).replace("QUARTZ_PATH_TS", str(QUARTZ_PATH_TS)), encoding="utf-8")
    (work / "transformer.mjs").write_text(TRANSFORMER_RUNNER.replace("TRANSFORMER_TS", str(TRANSFORMER_TS)),
                                          encoding="utf-8")
    built = subprocess.run(["node", str(work / "build.mjs"), str(work / "transformer.mjs"),
                            str(work / "transformer.bundle.mjs")], capture_output=True, text=True)
    if built.returncode != 0:
        return ["the transformer did not bundle: " + built.stderr.strip()[-600:]]
    said = subprocess.run(["node", str(work / "transformer.bundle.mjs"), str(site)], capture_output=True, text=True)
    if said.returncode != 0:
        return ["the transformer did not run: " + said.stderr.strip()[-600:]]
    result = json.loads(said.stdout.strip().splitlines()[-1])
    if result["threw"] is not None:
        failures.append(f"one picture's reader failing failed the whole page: {result['threw']}")
        return failures
    wide, broken, tall = result["after"]
    if broken != {"src": "./Media/throws.png", "width": "auto", "height": "auto", "alt": ""}:
        failures.append(f"the picture whose reader failed was changed: {json.dumps(broken)}")
    if (wide.get("width"), wide.get("height"), "dataPlSized" in wide) != (600, 200, True):
        failures.append(f"the picture before it was not sized 600 x 200: {json.dumps(wide)}")
    if (tall.get("width"), tall.get("height"), "dataPlSized" in tall) != (30, 90, True):
        failures.append(f"the picture after it was not sized 30 x 90: {json.dumps(tall)}")
    return failures


def pillow_size(path: Path):
    try:
        with Image.open(path) as picture:
            picture.load()
            return list(ImageOps.exif_transpose(picture).size)
    except Exception:  # noqa: BLE001 - anything Pillow cannot decode is "no size"
        return None


def as_comparable(answer):
    if answer is None:
        return None
    if "ratio" in answer:
        return {"ratio": answer["ratio"]}
    return [answer["width"], answer["height"]]


def same(got, want) -> bool:
    if got is None or want is None:
        return got is None and want is None
    if isinstance(want, dict) or isinstance(got, dict):
        return (isinstance(want, dict) and isinstance(got, dict)
                and math.isclose(got["ratio"], want["ratio"], rel_tol=1e-9))
    return len(got) == 2 and math.isclose(got[0], want[0], rel_tol=1e-9) and math.isclose(got[1], want[1], rel_tol=1e-9)


def main() -> int:
    failures = []
    files = []
    for path in sorted(CORPUS.iterdir()):
        if path.is_file() and not path.name.startswith("."):
            files.append(path)
    work = Path(tempfile.mkdtemp(prefix="plantoir-picture-sizes-"))
    try:
        # The reader is an ES module, as the section's Quartz (type: module)
        # reads it; a copy beside a package.json saying so.
        (work / "package.json").write_text('{"type": "module"}\n', encoding="utf-8")
        shutil.copyfile(READER_JS, work / "pictureSizes.js")
        (work / "runner.mjs").write_text(RUNNER, encoding="utf-8")
        job = {"files": [str(path) for path in files], "attributeCases": []}
        for properties, size, _ in ATTRIBUTE_CASES:
            job["attributeCases"].append([properties, size])
        (work / "job.json").write_text(json.dumps(job), encoding="utf-8")
        said = subprocess.run(["node", str(work / "runner.mjs"), str(work / "pictureSizes.js"),
                               str(work / "job.json")], capture_output=True, text=True)
        if said.returncode != 0:
            print("FAIL: the reader did not run in Node: " + said.stderr.strip()[-600:])
            return 1
        result = json.loads(said.stdout.strip().splitlines()[-1])
        failures.extend(transformer_failures(work))
    finally:
        shutil.rmtree(work, ignore_errors=True)

    asked_pillow = 0
    asked_named = 0
    for path in files:
        answer = result["answers"][str(path)]
        got = as_comparable(answer["whole"])
        if path.name in NAMED:
            want = NAMED[path.name]
            asked_named += 1
            source = "named"
        else:
            want = pillow_size(path)
            asked_pillow += 1
            source = "Pillow"
        if not same(got, want):
            failures.append(f"{path.name}: the reader says {json.dumps(got)}, {source} says {json.dumps(want)}")
        if not same(as_comparable(answer["start"]), got):
            failures.append(f"{path.name}: read from its first 16 bytes the reader says "
                            f"{json.dumps(as_comparable(answer['start']))}, read whole {json.dumps(got)}")
    for name in NAMED:
        if not (CORPUS / name).is_file():
            failures.append(f"{name} is named here but is not in the corpus")

    for index, (properties, size, want) in enumerate(ATTRIBUTE_CASES):
        got = result["attributes"][index]
        if got != want:
            failures.append(f"sizedAttributes({json.dumps(properties)}, {json.dumps(size)}): "
                            f"{json.dumps(got)}, expected {json.dumps(want)}")

    if asked_pillow < PILLOW_FLOOR or asked_named < NAMED_FLOOR:
        failures.append(f"only {asked_pillow} picture(s) asked of Pillow (at least {PILLOW_FLOOR}) and "
                        f"{asked_named} named (all {NAMED_FLOOR}): the corpus is not all there")

    summary = (f"{asked_pillow} pictures agree with Pillow, {asked_named} named cases hold, "
               f"every one the same from a 16-byte first read, {len(ATTRIBUTE_CASES)} attribute cases, "
               f"and a picture whose reader fails left as Quartz wrote it while the rest of its page is sized")
    if failures:
        for failure in failures:
            print("FAIL: " + failure)
        print(f"{len(failures)} failure(s); {asked_pillow} asked of Pillow, {asked_named} named")
        return 1
    print("OK: " + summary)
    return 0


if __name__ == "__main__":
    sys.exit(main())
