#!/usr/bin/env python3
"""
Draws scripts/fixtures/picture-sizes/, the corpus the picture-size reader is
checked against (#612; scripts/check_picture_sizes_against_the_site.py).

The files are COMMITTED, so the check never depends on what a later Pillow
happens to write; this script is how they were made, kept so the corpus can
be retraced or grown. It needs Pillow, which only the image has:

    docker run --rm -v "$(pwd)/scripts/fixtures:/fixtures" quartz-teacher:dev-test \
        python3 /fixtures/make_picture_sizes_corpus.py /fixtures/picture-sizes

Every file is small (tens to hundreds of bytes). What each one is for:

* Pillow-written pictures of every format the reader knows, in the shapes
  the build meets (palette, grey, CMYK, progressive, interlaced, animated,
  lossless, alpha);
* EXIF orientations 1-8 on a JPEG as Pillow writes them, and the same tag
  in a PNG's eXIf chunk (review S2);
* JPEGs whose EXIF block is built byte by byte here, little-endian ("II",
  as Windows tools and many phones write) and big-endian ("MM"), with and
  without a tag before the orientation (review S3) - Pillow writes only one
  byte order, so without these the other branch is never reached;
* a JPEG with fill bytes before its frame header (review N2);
* broken files: a PNG cut after 12 bytes, a PNG with no picture data;
* the cases the check names rather than asks Pillow about: a WebP with EXIF
  (the engines disagree, so the reader answers null), a GIF whose first
  frame does not fill its screen (likewise), a TIFF (Chromium cannot draw
  it), and SVGs - Pillow cannot read SVG at all.
"""
import io
import struct
import sys
from pathlib import Path

from PIL import Image

out = Path(sys.argv[1])
out.mkdir(parents=True, exist_ok=True)


def colour(width, height, mode="RGB"):
    picture = Image.new("RGB", (width, height), (200, 100, 50))
    for x in range(0, width, 4):
        picture.putpixel((x, x % height), (10, 20, 200))
    return picture.convert(mode) if mode != "RGB" else picture


def save(name, picture, **options):
    picture.save(out / name, **options)


def exif_with(orientation):
    exif = Image.Exif()
    exif[0x0112] = orientation
    return exif.tobytes()


# PNG
save("png-rgb.png", colour(120, 40))
save("png-palette.png", colour(64, 48, "P"))
save("png-grey.png", colour(30, 90, "L"))
save("png-alpha.png", colour(50, 20, "RGBA"))
save("png-exif-o1.png", colour(120, 40), exif=exif_with(1))
save("png-exif-o6.png", colour(120, 40), exif=exif_with(6))
save("png-exif-o3.png", colour(120, 40), exif=exif_with(3))
whole = io.BytesIO()
colour(120, 40).save(whole, "PNG")
png = whole.getvalue()
(out / "png-cut-short.png").write_bytes(png[:12])
(out / "png-no-picture-data.png").write_bytes(png[:33])  # signature + IHDR, nothing after

# GIF
save("gif-still.gif", colour(100, 50, "P"))
save("gif-interlaced.gif", colour(90, 30, "P"), interlace=1)
frames = [colour(60, 20, "P"), colour(60, 20, "P").transpose(Image.FLIP_LEFT_RIGHT)]
frames[0].save(out / "gif-animated.gif", save_all=True, append_images=frames[1:], duration=100, loop=0)

# JPEG
save("jpeg-baseline.jpg", colour(160, 90))
save("jpeg-progressive.jpg", colour(150, 100), progressive=True)
save("jpeg-grey.jpg", colour(40, 70, "L"))
save("jpeg-cmyk.jpg", colour(80, 30, "CMYK"))
for orientation in range(1, 9):
    save(f"jpeg-o{orientation}.jpg", colour(120, 40), exif=exif_with(orientation))


def tiff_block(order, orientation, with_make):
    """A TIFF header and IFD0 holding Make (optional) then Orientation."""
    pack = "<" if order == "II" else ">"
    entries = []
    if with_make:
        # Make = "Pen", ASCII, 4 bytes inline.
        entries.append(struct.pack(pack + "HHI", 0x010F, 2, 4) + b"Pen\0")
    entries.append(struct.pack(pack + "HHIH", 0x0112, 3, 1, orientation) + b"\0\0")
    ifd = struct.pack(pack + "H", len(entries)) + b"".join(entries) + struct.pack(pack + "I", 0)
    return order.encode() + struct.pack(pack + "HI", 42, 8) + ifd


def jpeg_with_exif(order, orientation, with_make):
    plain = io.BytesIO()
    colour(120, 40).save(plain, "JPEG")
    body = plain.getvalue()
    payload = b"Exif\0\0" + tiff_block(order, orientation, with_make)
    app1 = b"\xff\xe1" + struct.pack(">H", len(payload) + 2) + payload
    return body[:2] + app1 + body[2:]


(out / "jpeg-hand-II-o6.jpg").write_bytes(jpeg_with_exif("II", 6, False))
(out / "jpeg-hand-II-o6-after-make.jpg").write_bytes(jpeg_with_exif("II", 6, True))
(out / "jpeg-hand-II-o3.jpg").write_bytes(jpeg_with_exif("II", 3, True))
(out / "jpeg-hand-MM-o8-after-make.jpg").write_bytes(jpeg_with_exif("MM", 8, True))

plain = io.BytesIO()
colour(70, 35).save(plain, "JPEG")
body = plain.getvalue()
frame = body.find(b"\xff\xc0")
(out / "jpeg-fill-bytes.jpg").write_bytes(body[:frame] + b"\xff\xff\xff" + body[frame:])

# WebP
save("webp-lossy.webp", colour(90, 60), quality=80)
save("webp-lossless.webp", colour(91, 61), lossless=True)
save("webp-alpha.webp", colour(77, 55, "RGBA"), quality=80)
frames = [colour(64, 32), colour(64, 32).transpose(Image.FLIP_LEFT_RIGHT)]
frames[0].save(out / "webp-animated.webp", save_all=True, append_images=frames[1:], duration=100)
save("named-webp-exif-o6.webp", colour(120, 40), exif=exif_with(6))

# BMP
save("bmp-rgb.bmp", colour(35, 15))
bmp = bytearray((out / "bmp-rgb.bmp").read_bytes())
height = struct.unpack_from("<i", bmp, 22)[0]
struct.pack_into("<i", bmp, 22, -height)  # top-down rows: a negative height
(out / "bmp-top-down.bmp").write_bytes(bytes(bmp))

# Named: a GIF whose first frame is smaller than its screen and offset.
small = io.BytesIO()
colour(40, 20, "P").save(small, "GIF")
gif = bytearray(small.getvalue())
struct.pack_into("<HH", gif, 6, 80, 50)  # the logical screen grows; the frame does not
(out / "named-gif-frame-smaller.gif").write_bytes(bytes(gif))

# Named: TIFF, which Chromium cannot draw.
save("named-tiff.tif", colour(30, 20))

# Named: SVGs.
svgs = {
    "named-svg-px.svg": '<svg xmlns="http://www.w3.org/2000/svg" width="300px" height="150px"/>',
    "named-svg-unitless.svg": '<svg xmlns="http://www.w3.org/2000/svg" width="320" height="160"/>',
    "named-svg-cm.svg": '<svg xmlns="http://www.w3.org/2000/svg" width="8cm" height="4cm"/>',
    "named-svg-inch-and-pt.svg": '<svg xmlns="http://www.w3.org/2000/svg" width="2in" height="72pt"/>',
    "named-svg-fraction.svg": '<svg xmlns="http://www.w3.org/2000/svg" width="300.6px" height="150.4px"/>',
    "named-svg-viewbox-only.svg": '<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 100 200"/>',
    "named-svg-percent.svg": '<svg xmlns="http://www.w3.org/2000/svg" width="100%" height="100%" viewBox="0 0 200 100"/>',
    "named-svg-em.svg": '<svg xmlns="http://www.w3.org/2000/svg" width="10em" height="5em"/>',
    "named-svg-width-only.svg": '<svg xmlns="http://www.w3.org/2000/svg" width="300" viewBox="0 0 200 100"/>',
    "named-svg-comment-first.svg":
        '<!-- exported from <svg width="10" height="10"> tool --><svg xmlns="http://www.w3.org/2000/svg" width="300" height="150"/>',
    "named-svg-upper-case.svg": '<svg xmlns="http://www.w3.org/2000/svg" WIDTH="300" HEIGHT="150" viewBox="0 0 100 100"/>',
    "named-svg-prolog-doctype.svg":
        '<?xml version="1.0"?>\n<!DOCTYPE svg PUBLIC "-//W3C//DTD SVG 1.1//EN" "http://www.w3.org/Graphics/SVG/1.1/DTD/svg11.dtd" '
        '[ <!ENTITY e "<svg width=\'1\' height=\'1\'>"> ]>\n<svg xmlns="http://www.w3.org/2000/svg" width="300" height="150"/>',
    "named-svg-bom.svg": '﻿<svg xmlns="http://www.w3.org/2000/svg" width="300" height="150"/>',
    "named-svg-prefixed.svg": '<svg:svg xmlns:svg="http://www.w3.org/2000/svg" width="300" height="150"/>',
    "named-svg-single-quotes.svg": "<svg xmlns='http://www.w3.org/2000/svg' height='50' width='200'/>",
    "named-svg-not-svg.svg": "<html><body>not a drawing</body></html>",
}
for name, text in svgs.items():
    (out / name).write_text(text + "\n", encoding="utf-8")

print(f"{len(list(out.iterdir()))} files in {out}")
