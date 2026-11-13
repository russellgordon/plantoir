#!/usr/bin/env python3
"""Blank the name box at the top of every scanned page, after checking each page against the BLANK test.

Part of the plantoir-marking skill. A STARTING POINT: copy it into the marking folder's Scripts/ folder,
adjust it to this teacher's header (see the two MARK blocks below), run --self-test, and only then use it.

    python3 -B redact_scans.py ORIGINALS REDACTED --blank BLANK.pdf --check-dir CHECK [--label Name]
                               [--box x0,y0,x1,y1] [--dpi 150] [--identifiers REGEX]
    python3 -B redact_scans.py --box-from BLANK.pdf [--label Name]
    python3 -B redact_scans.py --stack STACK.pdf --pages-per-paper N --into FOLDER --check-dir CHECK
    python3 -B redact_scans.py --name-papers TABLE --section N --into FOLDER
    python3 -B redact_scans.py --self-test

ORIGINALS holds one PDF per student named by identifier (Student A.pdf), directly or in "Section N"
folders; REDACTED gets the same layout. BLANK is the test as printed, with nothing written on it (the
kit's Version A.pdf, say): it holds no student data, so reading it is safe. CHECK is in the TEACHER-ONLY
folder: it gets "Name box check.pdf" (the top of every original page with the box outlined) and
"Blanked papers to skim.pdf" (every blanked page, one file). The assistant never opens either.

How a page is checked before it is blanked, and why (a box that misses its header says nothing):
  - its size against the blank test's page;
  - where its header and footer are against the blank test's: one-dimensional ink profiles (rows and
    columns) of the top left of the page and of the foot, each slid against the blank's to find the
    shift. From three shifts the script works out where the blank's name box lands on this page. If any
    corner of it lands more than 0.1 in from where the box will be painted, or the page is scaled by
    more than 2 percent, the file is NOT written and the line says CHECK and why;
  - a page that lines up only when turned half a turn is upside down: it is turned upright, blanked,
    and said so;
  - ink just around the box (0.25 in) that the blank test does not have there, once the page is lined
    up, is writing that runs past the box: a name written longer than the line, or above or below it.
    More than a speck of it stops the file with CHECK.
The success line says what was measured: "box placed; header matches your blank test". It never says
OK about coverage it did not measure. A name written anywhere other than the name box is NOT blanked.

Needs Poppler (pdftoppm, pdfinfo, pdftotext, pdfunite, pdfseparate) and the Python standard library.
"""
import os
import re
import shutil
import subprocess
import sys
import tempfile
import zlib
from pathlib import Path

# MARK: - What you may change for this teacher
#   the header label (--label, LABEL), the box margins below, the regions used to line a page up
#   (HEADER_DEPTH_IN, FOOTER_DEPTH_IN), the tolerances, the identifier pattern, the folder names,
#   the wording of the lines it prints, and the resolution.
LABEL = "Name"
BOX_LEFT_MARGIN_PT = 11          # the box starts this far left of the label
BOX_TOP_IN = 0.20                # and this far from the top of the page
BOX_BELOW_LABEL_PT = 12          # and ends this far below the label (handwriting rises and falls)
BOX_BEFORE_NEXT_PT = 3           # and stops this far before the next word on the line (Date)
LABEL_SEARCH_DEPTH_IN = 1.5      # the label is looked for in the top of the page only
HEADER_DEPTH_IN = 1.6            # the band at the top used to line a page up
FOOTER_DEPTH_IN = 1.2            # the band at the foot used to line a page up
SHIFT_TOLERANCE_IN = 0.10        # how far the box may land from the blank test's name box
SCALE_TOLERANCE = 0.02           # how much a page may be shrunk or enlarged
SIZE_TOLERANCE_IN = 0.08         # how far a page's size may differ from the blank test's
SEARCH_IN = 0.8                  # how far a header is looked for, either way
PROFILE_DPI = 50                 # pixels per inch for lining up
INK_NEIGHBOURS = 2               # ink has at least this many ink neighbours; a lone speck has none
SMOOTHING = 2                    # profile values averaged this many either way (0.04 in at 50 dpi)
INK_STEP = 40                    # how much darker than the paper a pixel must be to count as ink
RING_IN = 0.25                   # how far around the box writing past it is looked for
RING_DPI = 100                   # pixels per inch for that look
RING_STEP = 80                   # how much darker than the paper a pixel must be there to count as writing
RING_SLACK = 1                   # pixels either way the blank's own print may sit after lining up
RING_SEARCH = 3                  # pixels either way the last of the lining up is looked for
RING_LIMIT = 10                  # pixels of writing past the box that stop the file (0.001 square inches)
MIN_MATCH = 0.55                 # how well a profile must match the blank test's to be trusted
DPI = 150                        # pixels per inch for the blanked pages
JPEG_QUALITY = 75
IDENTIFIER = r"^Student [A-Z]{1,2}$"
SECTION = r"^Section \d+$"
NAME_BOX_CHECK = "Name box check.pdf"
SKIM_FILE = "Blanked papers to skim.pdf"
PAPERS_TO_NAME = "Papers to name.pdf"

# MARK: - What must not change
#   never print, log or write outside the teacher-only folder any value read from a name mapping table;
#   never print a file name that is not an identifier (or a Section / Paper label this script made);
#   capture every program's output and print only counts and identifiers; refuse (exit 1, with an
#   identifier-only message) when anything is unexpected; never write a page whose header does not
#   match the blank test; never render the box's own pixels into a blanked page; never say OK about
#   coverage that was not measured.

TOOLS = ("pdftoppm", "pdfinfo", "pdftotext", "pdfunite", "pdfseparate")


class Refusal(Exception):
    """A reason to stop, worded for the teacher, holding no file name that is not an identifier."""


# ---------------------------------------------------------------- running Poppler


def run(command):
    """Run a program with its output captured; the output is never printed."""
    result = subprocess.run(command, capture_output=True)
    if result.returncode != 0:
        raise Refusal(f"{command[0]} could not read a file")
    return result


def need_tools():
    missing = []
    for tool in TOOLS:
        if shutil.which(tool) is None:
            missing.append(tool)
    if missing:
        raise Refusal("Poppler is not installed (" + ", ".join(missing) + " not found). "
                      "On a Mac with Homebrew: brew install poppler. Nothing was read.")


def page_sizes(pdf):
    """[(width_pt, height_pt), ...] as the page is shown, a page's rotation included."""
    info = run(["pdfinfo", "-f", "1", "-l", "100000", str(pdf)]).stdout.decode("latin-1")
    sizes = {}
    rotations = {}
    for match in re.finditer(r"Page\s+(\d+) size:\s+([\d.]+) x ([\d.]+)", info):
        sizes[int(match.group(1))] = (float(match.group(2)), float(match.group(3)))
    for match in re.finditer(r"Page\s+(\d+) rot:\s+(\d+)", info):
        rotations[int(match.group(1))] = int(match.group(2)) % 360
    result = []
    for number in sorted(sizes):
        width, height = sizes[number]
        if rotations.get(number, 0) in (90, 270):
            width, height = height, width
        result.append((width, height))
    if not result:
        raise Refusal("a file has no pages")
    return result


def read_pgm(path):
    data = Path(path).read_bytes()
    match = re.match(rb"P5\s+(\d+)\s+(\d+)\s+(\d+)\s", data)
    if match is None:
        raise Refusal("a page could not be read")
    width = int(match.group(1))
    height = int(match.group(2))
    pixels = data[match.end():match.end() + width * height]
    return width, height, pixels


def render_gray(pdf, page, dpi, folder, crop=None):
    """(width, height, bytes) of one page in grey, optionally only a pixel rectangle (x, y, w, h)."""
    base = os.path.join(folder, "render")
    command = ["pdftoppm", "-gray", "-r", str(dpi), "-f", str(page), "-l", str(page), "-singlefile"]
    if crop is not None:
        command += ["-x", str(crop[0]), "-y", str(crop[1]), "-W", str(crop[2]), "-H", str(crop[3])]
    run(command + [str(pdf), base])
    image = read_pgm(base + ".pgm")
    os.remove(base + ".pgm")
    return image


def render_jpeg(pdf, page, dpi, folder, crop):
    base = os.path.join(folder, "tile")
    run(["pdftoppm", "-jpeg", "-jpegopt", f"quality={JPEG_QUALITY}", "-r", str(dpi), "-f", str(page),
         "-l", str(page), "-singlefile", "-x", str(crop[0]), "-y", str(crop[1]), "-W", str(crop[2]),
         "-H", str(crop[3]), str(pdf), base])
    data = Path(base + ".jpg").read_bytes()
    os.remove(base + ".jpg")
    return data


def text_of(pdf):
    return run(["pdftotext", str(pdf), "-"]).stdout.decode("utf-8", "replace").strip()


# ---------------------------------------------------------------- a small PDF writer


class PdfWriter:
    """Pages of JPEG pictures, filled rectangles, outlines and Helvetica labels. Nothing else."""

    def __init__(self):
        self.objects = []
        self.pages = []

    def add(self, body):
        self.objects.append(body)
        return len(self.objects)

    def jpeg(self, data, width, height):
        header = (b"<</Type/XObject/Subtype/Image/Width %d/Height %d/ColorSpace/DeviceRGB"
                  b"/BitsPerComponent 8/Filter/DCTDecode/Length %d>>stream\n" % (width, height, len(data)))
        return self.add(header + data + b"\nendstream")

    def gray(self, pixels, width, height):
        packed = zlib.compress(bytes(pixels), 6)
        header = (b"<</Type/XObject/Subtype/Image/Width %d/Height %d/ColorSpace/DeviceGray"
                  b"/BitsPerComponent 8/Filter/FlateDecode/Length %d>>stream\n" % (width, height, len(packed)))
        return self.add(header + packed + b"\nendstream")

    def page(self, width_pt, height_pt, images, content, with_font=False):
        """images: {name: object number}; content: the page's drawing operators (bytes)."""
        resources = b""
        for name in images:
            resources += b"/%s %d 0 R" % (name.encode("ascii"), images[name])
        font = b"/Font<</F1<</Type/Font/Subtype/Type1/BaseFont/Helvetica>>>>" if with_font else b""
        stream = self.add(b"<</Length %d>>stream\n" % len(content) + content + b"\nendstream")
        self.pages.append((width_pt, height_pt, resources, font, stream))

    def write(self, path):
        pages_number = self.add(b"")
        kids = []
        for width_pt, height_pt, resources, font, stream in self.pages:
            kids.append(self.add(b"<</Type/Page/Parent %d 0 R/MediaBox[0 0 %.2f %.2f]/Resources<</XObject<<%s>>%s>>"
                                 b"/Contents %d 0 R>>" % (pages_number, width_pt, height_pt, resources, font, stream)))
        kid_list = b" ".join(b"%d 0 R" % kid for kid in kids)
        self.objects[pages_number - 1] = b"<</Type/Pages/Kids[%s]/Count %d>>" % (kid_list, len(kids))
        catalog = self.add(b"<</Type/Catalog/Pages %d 0 R>>" % pages_number)
        body = bytearray(b"%PDF-1.4\n")
        offsets = []
        for number, data in enumerate(self.objects, start=1):
            offsets.append(len(body))
            body += b"%d 0 obj\n" % number + data + b"\nendobj\n"
        start = len(body)
        body += b"xref\n0 %d\n0000000000 65535 f \n" % (len(self.objects) + 1)
        for offset in offsets:
            body += b"%010d 00000 n \n" % offset
        body += b"trailer<</Size %d/Root %d 0 R>>\nstartxref\n%d\n%%%%EOF\n" % (len(self.objects) + 1, catalog, start)
        Path(path).write_bytes(bytes(body))


def pdf_text(text):
    return text.replace("\\", "\\\\").replace("(", "\\(").replace(")", "\\)").encode("latin-1", "replace")


# ---------------------------------------------------------------- the box, read from the blank test


def normalised(word):
    return re.sub(r"[^\w#]", "", word).casefold()


def words_near_top(blank, page):
    xml = run(["pdftotext", "-f", str(page), "-l", str(page), "-bbox", str(blank), "-"]).stdout.decode("utf-8", "replace")
    words = []
    for match in re.finditer(r'xMin="([\d.]+)" yMin="([\d.]+)" xMax="([\d.]+)" yMax="([\d.]+)">([^<]*)<', xml):
        x0, y0, x1, y1 = (float(match.group(index)) for index in range(1, 5))
        if y0 < LABEL_SEARCH_DEPTH_IN * 72:
            words.append((x0, y0, x1, y1, match.group(5)))
    return words


def rule_follows(image, dpi, word):
    """True when a horizontal line starts just after the word, near its baseline (a blank to write on)."""
    width, height, pixels = image
    scale = dpi / 72
    start = int(word[2] * scale) + 1
    stop = min(width, start + int(0.6 * dpi))
    for row in range(max(0, int(word[3] * scale) - 3), min(height, int(word[3] * scale) + 4)):
        run_length = 0
        best = 0
        for column in range(start, stop):
            if pixels[row * width + column] < 160:
                run_length += 1
                best = max(best, run_length)
            else:
                run_length = 0
        if best >= int(0.4 * dpi):
            return True
    return False


def box_for_page(blank, page, label, page_width_pt, folder):
    """The name box in inches (x0, y0, x1, y1) from the top-left of this page of the blank, or None."""
    words = words_near_top(blank, page)
    wanted = normalised(label)
    candidates = []
    for word in words:
        if normalised(word[4]) == wanted:
            candidates.append(word)
    if not candidates:
        return None
    image = render_gray(blank, page, 100, folder)
    ruled = []
    for word in candidates:
        if rule_follows(image, 100, word):
            ruled.append(word)
    chosen = ruled[-1] if ruled else candidates[-1]
    following = []
    for word in words:
        if abs(word[1] - chosen[1]) < 2 and word[0] > chosen[2]:
            following.append(word)
    following.sort()
    right = following[0][0] - BOX_BEFORE_NEXT_PT if following else page_width_pt - 54
    return ((chosen[0] - BOX_LEFT_MARGIN_PT) / 72, BOX_TOP_IN, right / 72, (chosen[3] + BOX_BELOW_LABEL_PT) / 72)


def boxes_from_blank(blank, label, given_box, folder):
    """One entry per page of the blank: the box in inches, or None for a page with no name label."""
    sizes = page_sizes(blank)
    if given_box is not None:
        return [given_box] * len(sizes)   # the teacher said where the name is: every page gets the box
    boxes = []
    for number, (width_pt, _height) in enumerate(sizes, start=1):
        boxes.append(box_for_page(blank, number, label, width_pt, folder))
    if boxes[0] is None:
        raise Refusal(f"there is no '{label}' label at the top of page 1 of your blank test. "
                      "Give the label another word with --label (such as Nom), or the box in inches with --box.")
    return boxes


# ---------------------------------------------------------------- lining a page up with the blank test


def ink_of(image):
    """The page's ink as darkness (0 = paper), in the bands at its top and foot that are lined up.

    A pixel is ink when it is clearly darker than the paper (the page's median) AND two of its
    neighbours are too, so the lone specks of a phone or copier scan do not count; the paper's own grey is taken off."""
    width, height, pixels = image
    sample = sorted(pixels[::7])
    paper = sample[len(sample) // 2] if sample else 255
    darkness = bytearray(width * height)
    top = min(height, int((HEADER_DEPTH_IN + SEARCH_IN) * PROFILE_DPI) + 1)
    bottom = max(0, height - int((FOOTER_DEPTH_IN + SEARCH_IN) * PROFILE_DPI) - 1)
    bands = [(0, top), (max(top, bottom), height)]
    for first, last in bands:
        for row in range(first, last):
            for column in range(width):
                value = paper - pixels[row * width + column]
                if value <= INK_STEP:
                    continue
                neighbours = 0
                for neighbour_row in (row - 1, row, row + 1):
                    if neighbour_row < 0 or neighbour_row >= height:
                        continue
                    for neighbour_column in (column - 1, column, column + 1):
                        if neighbour_column < 0 or neighbour_column >= width:
                            continue
                        if neighbour_row == row and neighbour_column == column:
                            continue
                        if paper - pixels[neighbour_row * width + neighbour_column] > INK_STEP:
                            neighbours += 1
                supported = neighbours >= INK_NEIGHBOURS
                if supported:
                    darkness[row * width + column] = min(255, value)
    return width, height, bytes(darkness)


def darkness_profile(image, columns, rows, axis):
    """Sum of ink along one axis of a pixel rectangle: axis 'rows' gives one value per row."""
    width, height, pixels = image
    c0, c1 = max(0, columns[0]), min(width, columns[1])
    r0, r1 = max(0, rows[0]), min(height, rows[1])
    if axis == "rows":
        profile = []
        for row in range(rows[0], rows[1]):
            if row < r0 or row >= r1 or c1 <= c0:
                profile.append(0)
                continue
            profile.append(sum(pixels[row * width + c0: row * width + c1]))
        return profile
    profile = [0] * (columns[1] - columns[0])
    for row in range(r0, r1):
        line = pixels[row * width: row * width + width]
        for column in range(c0, c1):
            profile[column - columns[0]] += line[column]
    return profile


def smoothed(profile):
    """Each value averaged with its neighbours, SMOOTHING either way, so a letter that lands one pixel
    over after a scan still lines up with itself."""
    result = []
    for index in range(len(profile)):
        window = profile[max(0, index - SMOOTHING): index + SMOOTHING + 1]
        result.append(sum(window) / len(window))
    return result


def correlation(first, second):
    count = len(first)
    if count == 0:
        return 0.0
    mean_first = sum(first) / count
    mean_second = sum(second) / count
    top = 0.0
    left = 0.0
    right = 0.0
    for a, b in zip(first, second):
        top += (a - mean_first) * (b - mean_second)
        left += (a - mean_first) ** 2
        right += (b - mean_second) ** 2
    if left == 0 or right == 0:
        return 0.0
    return top / (left * right) ** 0.5


def best_shift(blank_image, scan_image, columns, rows, axis, search):
    """(shift in pixels, match) sliding the scan's profile of a region against the blank's."""
    reference = darkness_profile(blank_image, columns, rows, axis)
    if max(reference) - min(reference) < 100:   # no print in this region of the blank test
        return None
    if axis == "rows":
        wide = darkness_profile(scan_image, columns, (rows[0] - search, rows[1] + search), axis)
    else:
        wide = darkness_profile(scan_image, (columns[0] - search, columns[1] + search), rows, axis)
    reference = smoothed(reference)
    wide = smoothed(wide)
    best = (0, -2.0)
    for shift in range(-search, search + 1):
        piece = wide[search + shift: search + shift + len(reference)]
        match = correlation(reference, piece)
        if match > best[1]:
            best = (shift, match)
    return best


def centre_of(profile):
    total = sum(profile)
    if total == 0:
        return len(profile) / 2
    weighted = 0.0
    for index, value in enumerate(profile):
        weighted += index * value
    return weighted / total


def rotate_half_turn(image):
    width, height, pixels = image
    return width, height, bytes(reversed(pixels))


def line_up(blank_image, scan_image, box_in):
    """Where the blank's name box lands on the scan, from shifts of three regions.

    Returns (worst corner distance in inches, scale error, weakest match)."""
    width, height, _pixels = blank_image
    dpi = PROFILE_DPI
    search = int(SEARCH_IN * dpi)
    head = (0, int(HEADER_DEPTH_IN * dpi))
    foot = (height - int(FOOTER_DEPTH_IN * dpi), height)
    box_left = int(box_in[0] * dpi)
    regions = [
        ("head", (0, box_left), head),
        ("foot left", (0, width // 2), foot),
        ("foot right", (width // 2, width), foot),
    ]
    points = []
    weakest = 1.0
    for _name, columns, rows in regions:
        vertical = best_shift(blank_image, scan_image, columns, rows, "rows", search)
        horizontal = best_shift(blank_image, scan_image, columns, rows, "columns", search)
        if vertical is None or horizontal is None:
            continue
        weakest = min(weakest, vertical[1], horizontal[1])
        # A shift belongs to where the print is, not to the middle of the region: its ink's centre.
        centre_x = columns[0] + centre_of(darkness_profile(blank_image, columns, rows, "columns"))
        centre_y = rows[0] + centre_of(darkness_profile(blank_image, columns, rows, "rows"))
        points.append((centre_x, centre_y, horizontal[0], vertical[0]))
    if len(points) < 3:
        return None
    # Solve x' - x = a x + b y + c and y' - y = d x + e y + f through the three points.
    (x1, y1, u1, v1), (x2, y2, u2, v2), (x3, y3, u3, v3) = points[:3]
    determinant = x1 * (y2 - y3) - y1 * (x2 - x3) + (x2 * y3 - x3 * y2)
    if abs(determinant) < 1e-6:
        return None

    def solve(t1, t2, t3):
        a = (t1 * (y2 - y3) - y1 * (t2 - t3) + (t2 * y3 - t3 * y2)) / determinant
        b = (x1 * (t2 - t3) - t1 * (x2 - x3) + (x2 * t3 - x3 * t2)) / determinant
        c = (x1 * (y2 * t3 - y3 * t2) - y1 * (x2 * t3 - x3 * t2) + t1 * (x2 * y3 - x3 * y2)) / determinant
        return a, b, c

    a, b, c = solve(u1, u2, u3)
    d, e, f = solve(v1, v2, v3)
    worst = 0.0
    for corner_x in (box_in[0], box_in[2]):
        for corner_y in (box_in[1], box_in[3]):
            x = corner_x * dpi
            y = corner_y * dpi
            moved = ((a * x + b * y + c) ** 2 + (d * x + e * y + f) ** 2) ** 0.5 / dpi
            worst = max(worst, moved)
    scale_error = max(abs(a), abs(e))
    centre_x = (box_in[0] + box_in[2]) / 2 * dpi
    centre_y = (box_in[1] + box_in[3]) / 2 * dpi
    shift = ((a * centre_x + b * centre_y + c) / dpi, (d * centre_x + e * centre_y + f) / dpi)
    return worst, scale_error, weakest, shift


def compare_with_blank(blank_image, scan_image, box_in):
    """('upright' | 'upside down', None, shift in inches at the box) when the page lines up, or (None, reason, None)."""
    upright = line_up(blank_image, scan_image, box_in)
    turned = line_up(blank_image, rotate_half_turn(scan_image), box_in)

    def fits(result):
        return (result is not None and result[2] >= MIN_MATCH and result[0] <= SHIFT_TOLERANCE_IN
                and result[1] <= SCALE_TOLERANCE)

    if fits(upright) and (not fits(turned) or upright[2] >= turned[2]):
        return "upright", None, upright[3]
    if fits(turned):
        return "upside down", None, turned[3]
    candidates = [result for result in (upright, turned) if result is not None]
    if not candidates:
        return None, "the top and foot of the page could not be lined up with your blank test", None
    result = max(candidates, key=lambda measured: measured[2])
    if result[2] < MIN_MATCH:
        return None, "the top and foot of the page do not match your blank test (another page, or crooked)", None
    if result[1] > SCALE_TOLERANCE:
        return None, f"the page is shrunk or enlarged by about {round(result[1] * 100)} percent against your blank test", None
    return None, f"the header is about {result[0]:.2f} in from where your blank test puts it", None


def writing_past_the_box(source, page, blank_page_image, box_in, shift_in, upside_down, size_pt, folder):
    """How many pixels of ink just outside the box (within RING_IN of it) the blank test does not have there.

    A name written longer than the blank, or above or below it, shows past the box: this is that ink,
    after the page is lined up with the blank (the shift found at the box) and lone specks are dropped."""
    width = round(size_pt[0] / 72 * RING_DPI)
    height = round(size_pt[1] / 72 * RING_DPI)
    x0 = max(0, round((box_in[0] - RING_IN) * RING_DPI))
    y0 = max(0, round((box_in[1] - RING_IN) * RING_DPI))
    x1 = min(width, round((box_in[2] + RING_IN) * RING_DPI))
    y1 = min(height, round((box_in[3] + RING_IN) * RING_DPI))
    if upside_down:
        crop = (width - x1, height - y1, x1 - x0, y1 - y0)
    else:
        crop = (x0, y0, x1 - x0, y1 - y0)
    crop_width, crop_height, crop_pixels = render_gray(source, page, RING_DPI, folder, crop)
    if upside_down:
        crop_pixels = bytes(reversed(crop_pixels))
    sample = sorted(crop_pixels[::3])
    paper = sample[len(sample) // 2] if sample else 255
    blank_width, blank_height, blank_pixels = blank_page_image
    shift_x = round(shift_in[0] * RING_DPI)
    shift_y = round(shift_in[1] * RING_DPI)
    box_x0, box_y0 = round(box_in[0] * RING_DPI), round(box_in[1] * RING_DPI)
    box_x1, box_y1 = round(box_in[2] * RING_DPI), round(box_in[3] * RING_DPI)

    def scan_ink(column, row):
        return 0 <= column < crop_width and 0 <= row < crop_height and paper - crop_pixels[row * crop_width + column] > RING_STEP

    writing = []
    for row in range(crop_height):
        for column in range(crop_width):
            x, y = x0 + column, y0 + row
            if box_x0 <= x < box_x1 and box_y0 <= y < box_y1:
                continue
            if not scan_ink(column, row):
                continue
            neighbours = 0
            for neighbour_row in (row - 1, row, row + 1):
                for neighbour_column in (column - 1, column, column + 1):
                    if (neighbour_row, neighbour_column) != (row, column) and scan_ink(neighbour_column, neighbour_row):
                        neighbours += 1
            if neighbours >= INK_NEIGHBOURS:
                writing.append((x, y))
    if not writing:
        return 0
    # The blank's print near the box, widened by RING_SLACK, at the blank's own place.
    reach = RING_SEARCH + RING_SLACK + max(abs(shift_x), abs(shift_y))
    printed = set()
    for blank_y in range(max(0, y0 - reach), min(blank_height, y1 + reach)):
        for blank_x in range(max(0, x0 - reach), min(blank_width, x1 + reach)):
            if blank_pixels[blank_y * blank_width + blank_x] < 200:
                for near_y in range(blank_y - RING_SLACK, blank_y + RING_SLACK + 1):
                    for near_x in range(blank_x - RING_SLACK, blank_x + RING_SLACK + 1):
                        printed.add((near_x, near_y))
    # The lining up is to about 0.02 in; the last few pixels are found here, where the least ink is left over.
    unexplained = len(writing)
    for offset_y in range(-RING_SEARCH, RING_SEARCH + 1):
        for offset_x in range(-RING_SEARCH, RING_SEARCH + 1):
            left_over = 0
            for x, y in writing:
                if (x - shift_x - offset_x, y - shift_y - offset_y) not in printed:
                    left_over += 1
                    if left_over >= unexplained:
                        break
            unexplained = min(unexplained, left_over)
    return unexplained


# ---------------------------------------------------------------- blanking one file


def tiles_around(width, height, box_px):
    x0, y0, x1, y1 = box_px
    return [(0, 0, width, y0), (0, y0, x0, y1 - y0), (x1, y0, width - x1, y1 - y0), (0, y1, width, height - y1)]


def blank_page(writer, source, page, size_pt, box_in, upside_down, folder):
    """Add one blanked page: the tiles AROUND the box, rendered from the original; the box filled black."""
    width_pt, height_pt = size_pt
    width = round(width_pt / 72 * DPI)
    height = round(height_pt / 72 * DPI)
    images = {}
    content = b""
    if box_in is None:
        box_px = (0, 0, 0, 0)
    else:
        box_px = (round(box_in[0] * DPI), max(0, round(box_in[1] * DPI)),
                  min(width, round(box_in[2] * DPI)), min(height, round(box_in[3] * DPI)))
    tiles = [(0, 0, width, height)] if box_in is None else tiles_around(width, height, box_px)
    for number, (x, y, tile_width, tile_height) in enumerate(tiles):
        if tile_width <= 0 or tile_height <= 0:
            continue
        if upside_down:
            source_x, source_y = width - x - tile_width, height - y - tile_height
        else:
            source_x, source_y = x, y
        data = render_jpeg(source, page, DPI, folder, (source_x, source_y, tile_width, tile_height))
        name = f"T{number}"
        images[name] = writer.jpeg(data, tile_width, tile_height)
        left = x * 72 / DPI
        bottom = height_pt - (y + tile_height) * 72 / DPI
        drawn_width = tile_width * 72 / DPI
        drawn_height = tile_height * 72 / DPI
        if upside_down:
            content += b"q %.3f 0 0 %.3f %.3f %.3f cm /%s Do Q\n" % (
                -drawn_width, -drawn_height, left + drawn_width, bottom + drawn_height, name.encode("ascii"))
        else:
            content += b"q %.3f 0 0 %.3f %.3f %.3f cm /%s Do Q\n" % (
                drawn_width, drawn_height, left, bottom, name.encode("ascii"))
    if box_in is not None:
        x0, y0, x1, y1 = box_px
        content += b"0 g %.3f %.3f %.3f %.3f re f\n" % (
            x0 * 72 / DPI, height_pt - y1 * 72 / DPI, (x1 - x0) * 72 / DPI, (y1 - y0) * 72 / DPI)
    writer.page(width_pt, height_pt, images, content)


def verify_blanked(path, boxes, blank, blank_images, folder):
    """Read the written file back: every box pixel black, no text, every page lined up and upright."""
    sizes = page_sizes(path)
    if len(sizes) != len(boxes):
        return "the blanked file does not have the same number of pages"
    if text_of(path):
        return "the blanked file has text in it"
    for number, box_in in enumerate(boxes, start=1):
        if box_in is not None:
            width, height, pixels = render_gray(path, number, DPI, folder)
            x0, y0 = round(box_in[0] * DPI), round(box_in[1] * DPI)
            x1, y1 = min(width, round(box_in[2] * DPI)), min(height, round(box_in[3] * DPI))
            for row in range(y0 + 1, y1 - 1):
                if max(pixels[row * width + x0 + 1: row * width + x1 - 1]) != 0:
                    return f"page {number}: the box is not black all through"
        scan_image = ink_of(render_gray(path, number, PROFILE_DPI, folder))
        way, _reason, _shift = compare_with_blank(blank_images[number - 1], scan_image, boxes[0])
        if way != "upright":
            return f"page {number}: the blanked page does not line up with your blank test"
    return None


def identifier_files(originals, identifier):
    """[(relative label, path)] for every PDF named like an identifier; and the count left alone."""
    found = []
    left_alone = 0
    for entry in sorted(Path(originals).iterdir()):
        if entry.name.startswith("."):
            continue
        if entry.is_dir() and re.match(SECTION, entry.name):
            for inner in sorted(entry.iterdir()):
                if inner.name.startswith("."):
                    continue
                if inner.is_file() and inner.suffix.lower() == ".pdf" and re.match(identifier, inner.stem):
                    found.append((f"{entry.name}/{inner.stem}", inner))
                else:
                    left_alone += 1
        elif entry.is_file() and entry.suffix.lower() == ".pdf" and re.match(identifier, entry.stem):
            found.append((entry.stem, entry))
        else:
            left_alone += 1
    return found, left_alone


def header_strip(writer, source, page, size_pt, box_in, upside_down, label, folder, slot, page_content):
    """One strip of the name box check: the top of a page as the box will see it, the box outlined in red."""
    width_pt, height_pt = size_pt
    strip_in = min(HEADER_DEPTH_IN, height_pt / 72)
    width = round(width_pt / 72 * 100)
    height = round(strip_in * 100)
    full_height = round(height_pt / 72 * 100)
    y = full_height - height if upside_down else 0
    data = render_jpeg(source, page, 100, folder, (0, y, width, height))
    name = f"S{slot}"
    number = writer.jpeg(data, width, height)
    scale = 0.95 * 612 / width_pt
    drawn_width = width_pt * scale
    drawn_height = strip_in * 72 * scale
    top = 792 - 30 - slot * (drawn_height + 26)
    bottom = top - drawn_height
    left = (612 - drawn_width) / 2
    if upside_down:
        page_content.append(b"q %.3f 0 0 %.3f %.3f %.3f cm /%s Do Q\n" % (
            -drawn_width, -drawn_height, left + drawn_width, bottom + drawn_height, name.encode("ascii")))
    else:
        page_content.append(b"q %.3f 0 0 %.3f %.3f %.3f cm /%s Do Q\n" % (
            drawn_width, drawn_height, left, bottom, name.encode("ascii")))
    if box_in is not None:
        page_content.append(b"q 1 0 0 RG 1.5 w %.3f %.3f %.3f %.3f re S Q\n" % (
            left + box_in[0] * 72 * scale, top - box_in[3] * 72 * scale,
            (box_in[2] - box_in[0]) * 72 * scale, (box_in[3] - box_in[1]) * 72 * scale))
    page_content.append(b"BT /F1 9 Tf %.3f %.3f Td (%s) Tj ET\n" % (left, top + 6, pdf_text(label)))
    return name, number


def write_check_file(entries, path, folder):
    """entries: [(label, source, page, size, box, upside_down)], six strips to a letter page."""
    writer = PdfWriter()
    for start in range(0, len(entries), 6):
        images = {}
        content = []
        for slot, entry in enumerate(entries[start:start + 6]):
            label, source, page, size_pt, box_in, upside_down = entry
            name, number = header_strip(writer, source, page, size_pt, box_in, upside_down, label, folder, slot, content)
            images[name] = number
        writer.page(612, 792, images, b"".join(content), with_font=True)
    if writer.pages:
        writer.write(path)


def redact_folder(originals, redacted, blank, check_dir, label, given_box, identifier):
    need_tools()
    for folder_path, what in ((originals, "the originals folder"), (blank, "the blank test")):
        if not Path(folder_path).exists():
            raise Refusal(f"{what} is not there; nothing was read")
    Path(redacted).mkdir(parents=True, exist_ok=True)
    Path(check_dir).mkdir(parents=True, exist_ok=True)
    blanked_paths = []
    check_entries = []
    totals = {"written": 0, "check": 0, "turned": 0}
    with tempfile.TemporaryDirectory() as folder:
        boxes = boxes_from_blank(blank, label, given_box, folder)
        blank_sizes = page_sizes(blank)
        blank_images = []
        for number in range(1, len(blank_sizes) + 1):
            blank_images.append(ink_of(render_gray(blank, number, PROFILE_DPI, folder)))
        found, left_alone = identifier_files(originals, identifier)
        ring_blanks = {}
        for label_text, source in found:
            reason = None
            ways = []
            try:
                sizes = page_sizes(source)
            except Refusal:
                sizes = []
                reason = "the file could not be read as a PDF"
            if reason is None and len(sizes) != len(blank_sizes):
                reason = f"it has {len(sizes)} pages and your blank test has {len(blank_sizes)}"
            for number, size_pt in enumerate(sizes, start=1):
                if reason is not None:
                    break
                blank_width, blank_height = blank_sizes[number - 1]
                tolerance = SIZE_TOLERANCE_IN * 72
                if abs(size_pt[0] - blank_width) > tolerance or abs(size_pt[1] - blank_height) > tolerance:
                    if abs(size_pt[0] - blank_height) <= tolerance and abs(size_pt[1] - blank_width) <= tolerance:
                        reason = f"page {number} is turned sideways"
                    else:
                        reason = f"page {number} is a different size from your blank test"
                    break
                scan_image = ink_of(render_gray(source, number, PROFILE_DPI, folder))
                way, why, shift = compare_with_blank(blank_images[number - 1], scan_image, boxes[0])
                if way is None:
                    reason = f"page {number}: {why}"
                    break
                page_box = boxes[number - 1]
                if page_box is not None:
                    if number not in ring_blanks:
                        ring_blanks[number] = render_gray(blank, number, RING_DPI, folder)
                    past = writing_past_the_box(source, number, ring_blanks[number], page_box, shift,
                                                way == "upside down", size_pt, folder)
                    if past > RING_LIMIT:
                        reason = f"page {number}: writing runs past the name box, so part of it would show"
                        break
                ways.append(way)
            target = Path(redacted) / (label_text + ".pdf")
            if reason is None:
                writer = PdfWriter()
                for number, size_pt in enumerate(sizes, start=1):
                    blank_page(writer, source, number, size_pt, boxes[number - 1], ways[number - 1] == "upside down", folder)
                target.parent.mkdir(parents=True, exist_ok=True)
                writer.write(target)
                problem = verify_blanked(target, boxes, blank, blank_images, folder)
                if problem is not None:
                    target.unlink()
                    reason = problem
            for number, size_pt in enumerate(sizes, start=1):
                upside_down = reason is None and ways[number - 1] == "upside down"
                page_box = boxes[number - 1] if number <= len(boxes) else boxes[0]
                note = " (turned upright)" if upside_down else ""
                if reason is not None:
                    note = " (CHECK: this file was not blanked)"
                check_entries.append((f"{label_text}, page {number}{note}", source, number, size_pt, page_box, upside_down))
            if reason is not None:
                if target.exists():
                    target.unlink()
                totals["check"] += 1
                print(f"{label_text}.pdf: CHECK ({reason}); not written")
                continue
            turned = []
            for number, way in enumerate(ways, start=1):
                if way == "upside down":
                    turned.append(str(number))
            boxed = sum(1 for box_in in boxes if box_in is not None)
            note = ""
            if turned:
                totals["turned"] += 1
                note = "; page" + ("s " if len(turned) > 1 else " ") + ", ".join(turned) + " turned upright"
            totals["written"] += 1
            blanked_paths.append(str(target))
            print(f"{label_text}.pdf: {len(sizes)} pages, box placed on {boxed}; header matches your blank test{note}")
        write_check_file(check_entries, Path(check_dir) / NAME_BOX_CHECK, folder)
    skim = Path(check_dir) / SKIM_FILE
    if skim.exists():
        skim.unlink()
    if len(blanked_paths) == 1:
        shutil.copyfile(blanked_paths[0], skim)
    elif blanked_paths:
        run(["pdfunite"] + blanked_paths + [str(skim)])
    if left_alone:
        print(f"{left_alone} files or folders not named like an identifier were left alone")
    print(f"{totals['written']} files blanked, {totals['check']} to CHECK; {totals['turned']} had a page turned upright. "
          "The box covers the name box at the top of each page and nothing else: please skim "
          f"'{SKIM_FILE}' and '{NAME_BOX_CHECK}' in your check folder before any paper is read.")
    return 0 if totals["check"] == 0 else 1


# ---------------------------------------------------------------- a whole class in one scan


def split_stack(stack, pages_per_paper, into, check_dir):
    need_tools()
    sizes = page_sizes(stack)
    if pages_per_paper < 1 or len(sizes) % pages_per_paper != 0:
        raise Refusal(f"the stack has {len(sizes)} pages, which is not a whole number of papers of {pages_per_paper} pages")
    Path(into).mkdir(parents=True, exist_ok=True)
    papers = len(sizes) // pages_per_paper
    entries = []
    with tempfile.TemporaryDirectory() as folder:
        run(["pdfseparate", str(stack), os.path.join(folder, "page-%d.pdf")])
        for paper in range(papers):
            label = f"Paper {paper + 1:02d}"
            target = Path(into) / (label + ".pdf")
            if target.exists():
                raise Refusal(f"{label}.pdf is already there; nothing more was written")
            pages = [os.path.join(folder, f"page-{paper * pages_per_paper + index + 1}.pdf") for index in range(pages_per_paper)]
            if len(pages) == 1:
                shutil.copyfile(pages[0], target)
            else:
                run(["pdfunite"] + pages + [str(target)])
            entries.append((label, target, 1, sizes[paper * pages_per_paper], None, False))
        Path(check_dir).mkdir(parents=True, exist_ok=True)
        write_check_file(entries, Path(check_dir) / PAPERS_TO_NAME, folder)
    print(f"{papers} papers of {pages_per_paper} pages written, Paper 01 to Paper {papers:02d}. "
          f"'{PAPERS_TO_NAME}' in your check folder shows the top of each, for you to fill in the paper column "
          "of your name mapping table.")
    return 0


def name_papers(table, section, into, identifier):
    """Rename Paper NN.pdf to its identifier from the table's section, paper and identifier columns only."""
    import csv
    rows = []
    with open(table, newline="", encoding="utf-8-sig") as handle:
        sample = handle.read(4096)
        handle.seek(0)
        dialect = "excel-tab" if "\t" in sample.split("\n")[0] else "excel"
        reader = csv.DictReader(handle, dialect=dialect)
        columns = [column.strip().casefold() for column in (reader.fieldnames or [])]
        for column in ("section", "paper", "identifier"):
            if column not in columns:
                raise Refusal(f"the mapping table has no {column} column; nothing was renamed")
        for row in reader:
            cleaned = {}
            for key in row:
                if key is not None:
                    cleaned[key.strip().casefold()] = (row[key] or "").strip()
            rows.append(cleaned)
    plan = {}
    bad_rows = 0
    for row in rows:
        if row.get("section", "") != str(section) or not row.get("paper"):
            continue
        if not re.match(identifier, row.get("identifier", "")) or not row["paper"].isdigit():
            bad_rows += 1
            continue
        plan[f"Paper {int(row['paper']):02d}"] = row["identifier"]
    if bad_rows:
        raise Refusal(f"{bad_rows} rows of section {section} have a paper number or identifier of the wrong shape; nothing was renamed")
    targets = list(plan.values())
    if len(set(targets)) != len(targets):
        raise Refusal("two papers would get the same identifier; nothing was renamed")
    renamed = 0
    unmatched = []
    for paper in sorted(Path(into).glob("Paper *.pdf")):
        if paper.stem in plan:
            target = paper.with_name(plan[paper.stem] + ".pdf")
            if target.exists():
                raise Refusal(f"{plan[paper.stem]}.pdf is already there; stopped after {renamed} renamed")
            paper.rename(target)
            renamed += 1
        else:
            unmatched.append(paper.stem)
    print(f"Section {section}: {renamed} papers renamed" +
          (f"; {len(unmatched)} have no row in the table ({', '.join(unmatched)})" if unmatched else ""))
    return 0 if not unmatched else 1


# ---------------------------------------------------------------- the self-test


def self_test():
    """Builds an invented blank test and invented scans, runs the main path, and checks what it printed."""
    need_tools()
    invented = ["Testpupil", "Alphaname", "Zedfamily"]
    with tempfile.TemporaryDirectory() as root:
        root_path = Path(root)
        blank = root_path / "blank.pdf"
        writer = PdfWriter()
        content = (b"BT /F1 9 Tf 54 744 Td (School Name) Tj ET\n"
                   b"BT /F1 9 Tf 258 744 Td (Name) Tj ET 0 G 0.4 w 284 742 m 374 742 l S\n"
                   b"BT /F1 9 Tf 386 744 Td (Date) Tj ET 410 742 m 470 742 l S\n"
                   b"BT /F1 18 Tf 97 700 Td (A Test About Dice) Tj ET\n"
                   b"BT /F1 11 Tf 97 640 Td (1. Roll two dice. How many outcomes are there?) Tj ET\n"
                   b"BT /F1 9 Tf 54 40 Td (A Test About Dice  -  COURSE) Tj ET\n"
                   b"BT /F1 9 Tf 500 40 Td (Page 1 of 1) Tj ET\n")
        writer.page(612, 792, {}, content, with_font=True)
        writer.write(blank)
        with tempfile.TemporaryDirectory() as folder:
            width, height, pixels = render_gray(blank, 1, DPI, folder)

        def scan(path, shift_down_in):
            ink = bytearray(b"\xff" * (width * height))
            shift = round(shift_down_in * DPI)
            for row in range(height):
                source = row - shift
                if 0 <= source < height:
                    ink[row * width:(row + 1) * width] = pixels[source * width:(source + 1) * width]
            for row in range(int(0.62 * DPI) + shift, int(0.70 * DPI) + shift):
                for column in range(int(4.0 * DPI), int(5.0 * DPI)):
                    ink[row * width + column] = 20
            page_writer = PdfWriter()
            image = page_writer.gray(ink, width, height)
            page_writer.page(612, 792, {"I": image}, b"q 612 0 0 792 0 0 cm /I Do Q\n")
            page_writer.write(path)

        originals = root_path / "Originals" / "Section 1"
        originals.mkdir(parents=True)
        scan(originals / "Student A.pdf", 0)
        scan(originals / "Student B.pdf", 0.3)
        scan(originals / (invented[0] + " " + invented[1] + ".pdf"), 0)
        result = subprocess.run([sys.executable, "-B", os.path.abspath(__file__), str(root_path / "Originals"),
                                 str(root_path / "Redacted"), "--blank", str(blank), "--check-dir",
                                 str(root_path / "Teacher only" / "Check")], capture_output=True, text=True)
        said = result.stdout + result.stderr
        problems = []
        for token in invented:
            if token.casefold() in said.casefold():
                problems.append("an invented name reached the output")
        if "Section 1/Student A.pdf: 1 pages, box placed on 1; header matches your blank test" not in said:
            problems.append("the upright paper was not blanked")
        if "Section 1/Student B.pdf: CHECK" not in said:
            problems.append("the paper scanned 0.3 in low was not stopped")
        if (root_path / "Redacted" / "Section 1" / "Student B.pdf").exists():
            problems.append("the paper scanned 0.3 in low was written")
        if "1 files or folders not named like an identifier were left alone" not in said:
            problems.append("the file not named like an identifier was not counted")
        written = sorted(path.name for path in (root_path / "Redacted").rglob("*") if path.is_file())
        if written != ["Student A.pdf"]:
            problems.append("the redacted folder holds something other than Student A.pdf")
        if problems:
            print("self-test FAILED: " + "; ".join(problems))
            return 1
    print("self-test passed: an upright invented paper blanked, one scanned 0.3 in low stopped, "
          "a file not named like an identifier counted and never named. "
          "This checks the paths the test knows; it is no guarantee about changes it does not reach.")
    return 0


# ---------------------------------------------------------------- the command line


def option(arguments, name, default=None):
    if name in arguments:
        index = arguments.index(name)
        if index + 1 >= len(arguments):
            raise Refusal(f"{name} needs a value")
        return arguments[index + 1]
    return default


def main(arguments):
    if not arguments or arguments[0] in ("-h", "--help"):
        print(__doc__)
        return 0
    if "--self-test" in arguments:
        return self_test()
    label = option(arguments, "--label", LABEL)
    identifier = option(arguments, "--identifiers", IDENTIFIER)
    global DPI
    DPI = int(option(arguments, "--dpi", str(DPI)))
    given_box = None
    if option(arguments, "--box") is not None:
        parts = option(arguments, "--box").split(",")
        if len(parts) != 4:
            raise Refusal("--box needs four numbers in inches: left,top,right,bottom")
        given_box = tuple(float(part) for part in parts)
    if option(arguments, "--box-from") is not None:
        need_tools()
        with tempfile.TemporaryDirectory() as folder:
            boxes = boxes_from_blank(option(arguments, "--box-from"), label, None, folder)
        for number, box_in in enumerate(boxes, start=1):
            if box_in is None:
                print(f"page {number}: no '{label}' label, so no box")
            else:
                print(f"page {number}: box in inches " + ",".join(f"{value:.2f}" for value in box_in))
        return 0
    if option(arguments, "--stack") is not None:
        return split_stack(option(arguments, "--stack"), int(option(arguments, "--pages-per-paper", "0")),
                           option(arguments, "--into"), option(arguments, "--check-dir"))
    if option(arguments, "--name-papers") is not None:
        return name_papers(option(arguments, "--name-papers"), option(arguments, "--section"),
                           option(arguments, "--into"), identifier)
    positional = []
    skip = False
    for argument in arguments:
        if skip:
            skip = False
            continue
        if argument.startswith("--"):
            skip = True
            continue
        positional.append(argument)
    if len(positional) != 2 or option(arguments, "--blank") is None or option(arguments, "--check-dir") is None:
        raise Refusal("give the originals folder, the redacted folder, --blank and --check-dir")
    return redact_folder(positional[0], positional[1], option(arguments, "--blank"),
                         option(arguments, "--check-dir"), label, given_box, identifier)


if __name__ == "__main__":
    try:
        sys.exit(main(sys.argv[1:]))
    except Refusal as refusal:
        print(f"Stopped: {refusal}")
        sys.exit(1)
    except Exception as error:   # never a traceback: it could carry a path holding a name
        print(f"Stopped: something unexpected went wrong ({type(error).__name__}); nothing more was written")
        sys.exit(1)
