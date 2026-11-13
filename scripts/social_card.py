"""
Draws the social sharing card for one section of a course — the image that
appears when a link to the published site is shared in iMessage, Slack,
and the like.

Design (matching the plantoir.app card's language): the section's colour
scheme as a full-bleed background, the course name large in the section's
header font, and beneath it a quieter subtitle — the course emoji beside
the course code (and the "S1"-style marker when that setting is on) in the
body font. No logo, and no domain: Apple's share sheet already overlays
the domain along the bottom of the card.

Regenerated on every build, so changes to the course name, scheme, fonts,
emoji, or marker setting always reach the card.
"""

from pathlib import Path

# The embeddable Python used by the native Windows runtime replaces
# sys.path wholesale (python311._pth), so the script's own folder must
# be added by hand before sibling imports. Harmless everywhere else.
import sys as _sys
_sys.path.insert(0, str(Path(__file__).resolve().parent))
import toolchain_paths
import contracts
import json
import unicodedata

from PIL import Image, ImageDraw, ImageFont, ImageColor

CARD_WIDTH = 1200
CARD_HEIGHT = 630
MARGIN_X = 120
TITLE_MAX_WIDTH = CARD_WIDTH - (MARGIN_X * 2)
TITLE_TO_SUBTITLE_GAP = 30
SUBTITLE_SIZE = 44
EMOJI_TEXT_GAP = 18

# Where the toolchain's support files live: baked into the image, with a
# repo-relative fallback so the renderer can be exercised outside it.
SUPPORT_CANDIDATES = [
    toolchain_paths.SUPPORT_DIR,
    Path(__file__).resolve().parent.parent / "support",
]

# Debian's package puts the colour emoji font here.
EMOJI_FONT_CANDIDATES = [
    Path("/usr/share/fonts/truetype/noto/NotoColorEmoji.ttf"),
    toolchain_paths.SUPPORT_DIR / "fonts" / "NotoColorEmoji.ttf",
]
if toolchain_paths.EMOJI_FONT:
    EMOJI_FONT_CANDIDATES.insert(0, Path(toolchain_paths.EMOJI_FONT))
# Pillow can only rasterize this font at its embedded bitmap size.
EMOJI_STRIKE_SIZE = 109


def _find_support_dir():
    for candidate in SUPPORT_CANDIDATES:
        if candidate.is_dir():
            return candidate
    return None


def _load_scheme_colors(scheme_id):
    """The light-mode palette for a scheme id, or {} when unavailable."""
    support = _find_support_dir()
    if not support:
        return {}
    schemes_path = support / "colour_schemes.json"
    try:
        schemes = json.loads(schemes_path.read_text(encoding="utf-8"))
    except Exception:
        return {}
    for scheme in schemes:
        if scheme.get("id") == scheme_id:
            return scheme.get("colors", {}).get("lightMode", {})
    return {}


def _font_rules():
    """contracts/shared-rules.json -> socialCardFonts (#766)."""
    return contracts.section("shared-rules", "socialCardFonts")


def _trimmed(font_name):
    """Text with the spaces at either end taken off; anything else as it is.
    Taking spaces off the ends can never make a path."""
    if isinstance(font_name, str):
        return font_name.strip()
    return font_name


def _is_offered(font_name):
    """True when the name, trimmed, is one of the fonts Plantoir offers,
    exactly as the apps write it, so it may open that font's file (#766)."""
    name = _trimmed(font_name)
    if not isinstance(name, str):
        return False
    return name in _font_rules()["fonts"]


def _is_silent(font_name):
    """An empty or missing name, or the system pairing ("Helvetica,
    Arial", which has no file of its own): Inter, and nothing to say."""
    name = _trimmed(font_name)
    if name is None:
        return True
    return isinstance(name, str) and name in _font_rules()["silentNames"]


def _font_file(font_name):
    """The bundled .ttf for a font Plantoir offers ("Playfair Display" →
    PlayfairDisplay.ttf), or the neutral Inter for anything else.

    Only a name in the contract's list ever reaches a path (#766). Pillow's
    FreeType decodes WOFF2 with a Brotli that has a known flaw, and it picks
    a font's format from the file's bytes, so a name joined onto the fonts
    folder unchecked (an absolute path, a ../ name) could hand that decoder
    any file. A course's settings are not always the teacher's own: a
    course imported for reference, or restored from an archive, brings its
    settings with it."""
    support = _find_support_dir()
    if not support:
        return None
    rules = _font_rules()
    fonts_dir = support / "fonts"
    if _is_offered(font_name):
        candidate = fonts_dir / rules["fonts"][_trimmed(font_name)]
        if candidate.is_file():
            return candidate
    fallback = fonts_dir / rules["fallbackFile"]
    if fallback.is_file():
        return fallback
    return None


def _shown_name(font_name):
    """The value as the console may show it: text with no control
    characters, cut to the contract's length (socialCardFonts.shownName)."""
    if isinstance(font_name, str):
        text = font_name
    else:
        text = json.dumps(font_name, ensure_ascii=False)
    kept = []
    for character in text:
        # Cc control, Cf format (a right-to-left override, say), Zl and Zp
        # the line and paragraph separators some line readers split on.
        if unicodedata.category(character) not in ("Cc", "Cf", "Zl", "Zp"):
            kept.append(character)
    shown = "".join(kept)
    limit = _font_rules()["shownName"]["maxCharacters"]
    if len(shown) > limit:
        shown = shown[:limit] + "…"
    return shown


def fonts_not_used(header_font_name, body_font_name):
    """The names the card could not use, header first, each once, as the
    console shows them. Empty when every name was offered or silent."""
    not_used = []
    for font_name in [header_font_name, body_font_name]:
        if _is_offered(font_name) or _is_silent(font_name):
            continue
        shown = _shown_name(_trimmed(font_name))
        if shown not in not_used:
            not_used.append(shown)
    return not_used


def unknown_font_sentence(shown_name):
    """socialCardFonts.wording.unknownFontName, filled in."""
    return _font_rules()["wording"]["unknownFontName"].replace("{name}", shown_name)


def _load_font(font_name, size):
    file_path = _font_file(font_name)
    if file_path:
        try:
            return ImageFont.truetype(str(file_path), size)
        except Exception:
            pass
    return ImageFont.load_default(size=size)


def _color(palette, key, fallback):
    value = palette.get(key) or fallback
    try:
        return ImageColor.getrgb(value)
    except Exception:
        return ImageColor.getrgb(fallback)


def _wrapped_title(text, font, max_width):
    """The title as lines that each fit, wrapped greedily by words."""
    lines = []
    current = ""
    for word in str(text).split():
        attempt = (current + " " + word).strip()
        if font.getlength(attempt) <= max_width or not current:
            current = attempt
        else:
            lines.append(current)
            current = word
    if current:
        lines.append(current)
    return lines


def _title_layout(text, font_name, max_width):
    """The largest title size (96 down to 44) whose wrapped lines number
    at most two and each fit the width."""
    for size in range(96, 43, -4):
        font = _load_font(font_name, size)
        lines = _wrapped_title(text, font, max_width)
        widest = max((font.getlength(line) for line in lines), default=0)
        if len(lines) <= 2 and widest <= max_width:
            return font, lines, size
    font = _load_font(font_name, 44)
    return font, _wrapped_title(text, font, max_width), 44


def _emoji_image(emoji, target_height):
    """The emoji as a transparent image scaled to the target height, or
    None when no colour emoji font is available (the card simply goes
    without)."""
    font_path = None
    for candidate in EMOJI_FONT_CANDIDATES:
        if candidate.is_file():
            font_path = candidate
            break
    if not font_path or not emoji:
        return None
    try:
        font = ImageFont.truetype(str(font_path), EMOJI_STRIKE_SIZE)
        canvas = Image.new("RGBA", (EMOJI_STRIKE_SIZE * 3, EMOJI_STRIKE_SIZE * 2), (0, 0, 0, 0))
        draw = ImageDraw.Draw(canvas)
        draw.text((EMOJI_STRIKE_SIZE // 2, EMOJI_STRIKE_SIZE // 2), emoji, font=font, embedded_color=True)
        cropped = canvas.crop(canvas.getbbox())
        scale = target_height / cropped.height
        return cropped.resize((max(1, round(cropped.width * scale)), target_height), Image.LANCZOS)
    except Exception:
        return None


def generate_card(course_config, section_number, output_path):
    """Draws the card for one section and writes it as a PNG."""
    section_key = f"section{section_number}"

    course_name = course_config.get("course_name") or course_config.get("course_code") or "My Course"
    course_code = course_config.get("course_code") or ""

    marker_map = (course_config.get("show_section_marker") or {}).get("sections") or {}
    shows_marker = marker_map.get(section_key, True)
    subtitle_text = f"{course_code} S{section_number}" if shows_marker else course_code

    emoji_map = (course_config.get("emojis") or {}).get("sections") or {}
    emoji = emoji_map.get(section_key, "")

    fonts_config = course_config.get("fonts") or {}
    section_fonts = (fonts_config.get("sections") or {}).get(section_key) or fonts_config.get("default") or {}
    header_font_name = section_fonts.get("header", "")
    body_font_name = section_fonts.get("body", "")

    scheme_id = (course_config.get("color_schemes") or {}).get(section_key)
    palette = _load_scheme_colors(scheme_id) if scheme_id else {}

    background = _color(palette, "light", "#faf8f8")
    title_color = _color(palette, "secondary", "#284b63")
    subtitle_color = _color(palette, "darkgray", "#4e4e4e")

    card = Image.new("RGB", (CARD_WIDTH, CARD_HEIGHT), background)
    draw = ImageDraw.Draw(card)

    title_font, title_lines, title_size = _title_layout(course_name, header_font_name, TITLE_MAX_WIDTH)
    title_line_height = round(title_size * 1.18)
    subtitle_font = _load_font(body_font_name, SUBTITLE_SIZE)
    emoji_art = _emoji_image(emoji, round(SUBTITLE_SIZE * 1.15))

    subtitle_height = max(SUBTITLE_SIZE, emoji_art.height if emoji_art else 0)
    block_height = (len(title_lines) * title_line_height) + TITLE_TO_SUBTITLE_GAP + subtitle_height
    y = (CARD_HEIGHT - block_height) // 2

    for line in title_lines:
        draw.text((MARGIN_X, y), line, font=title_font, fill=title_color)
        y += title_line_height

    y += TITLE_TO_SUBTITLE_GAP
    x = MARGIN_X
    if emoji_art:
        card.paste(emoji_art, (x, y + (subtitle_height - emoji_art.height) // 2), emoji_art)
        x += emoji_art.width + EMOJI_TEXT_GAP
    text_y = y + (subtitle_height - SUBTITLE_SIZE) // 2
    draw.text((x, text_y), subtitle_text, font=subtitle_font, fill=subtitle_color)

    output_path = Path(output_path)
    output_path.parent.mkdir(parents=True, exist_ok=True)
    card.save(output_path, format="PNG")
    for shown_name in fonts_not_used(header_font_name, body_font_name):
        print(unknown_font_sentence(shown_name))
    return output_path
