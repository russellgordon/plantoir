#!/usr/bin/env python3
"""Box the name line on every scanned page that has a name blank. The teacher's look is what confirms the names
are redacted.

Part of the plantoir-marking skill. A STARTING POINT: copy it into the marking folder's Scripts/ folder,
adjust it to this teacher's header (see the two MARK blocks below), run --self-test, and only then use it.
The assistant runs only --self-test and --box-from (on the BLANK test); the boxing itself, the split of a
whole class and the naming of its papers are run by the teacher's "Box the papers" launcher (#750, 750d),
through teacher_only.py and the runner, because they read the teacher-only folder:

    python3 -B redact_scans.py --box-from BLANK.pdf [--label "Name"] [--box x0,y0,x1,y1]
    python3 -B redact_scans.py --self-test
    python3 -B redact_scans.py ORIGINALS HOLDING --blank BLANK.pdf [--label "Name"]      (Box the papers)
                               [--box x0,y0,x1,y1] [--dpi 150]
    python3 -B redact_scans.py --stack STACK.pdf --pages-per-paper N --into FOLDER --check-dir CHECK   (Box the papers)
    python3 -B redact_scans.py --name-papers TABLE --section N --into FOLDER                         (Box the papers)

Russell, 2026-11-12, on #750: "script runs, teacher checks the papers, confirms names are redacted, then
agent based marking begins. Simple." and "Teacher confirms full redacted papers." So the script does three
things and claims nothing more:
  1. It finds the name blank on each page of the BLANK test from the blank's own text and drawing (the
     label, "Name", "Student Name" or "Nom" in any case, followed by a blank: a line, underscores, dots, a
     table cell or a frame), and boxes that line, margin to margin with room above it, on every scanned
     page that corresponds to it. A blank it cannot read plainly stops the run and asks.
  2. It checks only what needs no judgement about handwriting: the number of pages is a multiple of the
     blank's, and each page is the same way round (portrait or landscape) and of nearly the same shape as
     its blank page. Anything else stops that paper, with a plain reason. It does NOT detect a page that
     is upside down or shifted: the teacher sees that when looking through the papers.
  3. It writes the boxed papers into HOLDING, a folder on the teacher's side, clearing it first, so a previous
     batch can never stand in for this one; the papers are written beside it and moved in only when all
     are written. Box the papers then puts exactly those papers in ONE file for the teacher (the pinned
     teacher_only.py, never this file), and moves them to where the assistant reads only on the teacher's yes.

Needs Poppler (pdftoppm, pdfinfo, pdftotext, pdfunite, pdfseparate) and the Python standard library.
"""
import csv
import os
import re
import shutil
import subprocess
import sys
import tempfile
from pathlib import Path

# MARK: - What you may change for this teacher
#   the labels (--label, LABELS), the box below (never shrink it), the folder and
#   file names, the wording of the lines it prints (never claiming a name is covered, removed or safe),
#   and the resolution.
LABELS = ["Student Name", "Name", "Nom"]   # the words a name blank starts with, any case
OTHER_NAMES = ["School", "Teacher", "Partner", "Course", "Parent"]   # "<one of these> Name" is not the student's
BOX_SIDE_IN = 0.3                # the box runs margin to margin: this far in from each side
BOX_ABOVE_LABEL_IN = 0.35        # from this far above the label (room for handwriting above the line)
BOX_BELOW_LABEL_PT = 18          # to this far below the label (handwriting falls below the line), or to the
                                 # lower border of the cell or frame the label sits in, whichever is lower
LABEL_SEARCH_DEPTH_IN = 2.0      # the name blank is looked for in the top of each page
DPI = 150                        # pixels per inch for the boxed pages
JPEG_QUALITY = 75
SECTION = r"^Section \d+$"
PAPERS_TO_NAME = "Papers to name.pdf"

# MARK: - What must not change
#   never print, log or write outside the teacher-only folder any value read from a name mapping table;
#   never print a file name that is not an identifier (or a Section / Paper label this script made);
#   capture every program's output and print only counts and identifiers; refuse (exit 1, with an
#   identifier-only message) when anything is unexpected; never render the box's own pixels into a boxed
#   page; never say a name is covered, removed or safe (the teacher's look confirms it); write boxed papers
#   only into the folder it is given, and only once the whole batch is written; leave a file not named like
#   an identifier alone and count it, never stop the batch for it (the teacher's look is the check); never
#   write inside a Plantoir working folder; and these shape tolerances, which are generous on purpose:
SHAPE_TOLERANCE = 0.06           # how far a page's height-to-width ratio may differ from its blank page's

TOOLS = ("pdftoppm", "pdfinfo", "pdftotext", "pdfunite", "pdfseparate")


# >>> The identifier rule. ONE rule, carried byte for byte in every plantoir-marking script that reads an
# identifier (redact_scans.py, build_test_sheet.py, make_named_copies.py, class_results.py; 750c fix review M1:
# a loose pattern let a record named like a person through, and the scripts disagreed). An identifier is the
# WHOLE name, matched in full: Student A to Student ZZ, and nothing else. scripts/test_marking_results.py fails if
# the copies differ or the contract's assessment.identifiers.pattern is not this one. A teacher whose papers are
# named another way renames them (redact_scans.py --name-papers does it from the mapping table).
IDENTIFIER = r"^Student [A-Z]{1,2}$"


def is_identifier(text):
    return isinstance(text, str) and re.fullmatch(IDENTIFIER, text) is not None
# <<< The identifier rule.


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
                      "On a Mac with Homebrew: brew install poppler. Nothing was read, and no scan may be read "
                      "any other way until this script has blanked it.")


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




# ---------------------------------------------------------------- the name blank, read from the blank test


def normalised(word):
    """The word without punctuation, underscores or dots, whatever its case: Name, NAME:, Name:____ are one."""
    return re.sub(r"[\W_]", "", word).casefold()


def words_near_top(blank, page):
    xml = run(["pdftotext", "-f", str(page), "-l", str(page), "-bbox", str(blank), "-"]).stdout.decode("utf-8", "replace")
    words = []
    for match in re.finditer(r'xMin="([\d.]+)" yMin="([\d.]+)" xMax="([\d.]+)" yMax="([\d.]+)">([^<]*)<', xml):
        x0, y0, x1, y1 = (float(match.group(index)) for index in range(1, 5))
        if y0 < LABEL_SEARCH_DEPTH_IN * 72:
            words.append((x0, y0, x1, y1, match.group(5)))
    return words


def on_the_same_line(first, second):
    return abs(first[1] - second[1]) < 3 or abs(first[3] - second[3]) < 3


def a_blank_follows(word, words, image, dpi):
    """True when what follows the label is a place to write: underscores or dots typed after it (in the same
    word or the next), or a drawn line within 0.7 in after it, near its height: a rule, a table cell's
    border or a frame's edge. A sentence that starts with the label ("Name and date go on every page") is
    followed by a word, so it is not a name blank."""
    if re.search(r"(_{2,}|\.{3,}|…)", word[4]):
        return True
    after = [other for other in words if on_the_same_line(word, other) and other[0] >= word[2] - 1 and other is not word]
    after.sort()
    if after and after[0][0] - word[2] < 0.7 * 72:
        leaders = 0
        for other in after[:3]:
            if re.fullmatch(r"[_.…·]+", other[4]):
                leaders += len(other[4])
        if leaders >= 3 or re.fullmatch(r"[_.…·]{2,}", after[0][4]):
            return True   # underscores or a dotted leader, typed as one word or as many
        if normalised(after[0][4]):
            return False   # a word follows: an instruction, not a blank
    width, height, pixels = image
    scale = dpi / 72
    start = int(word[2] * scale) + 1
    stop = min(width, start + int(0.7 * dpi))
    for row in range(max(0, int((word[1] - 6) * scale)), min(height, int((word[3] + 8) * scale))):
        run_length = 0
        for column in range(start, stop):
            if pixels[row * width + column] < 160:
                run_length += 1
                if run_length >= int(0.35 * dpi):
                    return True
            else:
                run_length = 0
    return False


def rule_below(image, dpi, word):
    """Where (in points) the first drawn line under the label is, within 0.6 in, when the label sits in a form
    cell or a frame with the room to write UNDER it: the cell's lower border. None when there is no such line
    (750a fix review 3, M6: a name written low in such a cell showed below a box 18 pt under the label)."""
    width, height, pixels = image
    scale = dpi / 72
    left = max(0, int((word[0] - 7) * scale))
    right = min(width, int((word[0] + 180) * scale))
    for row in range(int((word[3] + 3) * scale), min(height, int((word[3] + 0.6 * 72) * scale))):
        run_length = 0
        for column in range(left, right):
            if pixels[row * width + column] < 160:
                run_length += 1
                if run_length >= int(0.5 * dpi):
                    return row / scale
            else:
                run_length = 0
    return None


def name_blanks(blank, page, labels, folder):
    """[(left, top, bottom) in points] of every name blank at the top of this page of the blank test."""
    words = words_near_top(blank, page)
    image = None
    found = []
    others = [normalised(word) for word in OTHER_NAMES]
    for index, word in enumerate(words):
        for label in sorted(labels, key=lambda text: -len(text.split())):
            parts = [normalised(part) for part in label.split()]
            run_of_words = words[index:index + len(parts)]
            if len(run_of_words) < len(parts) or [normalised(other[4]) for other in run_of_words] != parts:
                continue
            if any(not on_the_same_line(word, other) for other in run_of_words):
                continue
            before = [other for other in words if on_the_same_line(word, other) and 0 <= word[0] - other[2] < 8]
            if before and (normalised(before[0][4]) in others or
                           any(normalised(before[0][4]) == normalised(longer.split()[0]) for longer in labels
                               if len(longer.split()) > len(parts))):
                break   # "School Name" is not the student's; "Student Name" is matched as a whole
            if image is None:
                image = render_gray(blank, page, 100, folder)
            last = run_of_words[-1]
            if a_blank_follows(last, words, image, 100):
                bottom = max(other[3] for other in run_of_words) + BOX_BELOW_LABEL_PT
                cell = rule_below(image, 100, word)
                if cell is not None:
                    bottom = max(bottom, cell + 4)   # the label sits in a cell or frame: the box takes all of it
                found.append((word[0], min(other[1] for other in run_of_words), bottom))
            break
    return found


def boxes_from_blank(blank, labels, given_box, folder):
    """One entry per page of the blank: the box in inches (left, top, right, bottom), or None."""
    sizes = page_sizes(blank)
    if given_box is not None:
        return [given_box] * len(sizes)   # the teacher said where the name is: every page gets the box
    boxes = []
    for number, (width_pt, _height) in enumerate(sizes, start=1):
        found = name_blanks(blank, number, labels, folder)
        lines = []
        for left, top, bottom in found:
            if not any(abs(top - other[1]) < 4 for other in lines):
                lines.append((left, top, bottom))
        if len(lines) > 1:
            raise Refusal(f"page {number} of your blank test has {len(lines)} name blanks, and I will not guess which "
                          "is the student's. Tell me with --box (inches from the top-left: left,top,right,bottom).")
        if not lines:
            boxes.append(None)
            continue
        _left, top, bottom = lines[0]
        boxes.append((BOX_SIDE_IN, max(0.05, top / 72 - BOX_ABOVE_LABEL_IN), width_pt / 72 - BOX_SIDE_IN, bottom / 72))
    if all(box_in is None for box_in in boxes) and not any(words_near_top(blank, number) for number in range(1, len(sizes) + 1)):
        raise Refusal("your blank test has no text in it (is it a scan?), so I cannot read where the name blank is. "
                      "Give the box with --box (inches from the top-left: left,top,right,bottom), measured with the "
                      "teacher; --box-from with --box shows it before any paper is boxed.")
    if all(box_in is None for box_in in boxes):
        raise Refusal("I could not find a name blank on your blank test (a label such as Name followed by a line, "
                      "underscores, dots, a table cell or a frame). Tell me its label with --label, or where it is "
                      "with --box (inches from the top-left: left,top,right,bottom).")
    return boxes


# ---------------------------------------------------------------- boxing one paper


def tiles_around(width, height, box_px):
    x0, y0, x1, y1 = box_px
    return [(0, 0, width, y0), (0, y0, x0, y1 - y0), (x1, y0, width - x1, y1 - y0), (0, y1, width, height - y1)]


def box_page(writer, source, page, size_pt, box_in, folder):
    """Add one boxed page: the tiles AROUND the box, rendered from the scan; the box filled black."""
    width_pt, height_pt = size_pt
    width = round(width_pt / 72 * DPI)
    height = round(height_pt / 72 * DPI)
    images = {}
    content = b""
    if box_in is None:
        tiles = [(0, 0, width, height)]
    else:
        box_px = (max(0, round(box_in[0] * DPI)), max(0, round(box_in[1] * DPI)),
                  min(width, round(box_in[2] * DPI)), min(height, round(box_in[3] * DPI)))
        tiles = tiles_around(width, height, box_px)
    for number, (x, y, tile_width, tile_height) in enumerate(tiles):
        if tile_width <= 0 or tile_height <= 0:
            continue
        data = render_jpeg(source, page, DPI, folder, (x, y, tile_width, tile_height))
        name = f"T{number}"
        images[name] = writer.jpeg(data, tile_width, tile_height)
        content += b"q %.3f 0 0 %.3f %.3f %.3f cm /%s Do Q\n" % (
            tile_width * 72 / DPI, tile_height * 72 / DPI, x * 72 / DPI, height_pt - (y + tile_height) * 72 / DPI,
            name.encode("ascii"))
    if box_in is not None:
        x0, y0, x1, y1 = box_px
        content += b"0 g %.3f %.3f %.3f %.3f re f\n" % (
            x0 * 72 / DPI, height_pt - y1 * 72 / DPI, (x1 - x0) * 72 / DPI, (y1 - y0) * 72 / DPI)
    writer.page(width_pt, height_pt, images, content)


def fitted(box_in, size_pt, blank_size_pt):
    """The blank's box on a scanned page of nearly the same shape: the same place in proportion."""
    if box_in is None:
        return None
    across = size_pt[0] / blank_size_pt[0]
    down = size_pt[1] / blank_size_pt[1]
    return (box_in[0] * across, box_in[1] * down, box_in[2] * across, box_in[3] * down)


def shape_problem(number, size_pt, blank_number, blank_size_pt):
    """A plain reason when a page is not the same way round, or nearly the same shape, as its blank page."""
    def way(size):
        return "landscape" if size[0] > size[1] else "portrait"
    if way(size_pt) != way(blank_size_pt):
        return f"page {number} is {way(size_pt)} and page {blank_number} of your blank test is {way(blank_size_pt)}"
    ratio = (size_pt[1] / size_pt[0]) / (blank_size_pt[1] / blank_size_pt[0])
    if abs(ratio - 1) > SHAPE_TOLERANCE:
        return f"page {number} is a different shape from page {blank_number} of your blank test (another paper size?)"
    return None


def separator(writer, caption):
    """A page that names the paper after it, in Papers to name.pdf."""
    content = b"BT /F1 28 Tf 72 640 Td (%s) Tj ET\n" % pdf_text(caption)
    writer.page(612, 792, {}, content, with_font=True)


def combine(entries, path, folder):
    """entries: [(caption, PDF)]; writes each caption's page and then its PDF, in order, as one file."""
    parts = []
    for index, (caption, pdf) in enumerate(entries):
        page = Path(folder) / f"caption-{index}.pdf"
        writer = PdfWriter()
        separator(writer, caption)
        writer.write(page)
        parts += [str(page), str(pdf)]
    run(["pdfunite"] + parts + [str(path)])


def clear_previous_batch(redacted):
    """Take away everything in the holding folder, so nothing from before can stand in for this batch (the
    papers are copies: the originals are teacher-only)."""
    problem = False
    for entry in sorted(Path(redacted).iterdir()) if Path(redacted).is_dir() else []:
        try:
            if entry.is_dir() and not entry.is_symlink():
                shutil.rmtree(entry)
            else:
                os.remove(entry)
        except OSError:
            problem = True
    if problem:
        raise Refusal("the last batch could not all be cleared away; no paper was written, and none may be read")


def redact_folder(originals, redacted, blank, labels, given_box, identifier):
    refuse_inside_a_working_folder(redacted)
    redacted = Path(redacted)
    # The last batch goes FIRST, before any other check can stop the run (750a fix review 3, L1).
    clear_previous_batch(redacted)
    need_tools()
    for folder_path, what in ((originals, "the originals folder"), (blank, "the blank test")):
        if not Path(folder_path).exists():
            raise Refusal(f"{what} is not there; nothing was read, and no paper may be read")
    redacted.mkdir(parents=True, exist_ok=True)
    written = []
    stopped = 0
    with tempfile.TemporaryDirectory() as folder:
        boxes = boxes_from_blank(blank, labels, given_box, folder)
        blank_sizes = page_sizes(blank)
        found, left_alone = identifier_files(originals, identifier)
        try:
            holding = Path(tempfile.mkdtemp(prefix=".holding-", dir=redacted.parent))
        except OSError:
            raise Refusal("the folder beside the holding folder could not be written to; no paper was written, and "
                          "none may be read")
        try:
            for label_text, source in found:
                try:
                    sizes = page_sizes(source)
                    reason = None
                except Refusal:
                    sizes, reason = [], "the file could not be read as a PDF"
                if reason is None and (not sizes or len(sizes) % len(blank_sizes) != 0):
                    reason = (f"it has {len(sizes)} pages, which is not a whole number of copies of your blank test's "
                              f"{len(blank_sizes)}")
                for number, size_pt in enumerate(sizes, start=1):
                    if reason is None:
                        blank_number = (number - 1) % len(blank_sizes) + 1
                        reason = shape_problem(number, size_pt, blank_number, blank_sizes[blank_number - 1])
                if reason is not None:
                    stopped += 1
                    print(f"{label_text}.pdf: stopped ({reason}); not written")
                    continue
                writer = PdfWriter()
                boxed = 0
                for number, size_pt in enumerate(sizes, start=1):
                    blank_number = (number - 1) % len(blank_sizes)
                    box_in = fitted(boxes[blank_number], size_pt, blank_sizes[blank_number])
                    boxed += box_in is not None
                    box_page(writer, source, number, size_pt, box_in, folder)
                target = holding / (label_text + ".pdf")
                target.parent.mkdir(parents=True, exist_ok=True)
                writer.write(target)
                written.append((label_text, target, len(sizes), boxed))
            # Everything is written: only now does anything go into the holding folder.
            for label_text, target, _pages, _boxed in written:
                final = redacted / (label_text + ".pdf")
                final.parent.mkdir(parents=True, exist_ok=True)
                shutil.move(str(target), str(final))
        except (OSError, Refusal):
            clear_previous_batch(redacted)
            raise Refusal("the boxed papers could not all be written; none was left where they are read, and none "
                          "may be read")
        finally:
            shutil.rmtree(holding, ignore_errors=True)
    for label_text, _target, pages, boxed in written:
        unboxed = pages - boxed
        print(f"{label_text}.pdf: {pages} pages, {boxed} boxed" +
              (f"; {unboxed} with no name blank on your blank test, so no box" if unboxed else ""))
    if left_alone:
        print(f"{left_alone} files or folders not named like an identifier were left alone")
    pages = sum(entry[2] for entry in written)
    boxed = sum(entry[3] for entry in written)
    print(f"{len(written)} papers written, {pages} pages, {boxed} of them boxed; {stopped} papers stopped. "
          "The teacher's look is what confirms the names are redacted: no paper reaches the assistant until the "
          "teacher has looked through every page and typed yes. A name written anywhere else on a page is not boxed "
          "and would be seen, and every page the assistant reads goes to its service.")
    return 0 if stopped == 0 else 1


# ---------------------------------------------------------------- a whole class in one scan


def split_stack(stack, pages_per_paper, into, check_dir):
    need_tools()
    refuse_inside_a_working_folder(into, check_dir)
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
            entries.append((label, pages[0]))
        Path(check_dir).mkdir(parents=True, exist_ok=True)
        combine(entries, Path(check_dir) / PAPERS_TO_NAME, folder)
    print(f"{papers} papers of {pages_per_paper} pages written, Paper 01 to Paper {papers:02d}. "
          f"'{PAPERS_TO_NAME}' in your check folder shows the first page of each, for you to fill in the paper "
          "column of your name mapping table.")
    return 0


def natural(name):
    """Section 2 before Section 10, Student B before Student AA, as a class list runs (750a fix review 3, L5)."""
    key = []
    for token in re.findall(r"\d+|[^\W\d_]+|[\W_]+", name):
        key.append((0, int(token), "") if token.isdigit() else (1, len(token), token.casefold()))
    return key


def identifier_files(originals, identifier):
    """[(relative label, path)] for every PDF named like an identifier; and the count left alone."""
    found = []
    left_alone = 0
    for entry in sorted(Path(originals).iterdir(), key=lambda path: natural(path.name)):
        if entry.name.startswith("."):
            continue
        if entry.is_dir() and re.match(SECTION, entry.name):
            for inner in sorted(entry.iterdir(), key=lambda path: natural(path.name)):
                if inner.name.startswith("."):
                    continue
                if inner.is_file() and inner.suffix.lower() == ".pdf" and is_identifier(inner.stem):
                    found.append((f"{entry.name}/{inner.stem}", inner))
                else:
                    left_alone += 1
        elif entry.is_file() and entry.suffix.lower() == ".pdf" and is_identifier(entry.stem):
            found.append((entry.stem, entry))
        else:
            left_alone += 1
    return found, left_alone



def inside_a_working_folder(path):
    """True when the path, or a folder above it, is a Plantoir working folder (it holds courses/ and .toolchain/)."""
    path = Path(path).resolve()
    for folder in [path] + list(path.parents):
        if (folder / "courses").is_dir() and (folder / ".toolchain").is_dir():
            return True
    return False


def refuse_inside_a_working_folder(*paths):
    for path in paths:
        if path is not None and inside_a_working_folder(path):
            raise Refusal("a folder given is inside the Plantoir working folder, where it could be built into a "
                          "class website or copied with a course; choose folders outside it. Nothing was written")



def name_papers(table, section, into, identifier):
    """Rename Paper NN.pdf to its identifier from the table's section, paper and identifier columns only."""
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
        if not is_identifier(row.get("identifier", "")) or not row["paper"].isdigit():
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
          (f"; {len(unmatched)} missing from the table ({', '.join(unmatched)})" if unmatched else ""))
    return 0 if not unmatched else 1



def option(arguments, name, default=None):
    if name in arguments:
        index = arguments.index(name)
        if index + 1 >= len(arguments):
            raise Refusal(f"{name} needs a value")
        return arguments[index + 1]
    return default



# ---------------------------------------------------------------- the self-test


def self_test():
    """An invented blank test and invented papers through the main path, the record and the check."""
    need_tools()
    invented = ["Testpupil", "Alphaname", "Zedfamily"]
    with tempfile.TemporaryDirectory() as root:
        root_path = Path(root)
        blank = root_path / "blank.pdf"
        writer = PdfWriter()
        writer.page(612, 792, {}, b"BT /F1 9 Tf 54 744 Td (School Name) Tj ET\n"
                                  b"BT /F1 9 Tf 258 744 Td (Name) Tj ET 0 G 0.6 w 284 742 m 374 742 l S\n"
                                  b"BT /F1 18 Tf 97 700 Td (A Test About Dice) Tj ET\n"
                                  b"BT /F1 9 Tf 54 40 Td (A Test About Dice  -  COURSE) Tj ET\n", with_font=True)
        writer.write(blank)

        def paper(path, landscape):
            page_writer = PdfWriter()
            width, height = (792, 612) if landscape else (612, 792)
            page_writer.page(width, height, {}, b"BT /F1 12 Tf 300 744 Td (scanned) Tj ET\n", with_font=True)
            page_writer.write(path)

        originals = root_path / "Originals" / "Section 1"
        originals.mkdir(parents=True)
        paper(originals / "Student A.pdf", False)
        paper(originals / "Student B.pdf", True)
        paper(originals / (invented[0] + " " + invented[1] + ".pdf"), False)
        holding = root_path / "Teacher only" / "Holding"

        def script(*arguments):
            result = subprocess.run([sys.executable, "-B", os.path.abspath(__file__), *map(str, arguments)],
                                    capture_output=True, text=True)
            return result.stdout + result.stderr, result.returncode

        said, _code = script(root_path / "Originals", holding, "--blank", blank)
        problems = []
        if any(token.casefold() in said.casefold() for token in invented):
            problems.append("an invented name reached the output")
        if "Section 1/Student A.pdf: 1 pages, 1 boxed" not in said:
            problems.append("the paper was not boxed")
        if "Section 1/Student B.pdf: stopped (page 1 is landscape" not in said:
            problems.append("the landscape paper was not stopped")
        if "1 files or folders not named like an identifier were left alone" not in said:
            problems.append("the file not named like an identifier was not counted")
        if sorted(path.name for path in holding.rglob("*.pdf")) != ["Student A.pdf"]:
            problems.append("the holding folder does not hold exactly the boxed paper")
        if problems:
            print("self-test FAILED: " + "; ".join(problems))
            return 1
    print("self-test passed: an invented paper boxed into the holding folder, a landscape one stopped, and a file not "
          "named like an identifier counted and never named. This checks the paths the test knows; it is no "
          "guarantee about changes it does not reach, and the teacher's look is the proof.")
    return 0


# ---------------------------------------------------------------- the command line


def main(arguments):
    if not arguments or arguments[0] in ("-h", "--help"):
        print(__doc__)
        return 0
    if "--self-test" in arguments:
        return self_test()
    labels = [option(arguments, "--label")] if option(arguments, "--label") else LABELS
    identifier = IDENTIFIER          # one rule for every script: the identifier block above
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
            boxes = boxes_from_blank(option(arguments, "--box-from"), labels, given_box, folder)
        for number, box_in in enumerate(boxes, start=1):
            if box_in is None:
                print(f"page {number}: no name blank on your blank test, so no box")
            else:
                print(f"page {number}: box in inches " + ",".join(f"{value:.2f}" for value in box_in))
        return 0
    if option(arguments, "--confirm") is not None or option(arguments, "--verify") is not None:
        raise Refusal("the teacher's yes is no longer this script's: Box the papers asks for it, and teacher_only.py "
                      "--verify checks it")
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
    if len(positional) != 2 or option(arguments, "--blank") is None:
        raise Refusal("give the originals folder, the holding folder and --blank")
    return redact_folder(positional[0], positional[1], option(arguments, "--blank"), labels, given_box, identifier)


if __name__ == "__main__":
    try:
        sys.exit(main(sys.argv[1:]))
    except Refusal as refusal:
        print(f"Stopped: {refusal}")
        sys.exit(1)
    except Exception as error:   # never a traceback: it could carry a path holding a name
        print(f"Stopped: something unexpected went wrong ({type(error).__name__}); no paper may be read until the "
              "boxing has run through")
        sys.exit(1)
