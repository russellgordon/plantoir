#!/usr/bin/env python3
"""
The plantoir-marking skill's scan redaction (#750, piece 750a): scripts/redact_scans.py.

A scan is blanked only after each page has been compared with the BLANK test (750 plan review R2:
the first design printed OK on pages where the box missed the name). This builds invented "scans"
from the committed blank tests with the standard library alone (an invented name written as ink
strokes in the Name blank of every page, and in the body of page 2), then makes the nine kinds of
scan the plan review measured: upright, shifted down 0.15 in and 0.30 in, scaled 94 percent,
rotated 1.5 and 3 degrees, upside down on page 2 (a duplex scan on the wrong flip), an A4 page
with the letter test centred, and a phone crop stretched back to size. Every variant either
prints CHECK and writes nothing, or is written with NONE of the name's ink left visible outside
the box; the upright paper and the upside-down one must be written.

Also: the box read from the blank letter and legal tests; the box's pixels black and nothing
drawn over them (no picture is placed across the box, so nothing sits under the black); no text
and no font in a blanked file; a page turned sideways refused; a file not named like an
identifier counted, and its name never printed; the body of page 2 left as it was; the check
files written; the stack split and the papers renamed from a table's paper column; and the
script's own --self-test.

Needs Poppler (pdftoppm, pdfinfo, pdftotext, pdfunite, pdfseparate); every case skips, saying
so, where it is missing. Stdlib only otherwise. Windows' PythonToolchainTests discovers this file.
"""
import json
import math
import random
import os
import re
import shutil
import subprocess
import sys
import tempfile
import time
import unittest
import zlib
from pathlib import Path

REPOSITORY = Path(__file__).resolve().parents[1]
SKILL = REPOSITORY / "support" / "agent_guidance" / "skills" / "plantoir-marking"
SCRIPT = SKILL / "scripts" / "redact_scans.py"
FIXTURES = REPOSITORY / "scripts" / "fixtures" / "marking"
BLANK_LETTER = FIXTURES / "blank-quiz-letter.pdf"
BLANK_LEGAL = FIXTURES / "blank-quiz-legal.pdf"
TOOLS = ("pdftoppm", "pdfinfo", "pdftotext", "pdfunite", "pdfseparate")
MISSING = [tool for tool in TOOLS if shutil.which(tool) is None]
SKIP_REASON = "Poppler is not installed here (" + ", ".join(MISSING) + " not found); the redaction cases need it"
SHARED_RULES = REPOSITORY / "contracts" / "shared-rules.json"
BOX = (3.44, 0.20, 5.33, 0.89)
DPI = 100
INVENTED = ("Testpupil", "Alphaname")

# Where the invented name is written, in inches from the top-left: on the Name blank of the header
# (the label ends at 3.93 in; its rule runs to 5.19 in), and in the body of page 2.
NAME_STROKES = [(3.98, 0.56, 4.30, 0.74), (4.36, 0.58, 4.62, 0.75), (4.68, 0.55, 5.02, 0.73)]
BODY_STROKES = [(1.6, 3.1, 3.2, 3.3)]


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


def variants(width, height):
    """name -> (function of (image, fill) -> image, which pages it applies to)."""
    centre_x, centre_y = width / 2, height / 2

    def shift(down_in):
        return lambda image, fill: transform(image, width, height, lambda x, y: (x, y - down_in * DPI), fill)

    def scale(factor):
        return lambda image, fill: transform(
            image, width, height, lambda x, y: ((x - centre_x) / factor + centre_x, (y - centre_y) / factor + centre_y), fill)

    def rotate(degrees):
        angle = math.radians(degrees)
        cos, sin = math.cos(angle), math.sin(angle)
        return lambda image, fill: transform(
            image, width, height,
            lambda x, y: (cos * (x - centre_x) + sin * (y - centre_y) + centre_x,
                          -sin * (x - centre_x) + cos * (y - centre_y) + centre_y), fill)

    def upside_down(image, fill):
        return image[0], image[1], bytearray(reversed(image[2]))

    def a4(image, fill):
        out_width, out_height = round(8.27 * DPI), round(11.69 * DPI)
        left, top = (out_width - width) // 2, (out_height - height) // 2
        return transform(image, out_width, out_height, lambda x, y: (x - left, y - top), fill)

    def phone_crop(image, fill):
        cut = 0.35 * DPI
        return transform(image, width, height, lambda x, y: (x, cut + y * (height - cut) / height), fill)

    def grey_and_speckled(image, fill):
        if fill == 0:
            return image
        speckle = random.Random(7)
        width_now, height_now, pixels = image
        out = bytearray(len(pixels))
        for position, value in enumerate(pixels):
            value = 40 + value * 185 // 255
            if speckle.random() < 0.004:
                value = speckle.randint(60, 160)
            out[position] = value
        return width_now, height_now, out

    def shift_right(right_in):
        return lambda image, fill: transform(image, width, height, lambda x, y: (x - right_in * DPI, y), fill)

    def faint_past_the_box(image, fill):
        width_now, height_now, pixels = image
        if fill == 0:
            out = (width_now, height_now, bytearray(pixels))
            paint(out, [(5.02, 0.57, 5.62, 0.73)], 255)
            return out
        out = (width_now, height_now, bytearray(pixels))
        for row in range(height_now):
            for column in range(width_now):
                if pixels[row * width_now + column] == 15:
                    out[2][row * width_now + column] = 178   # the name, in light pencil
        paint(out, [(5.02, 0.57, 5.62, 0.73)], 178)
        return out

    def paper_marks(image, fill):
        if fill == 0:
            return image
        grain = random.Random(11)
        width_now, height_now, pixels = image
        out = bytearray(len(pixels))
        for position, value in enumerate(pixels):
            out[position] = max(0, min(255, value - grain.randint(0, 18)))
        page = (width_now, height_now, out)
        paint(page, [(0.0, 0.98, width_now / DPI, 1.0)], 150)        # a ruled line across the page, under the box
        paint(page, [(5.9, 0.0, 5.91, 1.4)], 160)                    # a fold line, down past the box's right
        for step in range(25):                                       # a staple's shadow at the top left
            paint(page, [(0.2 + step * 0.012, 0.15 + step * 0.006, 0.22 + step * 0.012, 0.17 + step * 0.006)], 90)
        centre_x, centre_y, radius = 0.375 * DPI, 1.25 * DPI, 0.13 * DPI  # a three-hole punch's top hole
        for row in range(int(centre_y - radius), int(centre_y + radius)):
            for column in range(int(centre_x - radius), int(centre_x + radius)):
                if (row - centre_y) ** 2 + (column - centre_x) ** 2 <= radius ** 2:
                    out[row * width_now + column] = 40
        return page

    def written_past_the_box(image, fill):
        width_now, height_now, pixels = image
        out = (width_now, height_now, bytearray(pixels))
        paint(out, [(5.02, 0.57, 5.62, 0.73)], 15 if fill == 255 else 255)
        return out

    return {
        "upright": (lambda image, fill: image, (1, 2)),
        "shifted down 0.15 in": (shift(0.15), (1, 2)),
        "shifted down 0.30 in": (shift(0.30), (1, 2)),
        "scaled 94% (fit to page)": (scale(0.94), (1, 2)),
        "rotated 1.5 degrees": (rotate(1.5), (1, 2)),
        "rotated 3 degrees": (rotate(3), (1, 2)),
        "page 2 upside down": (upside_down, (2,)),
        "A4, letter test centred": (a4, (1, 2)),
        "phone crop, stretched": (phone_crop, (1, 2)),
        # Three a scanner gives every day, which must NOT be stopped: a small shift, a small shrink, and
        # a grey, speckled page from a phone.
        "shifted down 0.05 in": (shift(0.05), (1, 2)),
        "scaled 99%": (scale(0.99), (1, 2)),
        "grey and speckled": (grey_and_speckled, (1, 2)),
        # A name written longer than the blank runs past the box (750 plan review L2).
        "a name written past the box": (written_past_the_box, (1,)),
        # The same in light pencil (750a review H1: 80 levels darker than the paper missed it).
        "a faint pencil name past the box": (faint_past_the_box, (1,)),
        # Everyday scans the check after writing stopped (750a review M1).
        "shifted right 0.04 in": (shift_right(0.04), (1, 2)),
        "rotated 0.5 degrees": (rotate(0.5), (1, 2)),
        # Paper and its marks near the header that are not writing (750a review H1, the other direction).
        "paper grain, a ruled line, a staple and a punched hole": (paper_marks, (1, 2)),
    }


def build_scans(blank, folder, names):
    """Write one invented scan per variant into folder/Section 1/<identifier>.pdf.

    Returns {identifier: (variant, [(mask pixels as a set, page size in pixels, turned) per page])}."""
    pages = []
    for page in range(1, page_count(blank) + 1):
        image = render(blank, page)
        paint(image, NAME_STROKES, 15)
        if page == 2:
            paint(image, BODY_STROKES, 25)
        mask = (image[0], image[1], bytearray(image[0] * image[1]))
        paint(mask, NAME_STROKES, 255)
        pages.append((image, mask))
    width, height = pages[0][0][0], pages[0][0][1]
    section = Path(folder) / "Section 1"
    section.mkdir(parents=True, exist_ok=True)
    made = {}
    for index, (variant, (change, which)) in enumerate(variants(width, height).items()):
        if variant not in names:
            continue
        identifier = "Student " + "ABCDEFGHIJKLMNOPQRSTUVWXYZ"[index]
        scan_pages = []
        masks = []
        for number, (image, mask) in enumerate(pages, start=1):
            if number in which:
                image, mask = change(image, 255), change(mask, 0)
            scan_pages.append(image)
            spots = set()
            mask_width = mask[0]
            for position, value in enumerate(mask[2]):
                if value:
                    spots.add((position % mask_width, position // mask_width))
            masks.append((spots, (mask[0], mask[1]), variant == "page 2 upside down" and number == 2))
        write_image_pdf(section / (identifier + ".pdf"), scan_pages)
        made[identifier] = (variant, masks)
    return made


def run_script(script, *arguments):
    return subprocess.run([sys.executable, "-B", str(script), *[str(argument) for argument in arguments]],
                          capture_output=True, text=True, encoding="utf-8")


def turned_pages(line):
    """The pages the script's own line says it turned upright."""
    match = re.search(r"; pages? ([\d, ]+) turned upright", line)
    return {int(number) for number in match.group(1).split(", ")} if match else set()


def ink_left_outside_the_box(blanked, masks, turned_by_the_script):
    """How many pixels of the name's ink are visible in a blanked file outside its box. The ink is looked
    for where the page the SCRIPT wrote puts it: turned half a turn only on the pages it says it turned."""
    left = 0
    for number, (spots, (width, height), _scanned_upside_down) in enumerate(masks, start=1):
        out_width, out_height, pixels = render(blanked, number)
        for x, y in spots:
            if number in turned_by_the_script:
                x, y = width - 1 - x, height - 1 - y
            inside = BOX[0] * DPI <= x < BOX[2] * DPI and BOX[1] * DPI <= y < BOX[3] * DPI
            if not inside and 0 <= x < out_width and 0 <= y < out_height and pixels[y * out_width + x] < 128:
                left += 1
    return left


def placed_pictures(pdf_bytes):
    """Every picture's rectangle on each page, in points: [(x0, y0, x1, y1)], from the cm before a Do."""
    rectangles = []
    for match in re.finditer(rb"q ([-\d.]+) 0 0 ([-\d.]+) ([-\d.]+) ([-\d.]+) cm /\w+ Do Q", pdf_bytes):
        a, d, e, f = (float(value) for value in match.groups())
        rectangles.append((min(e, e + a), min(f, f + d), max(e, e + a), max(f, f + d)))
    return rectangles


@unittest.skipIf(MISSING, SKIP_REASON)
class RedactionTests(unittest.TestCase):

    @classmethod
    def setUpClass(cls):
        cls.root = Path(tempfile.mkdtemp(prefix="marking-redact-"))
        cls.originals = cls.root / "Originals"
        cls.made = build_scans(BLANK_LETTER, cls.originals, set(variants(850, 1100)))
        (cls.originals / "Section 1" / (INVENTED[0] + " " + INVENTED[1] + ".pdf")).write_bytes(
            (cls.originals / "Section 1" / "Student A.pdf").read_bytes())
        started = time.time()
        cls.outcome = run_script(SCRIPT, cls.originals, cls.root / "Redacted", "--blank", BLANK_LETTER,
                             "--check-dir", cls.root / "Teacher only" / "Check")
        cls.seconds = time.time() - started

    @classmethod
    def tearDownClass(cls):
        shutil.rmtree(cls.root, ignore_errors=True)

    def line_for(self, identifier):
        for line in self.outcome.stdout.splitlines():
            if line.startswith(f"Section 1/{identifier}.pdf:"):
                return line
        self.fail(f"no line for {identifier}:\n{self.outcome.stdout}")

    def test_every_variant_is_stopped_or_blanked_with_no_name_ink_left(self):
        cases = redaction()["scanCases"]["cases"]
        self.assertEqual(sorted(case["variant"] for case in cases), sorted(variant for variant, _masks in self.made.values()),
                         "the contract's scan cases and the variants this test builds are the same list")
        by_variant = {variant: identifier for identifier, (variant, _masks) in self.made.items()}
        report = []
        for case in cases:
            identifier = by_variant[case["variant"]]
            masks = self.made[identifier][1]
            line = self.line_for(identifier)
            blanked = self.root / "Redacted" / "Section 1" / (identifier + ".pdf")
            if "CHECK" in line:
                self.assertNotEqual(case["expect"], "written", f"{case['variant']} must be written: {line}")
                self.assertFalse(blanked.exists(), f"{case['variant']}: a CHECK file must not be written")
                report.append(f"{case['variant']}: CHECK")
                continue
            self.assertNotEqual(case["expect"], "CHECK", f"{case['variant']} must be stopped: {line}")
            self.assertIn("header matches your blank test", line, case["variant"])
            self.assertNotIn(" OK", line, "the line says what was measured, never OK")
            left = ink_left_outside_the_box(blanked, masks, turned_pages(line))
            report.append(f"{case['variant']}: written, {left} name pixels left")
            self.assertEqual(left, 0, f"{case['variant']}: name ink is visible in a written file")
        print("\n" + "\n".join(report) + f"\n({self.seconds:.1f} s for {2 * len(self.made)} pages)")

    def test_the_duplex_paper_has_its_page_turned_upright(self):
        self.assertIn("box placed on 2; header matches your blank test", self.line_for("Student A"))
        self.assertIn("page 2 turned upright", self.line_for("Student G"))

    def test_the_box_is_black_and_nothing_sits_under_it(self):
        blanked = self.root / "Redacted" / "Section 1" / "Student A.pdf"
        data = blanked.read_bytes()
        self.assertNotIn(b"/Font", data)
        text = subprocess.run(["pdftotext", str(blanked), "-"], capture_output=True, text=True).stdout.strip()
        self.assertEqual(text, "")
        box_pt = (BOX[0] * 72, 792 - BOX[3] * 72, BOX[2] * 72, 792 - BOX[1] * 72)
        pictures = placed_pictures(data)
        self.assertGreater(len(pictures), 0)
        for x0, y0, x1, y1 in pictures:
            overlap_x = min(x1, box_pt[2]) - max(x0, box_pt[0])
            overlap_y = min(y1, box_pt[3]) - max(y0, box_pt[1])
            self.assertFalse(overlap_x > 0.5 and overlap_y > 0.5, "a picture is placed across the box")
        for page in (1, 2):
            width, _height, pixels = render(blanked, page, 150)
            for row in range(round(BOX[1] * 150) + 1, round(BOX[3] * 150) - 1):
                self.assertEqual(max(pixels[row * width + round(BOX[0] * 150) + 1: row * width + round(BOX[2] * 150) - 1]), 0)

    def test_the_body_of_page_two_is_left_as_it_was(self):
        blanked = self.root / "Redacted" / "Section 1" / "Student A.pdf"
        width, _height, pixels = render(blanked, 2)
        x0, y0, x1, y1 = BODY_STROKES[0]
        dark = 0
        for row in range(int(y0 * DPI) + 2, int(y1 * DPI) - 2):
            for column in range(int(x0 * DPI) + 2, int(x1 * DPI) - 2):
                if pixels[row * width + column] < 100:
                    dark += 1
        self.assertGreater(dark, 100, "a name written in the body is not blanked: that is what the skim is for")

    def test_a_file_not_named_like_an_identifier_is_counted_and_never_named(self):
        said = self.outcome.stdout + self.outcome.stderr
        for token in INVENTED:
            self.assertNotIn(token.casefold(), said.casefold())
        self.assertIn("1 files or folders not named like an identifier were left alone", said)
        written = sorted(path.name for path in (self.root / "Redacted").rglob("*.pdf"))
        for name in written:
            self.assertRegex(name, r"^Student [A-Z]{1,2}\.pdf$")

    def test_the_check_files_are_written_on_the_teachers_side(self):
        check = self.root / "Teacher only" / "Check"
        self.assertTrue((check / "Name box check.pdf").exists())
        skim = check / "Blanked papers to skim.pdf"
        written = list((self.root / "Redacted").rglob("*.pdf"))
        self.assertEqual(page_count(skim), 2 * len(written))
        self.assertEqual(page_count(check / "Name box check.pdf"), math.ceil(2 * len(self.made) / 6))
        self.assertNotEqual(self.outcome.returncode, 0, "a run with any CHECK exits 1")


@unittest.skipIf(MISSING, SKIP_REASON)
class BoxAndRefusalTests(unittest.TestCase):

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
            self.assertEqual(result.returncode, 0, result.stdout)
            lines = result.stdout.splitlines()
            self.assertEqual(len(lines), page_count(FIXTURES / case["blank"]), case["name"])
            for line in lines:
                values = [float(value) for value in line.split("box in inches ")[1].split(",")]
                for found, expected in zip(values, case["box"]):
                    self.assertAlmostEqual(found, expected, delta=case["within"], msg=f"{case['name']}: {line}")

    def test_only_files_named_like_an_identifier_are_papers(self):
        cases = assessment()["identifiers"]["cases"]
        with tempfile.TemporaryDirectory() as root:
            originals = Path(root) / "Originals"
            originals.mkdir()
            build_scans(BLANK_LETTER, Path(root) / "made", {"upright"})
            scan = (Path(root) / "made" / "Section 1" / "Student A.pdf").read_bytes()
            for case in cases:
                (originals / case["file"]).write_bytes(scan)
            result = run_script(SCRIPT, originals, Path(root) / "Redacted", "--blank", BLANK_LETTER, "--check-dir", Path(root) / "Check")
            papers = [case for case in cases if case["isAPaper"]]
            for case in cases:
                stem = case["file"][:-4]
                if case["isAPaper"]:
                    self.assertIn(f"{stem}.pdf: 2 pages, box placed on 2", result.stdout, case["file"])
                else:
                    self.assertNotIn(stem, result.stdout, f"{case['file']} must be counted, never named")
            self.assertIn(f"{len(cases) - len(papers)} files or folders not named like an identifier were left alone", result.stdout)

    def test_a_page_turned_sideways_refuses(self):
        with tempfile.TemporaryDirectory() as root:
            originals = Path(root) / "Originals"
            originals.mkdir()
            pages = [render(BLANK_LETTER, 1), render(BLANK_LETTER, 2)]
            width, height, pixels = pages[1]
            turned = transform(pages[1], height, width, lambda x, y: (y, height - 1 - x), 255)
            write_image_pdf(originals / "Student A.pdf", [pages[0], turned])
            result = run_script(SCRIPT, originals, Path(root) / "Redacted", "--blank", BLANK_LETTER,
                                "--check-dir", Path(root) / "Check")
            self.assertIn("Student A.pdf: CHECK (page 2 is turned sideways)", result.stdout)
            self.assertFalse((Path(root) / "Redacted" / "Student A.pdf").exists())

    def test_a_legal_paper_is_blanked_against_its_legal_blank(self):
        with tempfile.TemporaryDirectory() as root:
            made = build_scans(BLANK_LEGAL, Path(root) / "Originals", {"upright"})
            result = run_script(SCRIPT, Path(root) / "Originals", Path(root) / "Redacted", "--blank", BLANK_LEGAL,
                                "--check-dir", Path(root) / "Check")
            self.assertIn("Section 1/Student A.pdf: 2 pages, box placed on 2; header matches your blank test", result.stdout)
            self.assertEqual(ink_left_outside_the_box(Path(root) / "Redacted" / "Section 1" / "Student A.pdf",
                                                      made["Student A"][1], set()), 0)

    def test_a_letter_paper_against_a_legal_blank_refuses(self):
        with tempfile.TemporaryDirectory() as root:
            build_scans(BLANK_LETTER, Path(root) / "Originals", {"upright"})
            result = run_script(SCRIPT, Path(root) / "Originals", Path(root) / "Redacted", "--blank", BLANK_LEGAL,
                                "--check-dir", Path(root) / "Check")
            self.assertIn("CHECK (page 1 is a different size from your blank test)", result.stdout)

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
            self.assertIn("Section 1: 2 papers renamed; 1 have no row in the table (Paper 03)", named.stdout)
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
            build_scans(BLANK_LETTER, Path(root) / "Originals", {"upright"})
            working = Path(root) / "Working"
            (working / "courses").mkdir(parents=True)
            (working / ".toolchain").mkdir()
            result = run_script(SCRIPT, Path(root) / "Originals", working / "Marking" / "Redacted", "--blank", BLANK_LETTER,
                                "--check-dir", Path(root) / "Check")
            self.assertEqual(result.returncode, 1)
            self.assertIn("inside the Plantoir working folder", result.stdout)
            self.assertFalse((working / "Marking").exists())

    def test_a_page_with_no_name_box_on_the_blank_is_said(self):
        # 750a review H2: a page whose blank test has no Name blank gets no box, and the line says so.
        blank = FIXTURES / "blank-quiz-letter-name-on-page-1.pdf"
        boxes = run_script(SCRIPT, "--box-from", blank)
        self.assertIn("page 1: box in inches 3.44,0.20,5.33,0.89", boxes.stdout)
        self.assertIn("page 2: no 'Name' label with a writing line, so no box", boxes.stdout,
                      "the starter's School Name is not a name blank")
        with tempfile.TemporaryDirectory() as root:
            pages = [render(blank, 1), render(blank, 2)]
            paint(pages[0], NAME_STROKES, 15)
            (Path(root) / "Originals").mkdir()
            write_image_pdf(Path(root) / "Originals" / "Student A.pdf", pages)
            result = run_script(SCRIPT, Path(root) / "Originals", Path(root) / "Redacted", "--blank", blank,
                                "--check-dir", Path(root) / "Check")
            self.assertIn("Student A.pdf: 2 pages, box placed on 1; header matches your blank test; page 2 has no name box "
                          "on your blank test, so nothing there was blanked", result.stdout)
            self.assertIn("whose blank test has one", result.stdout)
            self.assertNotIn("each page and", result.stdout)

    def test_its_own_self_test_passes(self):
        result = run_script(SCRIPT, "--self-test")
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
        self.assertIn("self-test passed", result.stdout)


if __name__ == "__main__":
    unittest.main()
