#!/usr/bin/env python3
"""
The plantoir-marking skill's scan redaction (#750, piece 750a): scripts/redact_scans.py.

Russell, 2026-11-12, on #750: "script runs, teacher checks the papers, confirms names are redacted, then
agent based marking begins. Simple." and "Teacher confirms full redacted papers." The script places boxes
from the BLANK test into a holding folder on the teacher's side, and says only what is true. Since 750d the
combined file, the teacher's yes and the move to where the assistant reads belong to the pinned
teacher_only.py and its launcher, tested in scripts/test_marking_teacher_run.py.

Every paper here has ANSWERS written down every page to the bottom (the review of the second fixes found
the old line-up stopped 8 of 8 such papers), on two layouts: the house style's Quiz (the title just under
the name line) and a plain one with its name blank drawn six ways. Each case of contracts/shared-rules.json
-> assessment -> redaction -> scanCases is built from the blank with an invented name written on each page's
name line, and must be written or stopped as the case says; where `nameInsideTheBox` is true, none of the
name's ink may show outside the box. The other cases: the box read from each blank (boxCases), a previous
batch cleared from the holding folder, a failed write leaving nothing in it, the old --confirm and --verify
refused with where they went, no line claiming a name is covered, the box black with nothing under it, a name in the body left as
it is, files not named like an identifier, the stack split, a working folder refused, and the self-test.

Needs Poppler (pdftoppm, pdfinfo, pdftotext, pdfunite, pdfseparate); every case skips, saying so, where it is
missing. Stdlib only otherwise. Windows' PythonToolchainTests discovers this file.
"""
import json
import math
import os
import random
import re
import shutil
import stat
import subprocess
import sys
import tempfile
import unittest
import zlib
from pathlib import Path

REPOSITORY = Path(__file__).resolve().parents[1]
SKILL = REPOSITORY / "support" / "agent_guidance" / "skills" / "plantoir-marking"
SCRIPT = SKILL / "scripts" / "redact_scans.py"
FIXTURES = REPOSITORY / "scripts" / "fixtures" / "marking"
SHARED_RULES = REPOSITORY / "contracts" / "shared-rules.json"
BLANKS = {"house": FIXTURES / "blank-quiz-letter.pdf", "plain": FIXTURES / "blank-name-styles.pdf"}
BLANK_LETTER = BLANKS["house"]
TOOLS = ("pdftoppm", "pdfinfo", "pdftotext", "pdfunite", "pdfseparate")
MISSING = [tool for tool in TOOLS if shutil.which(tool) is None]
SKIP_REASON = "Poppler is not installed here (" + ", ".join(MISSING) + " not found); the redaction cases need it"
DPI = 100
INVENTED = ("Testpupil", "Alphaname")


def redaction():
    return json.loads(SHARED_RULES.read_text(encoding="utf-8"))["assessment"]["redaction"]


def assessment():
    return json.loads(SHARED_RULES.read_text(encoding="utf-8"))["assessment"]


def render(pdf, page, dpi=DPI):
    with tempfile.TemporaryDirectory() as folder:
        base = os.path.join(folder, "p")
        subprocess.run(["pdftoppm", "-gray", "-r", str(dpi), "-f", str(page), "-l", str(page), "-singlefile",
                        str(pdf), base], check=True, capture_output=True)
        data = Path(base + ".pgm").read_bytes()
    match = re.match(rb"P5\s+(\d+)\s+(\d+)\s+(\d+)\s", data)
    width, height = int(match.group(1)), int(match.group(2))
    return width, height, bytearray(data[match.end():match.end() + width * height])


def page_count(pdf):
    out = subprocess.run(["pdfinfo", str(pdf)], capture_output=True, text=True).stdout
    return int(re.search(r"Pages:\s+(\d+)", out).group(1))


def write_image_pdf(path, pages):
    """pages: [(width, height, grey bytes)] at DPI, each one picture filling its page."""
    objects = [b"", b""]
    kids = []
    for width, height, pixels in pages:
        packed = zlib.compress(bytes(pixels), 6)
        objects.append(b"<</Type/XObject/Subtype/Image/Width %d/Height %d/ColorSpace/DeviceGray/BitsPerComponent 8"
                       b"/Filter/FlateDecode/Length %d>>stream\n" % (width, height, len(packed)) + packed + b"\nendstream")
        image = len(objects)
        width_pt, height_pt = width * 72 / DPI, height * 72 / DPI
        content = b"q %.3f 0 0 %.3f 0 0 cm /I Do Q" % (width_pt, height_pt)
        objects.append(b"<</Length %d>>stream\n" % len(content) + content + b"\nendstream")
        objects.append(b"<</Type/Page/Parent 2 0 R/MediaBox[0 0 %.3f %.3f]/Resources<</XObject<</I %d 0 R>>>>"
                       b"/Contents %d 0 R>>" % (width_pt, height_pt, image, len(objects)))
        kids.append(len(objects))
    objects[0] = b"<</Type/Catalog/Pages 2 0 R>>"
    objects[1] = b"<</Type/Pages/Kids[%s]/Count %d>>" % (b" ".join(b"%d 0 R" % kid for kid in kids), len(kids))
    body = bytearray(b"%PDF-1.4\n")
    offsets = []
    for number, data in enumerate(objects, start=1):
        offsets.append(len(body))
        body += b"%d 0 obj\n" % number + data + b"\nendobj\n"
    start = len(body)
    body += b"xref\n0 %d\n0000000000 65535 f \n" % (len(objects) + 1)
    for offset in offsets:
        body += b"%010d 00000 n \n" % offset
    body += b"trailer<</Size %d/Root 1 0 R>>\nstartxref\n%d\n%%%%EOF\n" % (len(objects) + 1, start)
    Path(path).write_bytes(bytes(body))


def paint(image, strokes, value):
    width, height, pixels = image
    for x0, y0, x1, y1 in strokes:
        for row in range(int(y0 * DPI), int(y1 * DPI)):
            for column in range(int(x0 * DPI), int(x1 * DPI)):
                pixels[row * width + column] = value


def transform(image, out_width, out_height, inverse, fill):
    """Nearest-neighbour: each output pixel takes the input pixel inverse(x, y) names."""
    width, height, pixels = image
    out = bytearray([fill]) * (out_width * out_height)
    for row in range(out_height):
        for column in range(out_width):
            x, y = inverse(column, row)
            x, y = int(round(x)), int(round(y))
            if 0 <= x < width and 0 <= y < height:
                out[row * out_width + column] = pixels[y * width + x]
    return out_width, out_height, out



def labels_of(blank):
    """{page: (x1, y0, y1) in inches} of each page's Name label, from the blank's own text."""
    xml = subprocess.run(["pdftotext", "-bbox", str(blank), "-"], capture_output=True, text=True).stdout
    found = {}
    for number, page in enumerate(xml.split("<page ")[1:], start=1):
        match = re.search(r'xMin="[\d.]+" yMin="([\d.]+)" xMax="([\d.]+)" yMax="([\d.]+)">Name:?<', page)
        if match:
            found[number] = (float(match.group(2)) / 72, float(match.group(1)) / 72, float(match.group(3)) / 72)
    return found


def answers(image, seed):
    """Handwriting-like answers down the page, every half inch from 1.3 in to the foot (10.3 in)."""
    strokes = []
    rows = random.Random(seed)
    y = 1.3
    while y < 10.35:
        x = 1.5
        while x < 6.8:
            length = rows.uniform(0.15, 0.45)
            strokes.append((x, y, x + length, y + rows.uniform(0.06, 0.12)))
            x += length + rows.uniform(0.08, 0.15)
        y += 0.5
    paint(image, strokes, 30)


def name_strokes(label):
    x1, y0, y1 = label
    return [(x1 + 0.1, y0 - 0.02, x1 + 0.6, y1 + 0.02), (x1 + 0.7, y0, x1 + 1.5, y1 + 0.03)]


def variants(width, height):
    """name -> (function of (image, fill) -> image, which pages it applies to)."""
    def shift(down_in):
        return lambda image, fill: transform(image, width, height, lambda x, y: (x, y - down_in * DPI), fill)

    def scale(factor):
        return lambda image, fill: transform(
            image, width, height, lambda x, y: ((x - width / 2) / factor + width / 2, (y - height / 2) / factor + height / 2), fill)

    def upside_down(image, fill):
        return image[0], image[1], bytearray(reversed(image[2]))

    def a4(image, fill):
        out_width, out_height = round(8.27 * DPI), round(11.69 * DPI)
        left, top = (out_width - width) // 2, (out_height - height) // 2
        return transform(image, out_width, out_height, lambda x, y: (x - left, y - top), fill)

    def landscape(image, fill):
        return transform(image, height, width, lambda x, y: (y, height - 1 - x), fill)

    def grey_and_speckled(image, fill):
        if fill == 0:
            return image
        speckle = random.Random(7)
        out = bytearray(len(image[2]))
        for position, value in enumerate(image[2]):
            value = 40 + value * 185 // 255
            if speckle.random() < 0.004:
                value = speckle.randint(60, 160)
            out[position] = value
        return image[0], image[1], out

    return {
        "upright, answers on every page": (lambda image, fill: image, "all"),
        "grey and speckled": (grey_and_speckled, "all"),
        "shifted down 0.15 in": (shift(0.15), "all"),
        "shifted down 0.40 in": (shift(0.40), "all"),
        "scaled 94% (fit to page)": (scale(0.94), "all"),
        "the last page upside down": (upside_down, "last"),
        "A4, letter test centred": (a4, "all"),
        "the last page landscape": (landscape, "last"),
    }


def build_scans(blank, folder, names, extra_copies=False):
    """One invented paper with answers on every page per variant, in folder/Section 1/<identifier>.pdf.

    Returns {identifier: (variant, [(name ink pixels, (width, height), turned) per page])}."""
    labels = labels_of(blank)
    pages = []
    for number in range(1, page_count(blank) + 1):
        image = render(blank, number)
        answers(image, number)
        mask = (image[0], image[1], bytearray(image[0] * image[1]))
        if number in labels:
            paint(image, name_strokes(labels[number]), 15)
            paint(mask, name_strokes(labels[number]), 255)
        pages.append((image, mask))
    width, height = pages[0][0][0], pages[0][0][1]
    section = Path(folder) / "Section 1"
    section.mkdir(parents=True, exist_ok=True)
    made = {}
    for index, (variant, (change, which)) in enumerate(variants(width, height).items()):
        if variant not in names:
            continue
        identifier = "Student " + "ABCDEFGHIJKLMNOP"[index]
        scan_pages, masks = [], []
        for number, (image, mask) in enumerate(pages, start=1):
            if which == "all" or (which == "last" and number == len(pages)):
                image, mask = change(image, 255), change(mask, 0)
            scan_pages.append(image)
            spots = {(position % mask[0], position // mask[0]) for position, value in enumerate(mask[2]) if value}
            masks.append((spots, (mask[0], mask[1])))
        write_image_pdf(section / (identifier + ".pdf"), scan_pages + (scan_pages if extra_copies else []))
        made[identifier] = (variant, masks)
    return made


def boxes_of(blank):
    out = run_script(SCRIPT, "--box-from", blank).stdout
    boxes = []
    for line in out.splitlines():
        boxes.append(tuple(float(value) for value in line.split("box in inches ")[1].split(",")) if "box in inches" in line else None)
    return boxes


def name_ink_outside_the_box(redacted, masks, boxes):
    """How many pixels of the name's ink show in a written paper outside its page's box."""
    left = 0
    for number, (spots, _size) in enumerate(masks, start=1):
        box = boxes[(number - 1) % len(boxes)]
        width, height, pixels = render(redacted, number)
        for x, y in spots:
            inside = box is not None and box[0] * DPI <= x < box[2] * DPI and box[1] * DPI <= y < box[3] * DPI
            if not inside and 0 <= x < width and 0 <= y < height and pixels[y * width + x] < 128:
                left += 1
    return left


def run_script(script, *arguments):
    return subprocess.run([sys.executable, "-B", str(script), *[str(argument) for argument in arguments]],
                          capture_output=True, text=True, encoding="utf-8")


def pdf_words(pdf):
    return subprocess.run(["pdftotext", str(pdf), "-"], capture_output=True, text=True).stdout


def placed_pictures(pdf_bytes):
    """Every picture's rectangle on each page, in points: [(x0, y0, x1, y1)], from the cm before a Do."""
    rectangles = []
    for match in re.finditer(rb"q ([-\d.]+) 0 0 ([-\d.]+) ([-\d.]+) ([-\d.]+) cm /\w+ Do Q", pdf_bytes):
        a, d, e, f = (float(value) for value in match.groups())
        rectangles.append((min(e, e + a), min(f, f + d), max(e, e + a), max(f, f + d)))
    return rectangles


@unittest.skipIf(MISSING, SKIP_REASON)
class ScanCaseTests(unittest.TestCase):
    """Every scanCases case, on both layouts, with answers on every page."""

    @classmethod
    def setUpClass(cls):
        cls.root = Path(tempfile.mkdtemp(prefix="marking-redact-"))
        cls.runs = {}
        names = set(variants(850, 1100))
        for layout, blank in BLANKS.items():
            originals = cls.root / layout / "Originals"
            made = build_scans(blank, originals, names)
            (originals / "Section 1" / (INVENTED[0] + " " + INVENTED[1] + ".pdf")).write_bytes(
                (originals / "Section 1" / "Student A.pdf").read_bytes())
            outcome = run_script(SCRIPT, originals, cls.root / layout / "Redacted", "--blank", blank,
                                 "--check-dir", cls.root / layout / "Teacher only" / "Check")
            cls.runs[layout] = (made, outcome, boxes_of(blank))

    @classmethod
    def tearDownClass(cls):
        shutil.rmtree(cls.root, ignore_errors=True)

    def line_for(self, layout, identifier):
        for line in self.runs[layout][1].stdout.splitlines():
            if line.startswith(f"Section 1/{identifier}.pdf:"):
                return line
        self.fail(f"{layout}: no line for {identifier}:\n{self.runs[layout][1].stdout}")

    def test_every_case_is_written_or_stopped_as_the_contract_says(self):
        cases = redaction()["scanCases"]["cases"]
        report = []
        for layout in BLANKS:
            made, _outcome, boxes = self.runs[layout]
            self.assertEqual(sorted(case["variant"] for case in cases), sorted(variant for variant, _masks in made.values()))
            by_variant = {variant: identifier for identifier, (variant, _masks) in made.items()}
            for case in cases:
                identifier = by_variant[case["variant"]]
                line = self.line_for(layout, identifier)
                redacted = self.root / layout / "Redacted" / "Section 1" / (identifier + ".pdf")
                if case["expect"] == "stopped":
                    self.assertIn("stopped (", line, f"{layout}: {case['variant']}")
                    self.assertFalse(redacted.exists())
                    report.append(f"{layout}, {case['variant']}: stopped")
                    continue
                self.assertNotIn("stopped", line, f"{layout}: {case['variant']} must be written: {line}")
                left = name_ink_outside_the_box(redacted, made[identifier][1], boxes)
                report.append(f"{layout}, {case['variant']}: written, {left} name pixels outside the box")
                if case.get("nameInsideTheBox"):
                    self.assertEqual(left, 0, f"{layout}: {case['variant']}")
        print("\n" + "\n".join(report))

    def test_papers_with_answers_on_every_page_are_not_stopped(self):
        # 750a fix review 2, H1: answers to the foot of a page stopped 8 of 8 papers under the old line-up.
        for layout in BLANKS:
            self.assertIn("boxed", self.line_for(layout, "Student A"))
            self.assertNotIn("stopped", self.line_for(layout, "Student A"))

    def test_nothing_it_says_claims_a_name_is_covered(self):
        for layout in BLANKS:
            said = (self.runs[layout][1].stdout + self.runs[layout][1].stderr).casefold()
            for claim in ("covered", "covers", "removed", "safe", "no names", " ok", "redacted the name", "names are hidden"):
                self.assertNotIn(claim, said, f"the run must not claim '{claim}'")
            last = self.runs[layout][1].stdout.strip().splitlines()[-1]
            self.assertIn("The teacher's look is what confirms the names are redacted", last)
            self.assertIn("A name written anywhere else on a page is not boxed and would be seen", last)
            self.assertIn("goes to its service", last)

    def test_the_box_is_black_and_nothing_sits_under_it(self):
        redacted = self.root / "house" / "Redacted" / "Section 1" / "Student A.pdf"
        box = self.runs["house"][2][0]
        data = redacted.read_bytes()
        self.assertNotIn(b"/Font", data)
        self.assertEqual(pdf_words(redacted).strip(), "")
        box_pt = (box[0] * 72, 792 - box[3] * 72, box[2] * 72, 792 - box[1] * 72)
        for x0, y0, x1, y1 in placed_pictures(data):
            overlap_x = min(x1, box_pt[2]) - max(x0, box_pt[0])
            overlap_y = min(y1, box_pt[3]) - max(y0, box_pt[1])
            self.assertFalse(overlap_x > 0.5 and overlap_y > 0.5, "a picture is placed across the box")
        width, _height, pixels = render(redacted, 1, 150)
        for row in range(round(box[1] * 150) + 1, round(box[3] * 150) - 1):
            self.assertEqual(max(pixels[row * width + round(box[0] * 150) + 1: row * width + round(box[2] * 150) - 1]), 0)

    def test_the_answers_are_left_as_they_were(self):
        redacted = self.root / "house" / "Redacted" / "Section 1" / "Student A.pdf"
        width, _height, pixels = render(redacted, 2)
        dark = sum(1 for row in range(int(9.8 * DPI), int(10.4 * DPI)) for column in range(150, 680)
                   if pixels[row * width + column] < 100)
        self.assertGreater(dark, 200, "answers, and a name written among them, are not boxed: the teacher's look finds a name")

    def test_a_file_not_named_like_an_identifier_is_counted_and_never_named(self):
        for layout in BLANKS:
            said = self.runs[layout][1].stdout + self.runs[layout][1].stderr
            for token in INVENTED:
                self.assertNotIn(token.casefold(), said.casefold())
            self.assertIn("1 files or folders not named like an identifier were left alone", said)


@unittest.skipIf(MISSING, SKIP_REASON)
class BoxTests(unittest.TestCase):

    def test_the_box_cases(self):
        for case in redaction()["boxCases"]:
            arguments = ["--box-from", FIXTURES / case["blank"]]
            if "label" in case:
                arguments += ["--label", case["label"]]
            result = run_script(SCRIPT, *arguments)
            if "refused" in case:
                self.assertEqual(result.returncode, 1, case["name"])
                self.assertIn(case["refused"], result.stdout, case["name"])
                continue
            self.assertEqual(result.returncode, 0, f"{case['name']}: {result.stdout}")
            lines = result.stdout.splitlines()
            self.assertEqual(len(lines), len(case["pages"]), case["name"])
            for line, expected in zip(lines, case["pages"]):
                if expected is None:
                    self.assertIn("no name blank on your blank test, so no box", line, case["name"])
                    continue
                self.assertIn("box in inches ", line, case["name"])
                values = [float(value) for value in line.split("box in inches ")[1].split(",")]
                for found, wanted in zip(values, expected):
                    self.assertAlmostEqual(found, wanted, delta=0.02, msg=f"{case['name']}: {line}")

    def test_only_files_named_like_an_identifier_are_papers(self):
        cases = assessment()["identifiers"]["cases"]
        with tempfile.TemporaryDirectory() as root:
            originals = Path(root) / "Originals"
            originals.mkdir()
            build_scans(BLANK_LETTER, Path(root) / "made", {"upright, answers on every page"})
            scan = (Path(root) / "made" / "Section 1" / "Student A.pdf").read_bytes()
            for case in cases:
                (originals / case["file"]).write_bytes(scan)
            result = run_script(SCRIPT, originals, Path(root) / "Redacted", "--blank", BLANK_LETTER, "--check-dir", Path(root) / "Check")
            papers = [case for case in cases if case["isAPaper"]]
            for case in cases:
                stem = case["file"][:-4]
                if case["isAPaper"]:
                    self.assertIn(f"{stem}.pdf: 2 pages, 2 boxed", result.stdout, case["file"])
                else:
                    self.assertNotIn(stem, result.stdout, f"{case['file']} must be counted, never named")
            self.assertIn(f"{len(cases) - len(papers)} files or folders not named like an identifier were left alone", result.stdout)

    def test_two_copies_of_the_blank_in_one_file_are_both_boxed(self):
        with tempfile.TemporaryDirectory() as root:
            build_scans(BLANK_LETTER, Path(root) / "Originals", {"upright, answers on every page"}, extra_copies=True)
            result = run_script(SCRIPT, Path(root) / "Originals", Path(root) / "Redacted", "--blank", BLANK_LETTER,
                                "--check-dir", Path(root) / "Check")
            self.assertIn("Section 1/Student A.pdf: 4 pages, 4 boxed", result.stdout)

    def test_a_page_count_that_is_not_whole_copies_is_stopped(self):
        with tempfile.TemporaryDirectory() as root:
            (Path(root) / "Originals").mkdir()
            write_image_pdf(Path(root) / "Originals" / "Student A.pdf", [render(BLANK_LETTER, 1)] * 3)
            result = run_script(SCRIPT, Path(root) / "Originals", Path(root) / "Redacted", "--blank", BLANK_LETTER,
                                "--check-dir", Path(root) / "Check")
            self.assertIn("Student A.pdf: stopped (it has 3 pages, which is not a whole number of copies of your blank "
                          "test's 2); not written", result.stdout)

    def test_a_name_written_low_in_a_form_cell_is_inside_the_box(self):
        # 750a fix review 3, M6: the box takes the whole cell the label sits in, from the blank's own drawing.
        blank = FIXTURES / "blank-name-in-a-cell.pdf"
        box = boxes_of(blank)[0]
        image = render(blank, 1)
        low = [(1.0, 1.08, 3.2, 1.25)]
        paint(image, low, 15)
        mask = (image[0], image[1], bytearray(image[0] * image[1]))
        paint(mask, low, 255)
        spots = {(position % mask[0], position // mask[0]) for position, value in enumerate(mask[2]) if value}
        with tempfile.TemporaryDirectory() as root:
            (Path(root) / "Originals").mkdir()
            write_image_pdf(Path(root) / "Originals" / "Student A.pdf", [image])
            run_script(SCRIPT, Path(root) / "Originals", Path(root) / "Redacted", "--blank", blank, "--check-dir", Path(root) / "Check")
            self.assertEqual(name_ink_outside_the_box(Path(root) / "Redacted" / "Student A.pdf", [(spots, (0, 0))], [box]), 0)

    def test_a_scanned_blank_is_told_to_give_the_box(self):
        # 750a fix review 3, L3: a blank with no text layer cannot be read; --box can, and --box-from shows it.
        with tempfile.TemporaryDirectory() as root:
            scanned = Path(root) / "scanned blank.pdf"
            write_image_pdf(scanned, [render(BLANK_LETTER, 1), render(BLANK_LETTER, 2)])
            result = run_script(SCRIPT, "--box-from", scanned)
            self.assertIn("no text in it (is it a scan?)", result.stdout)
            self.assertIn("--box", result.stdout)
            shown = run_script(SCRIPT, "--box-from", scanned, "--box", "0.3,0.25,8.2,0.98")
            self.assertIn("page 2: box in inches 0.30,0.25,8.20,0.98", shown.stdout)

    def test_a_page_with_no_name_blank_is_said(self):
        blank = FIXTURES / "blank-quiz-letter-name-on-page-1.pdf"
        with tempfile.TemporaryDirectory() as root:
            build_scans(blank, Path(root) / "Originals", {"upright, answers on every page"})
            result = run_script(SCRIPT, Path(root) / "Originals", Path(root) / "Redacted", "--blank", blank,
                                "--check-dir", Path(root) / "Check")
            self.assertIn("Section 1/Student A.pdf: 2 pages, 1 boxed; 1 with no name blank on your blank test, so no box",
                          result.stdout)


@unittest.skipIf(MISSING, SKIP_REASON)
class HoldingFolderTests(unittest.TestCase):
    """The boxing writes into a holding folder on the teacher's side (750d), clearing it first."""

    def setUp(self):
        self.root = Path(tempfile.mkdtemp(prefix="marking-batch-"))
        self.addCleanup(shutil.rmtree, self.root, True)
        self.originals = self.root / "Teacher only" / "Unit Test" / "Originals"
        build_scans(BLANK_LETTER, self.originals, {"upright, answers on every page", "grey and speckled"})
        self.holding = self.root / "Teacher only" / "Unit Test" / "Holding"

    def box(self):
        return run_script(SCRIPT, self.originals, self.holding, "--blank", BLANK_LETTER)

    def test_a_new_batch_clears_the_last_one(self):
        self.box()
        os.remove(self.originals / "Section 1" / "Student B.pdf")
        planted = self.holding / "Section 1" / "Student Q.PDF"
        planted.write_bytes((self.originals / "Section 1" / "Student A.pdf").read_bytes())
        self.box()
        self.assertEqual(sorted(path.name for path in self.holding.rglob("*") if path.is_file()), ["Student A.pdf"],
                         "nothing from the last batch, of any name or kind, stands in for this one")

    def test_a_failure_while_writing_leaves_nothing_in_the_holding_folder(self):
        self.box()
        fake = self.root / "bin"
        fake.mkdir()
        (fake / "pdftoppm").write_text("#!/bin/sh\nexit 1\n", encoding="utf-8")
        (fake / "pdftoppm").chmod(stat.S_IRWXU)
        environment = dict(os.environ, PATH=str(fake) + os.pathsep + os.environ.get("PATH", ""))
        result = subprocess.run([sys.executable, "-B", str(SCRIPT), str(self.originals), str(self.holding), "--blank",
                                 str(BLANK_LETTER)], capture_output=True, text=True, env=environment)
        self.assertEqual(result.returncode, 1)
        self.assertIn("Stopped:", result.stdout)
        self.assertEqual(list(self.holding.rglob("*.pdf")), [], "no paper is left for Box the papers to put together")

    def test_a_run_that_stops_early_leaves_the_holding_folder_empty(self):
        # 750a fix review 3, L1: a missing blank stopped the run before the last batch was cleared.
        self.box()
        result = run_script(SCRIPT, self.originals, self.holding, "--blank", self.root / "missing.pdf")
        self.assertEqual(result.returncode, 1)
        self.assertEqual(list(self.holding.rglob("*")), [])

    def test_a_failed_write_leaves_nothing_in_the_holding_folder(self):
        self.box()
        self.assertTrue(list(self.holding.rglob("*.pdf")))
        beside = self.holding.parent
        beside.chmod(stat.S_IRUSR | stat.S_IXUSR)
        try:
            result = self.box()
        finally:
            beside.chmod(stat.S_IRWXU)
        self.assertEqual(result.returncode, 1)
        self.assertIn("none may be read", result.stdout)
        self.assertEqual(list(self.holding.rglob("*.pdf")), [])

    def test_the_teachers_yes_is_no_longer_this_scripts(self):
        # 750d: --confirm and --verify moved to the never-adapted teacher_only.py (a trial assistant rewrote
        # its copy of this script and that copy's self-test).
        for flag in ("--confirm", "--verify"):
            result = run_script(SCRIPT, flag, self.holding, "--check-dir", self.root / "Check")
            self.assertEqual(result.returncode, 1, flag)
            self.assertIn("teacher_only.py --verify", result.stdout, flag)
        source = SCRIPT.read_text(encoding="utf-8")
        for gone in ("Teacher confirmed.json", "Batch.json", "Redacted papers to look through.pdf"):
            self.assertNotIn(gone, source)


@unittest.skipIf(MISSING, SKIP_REASON)
class OtherTests(unittest.TestCase):

    def test_a_stack_is_split_and_the_papers_renamed_from_the_table(self):
        with tempfile.TemporaryDirectory() as root:
            stack_pages = []
            for _paper in range(3):
                stack_pages += [render(BLANK_LETTER, 1), render(BLANK_LETTER, 2)]
            write_image_pdf(Path(root) / "stack.pdf", stack_pages)
            into = Path(root) / "Originals" / "Section 1"
            split = run_script(SCRIPT, "--stack", Path(root) / "stack.pdf", "--pages-per-paper", "2", "--into", into,
                               "--check-dir", Path(root) / "Check")
            self.assertEqual(split.returncode, 0, split.stdout)
            self.assertEqual(sorted(path.name for path in into.iterdir()), ["Paper 01.pdf", "Paper 02.pdf", "Paper 03.pdf"])
            self.assertTrue((Path(root) / "Check" / "Papers to name.pdf").exists())
            table = Path(root) / "Name Mapping Table.csv"
            table.write_text("section,identifier,name,paper\n1,Student A,\"Testpupil, Alphaname\",2\n"
                             "1,Student B,\"Zedfamily, Betaname\",1\n2,Student A,\"Other, Person\",1\n", encoding="utf-8")
            named = run_script(SCRIPT, "--name-papers", table, "--section", "1", "--into", into)
            self.assertIn("Section 1: 2 papers renamed; 1 missing from the table (Paper 03)", named.stdout)
            self.assertEqual(sorted(path.name for path in into.iterdir()), ["Paper 03.pdf", "Student A.pdf", "Student B.pdf"])
            for token in ("Testpupil", "Alphaname", "Zedfamily", "Betaname", "Other", "Person"):
                self.assertNotIn(token, named.stdout + named.stderr)

    def test_a_stack_that_is_not_whole_papers_refuses(self):
        with tempfile.TemporaryDirectory() as root:
            write_image_pdf(Path(root) / "stack.pdf", [render(BLANK_LETTER, 1)] * 3)
            result = run_script(SCRIPT, "--stack", Path(root) / "stack.pdf", "--pages-per-paper", "2", "--into",
                                Path(root) / "out", "--check-dir", Path(root) / "Check")
            self.assertEqual(result.returncode, 1)
            self.assertIn("not a whole number of papers", result.stdout)

    def test_nothing_is_written_inside_a_working_folder(self):
        with tempfile.TemporaryDirectory() as root:
            build_scans(BLANK_LETTER, Path(root) / "Originals", {"upright, answers on every page"})
            working = Path(root) / "Working"
            (working / "courses").mkdir(parents=True)
            (working / ".toolchain").mkdir()
            result = run_script(SCRIPT, Path(root) / "Originals", working / "Marking" / "Redacted", "--blank", BLANK_LETTER,
                                "--check-dir", Path(root) / "Check")
            self.assertEqual(result.returncode, 1)
            self.assertIn("inside the Plantoir working folder", result.stdout)
            self.assertFalse((working / "Marking").exists())

    def test_its_own_self_test_passes(self):
        result = run_script(SCRIPT, "--self-test")
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
        self.assertIn("self-test passed", result.stdout)


if __name__ == "__main__":
    unittest.main()
