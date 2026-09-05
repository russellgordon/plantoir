#!/usr/bin/env python3
import os
import shutil
import sys
import argparse
try:
    import frontmatter
except ImportError:
    frontmatter = None
import subprocess
import signal
import json
import re
from pathlib import Path

# The embeddable Python used by the native Windows runtime replaces
# sys.path wholesale (python311._pth), so the script's own folder must
# be added by hand before sibling imports. Harmless everywhere else.
import sys as _sys
_sys.path.insert(0, str(Path(__file__).resolve().parent))
import site_health
import contracts
import class_pages
import toolchain_paths
from datetime import datetime, timezone
import threading
import time


# ---- Host OS signaling (for example command rendering) ----------------------
_HOST_OS = "unknown"
def _is_windows(host_os: str) -> bool:
    return (host_os or "").lower() == "windows"

def _cmd_example(script_base: str, course, section, host_os: str) -> str:
    return (f".\\{script_base}.bat {course} {section}") if _is_windows(host_os) else (f"./{script_base}.sh {course} {section}")
# ----------------------------------------------------------------------------

# --- ADD: PATCH LOCALE helper (placed near the bottom of file in the live code) ---
def patch_quartz_locale(quartz_config_path: Path, locale_code: str):
    """
    Ensure `locale: "<code>",` in quartz.config.ts matches `locale_code`.
    Tries a targeted replacement first; if not present, injects a locale key
    at the start of the exported config object.
    """
    if not quartz_config_path.exists():
        print(f"⚠️ quartz.config.ts not found at {quartz_config_path}")
        return
    try:
        src = quartz_config_path.read_text(encoding="utf-8")

        # 1) Targeted replacement: locale: "..." or locale: '...'
        pattern = re.compile(r'(locale\s*:\s*)(["\'])([^"\']*)(\2)')
        def _repl(m: re.Match) -> str:
            quote = m.group(2)
            return f'{m.group(1)}{quote}{locale_code}{quote}'
        new_src, n = pattern.subn(_repl, src, count=1)

        # 2) Fallback: inject after the opening of defineConfig({ ... })
        if n == 0:
            m = re.search(r'defineConfig\(\s*\{', src)
            if m:
                insert_at = m.end()
                new_src = src[:insert_at] + f'\n  locale: "{locale_code}",' + src[insert_at:]
                n = 1
            else:
                new_src = src

        if n > 0 and new_src != src:
            result = toolchain_paths.write_file(str(quartz_config_path), new_src.encode("utf-8"))
            if result.returncode != 0:
                print("❌ Failed to set locale in quartz.config.ts:", result.stderr.decode())
            else:
                print(f'✅ Set Quartz locale → "{locale_code}"')
        else:
            print("ℹ️ Quartz locale already set as desired (no change).")
    except Exception as e:
        print(f"⚠️ Error patching Quartz locale: {e}")

# --- Base URL helper & resolution -------------------------------------------
def clean_base_url(val: str | None) -> str:
    """Normalize a domain/baseUrl: strip http(s):// scheme, whitespace, and trailing slashes."""
    if not val:
        return ""
    val = val.strip()
    val = re.sub(r"^https?://", "", val, flags=re.IGNORECASE)
    val = val.rstrip("/")
    return val

def resolve_section_domain(course_dir: Path, config: dict, section_number: int) -> str:
    """
    Find the public hostname/domain for this course section.
    Checks:
      1. Advanced custom domain in course_config.json
      2. Netlify site marker in .netlify_sites/sectionN.json (or legacy .netlify_site.json)
      3. Cloudflare site marker in .cloudflare_sites/sectionN.json
    Returns empty string if not yet published / no domain assigned.
    """
    section_key = f"section{section_number}"

    # 1. Custom domain from course_config.json — keyed by destination type
    # since a course may publish to more than one place at once, but the
    # baseUrl baked into THIS build (sitemap, RSS, social-card absolute
    # URLs) can only ever be one value. Reads the PRIMARY destination's own
    # domain, matching what the "Live URL" link on a finished deploy has
    # always pointed at — the mac/Windows apps' "Advanced" custom-domain
    # fields are per-destination for exactly this reason (a Netlify-only
    # domain must never leak into a Cloudflare Pages leg's own link), and
    # the primary is the one destination this single build is canonically
    # published as. An older, single-string shape is read as-is: it was
    # written back when a course could only ever have one destination, so
    # there was only ever one destination it could have meant.
    custom_domains = config.get("custom_domains", {})
    if isinstance(custom_domains, dict):
        section_domains = (custom_domains.get("sections") or {}).get(section_key)
        if isinstance(section_domains, dict):
            primary_destination_type = config.get("deploy_target") or "netlify"
            section_custom_domain = section_domains.get(primary_destination_type)
        else:
            section_custom_domain = section_domains
        if section_custom_domain:
            cleaned = clean_base_url(section_custom_domain)
            if cleaned:
                return cleaned

    # 2. Netlify site marker (.netlify_sites/sectionN.json or legacy .netlify_site.json)
    stable_netlify = course_dir / ".netlify_sites" / f"{section_key}.json"
    if stable_netlify.is_file():
        try:
            data = json.loads(stable_netlify.read_text(encoding="utf-8"))
            if data.get("custom_domain"):
                return clean_base_url(data["custom_domain"])
            if data.get("ssl_url"):
                return clean_base_url(data["ssl_url"])
            if data.get("url"):
                return clean_base_url(data["url"])
            if data.get("name"):
                return f"{data['name']}.netlify.app"
        except Exception:
            pass

    legacy_netlify = course_dir / section_key / ".netlify_site.json"
    if legacy_netlify.is_file():
        try:
            data = json.loads(legacy_netlify.read_text(encoding="utf-8"))
            if data.get("custom_domain"):
                return clean_base_url(data["custom_domain"])
            if data.get("ssl_url"):
                return clean_base_url(data["ssl_url"])
            if data.get("url"):
                return clean_base_url(data["url"])
            if data.get("name"):
                return f"{data['name']}.netlify.app"
        except Exception:
            pass

    # 3. Cloudflare site marker (.cloudflare_sites/sectionN.json)
    stable_cf = course_dir / ".cloudflare_sites" / f"{section_key}.json"
    if stable_cf.is_file():
        try:
            data = json.loads(stable_cf.read_text(encoding="utf-8"))
            if data.get("subdomain"):
                return clean_base_url(data["subdomain"])
            if data.get("name"):
                return f"{data['name']}.pages.dev"
            if data.get("production_branch_url"):
                return clean_base_url(data["production_branch_url"])
        except Exception:
            pass

    return ""

def patch_quartz_base_url(quartz_config_path: Path, base_url: str):
    """
    Ensure `baseUrl: "<domain>",` in quartz.config.ts matches `base_url` (or empty string if not deployed).
    """
    if not quartz_config_path.exists():
        print(f"⚠️ quartz.config.ts not found at {quartz_config_path}")
        return
    try:
        src = quartz_config_path.read_text(encoding="utf-8")
        clean_val = clean_base_url(base_url)
        replacement = f'"{clean_val}"' if clean_val else 'undefined'

        # Match baseUrl: "...", baseUrl: '...', baseUrl: undefined, baseUrl: null
        pattern = re.compile(r'(baseUrl\s*:\s*)(["\'][^"\']*["\']|undefined|null)')
        def _repl(m: re.Match) -> str:
            return f'{m.group(1)}{replacement}'
        new_src, n = pattern.subn(_repl, src, count=1)

        if n > 0 and new_src != src:
            result = toolchain_paths.write_file(str(quartz_config_path), new_src.encode("utf-8"))
            if result.returncode != 0:
                print("❌ Failed to set baseUrl in quartz.config.ts:", result.stderr.decode())
            else:
                if clean_val:
                    print(f'✅ Set Quartz baseUrl → "{clean_val}"')
                else:
                    print('✅ Cleared Quartz baseUrl')
        elif n > 0:
            pass
        else:
            print("⚠️ Could not find baseUrl in quartz.config.ts to update")
    except Exception as e:
        print(f"⚠️ Error updating baseUrl in quartz.config.ts: {e}")

# --- ADD: Patch typography fonts in quartz.config.ts -------------------------
def _escape_font(val: str) -> str:
    # Guard against stray quotes in family names
    return val.replace('"', r'\"')

def patch_typography_fonts(quartz_config_path: Path, header_font: str, body_font: str, code_font: str):
    """
    Updates the typography block in quartz.config.ts to use the selected fonts.
      typography: {
        header: "<header_font>",
        body: "<body_font>",
        code: "<code_font>",
      },
    Tries targeted replacements first; if not found, replaces the whole block.
    """
    if not quartz_config_path.exists():
        print(f"⚠️ quartz.config.ts not found at {quartz_config_path}")
        return

    try:
        with open(quartz_config_path, "r", encoding="utf-8") as f:
            content = f.read()

        hf = _escape_font(header_font)
        bf = _escape_font(body_font)
        cf = _escape_font(code_font)

        changed = False

        # Targeted replacements within existing typography block
        def replace_field(src: str, field: str, value: str) -> tuple[str, bool]:
            # Replace the value of e.g. header: "Old"
            pattern = re.compile(
                rf'(typography\s*:\s*\{{[\s\S]*?{field}\s*:\s*)"(.*?)"',
                flags=re.DOTALL
            )
            new_src, n = pattern.subn(rf'\1"{value}"', src, count=1)
            return new_src, (n > 0)

        new_content, hit_h = replace_field(content, "header", hf)
        new_content, hit_b = replace_field(new_content, "body", bf)
        new_content, hit_c = replace_field(new_content, "code", cf)

        changed = hit_h or hit_b or hit_c

        if not changed:
            # Replace the entire typography block if targeted replacements failed
            block_re = re.compile(r'typography\s*:\s*\{[\s\S]*?\}\s*,?', flags=re.DOTALL)
            new_block = (
                'typography: {\n'
                f'        header: "{hf}",\n'
                f'        body: "{bf}",\n'
                f'        code: "{cf}",\n'
                '      },'
            )
            new_content2, n2 = block_re.subn(new_block, new_content, count=1)
            if n2 == 0:
                # As a last resort, try to inject a typography block next to colors/theme
                # Insert after "theme: {" opening if present
                theme_open = re.search(r'(theme\s*:\s*\{)', new_content)
                if theme_open:
                    insert_at = theme_open.end()
                    new_content2 = new_content[:insert_at] + "\n      " + new_block + new_content[insert_at:]
                    changed = True
                else:
                    new_content2 = new_content
            else:
                changed = True
            new_content = new_content2

        if changed:
            result = toolchain_paths.write_file(str(quartz_config_path), new_content.encode("utf-8"))
            if result.returncode != 0:
                print("❌ Failed to update typography fonts in quartz.config.ts:", result.stderr.decode())
            else:
                print(f"✅ Set fonts → header: '{header_font}', body: '{body_font}', code: '{code_font}'")
        else:
            print("ℹ️ Typography fonts already match desired values (no change).")

    except Exception as e:
        print(f"⚠️ Error patching typography fonts: {e}")
# --- END ADD -----------------------------------------------------------------


# --- ADD: Patch base.scss internal link highlight ---
def patch_internal_link_highlight(base_scss_path: Path):
    """Comment out background-color for .internal links in base.scss."""
    if not base_scss_path.exists():
        print(f"⚠️ base.scss not found at {base_scss_path}")
        return
    try:
        with open(base_scss_path, "r", encoding="utf-8") as f:
            content = f.read()

        pattern = re.compile(
            r'(&\.internal\s*\{[^}]*?)background-color:\s*var\(--highlight\);\s*',
            flags=re.DOTALL
        )

        replacement = r'\1/*    background-color: var(--highlight); */\n'

        new_content = pattern.sub(replacement, content)

        if new_content != content:
            result = toolchain_paths.write_file(str(base_scss_path), new_content.encode("utf-8"))
            if result.returncode != 0:
                print("❌ Failed to patch base.scss internal link highlight:", result.stderr.decode())
            else:
                print("✅ Patched base.scss to comment out internal link background-color")
        else:
            print("ℹ️ base.scss internal link background-color already commented out (no change).")
    except Exception as e:
        print(f"⚠️ Error patching base.scss: {e}")
# --- END ADD ---

# --- ADD: Append transclusion styles to base.scss ---
def append_transclusion_styles(base_scss_path: Path):
    """
    Appends styles for transcluded content to the bottom of base.scss, idempotently.
    """
    if not base_scss_path.exists():
        print(f"⚠️ base.scss not found at {base_scss_path}")
        return
    try:
        marker = "/* Additions for containerized Quartz for teachers styles */"
        block = (
            "\n\n"
            "/* Additions for containerized Quartz for teachers styles */\n"
            "a.transclude-src {\n"
            "  display: none;\n"
            "}\n\n"
            "blockquote.transclude {\n"
            "  padding-left: 0;\n"
            "  border-left: none;\n"
            "}\n\n"
            "#quartz-body > div.center > div.page-header > div > h1 {\n"
            "  font-size: 2rem;\n"
            "}\n"
        )

        with open(base_scss_path, "r", encoding="utf-8") as f:
            content = f.read()

        if marker in content:
            print("ℹ️ Transclusion styles already present in base.scss (no change).")
            return

        new_content = content + block
        result = toolchain_paths.write_file(str(base_scss_path), new_content.encode("utf-8"))
        if result.returncode != 0:
            print("❌ Failed to append transclusion styles to base.scss:", result.stderr.decode())
        else:
            print("✅ Appended transclusion styles to base.scss")
    except Exception as e:
        print(f"⚠️ Error appending transclusion styles: {e}")
# --- END ADD ---


# --- ADD: Stop diagram labels being hyphenated ---
def append_mermaid_styles(base_scss_path: Path):
    """
    Turns hyphenation off inside mermaid diagrams, idempotently.

    Quartz hyphenates body text, which reads well in a paragraph. Inside
    a mermaid diagram it is a bug: the label of a box is not prose, and
    breaking it mid-word puts "Ca-" and "reers" on separate lines of a
    flowchart node. WebKit does this and Chromium does not, which is why
    a site can look right in Chrome and wrong in the Plantoir preview.

    Carries its own marker rather than joining the transclusion block, so
    course folders built before this existed pick it up on their next
    build instead of being skipped.
    """
    if not base_scss_path.exists():
        print(f"⚠️ base.scss not found at {base_scss_path}")
        return
    try:
        marker = "/* Diagram labels are not prose: never hyphenate them */"
        block = (
            "\n\n"
            f"{marker}\n"
            ".mermaid,\n"
            ".mermaid * {\n"
            "  -webkit-hyphens: none;\n"
            "  hyphens: none;\n"
            "}\n"
        )

        with open(base_scss_path, "r", encoding="utf-8") as f:
            content = f.read()

        if marker in content:
            print("ℹ️ Mermaid label styles already present in base.scss (no change).")
            return

        with open(base_scss_path, "w", encoding="utf-8") as f:
            f.write(content + block)
        print("✅ Appended mermaid label styles to base.scss")
    except Exception as e:
        print(f"⚠️ Error appending mermaid label styles: {e}")
# --- END ADD ---


# --- ADD: Let the right sidebar's two panels share the column ---
def append_sidebar_sharing_styles(base_scss_path: Path):
    """
    Stop a long backlinks list from crowding out the table of contents.

    The right sidebar holds "Navigate this page" above "When did we do
    this?". A page linked from many others gave the backlinks list its
    full natural height first, squeezing the table of contents down to a
    line or two with a scrollbar — on the very pages where the contents
    are most useful.

    The rules below give each panel its own scrollbar and make them share
    the column: the table of contents takes only the height it needs, up
    to half, and the backlinks take whatever is left. So a short contents
    list keeps the backlinks tucked directly beneath it, and when both are
    long they land at roughly half each.

    The cap is skipped when the contents are the only panel, so a page
    nothing links to still uses the whole column. Specificity is kept
    below Quartz's own `.toc:has(button.toc-header.collapsed)` rule, so
    collapsing the contents still works.

    Carries its own marker so existing course folders pick it up.
    """
    if not base_scss_path.exists():
        print(f"⚠️ base.scss not found at {base_scss_path}")
        return
    try:
        marker = "/* The right sidebar's two panels share the column */"
        block = (
            "\n\n"
            f"{marker}\n"
            "/* Not shrinkable: the contents keep the height they need,\n"
            "   and the cap below is what stops them taking over. */\n"
            ".right.sidebar > .toc {\n"
            "  flex: 0 0 auto;\n"
            "  min-height: 0;\n"
            "  max-height: 100%;\n"
            "}\n\n"
            ".right.sidebar > .toc:not(:only-child) {\n"
            "  max-height: 50%;\n"
            "}\n\n"
            ".right.sidebar > *:not(.toc) {\n"
            "  flex: 1 1 auto;\n"
            "  min-height: 0;\n"
            "}\n\n"
            ".right.sidebar .toc-content,\n"
            ".right.sidebar .backlinks {\n"
            "  flex: 1 1 auto;\n"
            "  min-height: 0;\n"
            "  max-height: 100%;\n"
            "  overflow-y: auto;\n"
            "}\n\n"
            "/* The lists are the real scrollers: their parents are row\n"
            "   flex containers, so the overflow happens one level in. */\n"
            ".right.sidebar .toc-content > ul,\n"
            ".right.sidebar .backlinks > ul {\n"
            "  min-height: 0;\n"
            "  max-height: 100%;\n"
            "  overflow-y: auto;\n"
            "}\n"
        )

        with open(base_scss_path, "r", encoding="utf-8") as f:
            content = f.read()

        if marker in content:
            print("ℹ️ Sidebar sharing styles already present in base.scss (no change).")
            return

        with open(base_scss_path, "w", encoding="utf-8") as f:
            f.write(content + block)
        print("✅ Appended sidebar sharing styles to base.scss")
    except Exception as e:
        print(f"⚠️ Error appending sidebar sharing styles: {e}")
# --- END ADD ---

# --- ADD: Prevent page title wrapping and vertically center navbar elements ---
def append_page_title_styles(base_scss_path: Path):
    """
    Prevents the navbar course code and section number from wrapping onto
    a second line on mobile by dynamically scaling the page title font size
    down (up to 50% of its original 1.75rem size) and setting white-space: nowrap.
    Also vertically centers the course emoji, code, and section as well as the
    light/dark mode toggle button with the adjacent search field.

    Using clamp(0.875rem, 4.5vw, 1.75rem) keeps the title at full 1.75rem size
    on desktop and tablet (where viewport >= 800px), smoothly shrinks it on
    mobile screens, and ensures it never drops below 0.875rem (50% of original).
    """
    if not base_scss_path.exists():
        print(f"⚠️ base.scss not found at {base_scss_path}")
        return
    try:
        marker = "/* Page title dynamic sizing and no-wrap on mobile */"
        block = (
            "\n\n"
            f"{marker}\n"
            ".page-title {\n"
            "  font-size: clamp(0.875rem, 4.5vw, 1.75rem);\n"
            "  white-space: nowrap;\n"
            "  margin: 0;\n"
            "  align-self: flex-start;\n"
            "  display: inline-flex;\n"
            "  align-items: center;\n"
            "  line-height: 1;\n\n"
            "  @media all and ($mobile) {\n"
            "    align-self: center;\n"
            "  }\n"
            "}\n\n"
            ".page-title a {\n"
            "  display: inline-flex;\n"
            "  align-items: center;\n"
            "  max-width: 100%;\n"
            "  overflow: hidden;\n"
            "  text-overflow: ellipsis;\n"
            "  white-space: nowrap;\n"
            "  line-height: 1;\n"
            "}\n\n"
            ".darkmode {\n"
            "  height: 2rem;\n"
            "  display: inline-flex;\n"
            "  align-items: center;\n"
            "  justify-content: center;\n"
            "  vertical-align: middle;\n\n"
            "  & svg {\n"
            "    position: relative;\n"
            "    top: 0;\n"
            "  }\n"
            "}\n"
        )

        with open(base_scss_path, "r", encoding="utf-8") as f:
            content = f.read()

        if marker in content:
            pattern = re.compile(re.escape(marker) + r".*?(?:\.darkmode\s*\{.*?\n\}|\.page-title a\s*\{[^}]*\})", re.DOTALL)
            if pattern.search(content):
                new_block_body = block.split(f"{marker}\n")[1].rstrip()
                content = pattern.sub(f"{marker}\n{new_block_body}", content)
                with open(base_scss_path, "w", encoding="utf-8") as f:
                    f.write(content)
                print("✅ Updated navbar header styles in base.scss")
                return

        with open(base_scss_path, "w", encoding="utf-8") as f:
            f.write(content + block)
        print("✅ Appended navbar header styles to base.scss")
    except Exception as e:
        print(f"⚠️ Error appending navbar header styles: {e}")
# --- END ADD ---

# --- ADD: Patch ContentMeta.tsx date format ---
def patch_date_format(date_tsx_file_path: Path):
    """Update formatDate in Date.tsx to show full weekday, month, and day."""
    if not date_tsx_file_path.exists():
        print(f"⚠️ Date.tsx not found at {date_tsx_file_path}")
        return
    try:
        with open(date_tsx_file_path, "r", encoding="utf-8") as f:
            content = f.read()

        pattern = re.compile(
            r'export function formatDate\(d: Date, locale: ValidLocale = "en-US"\): string \{\s*return d\.toLocaleDateString\(locale, \{\s*year: "numeric",\s*month: "short",\s*day: "2-digit",\s*\}\s*\)\s*\}',
            flags=re.DOTALL
        )

        replacement = (
            'export function formatDate(d: Date, locale: ValidLocale = "en-US"): string {\n'
            '  return d.toLocaleDateString(locale, {\n'
            '    weekday: "long",\n'
            '    year: "numeric",\n'
            '    month: "long",\n'
            '    day: "numeric",\n'
            '  })\n'
            '}\n'
        )

        new_content = pattern.sub(replacement, content)

        if new_content != content:
            result = toolchain_paths.write_file(str(date_tsx_file_path), new_content.encode("utf-8"))
            if result.returncode != 0:
                print("❌ Failed to patch Date.tsx date format:", result.stderr.decode())
            else:
                print("✅ Patched Date.tsx to show full weekday/month/day date format")
        else:
            print("ℹ️ Date.tsx date format already matches desired settings.")
    except Exception as e:
        print(f"⚠️ Error patching Date.tsx: {e}")
# --- END ADD ---

# --- ADD: Patch listPage.scss meta width ---
def patch_list_page_meta_width(list_page_scss_path: Path):
    """Add width: 240px; to .meta in listPage.scss."""
    if not list_page_scss_path.exists():
        print(f"⚠️ listPage.scss not found at {list_page_scss_path}")
        return
    try:
        with open(list_page_scss_path, "r", encoding="utf-8") as f:
            content = f.read()

        pattern = re.compile(
            r'(&\s*\.meta\s*\{\s*margin:\s*0\s*1em\s*0\s*0;\s*opacity:\s*0\.6;\s*\})',
            flags=re.DOTALL
        )

        replacement = (
            "& .meta {\n"
            "      margin: 0 1em 0 0;\n"
            "      opacity: 0.6;\n"
            "      width: 240px;\n"
            "    }"
        )

        new_content = pattern.sub(replacement, content)

        if new_content != content:
            result = toolchain_paths.write_file(str(list_page_scss_path), new_content.encode("utf-8"))
            if result.returncode != 0:
                print("❌ Failed to patch listPage.scss .meta width:", result.stderr.decode())
            else:
                print("✅ Patched listPage.scss to set .meta width to 240px")
        else:
            print("ℹ️ listPage.scss .meta already has desired width.")
    except Exception as e:
        print(f"⚠️ Error patching listPage.scss: {e}")
# --- END ADD ---

def adjust_created_modified_priority(config_path: Path):
    """Remove 'git' from Plugin.CreatedModifiedDate priority array."""
    if not config_path.exists():
        print(f"⚠️ quartz.config.ts not found at {config_path}")
        return

    try:
        with open(config_path, "r", encoding="utf-8") as f:
            content = f.read()

        # Replace only inside Plugin.CreatedModifiedDate block
        new_content = re.sub(
            r'Plugin\.CreatedModifiedDate\(\{\s*priority:\s*\["git",\s*"frontmatter",\s*"filesystem"\]\s*,?\s*\}\)',
            'Plugin.CreatedModifiedDate({\n        priority: ["frontmatter", "filesystem"],\n      })',
            content
        )

        if new_content != content:
            result = toolchain_paths.write_file(str(config_path), new_content.encode())
            if result.returncode != 0:
                print("❌ Failed to update CreatedModifiedDate priority:", result.stderr.decode())
            else:
                print("✅ Updated CreatedModifiedDate priority to exclude 'git'")
        else:
            print("ℹ️ No matching CreatedModifiedDate priority array found — no changes made.")

    except Exception as e:
        print(f"❌ Error adjusting CreatedModifiedDate priority: {e}")

# --- ADD: Ensure configuration.defaultDateType === "created" -----------------
def patch_default_date_type(quartz_config_path: Path):
    """
    Ensure quartz.config.ts has configuration.defaultDateType set to "created".
    Tries to update if present; otherwise injects into the configuration block.
    Idempotent.
    """
    if not quartz_config_path.exists():
        print(f"⚠️ quartz.config.ts not found at {quartz_config_path}")
        return

    try:
        txt = quartz_config_path.read_text(encoding="utf-8")

        # Find 'configuration: {' and match its balanced braces
        m = re.search(r'(configuration\s*:\s*\{)', txt)
        if not m:
            # No configuration block — inject one after 'theme' block or near top-level
            inject_block = 'configuration: {\n      defaultDateType: "created",\n    },'
            # Try to insert after theme: { ... }
            theme_m = re.search(r'(theme\s*:\s*\{)', txt)
            if not theme_m:
                # Insert at the start of the exported object (after first '{')
                first_brace = txt.find('{')
                if first_brace != -1:
                    new_txt = txt[:first_brace+1] + "\n  " + inject_block + "\n" + txt[first_brace+1:]
                else:
                    new_txt = txt + "\n" + inject_block + "\n"
            else:
                # Find end of theme block by counting braces
                brace_open = txt.find('{', theme_m.end()-1)
                if brace_open == -1:
                    new_txt = txt
                else:
                    depth = 1
                    i = brace_open + 1
                    n = len(txt)
                    while i < n and depth > 0:
                        ch = txt[i]
                        if ch == '{':
                            depth += 1
                        elif ch == '}':
                            depth -= 1
                        i += 1
                    end = i  # position after closing brace
                    new_txt = txt[:end] + ",\n    " + inject_block + "\n" + txt[end:]
            if new_txt != txt:
                result = toolchain_paths.write_file(str(quartz_config_path), new_txt.encode("utf-8"))
                if result.returncode != 0:
                    print("❌ Failed to inject configuration.defaultDateType:", result.stderr.decode())
                else:
                    print('✅ Inserted configuration.defaultDateType = "created"')
            else:
                print("ℹ️ Could not locate an insertion point for configuration block (no change).")
            return

        # We have a configuration block — find its closing brace
        brace_open = txt.find('{', m.end()-1)
        if brace_open == -1:
            print("ℹ️ Malformed configuration block (no change).")
            return
        depth = 1
        i = brace_open + 1
        n = len(txt)
        while i < n and depth > 0:
            ch = txt[i]
            if ch == '{':
                depth += 1
            elif ch == '}':
                depth -= 1
            i += 1
        brace_close = i - 1  # index of matching '}'

        inner = txt[brace_open+1:brace_close]

        # If defaultDateType exists, replace its value; else insert it at the top
        if re.search(r'\bdefaultDateType\s*:', inner):
            inner2 = re.sub(r'(defaultDateType\s*:\s*)"(.*?)"', r'\1"created"', inner, count=1)
        else:
            # Determine indentation
            line_start = txt.rfind('\n', 0, m.start()) + 1
            base_indent = re.match(r'[ \t]*', txt[line_start:m.start()]).group(0)
            inner_indent = base_indent + "  "
            if inner.strip():
                inner2 = "\n" + inner_indent + 'defaultDateType: "created",' + "\n" + inner.lstrip()
            else:
                inner2 = "\n" + inner_indent + 'defaultDateType: "created"' + "\n" + base_indent

        new_txt = txt[:brace_open+1] + inner2 + txt[brace_close:]
        if new_txt != txt:
            result = toolchain_paths.write_file(str(quartz_config_path), new_txt.encode("utf-8"))
            if result.returncode != 0:
                print("❌ Failed to patch configuration.defaultDateType:", result.stderr.decode())
            else:
                print('✅ Ensured configuration.defaultDateType = "created"')
        else:
            print("ℹ️ configuration.defaultDateType already set (no change).")

    except Exception as e:
        print(f"⚠️ Error ensuring configuration.defaultDateType: {e}")
# --- END ADD -----------------------------------------------------------------

# --- ADD: Resolve per-section emoji from course_config.json ------------------
def resolve_section_emoji(config: dict, section_number: int) -> str:
    """
    Returns the emoji to use for the page title, preferring the per-section choice.
    Falls back to a legacy course-level default only if present; otherwise '📚'.
    """
    try:
        emojis = config.get("emojis", {})
        if isinstance(emojis, dict):
            sec_map = emojis.get("sections") or {}
            sec_emo = sec_map.get(f"section{section_number}")
            if isinstance(sec_emo, str) and sec_emo.strip():
                return sec_emo.strip()
            # Back-compat: if older configs stored a course-level "default", use it as a fallback
            legacy_default = emojis.get("default")
            if isinstance(legacy_default, str) and legacy_default.strip():
                return legacy_default.strip()
    except Exception:
        pass
    return "📚"
# --- END ADD -----------------------------------------------------------------

# --- ADD: Resolve per-section 'show section marker' flag ---------------------

# --- ADD: Resolve header label (course code vs custom short name for clubs) ---
def resolve_header_label(config: dict, course_code: str) -> str:
    """Return the label that appears beside the emoji in the page title.

    A course code is ALWAYS shown in uppercase, whatever shape it has.

    This used to title-case a code with no digit in its fourth character —
    "CODING" became "Coding" — on the theory that a club's name reads better
    that way. It does not: a code is a code, the teacher typed it in capitals,
    and seeing it changed on their own site reads as a bug. It got worse once
    codes could carry a space, where the same rule turned "AP CALC" into
    "Ap Calc". A teacher who wants prose in that spot has "custom_short_name",
    which is their own text and is used as typed.
    """
    grade_label = get_grade_label(course_code)
    if grade_label:
        return course_code.upper()
    # Club or otherwise non-standard code: the teacher's own short name if
    # they set one, and otherwise the code itself — in capitals.
    custom = (config.get("custom_short_name") or "").strip()
    if custom:
        return custom
    return course_code.upper()
def resolve_show_section_marker(config: dict, section_number: int) -> bool:
    """
    Return whether 'S{section}' should appear in the page title.
    Supports several shapes in course_config.json:

      {
        "show_section_marker": {
          "sections": { "section3": false, "section4": true },
          "default": true
        }
      }

    Also accepts:
      - {"show_section_marker": {"section3": false}}
      - {"show_section_marker": true/false}
      - Legacy/alt keys: show_section_in_title, showSectionMarkerInTitle, showSectionMarker

    Default when absent: True.
    """
    sec_key = f"section{section_number}"
    candidates = [
        "show_section_marker",
        "show_section_in_title",
        "showSectionMarkerInTitle",
        "showSectionMarker",
    ]

    for key in candidates:
        val = config.get(key)
        if isinstance(val, dict):
            # Prefer nested "sections" map
            sec_map = val.get("sections")
            if isinstance(sec_map, dict) and sec_key in sec_map:
                return bool(sec_map[sec_key])
            # Or direct section key at top-level
            if sec_key in val:
                return bool(val[sec_key])
            # Or a course-level default
            if "default" in val:
                return bool(val["default"])
        elif isinstance(val, bool):
            return val

    return True
# --- END ADD -----------------------------------------------------------------

# --- ADD: Remove section marker from a full course title ---------------------

GRADE_LABELS = {"1": "Grade 9", "2": "Grade 10", "3": "Grade 11", "4": "Grade 12"}


def get_grade_label(course_code: str) -> str:
    """
    Derive the grade label from a course code across jurisdictions.
    Supports Ontario (4th char 1-4) and BC (trailing 09, 10, 11, 12).
    """
    trimmed = (course_code or "").strip()
    if not trimmed:
        return ""
    if trimmed.endswith("09") or trimmed.endswith("-09"):
        return "Grade 9"
    if trimmed.endswith("10") or trimmed.endswith("-10"):
        return "Grade 10"
    if trimmed.endswith("11") or trimmed.endswith("-11"):
        return "Grade 11"
    if trimmed.endswith("12") or trimmed.endswith("-12"):
        return "Grade 12"
    if len(trimmed) >= 4 and trimmed[3].isdigit():
        return GRADE_LABELS.get(trimmed[3], "Grade ?")
    return ""


def resolve_show_grade_in_title(cfg, section_number):
    """Per-section, like the section marker; defaults on. An older config
    that stored one course-wide boolean is honoured."""
    raw = cfg.get("show_grade_in_title", True)
    if isinstance(raw, dict):
        return bool((raw.get("sections") or {}).get(f"section{section_number}", True))
    return bool(raw)


def computed_landing_title(cfg, section_number, show_marker):
    """
    The landing page's title, computed from the CURRENT settings at build
    time — never baked in at scaffold time. This is what makes a course
    rename reach the site, makes the grade a switch (show_grade_in_title,
    default on), and keeps the grade from doubling when the course name
    already carries one ("Computer Science, Grade 12, U").
    """
    name = str(cfg.get("course_name") or cfg.get("course_code") or "").strip()
    code = str(cfg.get("course_code") or "")
    # Deliberately literal: the switch alone decides. The app warns when
    # the name already carries the grade; what to do about it — edit the
    # name or turn the switch off — is the teacher's call, never guessed.
    prefix = ""
    grade_label = get_grade_label(code)
    if resolve_show_grade_in_title(cfg, section_number) and grade_label:
        prefix = f"{grade_label} "
    title = f"{prefix}{name}"
    if show_marker:
        title = f"{title}, Section {section_number}"
    return title


def set_landing_title(index_md_path: Path, cfg, section_number, show_marker):
    """Writes the computed title into the MERGED copy of the section's
    landing page. The teacher's source index.md is never touched."""
    if not index_md_path.exists():
        return
    try:
        post = frontmatter.load(index_md_path)
        post["title"] = computed_landing_title(cfg, section_number, show_marker)
        with open(index_md_path, "w", encoding="utf-8") as f:
            f.write(frontmatter.dumps(post))
        print(f"📝 Landing page title: '{post['title']}'")
    except Exception as e:
        print(f"⚠️ Could not set the landing page title: {e}")
# --- END ADD -----------------------------------------------------------------


# --- NEW: Read/validate timetable section numbers ---------------------------
def get_allowed_section_numbers(config: dict) -> list[int]:
    """
    Returns the list of timetable section numbers for this course.
    Falls back to [1..num_sections] if 'section_numbers' is not present.
    """
    try:
        seq = config.get("section_numbers")
        if isinstance(seq, list) and seq:
            # Ensure ints and sorted
            return sorted([int(x) for x in seq])
        n = int(config.get("num_sections", 1))
        return list(range(1, n + 1))
    except Exception:
        return [1]

def validate_requested_section(allowed: list[int], requested: int) -> bool:
    if requested in allowed:
        return True
    print("❌ The requested section is not part of this course's timetable sections.")
    print(f"   Allowed sections for this course: {allowed}")
    print("   Tip: Re-run with e.g. '--section 3' to build Section 3 if that's assigned to you.")
    return False
# ---------------------------------------------------------------------------

def update_page_title(config_path: Path, header_label: str, section_number: int, emoji: str, show_section_marker: bool = True):
    if not config_path.exists():
        print(f"⚠️ quartz.config.ts not found at {config_path}")
        return

    with open(config_path, "r", encoding="utf-8") as f:
        lines = f.readlines()

    new_lines = []
    updated = False
    # --- MODIFIED: use resolved emoji & optional section marker ---
    safe_emoji = (emoji or "📚").strip()
    if show_section_marker:
        new_title = f'{safe_emoji} {header_label} S{section_number}'
    else:
        new_title = f'{safe_emoji} {header_label}'

    for line in lines:
        if "pageTitle:" in line:
            new_lines.append(f'  pageTitle: "{new_title}",\n')
            updated = True
        else:
            new_lines.append(line)

    if updated:
        content = ''.join(new_lines)
        result = toolchain_paths.write_file(str(config_path), content.encode())
        if result.returncode != 0:
            print("⚠️ Error updating pageTitle in quartz.config.ts:", result.stderr.decode())
        else:
            print(f"✅ Updated pageTitle to '{new_title}' in quartz.config.ts")
    else:
        print("⚠️ Could not find pageTitle in quartz.config.ts to update")

def toggle_custom_og_images(config_path: str, enable: bool):
    with open(config_path, 'r') as file:
        lines = file.readlines()

    modified_lines = []
    changed = False

    for line in lines:
        stripped = line.strip()
        if re.search(r'Plugin\.CustomOgImages\(\)', stripped):
            if enable and stripped.startswith("//"):
                line = line.replace("//", "", 1)
                changed = True
            elif not enable and not stripped.startswith("//"):
                line = "//" + line
                changed = True
        modified_lines.append(line)

    if changed:
        content = ''.join(modified_lines)
        result = toolchain_paths.write_file(config_path, content.encode())
        if result.returncode != 0:
            print("⚠️ Error updating quartz.config.ts:", result.stderr.decode())
        else:
            print("✅ Updated quartz.config.ts to", "enable" if enable else "disable", "social media previews")
    else:
        print("No changes needed to quartz.config.ts")


def stop_preview_serving(output_dir: Path) -> int:
    """
    Stop the preview serving THIS section, and nothing else.

    Killing by port is wrong for a build that was given no port — see the
    caller. Killing by the section's own build directory is exact: the
    launcher runs the Quartz CLI by absolute path, so the directory is on the
    serve process's command line.

    Stopping the node server is enough. Its Python parent waits on it with
    `check=True`, so the parent exits when it dies, and the parent's sync
    watcher — a daemon thread, and the actual cause of the race this closes —
    goes with it.

    Reads `/proc`, which exists wherever this runs on the mac (inside the
    container) and on Linux. Natively on Windows there is no `/proc` and this
    does nothing, exactly as `kill_existing_quartz` already does nothing there
    without `lsof`; Windows has its own answer to make — see WINDOWS-HANDOFF.
    """
    marker = str(output_dir).rstrip("/") + "/"
    proc = Path("/proc")
    if not proc.is_dir():
        return 0
    stopped = 0
    for entry in proc.iterdir():
        if not entry.name.isdigit():
            continue
        try:
            command = (entry / "cmdline").read_bytes().replace(b"\x00", b" ").decode(
                "utf-8", "replace")
        except OSError:
            continue
        if marker not in command or "--serve" not in command:
            continue
        try:
            os.kill(int(entry.name), signal.SIGKILL)
            stopped += 1
            print(f"🛑 Stopped the preview that was still serving this section "
                  f"(PID {entry.name}), so it cannot overwrite this build.")
        except (ValueError, ProcessLookupError, PermissionError) as error:
            print(f"⚠️ Could not stop the preview process {entry.name}: {error}")
    return stopped


def kill_existing_quartz(port: int = 8081):
    # Only OUR port: several previews can run at once, one per port, and
    # starting one must never take down another window's preview.
    #
    # Signal the process directly rather than shelling out to `kill`:
    # `kill` is a shell builtin, and the /bin/kill binary (procps) is not
    # installed in this image, so subprocess could not find it.
    try:
        output = subprocess.check_output(["lsof", "-ti", f":{port}"])
    except (subprocess.CalledProcessError, FileNotFoundError):
        return
    pids = output.decode().strip().split("\n")
    for pid in pids:
        if not pid:
            continue
        try:
            os.kill(int(pid), signal.SIGKILL)
            print(f"🛑 Killed existing process on port {port} (PID: {pid})")
        except (ValueError, ProcessLookupError, PermissionError) as e:
            print(f"⚠️ Could not stop process {pid} on port {port}: {e}")


# --- HARDENING TWEAK #1: Future-proof omit replacement (update all matches) --
def update_quartz_layout(quartz_layout_path: Path, hidden_components: list):
    if not quartz_layout_path.exists():
        print(f"⚠️ quartz.layout.ts not found at {quartz_layout_path}")
        return

    normalized_hidden = [
        item[:-3] if item.endswith(".md") else item
        for item in hidden_components
    ]

    content = Path(quartz_layout_path).read_text(encoding="utf-8")
    formatted = ", ".join(f'"{n}"' for n in normalized_hidden)
    replacement_line = f"const omit = new Set([{formatted}])"

    # Match both:
    #   const omit = new Set([...])
    #   const omit = new Set<string>([ ... ])
    # and keep the CQ4T-OMIT-ANCHOR line if it's directly above.
    pattern_omit = re.compile(
        r'(?P<anchor>^[ \t]*//[ \t]*CQ4T-OMIT-ANCHOR:.*?\n)?'  # optional anchor line
        r'[ \t]*const[ \t]+omit[ \t]*=[ \t]*new[ \t]+Set'     # const omit = new Set
        r'(?:<[^>]*>)?'                                       # optional generic, e.g., <string>
        r'[ \t]*\([ \t]*\[[\s\S]*?\][ \t]*\)[ \t]*;?',        # ([ ... ])
        flags=re.DOTALL | re.MULTILINE,
    )

    def _repl(m: re.Match) -> str:
        anchor = m.group('anchor') or ''
        return f"{anchor}{replacement_line}"

    new_content, replaced_count = pattern_omit.subn(_repl, content, count=0)  # replace ALL

    if replaced_count == 0:
        # If not found, insert right after the imports block (or at top)
        m = re.search(r'^(?:import .*?;\s*)+', content, flags=re.MULTILINE | re.DOTALL)
        insert_at = m.end() if m else 0
        new_content = (
            content[:insert_at]
            + ("" if insert_at == 0 else "\n")
            + replacement_line
            + "\n"
            + content[insert_at:]
        )

    result = toolchain_paths.write_file(str(quartz_layout_path), new_content.encode("utf-8"))
    if result.returncode != 0:
        print("❌ Failed to write omit list to quartz.layout.ts:", result.stderr.decode())
    else:
        plural = "entries" if replaced_count != 1 else "entry"
        print(f"✅ Updated quartz.layout.ts omit set ({replaced_count} {plural} replaced or inserted).")
# -----------------------------------------------------------------------------

def inject_custom_footer_components(quartz_layout_path: Path, footer_component_path: Path, footer_html: str):
    if quartz_layout_path.exists():
        with open(quartz_layout_path, "r", encoding="utf-8") as f:
            layout_content = f.read()

        modified_layout = re.sub(
            r'footer:\s*Component\.Footer\(\{[\s\S]*?\}\)',
            'footer: Component.Footer()',
            layout_content
        )

        result = toolchain_paths.write_file(str(quartz_layout_path), modified_layout.encode())
        if result.returncode != 0:
            print("❌ Failed to update quartz.layout.ts:", result.stderr.decode())
        else:
            print("✅ Updated quartz.layout.ts to use Component.Footer()")
    else:
        print(f"⚠️ quartz.layout.ts not found at: {quartz_layout_path}")

    if footer_component_path.exists():
        with open(footer_component_path, "r", encoding="utf-8") as f:
            footer_code = f.read()

        # Use a JS template literal to preserve multi-line HTML and quotes safely
        safe_html = footer_html.replace("`", "\\`")

        replacement = f"""<footer class={{displayClass ?? ""}}>
                <div dangerouslySetInnerHTML={{{{ __html: `{safe_html}` }}}} />
              </footer>"""

        modified_code = re.sub(
            r'<footer class=\{.*?\}>(.*?)</footer>',
            replacement,
            footer_code,
            flags=re.DOTALL
        )

        result = toolchain_paths.write_file(str(footer_component_path), modified_code.encode())
        if result.returncode != 0:
            print("❌ Failed to update Footer.tsx:", result.stderr.decode())
        else:
            print("✅ Injected custom HTML into Footer.tsx")
    else:
        print(f"⚠️ Footer.tsx not found at {footer_component_path}")


COLOUR_JSON_CANDIDATES = [
    Path("support/colour_schemes.json"),
    toolchain_paths.SUPPORT_DIR / "colour_schemes.json",
    Path(__file__).resolve().parent.parent / "support" / "colour_schemes.json",
    Path(__file__).resolve().parent / "support" / "colour_schemes.json",
]

def load_colour_schemes():
    for p in COLOUR_JSON_CANDIDATES:
        if p.exists():
            try:
                with open(p, "r", encoding="utf-8") as f:
                    data = json.load(f)
                if isinstance(data, dict) and "schemes" in data:
                    return data["schemes"]
                return data
            except Exception as e:
                print(f"⚠️ Failed to load colour_schemes.json from {p}: {e}")
    print("⚠️ colour_schemes.json not found — using existing Quartz colors.")
    return []

def find_scheme_by_id(schemes, scheme_id):
    for s in schemes:
        if s.get("id") == scheme_id:
            return s
    return None

def format_colors_block(colors: dict) -> str:
    def dict_to_ts(d, indent="          "):
        order = ["light", "lightgray", "gray", "darkgray", "dark", "secondary", "tertiary", "highlight", "textHighlight"]
        lines = []
        for k in order:
            if k in d:
                v = d[k]
                if isinstance(v, str):
                    lines.append(f'{indent}{k}: "{v}",')
        return "\n".join(lines)

    lm = colors.get("lightMode", {})
    dm = colors.get("darkMode", {})

    return (
        "      colors: {\n"
        "        lightMode: {\n"
        f"{dict_to_ts(lm)}\n"
        "        },\n"
        "        darkMode: {\n"
        f"{dict_to_ts(dm)}\n"
        "        },\n"
        "      },"
    )

def _replace_colors_block_ts(content: str, new_colors_block: str) -> str:
    m = re.search(r'colors\s*:\s*\{', content)
    if not m:
        return content

    start = m.start()
    brace_open = content.find('{', m.end() - 1)
    if brace_open == -1:
        return content

    depth = 1
    i = brace_open + 1
    n = len(content)
    while i < n and depth > 0:
        ch = content[i]
        if ch == '{':
            depth += 1
        elif ch == '}':
            depth -= 1
        i += 1

    if depth != 0:
        return content

    brace_close = i - 1
    end = brace_close + 1
    if end < n and content[end] == ',':
        end += 1

    return content[:start] + new_colors_block + content[end:]

def apply_color_scheme_to_quartz_config(quartz_config_path: Path, scheme_colors: dict):
    if not quartz_config_path.exists():
        print(f"⚠️ quartz.config.ts not found at {quartz_config_path}")
        return

    with open(quartz_config_path, "r", encoding="utf-8") as f:
        content = f.read()

    new_colors_block = format_colors_block(scheme_colors)

    updated = _replace_colors_block_ts(content, new_colors_block)
    if updated == content:
        updated = re.sub(
            r'(theme:\s*\{\s*[\s\S]*?typography:\s*\{[\s\S]*?\},\s*)',
            r'\1\n' + new_colors_block + "\n",
            content,
            count=1
        )

    result = toolchain_paths.write_file(str(quartz_config_path), updated.encode())
    if result.returncode != 0:
        print("⚠️ Error writing colors to quartz.config.ts:", result.stderr.decode())
    else:
        print("✅ Applied selected colour scheme to quartz.config.ts")


BACKLINKS_TS_CANDIDATES = [
    Path("support/Backlinks.tsx"),
    toolchain_paths.SUPPORT_DIR / "Backlinks.tsx",
    Path(__file__).resolve().parent.parent / "support" / "Backlinks.tsx",
    Path(__file__).resolve().parent / "support" / "Backlinks.tsx",
]

def install_patched_backlinks(output_dir: Path):
    """
    Copy a patched Backlinks.tsx into the build, but avoid touching the
    filesystem if it's already identical (reduces churn).
    """
    target = output_dir / "quartz" / "components" / "Backlinks.tsx"
    src = None
    for p in BACKLINKS_TS_CANDIDATES:
        if p.exists():
            src = p
            break

    if src is None:
        print("ℹ️ Patched Backlinks.tsx not found — leaving Quartz default.")
        return

    try:
        target.parent.mkdir(parents=True, exist_ok=True)

        # Only copy if different or missing
        try:
            src_bytes = Path(src).read_bytes()
        except Exception:
            src_bytes = b""
        try:
            dst_bytes = Path(target).read_bytes() if target.exists() else b""
        except Exception:
            dst_bytes = b""

        if target.exists() and src_bytes == dst_bytes:
            try:
                rel = target.relative_to(output_dir)
            except Exception:
                rel = target
            print(f"✔️  Backlinks.tsx already up to date → {rel}")
            return

        shutil.copy2(src, target)
        try:
            rel = target.relative_to(output_dir)
        except Exception:
            rel = target
        print(f"✅ Installed patched Backlinks.tsx → {rel}")
    except Exception as e:
        print(f"❌ Failed to install patched Backlinks.tsx: {e}")


LOCALES_SRC_CANDIDATES = [
    Path("support/locales"),
    toolchain_paths.SUPPORT_DIR / "locales",
    Path(__file__).resolve().parent.parent / "support" / "locales",
    Path(__file__).resolve().parent / "support" / "locales",
]

FAVICON_SRC_CANDIDATES = [
    Path("support/favicon"),
    # Not a hard-coded /opt: Windows now runs these scripts NATIVELY, with no
    # container at all, and points this at the app's bundled runtime through
    # PLANTOIR_SUPPORT_DIR. Inside the container the default is still /opt/support.
    toolchain_paths.SUPPORT_DIR / "favicon",
    Path(__file__).resolve().parent.parent / "support" / "favicon",
    Path(__file__).resolve().parent / "support" / "favicon",
]

# What goes into quartz/static, and what Head.tsx links from every page.
# Overwriting Quartz's own icon.png is deliberate even though nothing links it
# any more: leaving it behind would ship somebody else's logo inside a
# teacher's site, findable by anything that goes looking.
FAVICON_FILES = ["favicon.ico", "icon.svg", "apple-touch-icon.png", "icon.png"]


def _find_favicon_source() -> Path | None:
    for candidate in FAVICON_SRC_CANDIDATES:
        if candidate.is_dir() and (candidate / "favicon.ico").is_file():
            return candidate
    return None


def install_favicon(output_dir: Path, content_root: Path | None = None):
    """
    Give the built site Plantoir's icon instead of Quartz's.

    Quartz ships `quartz/static/icon.png` — its own logo — and its Head links
    that as the favicon, so every site a teacher published wore the Quartz mark
    in the browser tab. The replacement set is drawn from the app icon by
    scripts/brand_images.py and baked into the image at /opt/support/favicon.

    Two destinations, and the second one is not redundant:

      * `quartz/static/` is what the Static emitter copies to `public/static/`,
        and what the <link> tags in Head.tsx point at. That covers every
        browser that reads the page.
      * `content/favicon.ico` is how the site gets a favicon at its ROOT.
        Quartz's Assets emitter copies non-Markdown files out of content/
        into public/ unchanged, and it is the only route there — the Static
        emitter can write nothing above public/static/. The root copy is what
        answers the implicit GET /favicon.ico that feed readers, link
        unfurlers and older browsers make without reading the page at all.

    Runs on every build rather than only on a full rebuild, so a course folder
    built before this existed picks the icon up next time it is previewed.
    """
    src = _find_favicon_source()
    if src is None:
        print("ℹ️ Favicon set not found — leaving Quartz's own icon in place.")
        return

    static_dir = output_dir / "quartz" / "static"
    copied = 0
    try:
        static_dir.mkdir(parents=True, exist_ok=True)
        for name in FAVICON_FILES:
            source_file = src / name
            if not source_file.is_file():
                continue
            shutil.copy2(source_file, static_dir / name)
            copied += 1
    except Exception as e:
        print(f"⚠️ Could not install the site icon: {e}")
        return

    if content_root is not None:
        try:
            shutil.copy2(src / "favicon.ico", content_root / "favicon.ico")
        except Exception as e:
            print(f"⚠️ Could not place favicon.ico at the site root: {e}")

    print(f"🌱 Installed the Plantoir site icon ({copied} file(s) → quartz/static).")


def install_locales(output_dir: Path):
    target = output_dir / "quartz" / "i18n" / "locales"
    src = None
    for p in LOCALES_SRC_CANDIDATES:
        if p.exists() and p.is_dir():
            src = p
            break
    if src is None:
        print("ℹ️ Locales folder not found — leaving Quartz default locales.")
        return
    try:
        target.parent.mkdir(parents=True, exist_ok=True)
        shutil.copytree(src, target, dirs_exist_ok=True)
        try:
            rel = target.relative_to(output_dir)
        except Exception:
            rel = target
        print(f"✅ Installed custom locales → {rel}")
    except Exception as e:
        print(f"❌ Failed to install custom locales: {e}")


# --- NEW: helper to generate timestamp string in desired format --------------
def _current_created_timestamp() -> str:
    """
    Returns current timestamp like: 2025-08-10T12:30:24.000-0400
    Uses America/Toronto when available, otherwise system local time.
    """
    ts = None
    try:
        # Prefer explicit TZ when tzdata is available
        from zoneinfo import ZoneInfo  # Python 3.11+
        ts = datetime.now(ZoneInfo("America/Toronto"))
    except Exception:
        ts = datetime.now().astimezone()
    # Build string with fixed millisecond precision ".000" (as requested)
    return ts.strftime("%Y-%m-%dT%H:%M:%S") + ".000" + ts.strftime("%z")
# ---------------------------------------------------------------------------


# === Non-class pages 'created' synchronization helpers ====================
def _is_in_curriculum_folder(path: Path) -> bool:
    """
    True if any directory segment in the file's path contains 'curriculum' (case-insensitive).
    We check parent folders only; filenames themselves do not trigger this.
    """
    parts = list(path.parts)
    if parts:
        parts = parts[:-1]
    for seg in parts:
        if "curriculum" in seg.lower():
            return True
    return False

def _fix_tz_colon(s: str) -> str:
    # Turn trailing +HHMM/-HHMM into +HH:MM/-HH:MM for fromisoformat
    return re.sub(r'([+-]\d{2})(\d{2})$', r'\1:\2', s)

def _parse_created_value(val) -> datetime | None:
    """
    Parse a frontmatter 'created' value into an aware datetime (best-effort).
    Supports:
      - 2025-08-10
      - 2025-08-10T12:34
      - 2025-08-10T12:34:56
      - 2025-08-10 12:34:56
      - 2025-08-10T12:34:56.000-0400 (no colon offset)
      - 2025-08-10T12:34:56.000-04:00
      - 2025-08-10T12:34:56Z
    Naive datetimes are assumed in America/Toronto.
    """
    if isinstance(val, datetime):
        dt = val
    elif isinstance(val, str):
        s = val.strip()
        if not s:
            return None
        # Handle Zulu
        if s.endswith("Z") or s.endswith("z"):
            s = s[:-1] + "+00:00"
        # Fix timezone offset without colon
        s = _fix_tz_colon(s)
        # Try fromisoformat
        try:
            dt = datetime.fromisoformat(s)
        except Exception:
            # Try a few common patterns
            fmts = [
                "%Y-%m-%d",
                "%Y-%m-%d %H:%M",
                "%Y-%m-%d %H:%M:%S",
                "%Y-%m-%dT%H:%M",
                "%Y-%m-%dT%H:%M:%S",
                "%Y-%m-%dT%H:%M:%S.%f",
            ]
            dt = None
            for fmt in fmts:
                try:
                    dt = datetime.strptime(s, fmt)
                    break
                except Exception:
                    continue
            if dt is None:
                return None
    else:
        return None

    # Ensure timezone-aware
    try:
        from zoneinfo import ZoneInfo
        if dt.tzinfo is None:
            dt = dt.replace(tzinfo=ZoneInfo("America/Toronto"))
    except Exception:
        if dt.tzinfo is None:
            dt = dt.astimezone()
    return dt

def _format_created_timestamp_from_dt(dt: datetime) -> str:
    """
    Format a datetime using the same canonical style as _current_created_timestamp(),
    always emitting no-colon offset and fixed '.000' milliseconds, in America/Toronto.
    """
    try:
        from zoneinfo import ZoneInfo
        dt = dt.astimezone(ZoneInfo("America/Toronto"))
    except Exception:
        if dt.tzinfo is None:
            dt = dt.astimezone()
    return dt.strftime("%Y-%m-%dT%H:%M:%S") + ".000" + dt.strftime("%z")

# ---------------------------------------------------------------------------
# What THIS build's course calls a unit
# ---------------------------------------------------------------------------
#
# The rule itself — the default, the regexes, and the rewrite used when a new
# course is poured — lives in `class_pages.py`, because `setup_course.py` needs
# it too and long before any build. What lives here is this build's ANSWER.
#
# Held at module level rather than threaded through six functions because this
# script builds exactly one section of one course per process, so there is only
# ever one answer. `set_unit_word` is called once, from `build_section_site`,
# as soon as the configuration has been read.

DEFAULT_UNIT_WORD = class_pages.DEFAULT_UNIT_WORD

_unit_word = DEFAULT_UNIT_WORD


def set_unit_word(word) -> str:
    """Records what this build's course calls a unit, and returns it."""
    global _unit_word
    _unit_word = class_pages._cleaned(word)
    return _unit_word


def unit_word() -> str:
    """What this build's course calls a unit."""
    return _unit_word


def unit_word_from_config(config: dict) -> str:
    """The course's word, defaulting the way an absent key must."""
    return class_pages.word_from_config(config)


def class_page_pattern(word: str | None = None) -> str:
    """This build's class-page pattern, or one for a word given outright."""
    return class_pages.class_page_pattern(word if word is not None else _unit_word)


def first_class_pattern(word: str | None = None) -> str:
    """This build's first-class-of-the-year pattern."""
    return class_pages.first_class_pattern(word if word is not None else _unit_word)


def _is_class_page(path: Path, title: str | None = None, word: str | None = None) -> bool:
    """
    True if the file represents a class page (e.g., 'Unit 1, Day 1.md' or titled 'Unit 1, Day 1').
    Folder index files ('index.md'), Key Links, Curriculum Coverage, and other non-class files are never class pages.

    `word` defaults to whatever this build's course calls it — see
    `set_unit_word`. A course that says "Module" names its pages
    "Module 2, Day 3", and a check still looking for "Unit" would decide the
    course teaches nothing at all: the coverage map would fall back to counting
    every published page, which is a wrong map that reports success.
    """
    if path.name.lower() in ("index.md", "key links.md", "curriculum coverage.md"):
        return False
    pattern = class_page_pattern(word)
    stem = path.stem.strip()
    if re.match(pattern, stem, re.IGNORECASE):
        return True
    if title:
        trimmed_title = title.strip()
        if re.match(pattern, trimmed_title, re.IGNORECASE):
            return True
    return False

def _find_first_class_created(content_root: Path) -> datetime | None:
    """
    Find the frontmatter 'created' datetime of the first class of the year (Unit 1, Day 1).
    If Unit 1, Day 1 is not found or has no valid created date, falls back to the earliest
    dated class page, or the earliest dated markdown page in content_root.
    """
    first_class_unit1_day1_dt = None
    earliest_class_dt = None
    earliest_any_dt = None

    for root, dirs, files in os.walk(content_root):
        for name in files:
            if not name.lower().endswith(".md"):
                continue
            fp = Path(root) / name
            try:
                post = frontmatter.load(fp)
            except Exception:
                continue

            raw = post.get("created")
            dt = _parse_created_value(raw)
            if dt is None:
                continue

            if (earliest_any_dt is None) or (dt < earliest_any_dt):
                earliest_any_dt = dt

            title = str(post.get("title") or "")
            is_class = _is_class_page(fp, title)
            if is_class:
                if (earliest_class_dt is None) or (dt < earliest_class_dt):
                    earliest_class_dt = dt

                stem = fp.stem.strip()
                first_class = first_class_pattern()
                if re.match(first_class, stem, re.IGNORECASE) or \
                   re.match(first_class, title.strip(), re.IGNORECASE):
                    first_class_unit1_day1_dt = dt

    if first_class_unit1_day1_dt is not None:
        return first_class_unit1_day1_dt
    if earliest_class_dt is not None:
        return earliest_class_dt
    return earliest_any_dt

def _extract_wikilink_targets(text: str) -> set[str]:
    """Extract all normalized wikilink target names from markdown text, excluding code fences and index/meta links."""
    outside_fences = re.sub(r"```[\s\S]*?```", "", text)
    outside_fences = re.sub(r"`[^`\n]*`", "", outside_fences)
    link_pattern = re.compile(r"!?\[\[([^\]|#]+?)(?:\\?\|[^\]]*)?(?:#[^\]|]*)?\]\]")
    targets = set()
    for match in link_pattern.finditer(outside_fences):
        target = match.group(1).strip().rstrip("\\")
        if not target:
            continue
        stem = target.split("/")[-1].strip()
        if stem.lower().endswith(".md"):
            stem = stem[:-3].strip()
        stem_lower = stem.lower()
        if stem_lower in ("index", "key links", "curriculum coverage"):
            continue
        if stem:
            targets.add(stem_lower)
        norm_path = target.lower()
        if norm_path.endswith(".md"):
            norm_path = norm_path[:-3].strip()
        if norm_path:
            targets.add(norm_path)
    return targets

def _find_class_reachable_pages(content_root: Path) -> set[Path]:
    """
    Find all pages in content_root that are reachable (directly or transitively)
    from any Unit x, Day y class page via wikilinks.
    """
    pages_by_stem: dict[str, list[Path]] = {}
    pages_by_rel: dict[str, Path] = {}
    all_pages: dict[Path, frontmatter.Post] = {}

    for root, dirs, files in os.walk(content_root):
        for name in files:
            if not name.lower().endswith(".md"):
                continue
            fp = Path(root) / name
            try:
                post = frontmatter.load(fp)
                all_pages[fp] = post
            except Exception:
                continue

            stem_lower = fp.stem.lower()
            if name.lower() not in ("index.md", "key links.md", "curriculum coverage.md"):
                pages_by_stem.setdefault(stem_lower, []).append(fp)
            try:
                rel = fp.relative_to(content_root).as_posix().lower()
                if rel.endswith(".md"):
                    rel = rel[:-3]
                pages_by_rel[rel] = fp
            except Exception:
                pass

    class_page_paths: list[Path] = []
    for fp, post in all_pages.items():
        title = str(post.get("title") or "")
        if _is_class_page(fp, title):
            class_page_paths.append(fp)

    visited: set[Path] = set(class_page_paths)
    queue: list[Path] = list(class_page_paths)

    while queue:
        current_fp = queue.pop(0)
        post = all_pages.get(current_fp)
        if post is None:
            continue

        targets = _extract_wikilink_targets(post.content)
        for target in targets:
            matched_paths = []
            if target in pages_by_rel:
                matched_paths.append(pages_by_rel[target])
            if target in pages_by_stem:
                matched_paths.extend(pages_by_stem[target])

            for target_fp in matched_paths:
                if target_fp.name.lower() in ("index.md", "key links.md", "curriculum coverage.md") or _is_class_page(target_fp):
                    continue
                if target_fp not in visited:
                    visited.add(target_fp)
                    queue.append(target_fp)

    return visited

def _sync_non_class_pages_created(content_root: Path, first_class_dt: datetime) -> tuple[int, int]:
    """
    For all non-class pages (pages not linked from a Unit x, Day y page and not themselves
    a Unit x, Day y page), update their frontmatter 'created' timestamp to first_class_dt.
    Returns (updated_count, total_non_class_count).
    """
    if first_class_dt is None:
        return (0, 0)

    reachable_from_classes = _find_class_reachable_pages(content_root)
    stamp = _format_created_timestamp_from_dt(first_class_dt)
    updated = 0
    total_non_class = 0

    for root, dirs, files in os.walk(content_root):
        for name in files:
            if not name.lower().endswith(".md"):
                continue
            fp = Path(root) / name
            try:
                post = frontmatter.load(fp)
            except Exception:
                continue

            # The root section landing page (content/index.md) carries the date of
            # the section's newest published class; it is never reset to the first day.
            if fp == content_root / "index.md":
                continue
            title = str(post.get("title") or "")
            if _is_class_page(fp, title):
                continue
            if fp in reachable_from_classes:
                continue

            total_non_class += 1
            curr_created = post.get("created")
            curr_dt = _parse_created_value(curr_created)
            if curr_dt is None or _format_created_timestamp_from_dt(curr_dt) != stamp:
                post["created"] = stamp
                try:
                    with open(fp, "w", encoding="utf-8") as f:
                        f.write(frontmatter.dumps(post))
                    updated += 1
                except Exception:
                    pass

    return (updated, total_non_class)
# ===========================================================================


# Track curriculum folders we've already logged this build (legacy; no longer used directly)
_logged_curriculum_folders = set()

# UPDATED: process frontmatter for publish/created fields (no unconditional curriculum bump)
def use_publish_filter(quartz_config_path: Path):
    """
    Point Quartz at the `publish:` filter instead of the stock draft one.

    Quartz's own RemoveDrafts reads `draft: true`; PublishFlag (patches/publish.ts)
    reads `publish: false` and keeps the same default, so a page with no flag
    stays visible. Patched here rather than in a config file because the
    config comes from Quartz's own repo at image build time.
    """
    try:
        text = quartz_config_path.read_text(encoding="utf-8")
    except Exception as e:
        print(f"⚠️ Could not read quartz.config.ts to set the publish filter: {e}")
        return

    if "Plugin.PublishFlag()" in text:
        print("ℹ️ Quartz already filters on 'publish' (no change).")
        return

    updated = text.replace("Plugin.RemoveDrafts()", "Plugin.PublishFlag()")
    if updated == text:
        print("⚠️ Could not find the draft filter in quartz.config.ts — pages may not be filtered as expected.")
        return

    try:
        quartz_config_path.write_text(updated, encoding="utf-8")
        print("✅ Quartz now decides visibility from 'publish:' rather than 'draft:'.")
    except Exception as e:
        print(f"⚠️ Could not set the publish filter: {e}")


def _as_bool(value) -> bool:
    """YAML quoting varies, so a quoted "true" counts as true."""
    if isinstance(value, bool):
        return value
    return str(value).strip().lower() == "true"


def _get_excluded_note_config() -> tuple[str, str, str]:
    """Return (sentinel_start, sentinel_end, note_body) from shared-rules contract."""
    try:
        cfg = contracts.section("shared-rules", "specialNames", "excludedFolderIndexNote")
        start = cfg.get("sentinelStart", "<!-- plantoir:excluded-folder-note:start -->")
        end = cfg.get("sentinelEnd", "<!-- plantoir:excluded-folder-note:end -->")
        body = cfg.get("noteBody", "")
        return start, end, body
    except Exception:
        start = "<!-- plantoir:excluded-folder-note:start -->"
        end = "<!-- plantoir:excluded-folder-note:end -->"
        body = "> [!NOTE]\n> This folder was removed in Course Settings and is excluded from your website. Its pages will not appear in previews or on your published site. To include it again, add it back in Course Settings."
        return start, end, body


def _apply_sentinel_note(file_path: Path, start: str, end: str, body: str):
    """
    Write or update the sentinel-delimited note in an existing index.md in the vault.
    Idempotent: preserves mtime if the note is already up to date.
    Never creates a file.
    """
    if not file_path.exists():
        return
    try:
        text = file_path.read_text(encoding="utf-8")
    except Exception as e:
        print(f"⚠️ Could not read {file_path} to apply exclusion note: {e}")
        return

    block = f"{start}\n{body}\n{end}"

    if start in text and end in text:
        pattern = re.compile(re.escape(start) + r".*?" + re.escape(end), re.DOTALL)
        new_text = pattern.sub(block, text)
        if new_text == text:
            return
    else:
        fm_match = re.match(r"^---\s*\n.*?\n---\s*\n?", text, re.DOTALL)
        if fm_match:
            fm_end = fm_match.end()
            rest = text[fm_end:]
            new_text = text[:fm_end] + block + "\n\n" + rest.lstrip("\n")
        else:
            new_text = block + "\n\n" + text

    try:
        file_path.write_text(new_text, encoding="utf-8")
        print(f"📝 Added exclusion note to {file_path}")
    except Exception as e:
        print(f"⚠️ Could not write exclusion note to {file_path}: {e}")


def _remove_sentinel_note(file_path: Path, start: str, end: str):
    """
    Remove sentinel note from an index.md in the vault when re-included.
    Idempotent: does nothing if note is absent.
    """
    if not file_path.exists():
        return
    try:
        text = file_path.read_text(encoding="utf-8")
    except Exception as e:
        print(f"⚠️ Could not read {file_path} to remove exclusion note: {e}")
        return

    if start not in text or end not in text:
        return

    pattern = re.compile(re.escape(start) + r".*?" + re.escape(end) + r"\s*\n?", re.DOTALL)
    new_text = pattern.sub("", text)
    if new_text != text:
        try:
            file_path.write_text(new_text, encoding="utf-8")
            print(f"📝 Removed exclusion note from {file_path}")
        except Exception as e:
            print(f"⚠️ Could not update {file_path} after removing exclusion note: {e}")


def _strip_sentinels(text: str, start: str, end: str) -> str:
    """Strip sentinel blocks from content before building / deploying."""
    if start not in text or end not in text:
        return text
    pattern = re.compile(re.escape(start) + r".*?" + re.escape(end) + r"\s*\n?", re.DOTALL)
    return pattern.sub("", text)


def process_frontmatter(file_path: Path, section_number: int):
    if file_path.suffix.lower() != ".md":
        return
    try:
        post = frontmatter.load(file_path)
    except Exception as e:
        print(f"⚠️ Could not read frontmatter from {file_path}: {e}")
        return

    # Whether students see a page is `publish:`, and per-section it is
    # `publishForSection<N>:`. A teacher says a page is or is not published;
    # they never say it is or is not a draft, and "draft" reads as
    # "unfinished" rather than "not visible", which is a different thing.
    publish_key = f"publishForSection{section_number}"
    created_key = f"createdSection{section_number}"

    if publish_key in post:
        post["publish"] = post[publish_key]
    if created_key in post:
        post["created"] = post[created_key]

    # Courses written before the change still carry the old keys. Read them,
    # inverted, but never let them override an explicit publish flag — a page
    # carrying both has already been migrated and the old key is a leftover.
    legacy_key = f"draftSection{section_number}"
    if "publish" not in post:
        if legacy_key in post:
            post["publish"] = not _as_bool(post[legacy_key])
        elif "draft" in post:
            post["publish"] = not _as_bool(post["draft"])

    for key in list(post.keys()):
        if (re.match(r"publishForSection\d+", key) or re.match(r"draftSection\d+", key)
                or re.match(r"createdSection\d+", key) or key == "draft"):
            del post[key]

    # Strip any sentinel notes that may be present in copied files
    start_sentinel, end_sentinel, _ = _get_excluded_note_config()
    if post.content and start_sentinel in post.content and end_sentinel in post.content:
        post.content = _strip_sentinels(post.content, start_sentinel, end_sentinel)

    # NOTE: Removed unconditional Curriculum timestamp bump here.
    # The new logic runs after all files are copied, syncing curriculum files
    # to the section's latest 'created' value only when newer.

    try:
        with open(file_path, "w", encoding="utf-8") as f:
            f.write(frontmatter.dumps(post))
    except Exception as e:
        print(f"⚠️ Could not write updated frontmatter to {file_path}: {e}")

# --- ADD: NEW HELPER — Rewrite wikilinks with section path to alias-only -----
def rewrite_section_wikilinks(md_path: Path):
    """
    Rewrites Obsidian wikilinks that include a section path to alias-only form.
    Examples:
      [[section2/All Classes/Thread 2, Day 8|Thread 2, Day 8]] -> [[Thread 2, Day 8]]
      ![[section1/Bananas/Benefits of Banana Consumption|Benefits of Banana Consumption]] -> ![[Benefits of Banana Consumption]]
    Only rewrites when:
      - a '|' alias exists, and
      - the target contains 'section<digits>/' somewhere in its path.
    """
    if md_path.suffix.lower() != ".md" or not md_path.exists():
        return
    try:
        text = md_path.read_text(encoding="utf-8")
    except Exception as e:
        print(f"⚠️ Could not read {md_path} to rewrite wikilinks: {e}")
        return

    pattern = re.compile(r'(!?)\[\[([^\[\]]+?)\]\]')
    count = 0

    def _repl(m: re.Match) -> str:
        nonlocal count
        bang = m.group(1)  # '!' or ''
        inner = m.group(2) # e.g., 'section2/All Classes/Thread 2, Day 8|Thread 2, Day 8'
        if '|' not in inner:
            return m.group(0)
        target, alias = inner.split('|', 1)
        # Rewrite only if a section path is present
        if re.search(r'(?:^|/)section\d+/', target):
            count += 1
            return f"{bang}[[{alias.strip()}]]"
        return m.group(0)

    new_text = pattern.sub(_repl, text)
    if count > 0 and new_text != text:
        try:
            md_path.write_text(new_text, encoding="utf-8")
            print(f"🔗 Rewrote {count} section-path wikilink(s) in: {md_path}")
        except Exception as e:
            print(f"⚠️ Could not write rewritten wikilinks to {md_path}: {e}")
# --- END ADD -----------------------------------------------------------------

# --- ADD: Remove Graph from the right column in quartz.layout.ts (prints once) ---
_GRAPH_REMOVAL_LOGGED = False

def remove_graph_from_right(layout_path: Path):
    """Remove Component.Graph(...) from the 'right' layout array in quartz.layout.ts."""
    global _GRAPH_REMOVAL_LOGGED

    if not layout_path.exists():
        return

    try:
        with open(layout_path, "r", encoding="utf-8") as f:
            content = f.read()

        # Target only the right: [ ... ] block and remove any Component.Graph(...) entry inside it
        def _strip_graph_block(match: re.Match) -> str:
            before, inside, after = match.group(1), match.group(2), match.group(3)
            # Remove lines containing Component.Graph(...) with optional config and trailing comma/newlines
            cleaned = re.sub(
                r'^\s*Component\.Graph\(\s*(?:\{[\s\S]*?\}\s*)?\)\s*,?\s*\n?',
                '',
                inside,
                flags=re.MULTILINE
            )
            # Tidy extraneous blank lines
            cleaned = re.sub(r'\n{3,}', '\n\n', cleaned)
            return before + cleaned + after

        new_content = re.sub(
            r'(right:\s*\[\s*)(.*?)(\s*\],)',
            _strip_graph_block,
            content,
            flags=re.DOTALL
        )

        if new_content != content:
            # Use tee to avoid silent write failures in this environment
            toolchain_paths.write_file(str(layout_path), new_content.encode("utf-8"))
            if not _GRAPH_REMOVAL_LOGGED:
                print(f"🗑️  Removed Graph component from {layout_path}")
                _GRAPH_REMOVAL_LOGGED = True
    except Exception as e:
        print(f"⚠️ Could not modify {layout_path} to remove Graph: {e}")
# --- END ADD ---

# --- ADD: Patch folder page title and defaults on first build/full rebuild ---
def patch_folder_page_title(folder_page_path: Path):
    """Set folder page frontmatter title to `${folder}`."""
    if not folder_page_path.exists():
        print(f"⚠️ folderPage.tsx not found at {folder_page_path}")
        return
    try:
        with open(folder_page_path, "r", encoding="utf-8") as f:
            content = f.read()

        # Replace: title: `${i18n(locale).pages.folderContent.folder}: ${folder}`,
        pattern = re.compile(
            r'(frontmatter:\s*\{\s*[^}]*?title:\s*)`?\$\{i18n\(locale\)\.pages\.folderContent\.folder\}\s*:\s*\$\{folder\}`?(\s*,)',
            flags=re.DOTALL
        )
        new_content = pattern.sub(r'\1`${folder}`\2', content)

        if new_content != content:
            result = toolchain_paths.write_file(str(folder_page_path), new_content.encode("utf-8"))
            if result.returncode != 0:
                print("❌ Failed to patch folderPage.tsx:", result.stderr.decode())
            else:
                print("✅ Patched folderPage.tsx to use folder name as title")
        else:
            print("ℹ️ folderPage.tsx already uses folder name as title (no change).")
    except Exception as e:
        print(f"⚠️ Error patching folderPage.tsx: {e}")

def patch_folder_content_defaults(folder_content_path: Path):
    """Set FolderContent defaultOptions.showFolderCount to false."""
    if not folder_content_path.exists():
        print(f"⚠️ FolderContent.tsx not found at {folder_content_path}")
        return
    try:
        with open(folder_content_path, "r", encoding="utf-8") as f:
            content = f.read()

        # Only change inside the defaultOptions object
        pattern = re.compile(
            r'(const\s+defaultOptions\s*:\s*FolderContentOptions\s*=\s*\{\s*[^}]*?showFolderCount:\s*)true',
            flags=re.DOTALL
        )
        new_content = pattern.sub(r'\1false', content)

        if new_content != content:
            result = toolchain_paths.write_file(str(folder_content_path), new_content.encode("utf-8"))
            if result.returncode != 0:
                print("❌ Failed to patch FolderContent.tsx:", result.stderr.decode())
            else:
                print("✅ Set FolderContent default showFolderCount to false")
        else:
            print("ℹ️ FolderContent defaultOptions already set as desired (no change).")
    except Exception as e:
        print(f"⚠️ Error patching FolderContent.tsx: {e}")
# --- END ADD ---

# --- ADD: Patch ContentMeta defaultOptions based on course_config.show_reading_time ---
def patch_content_meta_options(date_tsx_file_path: Path, show_reading_time: bool):
    """
    Ensure ContentMeta defaultOptions reflects teacher preference:
      showReadingTime := show_reading_time
      showComma       := show_reading_time
    Runs EVERY build so a changed preference takes effect without a full rebuild.
    """
    if not date_tsx_file_path.exists():
        print(f"⚠️ ContentMeta.tsx not found at {date_tsx_file_path}")
        return
    try:
        with open(date_tsx_file_path, "r", encoding="utf-8") as f:
            content = f.read()

        # Capture the defaultOptions block and rewrite only showReadingTime/showComma within it
        def repl(match: re.Match) -> str:
            head, body, tail = match.group(1), match.group(2), match.group(3)
            desired = "true" if show_reading_time else "false"
            body2 = re.sub(r'(showReadingTime\s*:\s*)(true|false)', r'\1' + desired, body)
            body3 = re.sub(r'(showComma\s*:\s*)(true|false)', r'\1' + desired, body2)
            return head + body3 + tail

        new_content = re.sub(
            r'(const\s+defaultOptions\s*:\s*ContentMetaOptions\s*=\s*\{)([\s\S]*?)(\})',
            repl,
            content,
            count=1
        )

        if new_content != content:
            result = toolchain_paths.write_file(str(date_tsx_file_path), new_content.encode("utf-8"))
            if result.returncode != 0:
                print("❌ Failed to patch ContentMeta.tsx to adjust reading time estimates:", result.stderr.decode())
            else:
                label = "show" if show_reading_time else "hide"
                print(f"✅ Patched ContentMeta defaultOptions to {label} reading-time")
        else:
            print("ℹ️ ContentMeta defaultOptions already match desired settings for showing reading time (no change).")
    except Exception as e:
        print(f"⚠️ Error patching ContentMeta.tsx: {e}")
# --- END ADD ---

# --- ADD: Patch renderPage.tsx to allow transcludeTitleSize frontmatter ---
def patch_katex_mhchem(latex_ts_path: Path):
    """
    Turn on mhchem, the chemistry notation for KaTeX.

    Quartz renders maths at build time with rehype-katex, and KaTeX ships
    mhchem in the same package — it is simply not loaded. Without it
    `\\ce{...}` fails SILENTLY: no error, no red text, just garbage on the
    page that a proofreader skims past. With it, one import, chemistry
    gets the notation it deserves:

        $\\ce{CaCO3(s) <=> CaO(s) + CO2(g)}$

    renders with a real equilibrium arrow and upright element symbols,
    which is tedious and error-prone to hand-build out of \\text{} and
    \\rightleftharpoons.

    The import is a side effect on the shared KaTeX instance, and it runs
    in Node during the build — nothing extra is sent to a browser.
    Idempotent.
    """
    if not latex_ts_path.exists():
        print(f"⚠️ latex.ts not found at {latex_ts_path}")
        return
    try:
        with open(latex_ts_path, "r", encoding="utf-8") as f:
            content = f.read()

        if "katex/contrib/mhchem" in content:
            print("ℹ️ mhchem already enabled (no change).")
            return

        anchor = 'import rehypeKatex from "rehype-katex"'
        if anchor not in content:
            print("⚠️ Could not find the rehype-katex import; mhchem left off.")
            return

        content = content.replace(
            anchor,
            anchor + '\n// Chemistry notation for KaTeX. It ships inside the katex\n'
                     '// package and only needs loading; without it \\ce{} fails silently.\n'
                     'import "katex/contrib/mhchem"',
            1,
        )
        with open(latex_ts_path, "w", encoding="utf-8") as f:
            f.write(content)
        print("✅ Patched latex.ts to enable mhchem chemistry notation")
    except Exception as e:
        print(f"⚠️ Error enabling mhchem: {e}")


def patch_google_font_href(theme_ts_path: Path, head_tsx_path: Path):
    """
    Stop asking Google Fonts for fonts that are not Google Fonts.

    Quartz builds one stylesheet request from all three typography
    choices. Plantoir offers system stacks such as "Helvetica, Arial"
    alongside real Google families, and Google rejects the WHOLE request
    with HTTP 400 if any family is unknown to it. The observed effect:

        GET .../css2?family=Helvetica,%20Arial:...&family=IBM%20Plex%20Mono:...
        400

    So NO font downloads — including the code font mermaid measures its
    diagram labels in. That is why a diagram came out mangled until a
    reload, and why `static/fonts/` was empty: the emitter fetches the
    same URL to self-host the fonts and got the same 400.

    A system stack needs no download; it is already on the machine. This
    filters those families out of the request and, if nothing is left to
    ask for, drops the request entirely.
    """
    if not theme_ts_path.exists():
        print(f"⚠️ theme.ts not found at {theme_ts_path}")
        return
    try:
        with open(theme_ts_path, "r", encoding="utf-8") as f:
            content = f.read()

        marker = "isDownloadableFont"
        if marker in content:
            print("ℹ️ Google Fonts request already filtered (no change).")
            return

        old = (
            "export function googleFontHref(theme: Theme) {\n"
            "  const { code, header, body } = theme.typography\n"
            "  const headerFont = formatFontSpecification(\"header\", header)\n"
            "  const bodyFont = formatFontSpecification(\"body\", body)\n"
            "  const codeFont = formatFontSpecification(\"code\", code)\n"
            "\n"
            "  return `https://fonts.googleapis.com/css2?family=${bodyFont}&family=${headerFont}&family=${codeFont}&display=swap`\n"
            "}"
        )
        if old not in content:
            print("⚠️ googleFontHref not in the expected shape; left unchanged.")
            return

        new = '''// A CSS font stack ("Helvetica, Arial") or a family already on the
// machine is not something Google Fonts can serve, and ONE unknown
// family makes it reject the whole request with 400 — taking the real
// families down with it. Only ask for what it can actually provide.
const SYSTEM_FONT_FAMILIES = new Set([
  "arial",
  "consolas",
  "courier",
  "courier new",
  "georgia",
  "helvetica",
  "helvetica neue",
  "menlo",
  "monaco",
  "monospace",
  "sans-serif",
  "serif",
  "sf mono",
  "system-ui",
  "times",
  "times new roman",
  "ui-monospace",
  "verdana",
  "-apple-system",
])

function isDownloadableFont(spec: FontSpecification): boolean {
  const name = getFontSpecificationName(spec).trim()
  if (name.length === 0) {
    return false
  }
  // A comma means a stack, not a family.
  if (name.includes(",")) {
    return false
  }
  return !SYSTEM_FONT_FAMILIES.has(name.toLowerCase().replace(/^["']|["']$/g, ""))
}

export function googleFontHref(theme: Theme) {
  const { code, header, body } = theme.typography
  const families: string[] = []
  if (isDownloadableFont(body)) {
    families.push(formatFontSpecification("body", body))
  }
  if (isDownloadableFont(header)) {
    families.push(formatFontSpecification("header", header))
  }
  if (isDownloadableFont(code)) {
    families.push(formatFontSpecification("code", code))
  }
  if (families.length === 0) {
    return ""
  }

  return `https://fonts.googleapis.com/css2?${families
    .map((family) => `family=${family}`)
    .join("&")}&display=swap`
}'''
        content = content.replace(old, new, 1)
        with open(theme_ts_path, "w", encoding="utf-8") as f:
            f.write(content)
        print("✅ Patched theme.ts so only real Google families are requested")
    except Exception as e:
        print(f"⚠️ Error patching googleFontHref: {e}")
        return

    # With no families to fetch, the <link> must not be emitted at all.
    if not head_tsx_path.exists():
        return
    try:
        with open(head_tsx_path, "r", encoding="utf-8") as f:
            head = f.read()
        old_link = '            <link rel="stylesheet" href={googleFontHref(cfg.theme)} />'
        new_link = ('            {googleFontHref(cfg.theme) !== "" && (\n'
                    '              <link rel="stylesheet" href={googleFontHref(cfg.theme)} />\n'
                    '            )}')
        if old_link in head:
            head = head.replace(old_link, new_link, 1)
            with open(head_tsx_path, "w", encoding="utf-8") as f:
                f.write(head)
            print("✅ Patched Head.tsx to skip an empty font request")
    except Exception as e:
        print(f"⚠️ Error patching Head.tsx: {e}")


def patch_mermaid_font_wait(mermaid_ts_path: Path):
    """
    Make mermaid wait for the code font before it measures anything.

    Mermaid sizes every box by measuring its label, and Quartz tells it to
    measure in the course's code font (`--codeFont`). That font comes from
    Google Fonts with `display=swap`, which means the browser paints with
    a fallback first and swaps the real font in when it arrives. If the
    swap lands after mermaid has measured, every box was sized for the
    narrower fallback and the real text overflows it — labels come out
    clipped mid-word.

    Waiting for `document.fonts.ready` costs nothing when the font is
    already cached, and removes the race when it is not. Idempotent.
    """
    if not mermaid_ts_path.exists():
        print(f"⚠️ mermaid.inline.ts not found at {mermaid_ts_path}")
        return
    try:
        marker = "document.fonts.load"
        with open(mermaid_ts_path, "r", encoding="utf-8") as f:
            content = f.read()

        if marker in content:
            print("ℹ️ Mermaid already waits for fonts (no change).")
            return

        target = "    await mermaid.run({ nodes })"
        if target not in content:
            print("⚠️ Could not find mermaid.run call to patch; left unchanged.")
            return

        replacement = (
            "    // Mermaid measures label text to size each box, and it is\n"
            "    // told to measure in the code font. That font is served with\n"
            "    // display=swap, so without this wait it can measure the\n"
            "    // narrower fallback and size every box too small for the\n"
            "    // text that finally renders in it.\n"
            "    if (document.fonts) {\n"
            "      // document.fonts.ready only settles the loads already PENDING.\n"
            "      // If nothing on the page has demanded the code font yet, it\n"
            "      // resolves at once and mermaid measures the fallback anyway —\n"
            "      // so ask for the font first, in the weights a diagram uses.\n"
            "      const codeFamily = (computedStyleMap[\"--codeFont\"] || \"\").split(\",\")[0].trim()\n"
            "      if (codeFamily) {\n"
            "        try {\n"
            "          await Promise.all([\n"
            "            document.fonts.load(`400 16px ${codeFamily}`),\n"
            "            document.fonts.load(`700 16px ${codeFamily}`),\n"
            "          ])\n"
            "        } catch (error) {\n"
            "          // A font that will not load is not worth failing over.\n"
            "        }\n"
            "      }\n"
            "      await document.fonts.ready\n"
            "    }\n"
            "\n"
            + target
        )
        content = content.replace(target, replacement, 1)

        with open(mermaid_ts_path, "w", encoding="utf-8") as f:
            f.write(content)
        print("✅ Patched mermaid.inline.ts to wait for fonts before measuring")
    except Exception as e:
        print(f"⚠️ Error patching mermaid font wait: {e}")


def patch_mermaid_pie_colours(mermaid_ts_path: Path):
    """
    Give pie charts a palette in which every slice is visible and legible,
    whichever colour scheme the teacher picked.

    Mermaid's base theme takes a pie chart's first slice colour from
    `primaryColor`, and Quartz sets `primaryColor` to `--light` — the page
    background. That is right for a flowchart node and wrong for a pie
    slice: slice one was drawn in the background colour, so it vanished,
    and its legend swatch with it.

    The palette is SOLVED at render time rather than hardcoded, because
    Plantoir ships 43 colour schemes and each has a light and a dark mode.
    Fixed blend fractions tuned against one scheme failed 74 of those 86
    combinations — some slices came out barely distinguishable from the
    label text. Instead: build a pool of tints of the scheme's own colours,
    keep only those with at least 4.5:1 contrast against the label text and
    1.45:1 against the page, then walk the pool taking the farthest colour
    from everything chosen so far. That anchors on the course's main accent
    and keeps every later slice as distinct as the scheme allows.

    A monochrome scheme can only give tints of one hue, so its slices
    differ by lightness alone — inherent, not a defect.

    Idempotent, and it replaces the earlier fixed-fraction version in a
    scaffold that already carries it.
    """
    if not mermaid_ts_path.exists():
        print(f"⚠️ mermaid.inline.ts not found at {mermaid_ts_path}")
        return
    try:
        with open(mermaid_ts_path, "r", encoding="utf-8") as f:
            content = f.read()

        block_start = "    // Mermaid's base theme takes a pie chart's first slice from"
        block_end = '    pieSliceColours.pieOpacity = "1"'
        version = "pie palette: solved per scheme"

        if version in content:
            print("ℹ️ Mermaid pie palette already set (no change).")
            return

        # An earlier version of this patch is in the file: take it out
        # first, or its consts would be declared twice and the build fails.
        if block_start in content and block_end in content:
            head, rest = content.split(block_start, 1)
            _, tail = rest.split(block_end, 1)
            content = head + tail.lstrip("\n")
            print("ℹ️ Replacing the earlier fixed-fraction pie palette.")

        anchor = '    const darkMode = document.documentElement.getAttribute("saved-theme") === "dark"'
        if anchor not in content:
            print("⚠️ Could not find the mermaid theme setup to patch; left unchanged.")
            return

        palette = anchor + "\n" + '''
    // Mermaid's base theme takes a pie chart's first slice from
    // primaryColor, which Quartz sets to the page background — so slice one
    // was drawn in the background colour and disappeared, legend swatch and
    // all. Build the palette from this scheme's own colours instead.
    // pie palette: solved per scheme, because Plantoir ships 43 schemes and
    // fractions tuned against one of them fail most of the others.
    const toChannels = (value: string): number[] => {
      const text = value.trim()
      if (text.startsWith("#")) {
        const hex =
          text.length === 4
            ? text[1] + text[1] + text[2] + text[2] + text[3] + text[3]
            : text.slice(1, 7)
        return [0, 2, 4].map((i) => parseInt(hex.slice(i, i + 2), 16))
      }
      const parts = text.match(/\\d+(\\.\\d+)?/g) ?? ["0", "0", "0"]
      return [Number(parts[0]), Number(parts[1]), Number(parts[2])]
    }
    const blend = (from: string, to: string, amount: number): string => {
      const a = toChannels(from)
      const b = toChannels(to)
      return (
        "#" +
        [0, 1, 2]
          .map((i) =>
            Math.max(0, Math.min(255, Math.round(a[i] + (b[i] - a[i]) * amount)))
              .toString(16)
              .padStart(2, "0"),
          )
          .join("")
      )
    }
    const relativeLuminance = (colour: string): number => {
      const channels = toChannels(colour).map((value) => {
        const scaled = value / 255
        return scaled <= 0.03928
          ? scaled / 12.92
          : Math.pow((scaled + 0.055) / 1.055, 2.4)
      })
      return 0.2126 * channels[0] + 0.7152 * channels[1] + 0.0722 * channels[2]
    }
    const contrastRatio = (one: string, two: string): number => {
      const a = relativeLuminance(one)
      const b = relativeLuminance(two)
      return (Math.max(a, b) + 0.05) / (Math.min(a, b) + 0.05)
    }
    const separation = (one: string, two: string): number => {
      const a = toChannels(one)
      const b = toChannels(two)
      return Math.sqrt(
        [0, 1, 2].reduce((total, i) => total + (a[i] - b[i]) ** 2, 0),
      )
    }

    const pageColour = computedStyleMap["--light"]
    const labelColour = computedStyleMap["--dark"]
    // Readable against the label text, and clearly not the page itself.
    const readable = (colour: string) =>
      contrastRatio(colour, labelColour) >= 4.5 &&
      contrastRatio(colour, pageColour) >= 1.45

    const sliceSources = [
      computedStyleMap["--secondary"],
      computedStyleMap["--tertiary"],
      computedStyleMap["--darkgray"],
      computedStyleMap["--gray"],
      labelColour,
    ]
    const slicePool: string[] = []
    for (const source of sliceSources) {
      for (let step = 0; step <= 40; step++) {
        const candidate = blend(source, pageColour, step / 40)
        if (readable(candidate) && !slicePool.includes(candidate)) {
          slicePool.push(candidate)
        }
      }
    }

    // Start on the strongest readable tint of the course's main accent, so
    // the chart still looks like this course, then keep taking the colour
    // farthest from everything already chosen.
    let anchorColour = slicePool[0]
    for (let step = 0; step <= 40; step++) {
      const candidate = blend(computedStyleMap["--secondary"], pageColour, step / 40)
      if (readable(candidate)) {
        anchorColour = candidate
        break
      }
    }
    const sliceColours: string[] = anchorColour ? [anchorColour] : []
    while (sliceColours.length < 12 && slicePool.length > 0) {
      let best = slicePool[0]
      let bestGap = -1
      for (const candidate of slicePool) {
        const gap = Math.min(...sliceColours.map((c) => separation(candidate, c)))
        if (gap > bestGap) {
          bestGap = gap
          best = candidate
        }
      }
      if (bestGap <= 0) {
        break
      }
      sliceColours.push(best)
    }

    const pieSliceColours: Record<string, string> = {}
    sliceColours.forEach((colour, index) => {
      pieSliceColours["pie" + (index + 1)] = colour
    })
    pieSliceColours.pieSectionTextColor = labelColour
    pieSliceColours.pieLegendTextColor = labelColour
    pieSliceColours.pieStrokeColor = pageColour
    pieSliceColours.pieOuterStrokeColor = computedStyleMap["--darkgray"]
    // Mermaid softens its own garish defaults by drawing slices at 0.7
    // opacity, blending them 30% into the page. These are already the
    // scheme's own colours, and the dilution broke the contrast the
    // palette was solved for.
    pieSliceColours.pieOpacity = "1"
'''
        content = content.replace(anchor, palette, 1)

        theme_anchor = '        edgeLabelBackground: computedStyleMap["--highlight"],'
        if theme_anchor not in content:
            print("⚠️ Could not find themeVariables to extend; left unchanged.")
            return
        if "...pieSliceColours," not in content:
            content = content.replace(
                theme_anchor, theme_anchor + "\n        ...pieSliceColours,", 1
            )

        with open(mermaid_ts_path, "w", encoding="utf-8") as f:
            f.write(content)
        print("✅ Patched mermaid.inline.ts with a per-scheme pie chart palette")
    except Exception as e:
        print(f"⚠️ Error patching mermaid pie palette: {e}")


def patch_mermaid_pie_title_fit(mermaid_ts_path: Path):
    """
    Stop mermaid clipping the title off a pie chart.

    Mermaid sizes a pie chart's viewBox from the pie and its legend, then
    centres the title on the PIE — which the legend has pushed leftward.
    A title wider than the pie therefore spills past the left edge of the
    viewBox and is silently cut off, while empty space sits on the right.
    It is mermaid's own bug: both WebKit and Chromium show it.

    Nothing in CSS can fix it, because the viewBox is an attribute. So
    after mermaid has drawn, re-fit each pie chart's viewBox to what was
    actually drawn (`getBBox()` covers the title even when it lies outside
    the viewBox). Long titles then widen the chart instead of losing their
    first few words, and short ones lose the wasted margin.

    Only pie charts are touched — they are the ones mermaid mis-measures,
    and re-fitting every diagram would change layouts that are correct.
    Idempotent.
    """
    if not mermaid_ts_path.exists():
        print(f"⚠️ mermaid.inline.ts not found at {mermaid_ts_path}")
        return
    try:
        marker = 'aria-roledescription="pie"'
        with open(mermaid_ts_path, "r", encoding="utf-8") as f:
            content = f.read()

        if marker in content:
            print("ℹ️ Mermaid pie titles already re-fitted (no change).")
            return

        target = "    await mermaid.run({ nodes })"
        if target not in content:
            print("⚠️ Could not find mermaid.run call to patch; left unchanged.")
            return

        replacement = target + "\n" + (
            "\n"
            "    // Mermaid sizes a pie chart from its pie and legend, then\n"
            "    // centres the title on the pie — so a title wider than the pie\n"
            "    // spills outside the viewBox and is silently clipped, with room\n"
            "    // to spare on the right. Re-fit the box to what was drawn.\n"
            "    for (const node of nodes) {\n"
            "      const chart = node.querySelector('svg[aria-roledescription=\"pie\"]')\n"
            "      if (!chart) {\n"
            "        continue\n"
            "      }\n"
            "      const drawn = (chart as SVGGraphicsElement).getBBox()\n"
            "      const pad = 8\n"
            "      chart.setAttribute(\n"
            "        \"viewBox\",\n"
            "        `${drawn.x - pad} ${drawn.y - pad} ${drawn.width + pad * 2} ${drawn.height + pad * 2}`,\n"
            "      )\n"
            "      ;(chart as SVGElement).style.maxWidth = `${drawn.width + pad * 2}px`\n"
            "    }\n"
        )
        content = content.replace(target, replacement, 1)

        with open(mermaid_ts_path, "w", encoding="utf-8") as f:
            f.write(content)
        print("✅ Patched mermaid.inline.ts to re-fit pie chart titles")
    except Exception as e:
        print(f"⚠️ Error patching mermaid pie title fit: {e}")


# The five steps of the map, each as (fill, label). CHOSEN BY MEASUREMENT,
# not by eye: two shades that look obviously different in a list of
# swatches can be nearly the same colour in fact, which is how a deep red
# and a deep orange came to sit side by side on the map looking alike. The
# scale was searched — every combination of candidate shades in these five
# families, scored on the perceptual distance (CIEDE2000) between EVERY
# pair, and rejected outright unless each label cleared 4.5:1 against its
# own fill. Colour is the only visual carrier of the count here, so the
# same distances were measured again through simulations of the two common
# forms of red-green colour blindness; a scale that separates for most
# readers and collapses for the rest has not solved the problem.
#
# What that search settled, and why it is not the obvious answer: a
# mid-tone red fails BOTH labels — too dark for ink, too light for white —
# so red and orange cannot both be mid-tone, and the only way to hold them
# apart is to separate them by lightness as well as hue. Hence a deep red
# carrying white and a bright orange carrying dark ink. The closest pair
# any ordinary-sighted reader now sees is ΔE 31, against ΔE 10 before.
COVERAGE_LEVELS = [
    ("#7f1d1d", "#ffffff"),   # not yet addressed
    ("#f97316", "#1f2937"),   # addressed once
    ("#facc15", "#1f2937"),   # addressed twice
    ("#15803d", "#ffffff"),   # addressed three times
    ("#1e3a8a", "#ffffff"),   # addressed four or more times
]


def append_coverage_styles(base_scss_path: Path):
    """
    Styles for the curriculum coverage map.

    Colours are fixed rather than taken from the theme: the map's whole job
    is a graded reading from red through green to navy, and a colour scheme
    that recoloured it would destroy the meaning. The cells print no counts
    — the count reaches a screen reader through each cell's label, and a
    teacher reads it off the hover preview.

    The block always goes at the end of the file, so an earlier one is
    REPLACED rather than skipped: a stylesheet that survives from a previous
    build must still pick up a change made since.
    """
    marker = "/* === curriculum coverage map === */"
    if not base_scss_path.exists():
        return
    text = base_scss_path.read_text(encoding="utf-8")
    if marker in text:
        text = text[:text.index(marker)].rstrip() + "\n"

    # Both rules for a step come from the one definition above, so a fill
    # can never end up wearing a label that was chosen for a different
    # fill. The hover rule needs its own `!important` for the reason
    # explained beside it: Quartz recolours hovered links with one.
    level_rules = []
    level_hover_rules = []
    for level, (fill, label) in enumerate(COVERAGE_LEVELS):
        level_rules.append(f".coverage-{level} {{ background: {fill}; color: {label}; }}")
        level_hover_rules.append(
            f".coverage-{level}:hover,\n"
            f".coverage-{level}:focus-visible {{ color: {label} !important; }}")
    level_rules = "\n".join(level_rules)
    level_hover_rules = ("/* Each step keeps the label it wears at rest. */\n"
                         + "\n".join(level_hover_rules))

    text += f"""

{marker}
.coverage-panel {{
  /* The cell colours are fixed on purpose — the graded reading is the
     whole point (see COVERAGE_LEVELS) — but the page behind them is not. Plantoir's colour
     schemes run from near-white to near-black, so the darkest step had
     nothing to sit against in one scheme and the pale yellow one had
     nothing in another. The panel gives every scheme the same neutral
     ground, taken from the theme's OWN light grey: a light grey in light
     schemes, a dark grey in dark ones, by construction rather than by a
     second palette we would have to keep in step. */
  background: var(--lightgray);
  border-radius: 0.6rem;
  padding: 1.2rem 1.3rem 1.1rem;
  margin: 1.4rem 0;
  /* Hug the map instead of taking the whole column. A div is block-level,
     so a four-strand course drew a panel as wide as the article with two
     thirds of it empty. `fit-content` is min(max-content, available), so
     a map too wide for the column still gets the full width and still
     wraps — the panel only shrinks when there is something to shrink to. */
  width: fit-content;
  max-width: 100%;
}}
.coverage-map {{
  display: flex;
  flex-wrap: wrap;
  /* Wide enough that two ringed cells in neighbouring columns keep clear
     air between their outlines — the ring is 3px with a 2px offset, so
     each side needs at least 5px and the eye wants more. */
  gap: 1.4rem;
  align-items: flex-start;
  margin: 0;
}}
.coverage-strand {{
  display: flex;
  flex-direction: column;
  gap: 0.75rem;
  min-width: 4.6rem;
}}
.coverage-letter {{
  font-weight: 700;
  font-size: 1.1rem;
  text-align: center;
  padding-bottom: 0.1rem;
}}
.coverage-chips {{
  display: flex;
  gap: 0.15rem;
  justify-content: center;
  margin-bottom: 0.35rem;
  flex-wrap: wrap;
}}
.coverage-chip {{
  font-size: 0.62rem;
  line-height: 1;
  padding: 0.18rem 0.24rem;
  border-radius: 0.2rem;
  color: #fff;
  text-decoration: none;
  background: #6b7280;
}}
/* The chips answer a different question — is this overall expectation
   assessed at all — but they answer it in the map's own red and green, so
   the page does not use two reds. Taken from the scale above rather than
   written out again, so they cannot fall out of step with it. */
.coverage-chip-yes {{ background: {COVERAGE_LEVELS[3][0]}; }}
.coverage-chip-no {{ background: {COVERAGE_LEVELS[0][0]}; }}
.coverage-cell {{
  display: flex;
  align-items: center;
  justify-content: center;
  padding: 0.5rem 0.65rem;
  border-radius: 0.22rem;
  font-size: 0.72rem;
  line-height: 1.1;
  text-decoration: none;
  color: #fff;
  background: #9ca3af;
  /* A hairline so every cell keeps its shape whatever it is sitting on.
     The ramp spans near-white yellow to near-black green, so no single
     neutral ground can hold all five away from the page: on a dark
     scheme the darkest step all but vanished into the panel. Drawn in
     the theme's mid grey, which is mid in BOTH light and dark schemes,
     so it separates the pale end and the dark end at once. Inset, so it
     costs no layout and cannot be confused with the assessed ring. */
  box-shadow: inset 0 0 0 1px var(--gray);
}}
.coverage-code {{ font-weight: 600; }}
{level_rules}
/* Hovering. Quartz recolours any hovered link to the theme's accent —
   `color: var(--tertiary) !important` — which on a cell whose meaning IS
   its background reads as a contrast failure at exactly the moment the
   teacher is trying to read it: on the yellow level the label went from
   near-black to a pale sage, about 1.4:1. So the label's colour is pinned
   to what it already was (the `!important` is theirs, and only an
   `!important` can answer it), and the hover shows itself by lightening
   the BACKGROUND instead — a translucent white wash that composites over
   whatever level colour the cell carries.

   The lift to z-index 1000 is not decoration. Quartz appends its hover
   preview INSIDE the link being hovered, so the preview can only rank
   against that link's own children; the sidebar carries z-index 1 and
   painted over it. Lifting the hovered cell takes its preview along. */
.coverage-cell,
a.coverage-chip {{ position: relative; }}
.coverage-cell:hover,
.coverage-cell:focus-visible,
a.coverage-chip:hover,
a.coverage-chip:focus-visible {{
  z-index: 1000;
  color: #fff !important;
  /* Gentle on purpose, and the strength was measured rather than
     guessed. Lightening the field a white label sits on COSTS that label
     contrast, so a wash heavy enough to be obvious took the two
     mid-ramp colours from marginal to unreadable. This much is plainly
     visible on the dark cells — where most of a healthy course's map
     lives — and costs the worst-off label about half a point. */
  background-image: linear-gradient(rgba(255, 255, 255, 0.12),
                                    rgba(255, 255, 255, 0.12));
}}
{level_hover_rules}
/* Assessed work is marked by a ring OUTSIDE the cell, with a gap.
   Inset rings were tried twice and failed both times: drawn on top of the
   cell's own colour they read as a hairline, and no single tone works
   against five fixed colours. Moving the ring outside solves both — the
   gap separates it from the cell colour entirely, and `var(--dark)` is
   the theme's own text colour, so it contrasts with the page background
   in every Plantoir colour scheme, light or dark, by construction. */
.coverage-cell[data-assessed="true"],
.coverage-key[data-assessed="true"] {{
  outline: 3px solid var(--dark);
  outline-offset: 2px;
}}
.coverage-rule {{
  border: none;
  /* Mid grey, not the theme's light grey: the panel IS that light grey
     now, and a rule drawn in it would be invisible. */
  border-top: 1px solid var(--gray);
  margin: 1.3rem 0 1rem;
  width: 100%;
}}
.coverage-legend {{
  display: flex;
  flex-direction: column;
  align-items: flex-start;
  gap: 0.4rem;
  margin: 0;
  font-size: 0.85rem;
  /* Containment prevents the long legend text from expanding the panel's
     intrinsic width: the panel width is set by the expectation columns
     above, and the legend wraps to fit that width. */
  contain: inline-size;
  min-width: 100%;
}}
.coverage-legend-row {{
  display: flex;
  align-items: flex-start;
  /* 0.75rem provides comfortable breathing room between the swatch and
     the label text, particularly for the assessed swatch whose 3px outline
     + 2px offset extends 5px outward. */
  gap: 0.75rem;
  width: 100%;
}}
.coverage-key {{
  display: inline-block;
  width: 1.7rem;
  height: 1.35rem;
  border-radius: 0.22rem;
  flex: none;
  margin-top: 0.05rem;
  /* The key swatches are the same five colours, so they need the same
     hairline for the same reason. */
  box-shadow: inset 0 0 0 1px var(--gray);
}}
.coverage-legend-label {{
  flex: 1 1 auto;
  min-width: 0;
  line-height: 1.35;
}}
"""
    base_scss_path.write_text(text, encoding="utf-8")
    print("✅ Appended curriculum coverage map styles to base.scss")


def patch_render_page_transclude_title(render_page_tsx_path: Path):
    """
    Change tagName: "h1" to tagName: page.frontmatter?.transcludeTitleSize ?? "h1"
    in the node.children = [ { type: "element", tagName: "h1", ... } ] block.
    """
    if not render_page_tsx_path.exists():
        print(f"⚠️ renderPage.tsx not found at {render_page_tsx_path}")
        return
    try:
        with open(render_page_tsx_path, "r", encoding="utf-8") as f:
            content = f.read()

        # Target the first occurrence within node.children creation
        pattern_specific = re.compile(
            r'(node\.children\s*=\s*\[\s*\{\s*type:\s*"element",\s*tagName:\s*)"h1"(\s*,\s*properties:\s*\{\s*\}\s*,\s*children\s*:\s*\[)',
            flags=re.DOTALL
        )
        replaced = pattern_specific.sub(
            r'\1page.frontmatter?.transcludeTitleSize ?? "h1"\2',
            content,
            count=1
        )

        if replaced == content:
            # Fallback: replace the first tagName: "h1" occurrence only
            pattern_fallback = re.compile(r'(tagName:\s*)"h1"')
            replaced, n = pattern_fallback.subn(
                r'\1page.frontmatter?.transcludeTitleSize ?? "h1"',
                content,
                count=1
            )
            if n == 0:
                print('ℹ️ Could not locate target \'tagName: "h1"\' to replace in renderPage.tsx (no change).')
                return

        result = toolchain_paths.write_file(str(render_page_tsx_path), replaced.encode("utf-8"))
        if result.returncode != 0:
            print("❌ Failed to patch renderPage.tsx for transcludeTitleSize:", result.stderr.decode())
        else:
            print("✅ Patched renderPage.tsx to use frontmatter transcludeTitleSize for tagName")
    except Exception as e:
        print(f"⚠️ Error patching renderPage.tsx: {e}")
# --- END ADD ---

# The anchor comment is only proof of anything if it sits directly above the
# `const omit = new Set(...)` it is documenting — i.e. the string a plain
# `grep` (and, until this hardening, `ensure_quartz_layout_anchor` itself)
# accepts on its own can exist while the Set has drifted away from it (a
# hand-edit, a future Quartz upstream reshuffle) with nothing left to wire the
# hidden list into `filterFn`. Deliberately loose about what follows "Set" —
# it only needs to prove the marker and the Set are adjacent, the same pairing
# `update_quartz_layout`'s own `pattern_omit` requires to ever touch this Set.
#
# Two things this deliberately does NOT tolerate, because nothing in this
# codebase ever writes either shape and both are cheap to add back if that
# ever changes: a blank line between the anchor and the `const` (every writer
# — `_patch_explorer_with_anchor`, `EXPLORER_BLOCK`, `update_quartz_layout`'s
# own rewrite — puts them on consecutive lines), and a type-annotation form
# (`const omit: Set<string> = new Set(...)`) rather than a generic on `Set`
# itself. A hand-edit into either shape would make a healthy file fail this
# check and refuse to build — noted here rather than silently, so whoever
# hits it knows this is why, not a new bug.
#
# verify.sh's Explorer-anchor check (§4b) must accept exactly the same shapes
# this does — mirror any change here into that grep pattern too, and vice
# versa, or the Docker image and the Windows-native build start disagreeing
# about what "wired" means.
_ANCHOR_STRUCTURE_RE = re.compile(
    r'//[ \t]*CQ4T-OMIT-ANCHOR:[^\n]*\n'   # the whole marker line, same line only —
    r'[ \t]*const[ \t]+omit[ \t]*=[ \t]*new[ \t]+Set',  # — not `.` in DOTALL mode, which
)                                            # would let the anchor "match" a Set
                                             # pages of unrelated code away.


def _anchor_is_structurally_wired(txt: str) -> bool:
    return "CQ4T-OMIT-ANCHOR" in txt and bool(_ANCHOR_STRUCTURE_RE.search(txt))


# --- HARDENING TWEAK #2: Preflight to ensure omit anchor exists --------------
def ensure_quartz_layout_anchor(quartz_layout_path: Path) -> bool:
    """
    Make sure quartz.layout.ts carries the Explorer filter that hides pages.

    This is the one preflight that must never be allowed to "pass anyway".
    What it guards is the teacher's hide list: the Explorer's `filterFn` and
    the `CQ4T-OMIT-ANCHOR` marker inside it. Later on, `update_quartz_layout`
    only rewrites the CONTENTS of that Set — it cannot create the filter that
    reads it.

    It used to warn and inject a bare `const omit = new Set([])` "to unblock
    the build". That is worse than failing, and it shipped: the Set was then
    populated, NOTHING consumed it, the build succeeded, and every page the
    teacher had hidden — Private Notes, Curriculum, Learning Goals — went up
    on the class site. The build printed two lines about it and carried on.

    The block belongs to `setup_course.py`, which is also where the identical
    patch runs at course-creation time; it is imported rather than copied so
    the two cannot drift. Baked into the image as well (see the Dockerfile),
    so a freshly created container has it from birth — that is the real fix,
    and this is the belt to its braces for containers that predate it.

    The check is STRUCTURAL, not a bare substring match (`_anchor_is_
    structurally_wired`, added after an adversarial review of this fix on
    2026-08-23 flagged the gap): a file can contain the literal string
    "CQ4T-OMIT-ANCHOR" while the comment has drifted away from the `omit` Set
    it was documenting — e.g. a hand-edit, or a future Quartz upstream
    reshuffle inside `Component.Explorer({...})` that none of
    `_patch_explorer_with_anchor`'s three regex strategies produce cleanly.
    A bare substring check would report success while `update_quartz_layout`
    silently inserts a brand-new, disconnected `omit` Set at the top of the
    file on its next write (its own fallback for "pattern not found") — the
    hidden-page list would be written and never consulted, which is exactly
    the failure this whole preflight exists to catch.
    """
    if not quartz_layout_path.exists():
        print(f"❌ quartz.layout.ts not found at {quartz_layout_path}")
        return False

    txt = quartz_layout_path.read_text(encoding="utf-8")
    if _anchor_is_structurally_wired(txt):
        return True

    if "CQ4T-OMIT-ANCHOR" in txt:
        print("⚠️ The Explorer's hide filter marker is present in quartz.layout.ts")
        print("   but is no longer attached to a live omit Set — repairing it")
        print("   before building, since pages you have hidden would otherwise")
        print("   go unrecognized by the filter.")
    else:
        print("⚠️ The Explorer's hide filter is missing from quartz.layout.ts.")
        print("   Repairing it before building — without it, pages you have")
        print("   hidden would be published.")

    try:
        sys.path.insert(0, str(Path(__file__).resolve().parent))
        from setup_course import _patch_explorer_with_anchor
        repaired, changed = _patch_explorer_with_anchor(txt)
    except Exception as exc:
        print(f"❌ Could not load the Explorer patch: {exc}")
        return False

    if not changed or not _anchor_is_structurally_wired(repaired):
        print("❌ Could not restore the Explorer's hide filter.")
        return False

    quartz_layout_path.write_text(repaired, encoding="utf-8")
    print("✅ Restored the Explorer's hide filter.")
    return True
# -----------------------------------------------------------------------------

# --- NEW ADD: Patch Explorer.tsx to wire expand-on-navigate flag -------------
def patch_explorer_tsx_expand_behavior(explorer_tsx_path: Path):
    """
    Ensures Explorer.tsx reads expandOnFolderClick from course_config.json and exposes it via
    data-expand-on-navigate, so explorer.inline.ts can decide whether to auto-open on navigation.
    Idempotent.
    """
    if not explorer_tsx_path.exists():
        print(f"⚠️ Explorer.tsx not found at {explorer_tsx_path}")
        return
    try:
        src = explorer_tsx_path.read_text(encoding="utf-8")
        changed = False

        # Inject const expandOnFolderClick = courseConfig.expandOnFolderClick ?? true
        if "expandOnFolderClick" not in src:
            # Prefer inserting after expandableList definition
            src2, n = re.subn(
                r'(const\s+expandableList\s*=\s*courseConfig\.expandable\s*\?\?\s*\[\]\s*)',
                r'\1\n\nconst expandOnFolderClick = courseConfig.expandOnFolderClick ?? true\n',
                src, count=1
            )
            if n == 0:
                # Fallback: insert after courseConfig import
                src2, n = re.subn(
                    r'(import\s+courseConfig\s+from\s+["\'][^"\']*course_config\.json["\']\s*)',
                    r'\1\nconst expandOnFolderClick = courseConfig.expandOnFolderClick ?? true\n',
                    src, count=1
                )
            if src2 != src:
                src = src2
                changed = True

        # Add data-expand-on-navigate to wrapper div
        if "data-expand-on-navigate" not in src:
            src2, n = re.subn(
                r'(<div\s+class=\{classNames\(displayClass,\s*"explorer"\)\}[^>]*?)>',
                r'\1 data-expand-on-navigate={expandOnFolderClick}>',
                src, flags=re.DOTALL, count=1
            )
            if n > 0:
                src = src2
                changed = True

        if changed:
            result = toolchain_paths.write_file(str(explorer_tsx_path), src.encode("utf-8"))
            if result.returncode != 0:
                print("❌ Failed to patch Explorer.tsx:", result.stderr.decode())
            else:
                print("✅ Patched Explorer.tsx to wire expand-on-navigate flag")
        else:
            print("ℹ️ Explorer.tsx already has expand-on-navigate wiring (no change).")

    except Exception as e:
        print(f"⚠️ Error patching Explorer.tsx: {e}")
# -----------------------------------------------------------------------------

# --- NEW ADD: Patch explorer.inline.ts to honor expand-on-navigate -----------
def patch_explorer_inline_expand_on_navigate(inline_path: Path):
    """
    Ensures explorer.inline.ts:
      - adds 'expandOnNavigate: boolean' to ParsedOptions
      - reads dataset.expandOnNavigate into opts
      - gates auto-open on navigate with opts.expandOnNavigate
    Idempotent.
    """
    if not inline_path.exists():
        print(f"⚠️ explorer.inline.ts not found at {inline_path}")
        return
    try:
        src = inline_path.read_text(encoding="utf-8")
        changed = False

        # 1) Interface: add field if missing
        if "expandOnNavigate" not in src:
            src = re.sub(
                r'(interface\s+ParsedOptions\s*\{)([\s\S]*?)(\})',
                lambda m: m.group(1) + m.group(2) + "\n  expandOnNavigate: boolean\n" + m.group(3),
                src, count=1
            )
            changed = True

        # 2) opts object: add property if missing
        if "expandOnNavigate:" not in src:
            src = re.sub(
                r'(const\s+opts\s*:\s*ParsedOptions\s*=\s*\{[\s\S]*?)(\n\s*\})',
                r'\1\n      expandOnNavigate: (explorer.dataset.expandOnNavigate ?? "true") == "true",\2',
                src, count=1
            )
            changed = True

        # 3) Gate auto-open on navigate
        if re.search(r'if\s*\(\s*!isCollapsed\s*\|\|\s*folderIsPrefixOfCurrentSlug\s*\)\s*\{', src):
            src = re.sub(
                r'if\s*\(\s*!isCollapsed\s*\|\|\s*folderIsPrefixOfCurrentSlug\s*\)\s*\{',
                r'if (!isCollapsed || (opts.expandOnNavigate and folderIsPrefixOfCurrentSlug)) {',
                src, count=1
            )
            # Fix accidental 'and' if TS; replace with '&&'
            src = src.replace(' and folderIsPrefixOfCurrentSlug', ' && folderIsPrefixOfCurrentSlug')
            changed = True
        elif "opts.expandOnNavigate" not in src:
            # If condition already changed differently, we won't force it
            pass

        if changed:
            result = toolchain_paths.write_file(str(inline_path), src.encode("utf-8"))
            if result.returncode != 0:
                print("❌ Failed to patch explorer.inline.ts:", result.stderr.decode())
            else:
                print("✅ Patched explorer.inline.ts to honor expand-on-navigate")
        else:
            print("ℹ️ explorer.inline.ts already supports expand-on-navigate (no change).")

    except Exception as e:
        print(f"⚠️ Error patching explorer.inline.ts: {e}")

def patch_quartz_build_clean(build_ts_path: Path):
    """
    Patches quartz/build.ts so that directory cleaning handles virtiofs / Docker
    bind-mount latency gracefully (with retries and error catch) rather than crashing
    on ENOTEMPTY when removing existing public/ subdirectories.
    Idempotent.
    """
    if not build_ts_path.exists():
        return
    try:
        src = build_ts_path.read_text(encoding="utf-8")
        if "CQ4T-CLEAN-PATCH" in src:
            return

        old_pattern = r'await\s+rimraf\s*\(\s*path\.join\s*\(\s*output\s*,\s*["\']\*["\']\s*\)\s*,\s*\{\s*glob\s*:\s*true\s*\}\s*\)'
        new_code = (
            '/* CQ4T-CLEAN-PATCH */\n'
            '  try {\n'
            '    await rimraf(path.join(output, "*"), { glob: true, maxRetries: 5, retryDelay: 50 })\n'
            '  } catch (_rimrafErr) {\n'
            '    try {\n'
            '      const fs = await import("fs/promises")\n'
            '      const entries = await fs.readdir(output, { withFileTypes: true }).catch(() => [])\n'
            '      for (const entry of entries) {\n'
            '        const fp = path.join(output, entry.name)\n'
            '        await fs.rm(fp, { recursive: true, force: true, maxRetries: 5, retryDelay: 50 }).catch(() => {})\n'
            '      }\n'
            '    } catch (_ignore) {}\n'
            '  }'
        )
        new_src, count = re.subn(old_pattern, new_code, src, count=1)
        if count > 0:
            build_ts_path.write_text(new_src, encoding="utf-8")
            print("✅ Patched quartz/build.ts output directory cleaner")
    except Exception as e:
        print(f"⚠️ Could not patch quartz/build.ts: {e}")

def safe_clean_public_dir(public_dir: Path):
    """
    Safely clean the public output directory before running Quartz build,
    avoiding ENOTEMPTY / rimraf collisions on Docker bind-mounted filesystems.
    """
    if not public_dir.exists():
        return
    import time
    for attempt in range(5):
        try:
            for item in public_dir.iterdir():
                if item.is_dir() and not item.is_symlink():
                    shutil.rmtree(item, ignore_errors=False)
                else:
                    item.unlink(missing_ok=True)
            return
        except Exception:
            time.sleep(0.05 * (attempt + 1))
    try:
        shutil.rmtree(public_dir, ignore_errors=True)
        public_dir.mkdir(parents=True, exist_ok=True)
    except Exception:
        pass
        
def patch_folder_click_behavior(quartz_layout_path: Path, expand_on_name: bool):
    """
    Ensure Component.Explorer(...) uses the desired folderClickBehavior:
      - 'collapse'  → clicking the folder name toggles expansion
      - 'link'      → clicking the folder name navigates
    Patches ALL Explorer option objects it finds, idempotently.
    """
    if not quartz_layout_path.exists():
        print(f"⚠️ quartz.layout.ts not found at {quartz_layout_path}")
        return
    try:
        content = quartz_layout_path.read_text(encoding="utf-8")
        desired = "collapse" if expand_on_name else "link"

        # 1) Replace existing field values
        pattern = re.compile(
            r'(Component\.Explorer\(\s*\{[\s\S]*?folderClickBehavior\s*:\s*")(?:(?:link)|(?:collapse))(")',
            flags=re.DOTALL
        )
        new_content, n1 = pattern.subn(rf'\1{desired}\2', content, count=0)

        # 2) If the field is missing, insert it after the title field
        if n1 == 0:
            def insert_field(m: re.Match) -> str:
                block = m.group(0)
                inserted, n2 = re.subn(
                    r'(title\s*:\s*"[^"]*"\s*,?)',
                    r'\1\n    folderClickBehavior: "' + desired + '",',
                    block,
                    count=1
                )
                return inserted if n2 > 0 else block

            new_content, n2 = re.subn(
                r'Component\.Explorer\(\s*\{\s*[\s\S]*?\}\s*\)',
                insert_field,
                new_content,
                count=0
            )
            changed = (n2 > 0)
        else:
            changed = True

        if changed and new_content != content:
            result = toolchain_paths.write_file(str(quartz_layout_path), new_content.encode("utf-8"))
            if result.returncode != 0:
                print("❌ Failed to patch folderClickBehavior:", result.stderr.decode())
            else:
                print(f"✅ Set folderClickBehavior → '{desired}' in quartz.layout.ts")
        else:
            print("ℹ️ folderClickBehavior already set as desired (no change).")
    except Exception as e:
        print(f"⚠️ Error patching folderClickBehavior: {e}")

# -----------------------------------------------------------------------------

# --- NEW ADD: Media handling helpers -----------------------------------------
def _ensure_media_symlink(content_root: Path, course_dir: Path):
    """
    Ensure `content/Media` is a symlink to the course-level `Media` folder.
    Replaces any existing real folder with a symlink (to avoid duplication).
    """
    link_path = content_root / "Media"
    target_abs = (course_dir / "Media").resolve()

    if os.name == "nt":
        # No junction here: it is an NTFS mount point, and current Windows
        # refuses to TRAVERSE user-made mount points while enumerating
        # directories (WinError 448) - the coverage builder's walk over
        # content/ died on exactly this in the first real end-user test.
        # Hardlinks carry the same no-copy economics with nothing for the
        # OS to distrust. An old-style link left by a previous build is
        # replaced first (rmtree on a junction removes only the link).
        if link_path.is_symlink() or toolchain_paths.is_reparse_point(link_path):
            try:
                if link_path.is_dir():
                    os.rmdir(link_path)
                else:
                    link_path.unlink()
            except OSError as e:
                print(f"⚠️ Could not replace the old 'Media' link at {link_path}: {e}")
        try:
            toolchain_paths.hardlink_mirror(Path(str(target_abs)), link_path)
            print(f"🔗 Mirrored Media into the build (hardlinks): {link_path} -> {target_abs}")
        except Exception as e:
            print(f"❌ Failed to mirror Media at {link_path}: {e}")
        return

    # If a file/dir already exists at link_path, remove it first (carefully)
    if link_path.exists() or link_path.is_symlink():
        try:
            if link_path.is_symlink() or link_path.is_file():
                link_path.unlink()
            else:
                # It's a real directory; remove it to avoid duplication
                shutil.rmtree(link_path)
            print(f"♻️ Replaced existing 'Media' at {link_path} with a symlink.")
        except Exception as e:
            print(f"⚠️ Could not remove existing 'Media' at {link_path}: {e}")

    try:
        how = toolchain_paths.link_directory(Path(str(target_abs)), link_path)
        print(f"🔗 Created Media link ({how}): {link_path} -> {target_abs}")
    except Exception as e:
        print(f"❌ Failed to create Media symlink at {link_path}: {e}")

def _sync_public_to_host(output_dir: Path, host_output_dir: Path) -> bool:
    """
    Sync built static assets (public/) and course_config.json from internal
    container ext4 storage to the host-mounted output directory.

    Returns whether a built SITE was mirrored. The root `index.html` is the
    test, and the guard on it is right: Quartz emits one only when the merged
    tree has an `index.md`, and a pile of pages with no front page is not
    something anybody can publish. What was wrong is that the answer went
    nowhere — the build printed "Static build complete" either way. The caller
    now decides what to say based on what actually happened.
    """
    src_public = output_dir / "public"
    dst_public = host_output_dir / "public"
    mirrored_a_site = False
    if src_public.exists() and (src_public / "index.html").exists():
        dst_public.parent.mkdir(parents=True, exist_ok=True)
        try:
            res = subprocess.run(
                ["rsync", "-a", "--no-owner", "--no-group", "--delete", f"{src_public}/", f"{dst_public}/"],
                check=False,
                stdout=subprocess.DEVNULL,
                stderr=subprocess.DEVNULL,
            )
            if res.returncode != 0:
                toolchain_paths.mirror_tree(src_public, dst_public)
        except Exception:
            # No rsync on this host (Windows native): incremental mirror,
            # because this runs on every tick of the preview sync watcher.
            toolchain_paths.mirror_tree(src_public, dst_public)
        mirrored_a_site = True

    if (output_dir / "course_config.json").exists():
        try:
            shutil.copy2(output_dir / "course_config.json", host_output_dir / "course_config.json")
        except Exception:
            pass

    # Flush ONLY the host mount's filesystem, never os.sync(): a global sync
    # waits on every superblock in the kernel, and under WSL2 all distros share
    # one kernel — a leaked FUSE superblock anywhere (WSLg has produced one)
    # blocks it forever, presenting as a deploy that hangs after the Quartz
    # build with no error. syncfs() touches just the filesystem the site was
    # copied to, which is the only one this step has any business flushing.
    try:
        import ctypes
        libc = ctypes.CDLL(None, use_errno=True)
        fd = os.open(str(host_output_dir), os.O_RDONLY | os.O_DIRECTORY)
        try:
            libc.syncfs(fd)
        finally:
            os.close(fd)
    except Exception:
        pass

    return mirrored_a_site

def _clear_stale_host_site(host_output_dir: Path, course_code: str, section_number) -> None:
    """
    Throw away the last built site when this build cannot replace it.

    `_sync_public_to_host` mirrors nothing when the merged tree has no
    `index.md`, and that guard is right — half a build must never be
    published. What was wrong is what it left BEHIND. The previous build's
    `public/` stayed on the host, and `deploy.py` publishes whatever it finds
    there, so a teacher who deleted a front page, built, and published was
    told the publish had succeeded and shipped LAST week's pages. Nothing
    anywhere said so. That is the silent wrong answer this whole family of
    checks exists to end, and it was being produced by the check's own guard.

    Removing it turns a silent wrong answer into an honest refusal: `deploy`
    says the built site is not there, and the build has already said why.
    Nothing of the teacher's is lost — `.merged_output` is derived from their
    notes, and every successful build rewrites this tree wholesale
    (`rsync --delete`).
    """
    stale_public = host_output_dir / "public"
    if not stale_public.exists():
        return
    try:
        shutil.rmtree(stale_public)
        print(f"🗑️  Removed the last built website for {course_code} Section {section_number}: "
              f"without a front page this build cannot replace it, and publishing "
              f"it again would have sent out the older pages.")
    except Exception as error:
        print(f"⚠️  Could not remove the last built website at {stale_public}: {error}")

def _start_public_sync_watcher(output_dir: Path, host_output_dir: Path) -> threading.Thread:
    """
    Start a background daemon thread that periodically syncs public/ to host_output_dir
    when files in public/ are updated.
    """
    def _watcher():
        last_mtime = None
        while True:
            try:
                index_path = output_dir / "public" / "index.html"
                if index_path.exists():
                    mtime = index_path.stat().st_mtime
                    if mtime != last_mtime:
                        last_mtime = mtime
                        _sync_public_to_host(output_dir, host_output_dir)
            except Exception:
                pass
            time.sleep(1)

    t = threading.Thread(target=_watcher, daemon=True)
    t.start()
    return t

def _is_media_name(name) -> bool:
    """
    Whether a configured name refers to the Media folder, in ANY spelling.

    Case-insensitively, because the filesystem is. Both apps used to accept
    "media" typed into Settings, so configs in the field already carry it — and
    closing the input gate does nothing for a course that already has one.
    Left as "media" in the config on purpose: rewriting a teacher's file behind
    their back to change its capitalisation would be a surprise for no gain,
    and every reader now recognises it either way.
    """
    return str(name).strip().lower() == "media"


def _filter_out_media(items: list[str]) -> list[str]:
    """Return a copy of items with the Media folder removed, in any spelling."""
    return [x for x in (items or []) if not _is_media_name(x)]
# -----------------------------------------------------------------------------

# === NEW: Discovery + preflight config update ================================
_IGNORED_SHARED_FOLDERS = {
    "merged_output", ".merged_output", ".obsidian", "node_modules", "Media"
}
_IGNORED_SHARED_FILES = {
    "course_config.json",
    # Preflight's own write-back leaves these beside the config
    # (_atomic_write_json_with_backup). Without this, the build after any
    # write-back discovered the backup as a shared file and SHIPPED the
    # teacher's config to students at public/course_config.backup.json.
    # Found 2026-08-24; present since discovery was added (8f709000).
    "course_config.backup.json",
    "course_config.json.tmp",
    ".DS_Store",
    "Thumbs.db",
}

def _is_hidden(name: str) -> bool:
    return name.startswith(".")

def _is_section_folder(name: str) -> bool:
    return re.fullmatch(r"section\d+", name or "") is not None

def _safe_unique_append(dst: list[str], items: list[str]) -> int:
    """Append items to dst if not present; return how many were added."""
    added = 0
    for x in items:
        if x not in dst:
            dst.append(x)
            added += 1
    return added

def discover_shared_items(course_dir: Path) -> tuple[list[str], list[str]]:
    """Scan the course root and discover shared folders & files (top-level only)."""
    found_folders = []
    found_files = []
    try:
        for item in course_dir.iterdir():
            name = item.name
            if _is_hidden(name):
                continue
            if item.is_dir():
                if (name in _IGNORED_SHARED_FOLDERS or _is_media_name(name)
                        or _is_section_folder(name)):
                    continue
                found_folders.append(name)
            elif item.is_file():
                if name in _IGNORED_SHARED_FILES or name.startswith("hidden_explorer_components") or name.startswith("expandable_explorer_components"):
                    continue
                found_files.append(name)
    except Exception as e:
        print(f"⚠️ Could not scan course root for discovery: {e}")
    return found_folders, found_files

def discover_section_items(section_dir: Path) -> tuple[list[str], list[str]]:
    """Scan section root and discover per-section folders & files (top-level only)."""
    found_folders = []
    found_files = []
    try:
        for item in section_dir.iterdir():
            name = item.name
            if _is_hidden(name):
                continue
            if item.is_dir():
                if _is_media_name(name):
                    continue
                found_folders.append(name)
            elif item.is_file():
                if name in {".DS_Store", "Thumbs.db", "index.md"}:
                    continue
                found_files.append(name)
    except Exception as e:
        print(f"⚠️ Could not scan section root for discovery: {e}")
    return found_folders, found_files

def _atomic_write_json_with_backup(path: Path, data: dict):
    """Write JSON atomically and back up original"""
    try:
        if path.exists():
            backup = path.with_suffix(".backup.json")
            shutil.copy2(path, backup)
            print(f"🧾 Backed up course_config.json → {backup.name}")
    except Exception as e:
        print(f"⚠️ Could not create backup: {e}")
    tmp = path.with_suffix(".json.tmp")
    try:
        with open(tmp, "w", encoding="utf-8") as f:
            json.dump(data, f, indent=2, ensure_ascii=False)
            f.write("\n")
        os.replace(tmp, path)
        print("✅ Updated course_config.json with discovered items.")
    except Exception as e:
        print(f"❌ Failed to write updated course_config.json: {e}")
        try:
            if tmp.exists():
                tmp.unlink()
        except Exception:
            pass

def preflight_update_course_config(course_dir: Path, section_dir: Path, config_path: Path) -> dict:
    """Discover new items and append them to course_config.json (add-only). Return updated config dict.
    Also: any newly discovered folders are marked not hidden and added to the expandable list.
    Excludes any items listed in excluded_items (skips discovery, does not un-hide, and manages index.md note).
    """
    try:
        with open(config_path, "r", encoding="utf-8") as f:
            cfg = json.load(f)
    except Exception as e:
        print(f"❌ Could not read course_config.json for preflight: {e}")
        return {}

    # Read current lists (copy so we can mutate safely)
    shared_folders = list(cfg.get("shared_folders", []))
    shared_files = list(cfg.get("shared_files", []))
    per_section_folders = list(cfg.get("per_section_folders", []))
    per_section_files = list(cfg.get("per_section_files", []))
    hidden_list = list(cfg.get("hidden", []))
    expandable_list = list(cfg.get("expandable", []))
    excluded_items = cfg.get("excluded_items") or {}
    excluded_shared = set(excluded_items.get("shared") or [])
    excluded_per_section = set(excluded_items.get("per_section") or [])

    # The key is authoritative. Absence from a copy list is what actually
    # keeps a folder out of the site, and excluded_items is what stops
    # preflight putting it back - so a name in BOTH would publish while the
    # console and the index.md note say it is excluded. That state is never
    # written by a correct app, but a hand edit, a stale copy of the config
    # saved over a newer one, or an app that records the key without dropping
    # the name can all produce it. Reconcile here so the two can never
    # disagree, and say so (decided 2026-08-24, Piece 2 review).
    reconciled_changed = False
    for scope_label, names, list_pairs in (
        ("shared", excluded_shared, (("folder", shared_folders), ("file", shared_files))),
        ("per-section", excluded_per_section, (("folder", per_section_folders), ("file", per_section_files))),
    ):
        for kind, copy_list in list_pairs:
            for name in list(copy_list):
                if name in names:
                    copy_list.remove(name)
                    reconciled_changed = True
                    print(f"🚫 Dropped excluded {scope_label} {kind} from the copy list: {name} (listed in excluded_items)")

    # Discover
    disc_shared_folders, disc_shared_files = discover_shared_items(course_dir)
    disc_sec_folders, disc_sec_files = discover_section_items(section_dir)

    # Filter out excluded items from discovery and print skip notices
    allowed_disc_shared_folders = []
    for f in disc_shared_folders:
        if f in excluded_shared:
            print(f"🚫 Skipping excluded shared folder: {f} (listed in excluded_items)")
        else:
            allowed_disc_shared_folders.append(f)

    allowed_disc_shared_files = []
    for f in disc_shared_files:
        if f in excluded_shared:
            print(f"🚫 Skipping excluded shared file: {f} (listed in excluded_items)")
        else:
            allowed_disc_shared_files.append(f)

    allowed_disc_sec_folders = []
    for f in disc_sec_folders:
        if f in excluded_per_section:
            print(f"🚫 Skipping excluded per-section folder: {f} (listed in excluded_items)")
        else:
            allowed_disc_sec_folders.append(f)

    allowed_disc_sec_files = []
    for f in disc_sec_files:
        if f in excluded_per_section:
            print(f"🚫 Skipping excluded per-section file: {f} (listed in excluded_items)")
        else:
            allowed_disc_sec_files.append(f)

    # Determine which folders are *new* (before mutating lists)
    new_shared_folders = [x for x in allowed_disc_shared_folders if x not in shared_folders]
    new_sec_folders = [x for x in allowed_disc_sec_folders if x not in per_section_folders]

    # Append-only updates for copy lists
    added_sf = _safe_unique_append(shared_folders, allowed_disc_shared_folders)
    added_sfi = _safe_unique_append(shared_files, allowed_disc_shared_files)
    added_psf = _safe_unique_append(per_section_folders, allowed_disc_sec_folders)
    added_psfi = _safe_unique_append(per_section_files, allowed_disc_sec_files)

    # For newly discovered folders: ensure NOT hidden + ensure in expandable
    hidden_changed = False
    expandable_changed = False
    for name in new_shared_folders + new_sec_folders:
        if name in hidden_list:
            hidden_list = [h for h in hidden_list if h != name]
            hidden_changed = True
            print(f"👁️‍🗨️ Un-hid newly discovered folder: {name}")
        if name not in expandable_list:
            expandable_list.append(name)
            expandable_changed = True
            print(f"➕ Marked newly discovered folder as expandable: {name}")

    # Synchronize index.md sentinel notes for excluded and non-excluded folders
    start_sentinel, end_sentinel, note_body = _get_excluded_note_config()
    try:
        if course_dir.exists():
            for item in course_dir.iterdir():
                if item.is_dir() and not _is_hidden(item.name) and not _is_section_folder(item.name) and not _is_media_name(item.name) and item.name not in _IGNORED_SHARED_FOLDERS:
                    idx_file = item / "index.md"
                    if idx_file.exists():
                        if item.name in excluded_shared:
                            _apply_sentinel_note(idx_file, start_sentinel, end_sentinel, note_body)
                        else:
                            _remove_sentinel_note(idx_file, start_sentinel, end_sentinel)

            for sec_item in course_dir.iterdir():
                if sec_item.is_dir() and _is_section_folder(sec_item.name):
                    for item in sec_item.iterdir():
                        if item.is_dir() and not _is_hidden(item.name) and not _is_media_name(item.name):
                            idx_file = item / "index.md"
                            if idx_file.exists():
                                if item.name in excluded_per_section:
                                    _apply_sentinel_note(idx_file, start_sentinel, end_sentinel, note_body)
                                else:
                                    _remove_sentinel_note(idx_file, start_sentinel, end_sentinel)
    except Exception as e:
        print(f"⚠️ Could not synchronize excluded folder notes: {e}")

    print(f"\n📌 Auto-discovered shared folders: {allowed_disc_shared_folders or '—'}")
    print(f"📌 Auto-discovered shared files: {allowed_disc_shared_files or '—'}")
    print(f"📌 Auto-discovered per-section folders: {allowed_disc_sec_folders or '—'}")
    print(f"📌 Auto-discovered per-section files: {allowed_disc_sec_files or '—'}")

    if any([added_sf, added_sfi, added_psf, added_psfi, hidden_changed, expandable_changed, reconciled_changed]):
        cfg["shared_folders"] = shared_folders
        cfg["shared_files"] = shared_files
        cfg["per_section_folders"] = per_section_folders
        cfg["per_section_files"] = per_section_files
        if hidden_changed:
            cfg["hidden"] = hidden_list
        if expandable_changed:
            cfg["expandable"] = expandable_list
        _atomic_write_json_with_backup(config_path, cfg)
    else:
        print("ℹ️ No new items discovered; course_config.json unchanged.")

    return cfg
# =============================================================================

# === NEW: Fix Netlify static import for course_config.json ====================
def _copy_course_config_into_quartz(course_dir: Path, output_dir: Path):
    """
    Copy <course_dir>/course_config.json into <output_dir>/quartz/course_config.json.
    If missing at the course root, write a minimal default to prevent build errors.
    """
    src = course_dir / "course_config.json"
    quartz_dir = output_dir / "quartz"
    quartz_dir.mkdir(parents=True, exist_ok=True)
    dst = quartz_dir / "course_config.json"

    if src.exists():
        shutil.copy2(src, dst)
        print(f"✅ Copied course_config.json → {dst.relative_to(output_dir)}")
    else:
        fallback = {"courseCode": course_dir.name, "notes": "auto-generated fallback"}
        dst.write_text(json.dumps(fallback, indent=2), encoding="utf-8")
        print(f"ℹ️ No course_config.json found at {src}; wrote a minimal default to {dst}")

def _patch_quartz_imports_to_local_config(quartz_dir: Path):
    """
    Ensure Quartz components import course_config.json from the local quartz/ folder.
    Rewrites any existing import that targets course_config.json to the correct relative path.
    """
    targets = [
        quartz_dir / "components" / "Explorer.tsx",
        quartz_dir / "components" / "scripts" / "explorer.inline.ts",
    ]
    cfg_path = quartz_dir / "course_config.json"

    for fp in targets:
        if not fp.exists():
            continue
        rel_to_cfg = os.path.relpath(cfg_path, start=fp.parent).replace(os.sep, "/")
        try:
            src = fp.read_text(encoding="utf-8")
        except Exception as e:
            print(f"⚠️ Could not read {fp} to patch imports: {e}")
            continue

        # Replace any import ... from "....course_config.json"
        new_src, n = re.subn(
            r'(import\s+courseConfig\s+from\s+["\'])(.*?course_config\.json)(["\'])',
            rf'\1{rel_to_cfg}\3',
            src,
            flags=re.IGNORECASE,
        )

        if n == 0 and "course_config.json" not in src:
            # As a fallback, inject an import at the top
            new_src = f'import courseConfig from "{rel_to_cfg}"\n' + src

        if new_src != src:
            try:
                fp.write_text(new_src, encoding="utf-8")
                print(f"🔧 Patched import in {fp.relative_to(quartz_dir)} → {rel_to_cfg}")
            except Exception as e:
                print(f"⚠️ Could not write patched imports to {fp}: {e}")
        else:
            print(f"✔️  Import in {fp.relative_to(quartz_dir)} already points to {rel_to_cfg}")
# =============================================================================

# === NEW: Netlify link helper (no deploy here) ===============================
def _ensure_netlify_link(output_dir: Path, course_dir: Path):
    """
    Ensure output_dir contains a .netlify folder so 'netlify deploy' can diff.
    Prefer a symlink to an existing root .netlify; if that fails, copy.
    (This script does not deploy; it just makes the eventual deploy faster.)
    """
    dst = output_dir / ".netlify"
    if dst.exists():
        print("✔️  .netlify already present in output (will enable CLI diff).")
        return

    candidates = [course_dir / ".netlify", course_dir.parent / ".netlify"]
    for src in candidates:
        if src.exists() and src.is_dir():
            try:
                toolchain_paths.link_directory(src.resolve(), Path(dst))
                print(f"🔗 Linked .netlify → {src}")
                return
            except Exception as e:
                print(f"ℹ️ Symlink failed ({e}); attempting a copy...")
                try:
                    shutil.copytree(src, dst)
                    print("📦 Copied .netlify into output directory.")
                    return
                except Exception as e2:
                    print(f"⚠️ Could not copy .netlify folder: {e2}")
    # No message when there is nothing to link: that is the NORMAL state for
    # a fresh folder, and printing "Netlify" mid-preview made a teacher read
    # a routine build as a publishing failure (real smoke test, 2026-08-20).
# =============================================================================

# ---------------------------------------------------------------------------
# Curriculum coverage heat map
# ---------------------------------------------------------------------------
# Ontario asks two different things of a course: every SPECIFIC (minor)
# expectation should be addressed at least once, and every OVERALL (major)
# expectation must be evaluated for marks at least once. Both are easy to
# lose track of in November. This builds a page that answers them at a
# glance, from the site's own links — so it cannot drift from the course.
#
# What counts as coverage is deliberately narrow: a transclusion or link
# inside a `%%curriculum-start%%` / `%%curriculum-end%%` block. That is the
# form the course uses to say "this page addresses this expectation" on
# purpose, as opposed to a passing mention in prose.

# The generated page's title. Used by the generator, by the Key Links
# insertion, and by the Explorer omit list, so the three cannot drift.
COVERAGE_PAGE_TITLE = "Curriculum Coverage"

# The two explanatory sections at the foot of the coverage page. They are
# written for a teacher meeting the map for the first time, and a course
# can switch them off once that conversation has happened.
COVERAGE_NOTES = """## What counts

A page addresses an expectation when it **transcludes** it — when the
expectation's own wording appears on the page, under a *Curriculum
connection* heading. That is the deliberate form.

A passing mention in prose does not count. A concept page can discuss an
idea, and even link to the expectation behind it in a sentence, without
claiming to have addressed it — which is why the number here is usually
lower than the backlinks count on the expectation's own page, and why it
means more. If a page genuinely covers an expectation, put it in that
page's *Curriculum connection* rather than leaving it as a mention.

**Only pages this course teaches count.** The page carrying the
connection has to be reachable from a class page — linked from one
directly, or from a page a class page links to. A page written in August
and never put into a class has addressed nothing yet, and a page reached
only from Key Links is a reference, not a lesson.

**Only published pages count.** A page marked `publish: false` is not on
the site yet, so it cannot have addressed anything — next week's lesson,
written early, leaves the map exactly where it was until the day it is
published.

An expectation counts as **assessed** when one of those pages is in a
folder that counts for marks — {graded_folders} for this course, which you
can change in Settings. Ontario asks that every overall expectation be
evaluated for marks at least once; the chips under each strand letter
answer that, and the ring on a cell shows which specific expectations carry
assessed work.

## Reading it honestly

Red is not failure — in September everything is red, and that is what the
first months of a course look like. What matters is the direction of
travel, and whether anything is still red in May.

A strand of red in the skills strand usually means something different:
those expectations are being met in every investigation without being
cited by code. If that is the case here, it is worth citing a few of them
where they genuinely apply rather than leaving the record silent.
"""

SPECIFIC_CODE = re.compile(r"^([A-Z])(\d+)\.(\d+)$")
OVERALL_FILE = re.compile(r"^([A-Z]\d+)\.\s")
CURRICULUM_BLOCK = re.compile(r"%%curriculum-start%%(.*?)%%curriculum-end%%", re.S)
BLOCK_LINK = re.compile(r"!?\[\[([^\]|#]+?)(?:\\?\|[^\]]*)?(?:#[^\]|]*)?\]\]")
TRANSCLUSION = re.compile(r"!\[\[([^\]|#]+?)(?:\\?\|[^\]]*)?(?:#[^\]|]*)?\]\]")


def _quartz_slug(relative: Path) -> str:
    """The URL Quartz gives a page: spaces become hyphens, no extension."""
    parts = list(relative.parts)
    parts[-1] = relative.stem
    return "/".join(part.replace(" ", "-") for part in parts)


def _is_single_folder_name(name: str) -> bool:
    """
    Whether a configured folder name is just that — a name, not a path.

    `curriculum_folder` comes from `course_config.json`, and the value is used
    to build a path. "../Other Course/Curriculum" or an absolute path would
    quietly build somebody else's expectations into this site, and a value like
    "shared/Curriculum" would work here while disagreeing with every other
    reader. A name with a separator in it is a mistake either way, so it is
    refused and the scan takes over.
    """
    text = str(name)
    if not text or text in (".", ".."):
        return False
    if "/" in text or "\\" in text:
        return False
    return True


def _find_curriculum_folder(content_root: Path, named: str = None):
    """
    The folder holding expectation pages, whatever the course calls it.

    `named` is the course's own `curriculum_folder` — declared by every payload
    and skeleton manifest and carried into `course_config.json`. It is tried
    FIRST, which matters for a course whose folder does not contain the word
    "curriculum" at all: the scan below would never find one, and the map would
    quietly not be built.

    The scan remains the fallback, and remains the real path for the majority:
    a course made from scratch has no manifest to declare anything.
    """
    if named and _is_single_folder_name(named):
        candidate = content_root / named
        if candidate.is_dir():
            for page in candidate.glob("*.md"):
                if SPECIFIC_CODE.match(page.stem):
                    return candidate
    for candidate in sorted(content_root.iterdir()):
        if not candidate.is_dir():
            continue
        if "curriculum" not in candidate.name.lower():
            continue
        for page in candidate.glob("*.md"):
            if SPECIFIC_CODE.match(page.stem):
                return candidate
    return None


def _collect_expectations(curriculum_dir: Path):
    """Specific expectations by code, and overall expectations by code."""
    specific, overall = {}, {}
    for page in sorted(curriculum_dir.glob("*.md")):
        match = SPECIFIC_CODE.match(page.stem)
        if match:
            specific[page.stem] = page
            continue
        heading = OVERALL_FILE.match(page.stem)
        if heading:
            overall[heading.group(1)] = page
    return specific, overall


def _is_draft(text: str) -> bool:
    """
    Is this page held back from the built site?

    Visibility is `publish: false`. `draft: true` is the older spelling
    with the opposite polarity and is still read, because a teacher's
    existing course may carry it — but an explicit `publish` always wins.
    """
    if not text.startswith("---\n"):
        return False
    end = text.find("\n---", 4)
    if end < 0:
        return False
    legacy = None
    for line in text[4:end].split("\n"):
        match = re.match(r"^(publish|draft):\s*(.+?)\s*$", line)
        if match:
            key = match.group(1)
            value = match.group(2).strip().strip('"').strip("'").lower()
            if key == "publish":
                return value == "false"
            if legacy is None:
                legacy = value == "true"
    return bool(legacy)


def class_folder_name(config: dict) -> str:
    """
    WHERE A NEW CLASS PAGE IS WRITTEN — see `class_pages.folder_name`.

    Kept as a name here because `test_class_folder.py` imports it and it is the
    name every write-up refers to, but the RULE lives in `class_pages.py`,
    which `setup_course.py` also reads. One rule, one home: four disagreeing
    implementations of this question is what the whole `classFolder` contract
    was written to end, and a fifth living here would be the same mistake.
    """
    return class_pages.folder_name(config)


def class_folder_names(config: dict) -> list:
    """
    WHICH FOLDERS COUNT as holding class pages — see `class_pages.folder_names`.
    """
    return class_pages.folder_names(config)


GRADED_FOLDERS_KEY = "graded_folders"


def graded_folder_names(config: dict):
    """
    Which folders hold work that COUNTS FOR MARKS, and whether the teacher has
    said so explicitly.

    Returns `(names, was_configured)`. An expectation is "assessed" — the ring
    on a cell in the Curriculum Coverage map, and Ontario's requirement that
    every overall expectation be evaluated at least once — when a page that
    addresses it lives in one of these.

    **An ABSENT key is not an empty list, and the difference is the whole
    migration.** Absent means the teacher has never been asked, so the historical
    rule applies: any folder whose name CONTAINS "task". Every course made
    before this key existed keeps exactly the marks it had. An empty list means
    the teacher was asked and cleared it, which is a real answer and is left
    alone.

    Why that matters concretely: the exact-name rule is NARROWER than the
    substring one. `support/skeletons` ships a family whose folder is called
    "Thinking Tasks", which the old rule counted and a pool of ["Tasks"] would
    not — so seeding every course with ["Tasks"] would have silently taken the
    assessed marks off that course's map.

    Nothing is written back to the config here either. Both apps DO preserve
    keys they do not know about, so the general claim that a build's write would
    be dropped is too strong; the real risk is narrower and quite enough — an
    app holding a copy of the file it loaded BEFORE the build wrote the key will
    overwrite it on the next save, and a teacher with Settings open during a
    preview is an ordinary thing rather than a corner case.

    Pinned by contracts/shared-rules.json -> gradedFolders.
    """
    if GRADED_FOLDERS_KEY not in config:
        return [], False
    names = []
    for folder in config.get(GRADED_FOLDERS_KEY) or []:
        if folder:
            names.append(str(folder))
    return names, True


def _has_graded_folders(content_root: Path, graded_folders: list, was_configured: bool) -> bool:
    """
    Whether any folder in the merged content tree counts for marks.

    Configured: at least one directory matches a name in `graded_folders` (case-insensitively).
    Not configured (historical): at least one directory contains "task" (case-insensitively).
    """
    if was_configured:
        wanted = {str(name).lower() for name in (graded_folders or []) if name}
        if not wanted:
            return False
        for p in content_root.rglob("*"):
            if p.is_dir() and p.name.lower() in wanted:
                return True
        return False
    else:
        for p in content_root.rglob("*"):
            if p.is_dir() and "task" in p.name.lower():
                return True
        return False


def _escaped_for_markdown(text: str) -> str:
    """
    A folder's name, safe to drop into the page's prose.

    These names are the teacher's own, and a folder called `Tasks*` or one
    containing `[[` would otherwise close the bold early or inject a wikilink
    into a page Plantoir wrote.
    """
    escaped = text
    for character in ("\\", "*", "_", "[", "]", "<", ">", "`"):
        escaped = escaped.replace(character, "\\" + character)
    return escaped


def _graded_folders_in_words(graded_folders, was_configured: bool) -> str:
    """
    How to name this course's graded folders on the page itself.

    A course that has never been asked is described by what it actually does
    rather than by a list it does not have — saying "Tasks" there would be a
    guess, and the historical rule is a substring.
    """
    if not was_configured:
        # "mentions tasks" would be a near-miss: the rule is the substring
        # "task", so a folder called "Task 1" counts and a teacher reading
        # "tasks" would conclude it did not.
        return "any folder with \u201ctask\u201d in its name"
    names = [_escaped_for_markdown(str(name)) for name in (graded_folders or []) if name]
    if not names:
        return "no folder at present"
    if len(names) == 1:
        return f"**{names[0]}**"
    quoted = [f"**{name}**" for name in names]
    return ", ".join(quoted[:-1]) + " and " + quoted[-1]


def _is_graded_path(relative_path, graded_folders, was_configured: bool) -> bool:
    """
    Whether a page — given RELATIVE to the content root — is work that counts
    for marks.

    Configured: one of its FOLDER segments equals a pooled name, case
    insensitively, at any depth, so `Tasks/Unit 1/Quiz.md` counts.
    Not configured: the historical rule, any folder segment CONTAINING "task".

    Folder segments only, never the file name — a page is not assessed work
    because of what it is called.
    """
    segments = [piece for piece in re.split(r"[\\/]", str(relative_path)) if piece]
    folders = segments[:-1]
    if not was_configured:
        for segment in folders:
            if "task" in segment.lower():
                return True
        return False
    wanted = {str(name).lower() for name in (graded_folders or []) if name}
    for segment in folders:
        if segment.lower() in wanted:
            return True
    return False


def _is_class_page_path(relative_path, class_folders) -> bool:
    """
    Whether a page — given by its path RELATIVE to the content root — is one of
    the section's class pages.

    Not an `index.md`, and one of its FOLDER segments equals any of
    `class_folders`, case-insensitively. Either path separator is understood,
    because the same relative path arrives spelled either way depending on the
    platform that produced it.

    **Relative, never absolute.** This walked `page.parts` of an ABSOLUTE path
    — `content_root.rglob` yields absolute paths — so a teacher whose working
    folder was `~/Documents/All Classes` made every page in every course a
    class page. Where a teacher keeps their files is not a fact about their
    lessons.

    The file name is excluded as defence in depth rather than to fix an
    observed bug: under segment EQUALITY a file name cannot collide with a
    folder name, but a future change to prefix or substring matching must not
    silently start counting a page because of what it is CALLED.

    Pinned by contracts/class-planning.json -> classFolder.isClassPage.
    """
    if isinstance(class_folders, str):
        class_folders = [class_folders]
    text = str(relative_path)
    segments = [piece for piece in re.split(r"[\\/]", text) if piece]
    if not segments:
        return False
    if segments[-1].lower() == "index.md":
        return False
    wanted = {str(name).lower() for name in class_folders}
    for segment in segments[:-1]:
        if segment.lower() in wanted:
            return True
    return False


def resolve_include_curriculum_coverage(config: dict, section_number: int) -> bool:
    """
    Whether this SECTION wants the Curriculum Coverage map.

    `include_curriculum_coverage` is a per-section map of booleans
    (contracts/file-formats.json), and Windows writes it that way —
    `NewCourseDialog.cs` calls `PerSection(...)`, which produces an object. A
    plain `bool(config.get(...))` therefore reads EVERY Windows-made course as
    "coverage on", including one where the teacher said no, because a non-empty
    dict is truthy; and `{"sections": {}}` gets it wrong the other way.

    Follows resolve_show_section_marker's shape, which has been reading this
    kind of key correctly for a long time.
    """
    value = config.get("include_curriculum_coverage", True)
    if isinstance(value, dict):
        sec_key = f"section{section_number}"
        sections = value.get("sections")
        if isinstance(sections, dict) and sec_key in sections:
            return bool(sections[sec_key])
        if sec_key in value:
            return bool(value[sec_key])
        if "default" in value:
            return bool(value["default"])
        # A map that says nothing about this section: the feature is on by
        # default, the same answer a course with no key at all gets.
        return True
    return bool(value)


def _pages_the_course_teaches(content_root: Path, class_folders: list) -> set | None:
    """
    The pages a student actually reaches by following the schedule.

    A curriculum connection only counts when the page carrying it is
    taught: linked from a class page, or from a page a class page links
    to. That second hop is not a loophole — it is how courses are built.
    A class page's agenda links to the task; the task links to the
    reference page that carries the expectation, and the expectation was
    genuinely met by doing the task.

    Returns None when the course has no class pages at all, in which case
    the caller counts every published page — a map that hid everything
    would be worse than one that is slightly generous.
    """
    class_pages = {}
    for page in content_root.rglob("*.md"):
        if _is_class_page_path(page.relative_to(content_root), class_folders):
            class_pages[page.stem] = page
    if not class_pages:
        return None

    by_stem = {page.stem: page for page in content_root.rglob("*.md")}

    def links_from(page: Path) -> set:
        try:
            text = page.read_text(encoding="utf-8")
        except Exception:
            return set()
        outside_fences = re.sub(r"```[\s\S]*?```", "", text)
        return {match.group(1).strip().rstrip("\\").split("/")[-1]
                for match in BLOCK_LINK.finditer(outside_fences)}

    first_hop = set()
    for page in class_pages.values():
        first_hop |= links_from(page)
    second_hop = set()
    for stem in first_hop:
        if stem in by_stem:
            second_hop |= links_from(by_stem[stem])
    return set(class_pages) | first_hop | second_hop


def _coverage_counts(content_root: Path, curriculum_dir: Path, specific: dict,
                     class_folders: list, graded_folders: list,
                     graded_was_configured: bool):
    """
    How many pages address each expectation, and which of those are assessed.

    Coverage is counted from TRANSCLUSIONS — `![[A1.1]]` — because that is
    the form a curriculum connection takes: the expectation's own wording
    quoted on the page that addresses it. A piped inline mention
    (`[[A1.1|safe practice]]`) is prose referring to an expectation, not a
    claim to have covered it, and does not count.

    The `%%curriculum-start%%` markers that wrap those transclusions in a
    PAYLOAD are removed when the course is installed, so they cannot be
    what the map keys on — but where a teacher's own vault still has them,
    links inside them count too.

    Only PUBLISHED pages count. A page marked `publish: false` is not on
    the site a student can read, so it cannot have addressed anything yet —
    and a teacher who writes next week's lesson early should not see the map
    turn green before the class has happened. By the time this runs, the
    per-section keys have already been resolved (see `process_frontmatter`),
    so a page held back from one section is uncounted in that section's map
    and counted in the other's, which is the honest answer for each.

    A page counts once per expectation however many times it names it.

    And the page must be one the course actually TEACHES — reachable from
    a class page, directly or through one page a class page links to. A
    concept page written in August and never put in a class has not
    addressed anything yet, and the map should say so.
    """
    covered_by = {code: set() for code in specific}
    assessed_by = {code: set() for code in specific}
    taught = _pages_the_course_teaches(content_root, class_folders)
    for page in sorted(content_root.rglob("*.md")):
        if taught is not None and page.stem not in taught:
            continue
        if page.parent == curriculum_dir or curriculum_dir in page.parents:
            continue
        if page.name == f"{COVERAGE_PAGE_TITLE}.md":
            continue
        try:
            text = page.read_text(encoding="utf-8")
        except Exception:
            continue
        if _is_draft(text):
            continue
        relative = page.relative_to(content_root)
        # A page in a Tasks folder is assessed work — that is what makes an
        # overall expectation "evaluated" rather than merely "addressed".
        is_assessed = _is_graded_path(relative, graded_folders, graded_was_configured)

        targets = set()
        for link in TRANSCLUSION.finditer(text):
            targets.add(link.group(1).strip().rstrip("\\").split("/")[-1])
        for block in CURRICULUM_BLOCK.findall(text):
            for link in BLOCK_LINK.finditer(block):
                targets.add(link.group(1).strip().rstrip("\\").split("/")[-1])

        for target in targets:
            if target in covered_by:
                covered_by[target].add(relative.as_posix())
                if is_assessed:
                    assessed_by[target].add(relative.as_posix())
    return covered_by, assessed_by


# How a count reads in words — the legend's labels, and the wording a
# screen reader hears on a cell. Four or more is where the scale stops.
COVERAGE_WORDS = {
    0: "not yet addressed",
    1: "addressed once",
    2: "addressed twice",
    3: "addressed three times",
    4: "addressed four or more times",
}


def _coverage_cell(code: str, page: Path, content_root: Path, count: int, assessed: bool) -> str:
    """One cell: the expectation's code, coloured by how often it is addressed.

    The count is NOT printed. Fifty-odd cells each carrying a digit turns
    the map into a table of numbers, which is the one thing it is not for —
    the reading is the colour, and the exact count is a hover away. It
    still reaches a screen reader through the label, where it costs
    nothing.
    """
    level = min(count, 4)
    href = _quartz_slug(page.relative_to(content_root))
    marker = ' data-assessed="true"' if assessed else ""
    label = f"{code}, {COVERAGE_WORDS[level]}"
    if assessed:
        label += ", included in assessed work"
    return (f'<a class="internal coverage-cell coverage-{level}" href="{href}"{marker} '
            f'aria-label="{label}">'
            f'<span class="coverage-code">{code}</span></a>')


def build_curriculum_coverage(content_root: Path, course_code: str,
                             include_notes: bool = True,
                             class_folders: list = None,
                             graded_folders: list = None,
                             curriculum_folder_name: str = None,
                             graded_was_configured: bool = False,
                             first_class_stamp: str | None = None) -> bool:
    """
    Write the Curriculum Coverage page. Returns True when one was written.

    `include_notes` controls the two explanatory sections at the foot of
    the page — "What counts" and "Reading it honestly". They exist for a
    teacher meeting the map for the first time; a department that has
    already had that conversation can switch them off and keep the map,
    the legend, and the standings table.
    """
    curriculum_dir = _find_curriculum_folder(content_root, curriculum_folder_name)
    if not curriculum_dir:
        return False
    specific, overall = _collect_expectations(curriculum_dir)
    if not specific:
        return False

    if not class_folders:
        # Not a defaultable argument. An empty list matches no page, so
        # `_pages_the_course_teaches` returns None and the caller counts EVERY
        # published page — the "wrong map that reports success" this work
        # exists to close, reintroduced by a forgotten argument. The previous
        # hardcoded "All Classes" default was wrong-but-harmless for the 38
        # shipped payloads; this would be silently wrong for all of them.
        raise ValueError(
            "build_curriculum_coverage needs the course's class folders — "
            "pass class_folder_names(config). There is no safe default: the "
            "name is the teacher's to choose."
        )
    covered_by, assessed_by = _coverage_counts(content_root, curriculum_dir, specific,
                                               class_folders, graded_folders or [],
                                               graded_was_configured)
    folder = curriculum_dir.name

    strands = {}
    for code in specific:
        strands.setdefault(code[0], []).append(code)
    for letter in strands:
        strands[letter].sort(key=lambda code: (int(code.split(".")[0][1:]), int(code.split(".")[1])))

    columns = []
    for letter in sorted(strands):
        cells = []
        # The overall expectations of this strand, and whether an assessed
        # page addresses each one — through its own specifics or directly.
        chips = []
        for overall_code in sorted({code.split(".")[0] for code in strands[letter]},
                                   key=lambda code: int(code[1:])):
            evaluated = any(assessed_by.get(code) for code in strands[letter]
                            if code.startswith(overall_code + "."))
            page = overall.get(overall_code)
            state = "yes" if evaluated else "no"
            if page:
                href = _quartz_slug(page.relative_to(content_root))
                chips.append(f'<a class="internal coverage-chip coverage-chip-{state}" '
                             f'href="{href}">{overall_code}</a>')
            else:
                chips.append(f'<span class="coverage-chip coverage-chip-{state}">{overall_code}</span>')
        for code in strands[letter]:
            count = len(covered_by[code])
            cells.append(_coverage_cell(code, specific[code], content_root, count,
                                        bool(assessed_by[code])))
        columns.append(
            '<div class="coverage-strand">'
            f'<div class="coverage-letter">{letter}</div>'
            f'<div class="coverage-chips">{"".join(chips)}</div>'
            f'{"".join(cells)}'
            "</div>")

    total = len(specific)
    uncovered = [code for code in specific if not covered_by[code]]
    once = [code for code in specific if len(covered_by[code]) == 1]
    unevaluated = []
    for overall_code in sorted(overall, key=lambda code: (code[0], int(code[1:]))):
        related = [code for code in specific if code.startswith(overall_code + ".")]
        if related and not any(assessed_by[code] for code in related):
            unevaluated.append(overall_code)

    # The explanatory sections, which the teacher can switch off.
    # The page must describe THIS course's rule. It used to say "the Tasks
    # folder" whatever the teacher had chosen, so a course graded on "Tests"
    # got a page whose own explanation was wrong — and a teacher reading it
    # would reasonably conclude the map was broken.
    notes = COVERAGE_NOTES.replace(
        "{graded_folders}", _graded_folders_in_words(graded_folders, graded_was_configured)
    ) if include_notes else ""
    created_line = f"created: {first_class_stamp}\n" if first_class_stamp else ""

    body = f"""---
title: Curriculum Coverage
publish: true
{created_line}enableToc: true
---
Every expectation in {course_code}, coloured by how many pages address it.
The map is built from this site's own links each time the site is built, so
it cannot drift from the course.

<div class="coverage-panel">
<div class="coverage-map">{"".join(columns)}</div>
<hr class="coverage-rule">
<div class="coverage-legend">
<div class="coverage-legend-row"><span class="coverage-key coverage-0"></span><span class="coverage-legend-label">{COVERAGE_WORDS[0].capitalize()}</span></div>
<div class="coverage-legend-row"><span class="coverage-key coverage-1"></span><span class="coverage-legend-label">{COVERAGE_WORDS[1].capitalize()}</span></div>
<div class="coverage-legend-row"><span class="coverage-key coverage-2"></span><span class="coverage-legend-label">{COVERAGE_WORDS[2].capitalize()}</span></div>
<div class="coverage-legend-row"><span class="coverage-key coverage-3"></span><span class="coverage-legend-label">{COVERAGE_WORDS[3].capitalize()}</span></div>
<div class="coverage-legend-row"><span class="coverage-key coverage-4"></span><span class="coverage-legend-label">{COVERAGE_WORDS[4].capitalize()}</span></div>
<div class="coverage-legend-row"><span class="coverage-key coverage-2" data-assessed="true"></span><span class="coverage-legend-label">Included in assessed work — the cell carries a ring</span></div>
</div>
</div>

Hover any cell to preview the expectation. The row of small chips under
each strand letter is that strand's overall expectations: green when
assessed work addresses them, red when nothing marked does.

## Where this course stands

| | |
| --- | --- |
| Specific expectations | {total} |
| Not yet addressed | {len(uncovered)} |
| Addressed by exactly one page | {len(once)} |
| Overall expectations with no assessed work | {len(unevaluated)} |

{notes}"""
    (content_root / f"{COVERAGE_PAGE_TITLE}.md").write_text(body, encoding="utf-8")
    print(f"🗺️  Curriculum Coverage: {total} expectations, {len(uncovered)} not yet addressed, "
          f"{len(unevaluated)} overall expectation(s) without assessed work.")
    return True


def set_backlinks_structural_pages(backlinks_tsx_path: Path, content_root: Path,
                                   curriculum_folder_name: str = None):
    """
    Tell the backlinks panel which pages reference everything by design.

    "When did we do this?" is meant to answer which lessons touched a
    page. The curriculum folder's index transcludes every expectation and
    the generated coverage map links every expectation, so both appear as
    a backlink on every single expectation page — noise that hides the
    lessons underneath. This writes their names into Backlinks.tsx, the
    same way the Explorer's omit set is written, so the component filters
    them out without hard-coding a folder name that teachers rename.
    """
    if not backlinks_tsx_path.exists():
        return
    curriculum_dir = _find_curriculum_folder(content_root, curriculum_folder_name)
    # Both forms: the folder is matched by name, but a page is matched by
    # its SLUG, and Quartz slugs replace spaces with hyphens. Writing only
    # the title left the coverage map in the panel it was meant to leave.
    names = [COVERAGE_PAGE_TITLE, COVERAGE_PAGE_TITLE.replace(" ", "-")]
    if curriculum_dir:
        names.append(curriculum_dir.name)
        names.append(curriculum_dir.name.replace(" ", "-"))
    formatted = ", ".join(f'"{name}"' for name in names)
    text = backlinks_tsx_path.read_text(encoding="utf-8")
    pattern = re.compile(
        r'(?P<anchor>^[ \t]*//[ \t]*CQ4T-STRUCTURAL-ANCHOR:.*?\n)?'
        r'[ \t]*const[ \t]+structural[ \t]*=[ \t]*new[ \t]+Set'
        r'(?:<[^>]*>)?[ \t]*\([ \t]*\[[\s\S]*?\][ \t]*\)[ \t]*;?',
        re.MULTILINE)

    def replace(match):
        anchor = match.group("anchor") or ""
        indent = "    "
        return f'{anchor}{indent}const structural = new Set<string>([{formatted}])'

    updated, count = pattern.subn(replace, text)
    if count:
        backlinks_tsx_path.write_text(updated, encoding="utf-8")
        print(f"✅ Backlinks panel will skip: {', '.join(names)}")


def link_coverage_from_key_links(content_root: Path, curriculum_folder_name: str = None):
    """
    Put the coverage page in Key Links, directly under the curriculum entry.

    Written into the BUILT copy only: the teacher's own Key Links page is
    theirs, and a line that reappears every build would be infuriating.

    The curriculum entry is found by where it POINTS — a link into the
    curriculum folder — rather than by its wording. Teachers rename these
    links ("Curriculum expectations", "Ontario Curriculum", "The
    expectations"), and matching on text meant the example course, whose
    link differed by one lower-case letter, silently never got the map in
    its Key Links. Falls back to appending at the end.
    """
    key_links = content_root / "Key Links.md"
    if not key_links.exists():
        return
    text = key_links.read_text(encoding="utf-8")
    if f"[[{COVERAGE_PAGE_TITLE}]]" in text:
        return

    curriculum_dir = _find_curriculum_folder(content_root, curriculum_folder_name)
    folder = curriculum_dir.name if curriculum_dir else None
    lines = text.split("\n")
    target_index = None
    for index, line in enumerate(lines):
        if not line.lstrip().startswith("- "):
            continue
        points_at_curriculum = folder and f"[[{folder}/" in line
        if points_at_curriculum or "curriculum expectations]]" in line.lower():
            target_index = index
    if target_index is None:
        # No curriculum entry to sit under: put it after the last bullet.
        bullets = [i for i, line in enumerate(lines) if line.lstrip().startswith("- ")]
        if not bullets:
            return
        target_index = bullets[-1]
    lines.insert(target_index + 1, f"- [[{COVERAGE_PAGE_TITLE}]]")
    key_links.write_text("\n".join(lines), encoding="utf-8")


def build_section_site(
    course_code: str,
    section_number: int,
    include_social_media_previews: bool,
    force_npm_install: bool,
    full_rebuild: bool,
    build_only: bool,       # NEW: if True, do a single static build; if False (default), preview (serve) without extra build

    port: int = 8081,
):
    base_dir = toolchain_paths.COURSES_DIR
    course_dir = base_dir / course_code
    section_name = f"section{section_number}"

    visible_output_root = course_dir / "merged_output"
    hidden_output_root = toolchain_paths.merged_output_root(course_dir)

    if visible_output_root.exists() and not hidden_output_root.exists():
        try:
            print(f"📦 Migrating existing output '{visible_output_root.name}' → '{hidden_output_root.name}'...")
            visible_output_root.rename(hidden_output_root)
            print("✅ Migration complete.")
        except Exception as e:
            print(f"⚠️ Migration failed (will continue using hidden target): {e}")

    host_output_dir = hidden_output_root / section_name
    host_output_dir.mkdir(parents=True, exist_ok=True)

    # Use fast container-local ext4 storage (/tmp/quartz-builds/<COURSE>/section<N>)
    # for the build workspace so that node_modules, AST walks, and esbuild run at native
    # speed without crossing the slow 9P/virtiofs host bind mount.
    output_dir = toolchain_paths.WORK_DIR / course_code / section_name
    config_file = course_dir / "course_config.json"

    if not course_dir.exists():
        print(f"❌ Course folder '{course_code}' not found in {base_dir}")
        return
    if not (course_dir / section_name).exists():
        print(f"❌ Section folder '{section_name}' not found in {course_dir}")
        print("   Tip: run setup.sh again and include this section number in your timetable sections.")
        return
    if not config_file.exists():
        print(f"❌ course_config.json not found in {course_dir}")
        return

    section_dir = course_dir / section_name

    with open(config_file, "r", encoding="utf-8") as f:
        config = json.load(f)

    # Validate the requested section number against timetable sections
    allowed_sections = get_allowed_section_numbers(config)
    print(f"📋 Timetable sections for this course: {allowed_sections}")
    if not validate_requested_section(allowed_sections, section_number):
        return

    # === Preflight discovery → append into course_config.json =================
    print("\n🔎 Preflight: discovering new shared and per-section items...")
    config = preflight_update_course_config(course_dir, section_dir, config_file) or config
    # ========================================================================

    # What this course calls a unit, before anything asks what a class page is.
    # Set once here rather than passed through every caller — one process
    # builds one section of one course, so there is only ever one answer.
    chosen_unit_word = set_unit_word(unit_word_from_config(config))
    if chosen_unit_word != DEFAULT_UNIT_WORD:
        print(f"📘 This course calls its units “{chosen_unit_word}”, so a class page is "
              f"“{chosen_unit_word} 2, Day 3”.")

    shared_folders = config.get("shared_folders", [])
    shared_files = config.get("shared_files", [])
    per_section_folders = config.get("per_section_folders", [])
    per_section_files = config.get("per_section_files", [])
    hidden_list = config.get("hidden", [])
    # teacher preference for reading-time
    show_reading_time = bool(config.get("show_reading_time", False))
    # NEW: per-section section-marker preference (used for header and index title)
    show_marker = resolve_show_section_marker(config, section_number)

    # Exclude 'Media' from shared folder processing (we symlink it)
    if any(_is_media_name(name) for name in shared_folders):
        print("ℹ️ Skipping 'Media' in shared folders (handled via symlink).")
    shared_paths = [course_dir / folder for folder in _filter_out_media(shared_folders)]

    print(f"\n📁 Shared folders to include for '{section_name}':")
    for folder in shared_paths:
        print(f" - {folder.name}")

    quartz_src = toolchain_paths.QUARTZ_DIR

    # Fresh/full rebuild path
    if full_rebuild or not output_dir.exists():
        if output_dir.exists():
            print(f"\n🧹 Full rebuild: clearing output directory at: {output_dir}")
            shutil.rmtree(output_dir)
        output_dir.mkdir(parents=True, exist_ok=True)
        print(f"📂 Created fresh (internal) output directory: {output_dir}")

        print(f"📦 Staging the website builder's files from {quartz_src}...")
        for item in quartz_src.iterdir():
            dest = output_dir / item.name
            if item.name == "node_modules":
                # link_directory, not os.symlink: symlinks need privileges a
                # school-managed Windows account lacks, and the old fallback
                # silently copied ~430 MB of dependencies per section.
                how = toolchain_paths.link_directory(item, dest)
                if how == "copy":
                    print("  (node_modules copied rather than linked - links need privileges this account lacks)")
            elif item.is_dir():
                shutil.copytree(item, dest, symlinks=False)
                print(f"  📁 Copied directory: {item.name}")
            else:
                shutil.copy2(item, dest)
                print(f"  📄 Copied file: {item.name}")

        # Remove Graph once on first build / full rebuild
        remove_graph_from_right(output_dir / "quartz.layout.ts")

        install_locales(output_dir)

        # Adjust CreatedModifiedDate priority on first build/full rebuild
        config_path = output_dir / "quartz.config.ts"
        adjust_created_modified_priority(config_path)
        patch_default_date_type(config_path)

        # Patch folder page & defaults on first build/full rebuild
        folder_page_tsx = output_dir / "quartz" / "plugins" / "emitters" / "folderPage.tsx"
        patch_folder_page_title(folder_page_tsx)

        folder_content_tsx = output_dir / "quartz" / "components" / "pages" / "FolderContent.tsx"
        patch_folder_content_defaults(folder_content_tsx)
        
        # Patch Date.tsx date format & listPage.scss meta width
        date_tsx = output_dir / "quartz" / "components" / "Date.tsx"
        patch_date_format(date_tsx)

        list_page_scss = output_dir / "quartz" / "components" / "styles" / "listPage.scss"
        patch_list_page_meta_width(list_page_scss)
        
        # Patch base.scss + append styles
        base_scss = output_dir / "quartz" / "styles" / "base.scss"
        patch_internal_link_highlight(base_scss)
        append_transclusion_styles(base_scss)

        # Patch renderPage.tsx for transcludeTitleSize
        render_page_tsx = output_dir / "quartz" / "components" / "renderPage.tsx"
        patch_render_page_transclude_title(render_page_tsx)

        # Apply selected fonts (if configured)
        fonts_cfg = config.get("fonts", {})
        section_key = f"section{section_number}"
        section_fonts = (fonts_cfg.get("sections") or {}).get(section_key) or fonts_cfg.get("default")

        if section_fonts:
            patch_typography_fonts(
                quartz_config_path=config_path,
                header_font=section_fonts.get("header", "Schibsted Grotesk"),
                body_font=section_fonts.get("body", "Source Sans Pro"),
                code_font=section_fonts.get("code", "IBM Plex Mono"),
            )
        else:
            print("ℹ️ No font selections found in course_config.json — leaving Quartz defaults.")

        use_publish_filter(config_path)

        # NEW: copy/symlink .netlify into output so deploy CLI can diff (later step)
        _ensure_netlify_link(output_dir, course_dir)

    else:
        print(f"♻️ Reusing existing (hidden) output directory: {output_dir}")
        base_scss = output_dir / "quartz" / "styles" / "base.scss"

    # ALWAYS: Fix Netlify static import target
    _copy_course_config_into_quartz(course_dir, output_dir)
    _patch_quartz_imports_to_local_config(output_dir / "quartz")

    # Apply teacher preference to ContentMeta on each build
    content_meta_tsx = output_dir / "quartz" / "components" / "ContentMeta.tsx"
    patch_content_meta_options(content_meta_tsx, show_reading_time)

    # Mermaid diagram fixes, applied on EVERY build rather than only on a
    # full rebuild, so a course folder created before these existed heals
    # itself the next time it is previewed. Both are idempotent and cheap.
    append_mermaid_styles(base_scss)
    append_sidebar_sharing_styles(base_scss)
    append_page_title_styles(base_scss)
    mermaid_ts = output_dir / "quartz" / "components" / "scripts" / "mermaid.inline.ts"
    theme_ts = output_dir / "quartz" / "util" / "theme.ts"
    head_tsx = output_dir / "quartz" / "components" / "Head.tsx"
    patch_google_font_href(theme_ts, head_tsx)
    append_coverage_styles(output_dir / "quartz" / "styles" / "base.scss")
    latex_ts = output_dir / "quartz" / "plugins" / "transformers" / "latex.ts"
    patch_katex_mhchem(latex_ts)
    patch_mermaid_font_wait(mermaid_ts)
    patch_mermaid_pie_title_fit(mermaid_ts)
    patch_mermaid_pie_colours(mermaid_ts)

    # Patch Explorer expansion behaviour (idempotent)
    explorer_tsx = output_dir / "quartz" / "components" / "Explorer.tsx"
    explorer_inline = output_dir / "quartz" / "components" / "scripts" / "explorer.inline.ts"
    patch_explorer_tsx_expand_behavior(explorer_tsx)
    patch_explorer_inline_expand_on_navigate(explorer_inline)

    install_patched_backlinks(output_dir)
    patch_quartz_build_clean(output_dir / "quartz" / "build.ts")

    content_root = output_dir / "content"
    if content_root.exists():
        print(f"\n🧹 Clearing previous content folder at: {content_root}")
        shutil.rmtree(content_root)
    content_root.mkdir(exist_ok=True)
    print(f"📂 Created fresh content folder: {content_root}")

    # Ensure Media symlink is present inside content/
    _ensure_media_symlink(content_root, course_dir)

    # The site's own icon, into quartz/static AND the content root. Placed
    # here because the content root is rebuilt from scratch just above, so a
    # copy made any earlier would have been thrown away.
    install_favicon(output_dir, content_root)

    section_index = section_dir / "index.md"
    if section_index.exists():
        dest = content_root / "index.md"
        shutil.copy2(section_index, dest)
        process_frontmatter(dest, section_number)

        # The landing title comes from the current settings, not from
        # whatever was baked in at scaffold time.
        set_landing_title(dest, config, section_number, show_marker)

        # rewrite section-path wikilinks in the section index
        print("🔍 Checking for wikilinks to rewrite in content/index.md...")
        rewrite_section_wikilinks(dest)
        print(f"  🏠 Copied section index.md to content/index.md")
    else:
        print("⚠️ Section index.md not found — site may not render correctly.")

    # Copy shared folders
    print(f"\n📥 Copying shared folders into {content_root}...")
    for src_folder in shared_paths:
        print(f"🔍 Processing: {src_folder}")
        for root, dirs, files in os.walk(src_folder):
            rel_path = Path(root).relative_to(course_dir)
            dest_path = content_root / rel_path
            dest_path.mkdir(parents=True, exist_ok=True)
            for file in files:
                src_file = Path(root) / file
                dest_file = dest_path / file
                shutil.copy2(src_file, dest_file)
                process_frontmatter(dest_file, section_number)

    # Copy shared files
    print(f"\n📥 Copying shared files into {content_root}...")
    for file_name in shared_files:
        src = course_dir / file_name
        dest = content_root / file_name
        if src.exists():
            shutil.copy2(src, dest)
            process_frontmatter(dest, section_number)
            print(f"  📄 Copied shared file: {file_name}")

    # Copy per-section folders
    print(f"\n📥 Copying per-section folders...")
    for folder in per_section_folders:
        src = section_dir / folder
        dest = content_root / folder
        if src.exists():
            shutil.copytree(src, dest, dirs_exist_ok=True)
            for root, dirs, files in os.walk(dest):
                for file in files:
                    fp = Path(root) / file
                    process_frontmatter(fp, section_number)
                    if fp.suffix.lower() == ".md":
                        rewrite_section_wikilinks(fp)
            print(f"  📁 Copied per-section folder: {folder}")

    # Copy per-section files
    print(f"\n📥 Copying per-section files...")
    for file_name in per_section_files:
        src = section_dir / file_name
        dest = content_root / file_name
        if src.exists():
            shutil.copy2(src, dest)
            process_frontmatter(dest, section_number)
            print("🔍 Checking for wikilinks to rewrite in per-section loose files...")
            rewrite_section_wikilinks(dest)
            print(f"  📄 Copied per-section file: {file_name}")


    # === Health of the folders this course depends on =========================
    # Here, and not earlier, because every check is defined over the MERGED
    # tree, which only exists once the copying above has finished — and before
    # Quartz builds, so a teacher is told before a site is produced from it.
    #
    # NOT a complete guard on publishing: `deploy.py` uploads an EXISTING
    # `public/` and only rebuilds when a live preview is attached, and
    # `deploy.sh --to-folder` rsyncs on the host without entering the Python at
    # all. So a deploy of a build made in an earlier session carries no health
    # output of its own. What makes that acceptable is that the findings are
    # recorded when the build happens; what would NOT be acceptable is claiming
    # otherwise, which an earlier version of this comment did.
    class_folders_here = class_folder_names(config)
    graded_folders_here, graded_was_configured_here = graded_folder_names(config)
    coverage_wanted = resolve_include_curriculum_coverage(config, section_number)
    curriculum_folder_name_here = config.get("curriculum_folder") or None
    curriculum_dir_here = _find_curriculum_folder(content_root, curriculum_folder_name_here)

    # Worked out once and reused by the coverage builder below: this crawl
    # rglobs every page and reads every class page and every first-hop page,
    # and running it twice per build was pure waste.
    taught_here = _pages_the_course_teaches(content_root, class_folders_here)

    health_facts = {
        "coverage_wanted": coverage_wanted,
        "curriculum_found": curriculum_dir_here is not None,
        "class_pages_found": taught_here is not None,
        "graded_folders_found": _has_graded_folders(
            content_root, graded_folders_here, graded_was_configured_here
        ),
        # The COURSE-level folder, not content/Media: that one is recreated on
        # every build a few hundred lines above, so checking it always passes.
        # What actually breaks is the folder it points AT.
        "media_target_exists": (course_dir / "Media").is_dir(),
        "section_index_exists": (content_root / "index.md").exists(),
        # Anything by this name at this moment came from the teacher's own
        # notes: the build writes its own copy further down, so a page here now
        # is one that is about to be overwritten.
        "hand_written_coverage_page": (
            content_root / f"{COVERAGE_PAGE_TITLE}.md").exists(),
    }
    site_health.announce_or_stay_quiet(health_facts, course_code, section_number)

    # A section with no front page produces no root index.html, so this build
    # cannot replace the one already sitting on the host. Clear it here rather
    # than in the sync, because BOTH modes need it: a preview never reaches the
    # sync at all (its watcher waits on an index.html that never appears), and
    # a publish from the command line after a preview would otherwise upload
    # the older pages.
    if not health_facts["section_index_exists"]:
        _clear_stale_host_site(host_output_dir, course_code, section_number)

    # === Curriculum coverage heat map =========================================
    first_class_dt = _find_first_class_created(content_root)
    first_class_stamp = _format_created_timestamp_from_dt(first_class_dt) if first_class_dt else None

    if coverage_wanted:
        # The explanatory sections are a separate choice, and one that only
        # exists while the map does.
        if build_curriculum_coverage(
                content_root, course_code,
                class_folders=class_folders_here,
                graded_folders=graded_folders_here,
                graded_was_configured=graded_was_configured_here,
                curriculum_folder_name=curriculum_folder_name_here,
                include_notes=bool(config.get("include_coverage_notes", True)),
                first_class_stamp=first_class_stamp):
            link_coverage_from_key_links(content_root, curriculum_folder_name_here)
    else:
        print("ℹ️ Curriculum Coverage page is switched off for this course.")
    set_backlinks_structural_pages(
        output_dir / "quartz" / "components" / "Backlinks.tsx", content_root,
        curriculum_folder_name_here)
    # ==========================================================================

    # === Post-pass — sync 'created' timestamps for non-class pages =============
    print("\n📆 Post-processing: syncing 'created' for non-class pages (sidebar, Key Links, Curriculum)...")
    if first_class_dt is None:
        print("ℹ️ No parseable class dates found in this section — leaving non-class pages unchanged.")
    else:
        updated, total = _sync_non_class_pages_created(content_root, first_class_dt)
        print(f"📆 Synced non-class pages 'created' → {first_class_stamp} for {updated} file(s) ({total} non-class file(s) in total).")
    # ===========================================================================

    # Copy course config into output root (back-compat)
    shutil.copy2(config_file, output_dir / "course_config.json")
    print("✅ Copied course_config.json to output directory (root copy)")

    # Update Quartz layout & footer
    quartz_layout_ts = output_dir / "quartz.layout.ts"
    quartz_footer_tsx = output_dir / "quartz/components/Footer.tsx"
    # HARDENING: the hide filter must exist. A build that cannot guarantee it
    # is a build that would publish pages the teacher hid, so it stops here
    # rather than producing a site that looks finished and is not.
    if not ensure_quartz_layout_anchor(quartz_layout_ts):
        print()
        print("❌ Refusing to build: the Explorer's hide filter could not be")
        print("   established, so anything you have hidden would appear on")
        print("   your site. Run setup.sh for this course to restore it.")
        sys.exit(1)

    # ensure 'Media' is always hidden in Explorer omit set — checked in any
    # spelling, or a config that already says "media" would gain a SECOND entry
    # for the same directory every build.
    if not any(_is_media_name(name) for name in hidden_list):
        hidden_list.append("Media")

    # The Curriculum Coverage page is reached from Key Links, deliberately.
    # It is a teacher's instrument rather than a place students navigate to,
    # and it sits at the content root, so without this it would appear in
    # the sidebar above the folders — the most prominent position on the
    # site, for the page that needs it least.
    if COVERAGE_PAGE_TITLE not in hidden_list:
        hidden_list.append(COVERAGE_PAGE_TITLE)

    update_quartz_layout(quartz_layout_ts, hidden_list)  # ensure omit is present and updated
    
    # honor expandOnFolderClick from course_config.json
    expand_on_name = bool(config.get("expandOnFolderClick", False))
    patch_folder_click_behavior(quartz_layout_ts, expand_on_name)
    
    footer_html = config.get("footer_html", "")
    inject_custom_footer_components(quartz_layout_ts, quartz_footer_tsx, footer_html)

    # Update page title (now with per-section emoji and optional section marker)
    config_path = output_dir / "quartz.config.ts"
    page_emoji = resolve_section_emoji(config, section_number)
    header_label = resolve_header_label(config, course_code)
    update_page_title(config_path, header_label, section_number, page_emoji, show_marker)
    patch_default_date_type(config_path)

    # --- ADD: PATCH LOCALE in quartz.config.ts based on course_config.json ----
    locale_code = (config.get("locale") or "en-US").strip() or "en-US"
    patch_quartz_locale(config_path, locale_code)
    # --------------------------------------------------------------------------

    # --- ADD: PATCH baseUrl in quartz.config.ts based on section deploy domain ---
    section_domain = resolve_section_domain(course_dir, config, section_number)
    patch_quartz_base_url(config_path, section_domain)
    # --------------------------------------------------------------------------

    # Ensure patched Head.tsx is present in output_dir so social cards never point to quartz.jzhao.xyz
    head_src = toolchain_paths.QUARTZ_DIR / "quartz" / "components" / "Head.tsx"
    head_dst = output_dir / "quartz" / "components" / "Head.tsx"
    if head_src.is_file() and head_dst.parent.is_dir():
        try:
            shutil.copy2(head_src, head_dst)
        except Exception as e:
            print(f"⚠️ Could not copy patched Head.tsx: {e}")

    # Apply per-section colour scheme, if configured
    color_map = config.get("color_schemes", {})
    section_key = f"section{section_number}"
    chosen_scheme_id = color_map.get(section_key)
    if chosen_scheme_id:
        schemes = load_colour_schemes()
        scheme = find_scheme_by_id(schemes, chosen_scheme_id)
        if scheme and "colors" in scheme:
            apply_color_scheme_to_quartz_config(config_path, scheme["colors"])
            print(f"🎨 Applied colour scheme for {section_key}: {scheme.get('name', chosen_scheme_id)}")
        else:
            print(f"⚠️ Scheme '{chosen_scheme_id}' not found or missing 'colors' — leaving default Quartz colors.")
    else:
        print(f"ℹ️ No colour scheme selected for {section_key} — leaving default Quartz colors.")

    # Toggle CustomOgImages emitter
    if config_path.exists():
        toggle_custom_og_images(str(config_path), include_social_media_previews)
    else:
        print("Warning: quartz.config.ts not found to toggle CustomOgImages")

    # ---- Social sharing card -------------------------------------------
    # Drawn fresh on every build, so changes to the course name, scheme,
    # fonts, emoji, or marker setting always reach the card. Written over
    # Quartz's default og-image, which the site's head already links —
    # and never allowed to fail a build: a site without a custom card
    # still has the stock one.
    try:
        import social_card
        card_path = output_dir / "quartz" / "static" / "og-image.png"
        social_card.generate_card(
            course_config=config,
            section_number=section_number,
            output_path=card_path,
        )
        print(f"🖼️  Social sharing card drawn for {section_key}.")
    except Exception as e:
        print(f"⚠️ Could not draw the social sharing card: {e}")

    # Ensure npm dependencies are present (linking pre-baked node_modules if available)
    node_modules_dir = output_dir / "node_modules"
    # A junction left by an older build dies on the very next stat (WinError
    # 448) - repair BEFORE the exists() below ever touches it.
    if toolchain_paths.remove_stale_reparse_point(node_modules_dir):
        print("♻️ Replaced an older-style dependency link.")
    package_json = output_dir / "package.json"
    package_lock = output_dir / "package-lock.json"

    needs_install = (
        force_npm_install or
        not node_modules_dir.exists()
    )

    if needs_install:
        if (toolchain_paths.QUARTZ_DIR / "node_modules").exists() and not force_npm_install:
            print("📦 Linking pre-baked dependencies from image...")
            if node_modules_dir.exists() or node_modules_dir.is_symlink():
                try:
                    node_modules_dir.unlink()
                except Exception:
                    shutil.rmtree(node_modules_dir, ignore_errors=True)
            how = toolchain_paths.link_directory(toolchain_paths.QUARTZ_DIR / "node_modules", node_modules_dir)
            if how == "copy":
                print("   (copied rather than linked - links need privileges this account lacks)")
        else:
            print("\n📦 Installing dependencies...")
            subprocess.run([toolchain_paths.NPM, "install", "--no-audit", "--silent"], cwd=output_dir, check=True)
    else:
        print("✅ Skipping npm install (dependencies already present)")

    # ===========================
    # Build or Preview (server?)
    # ===========================
    # The scaffold's own CLI by ABSOLUTE path: `npx quartz` resolves the
    # CLI from the npm registry (a project's own bin is never linked into
    # its node_modules/.bin), which needs network and floats the version.
    # The absolute path also puts the section's work dir on the serve
    # process's command line - what the native stop matches on.
    env = os.environ.copy()
    env.setdefault("TZ", "UTC")
    env.setdefault("SOURCE_DATE_EPOCH", "1704067200")  # 2024-01-01T00:00:00Z

    if build_only:
        # A preview for THIS section may still be serving, and it does not stop
        # when the launcher that started it is killed: the Python and the node
        # server both live inside the container, and `_start_public_sync_watcher`
        # keeps mirroring the SERVE build to the host every second. A build for
        # publishing that runs alongside one is therefore overwritten within a
        # second of finishing — the production pages land on the host and the
        # preview's pages replace them, so what gets published is the preview,
        # live-reload client and all.
        #
        # The APP never meets this, because publishing stops an active preview
        # first. From the command line nothing did, and `deploy.sh`'s own
        # rebuild-before-publishing lost this race every time. Stopping the
        # preview here fixes it for every caller at once, and matches what the
        # app already does rather than inventing a second rule.
        #
        # Matched by this section's OWN BUILD DIRECTORY, never by port.
        #
        # The first version of this killed `port`, and `port` is 8081 for every
        # build-only run: `preview.sh` defaults it and the app's deploy passes
        # no `--port` at all. So it killed whatever was serving on 8081 — the
        # first section to have started previewing in this working folder,
        # which is usually a DIFFERENT section from the one being published.
        # Previewing section 1 while publishing section 2 took section 1's
        # preview down, in the exact multi-section workflow the app is built
        # around. Measured 2026-09-05 by doing it: "Killed existing process on
        # port 8081", and section 1 stopped answering.
        #
        # The section's build directory is on the serve process's command line
        # (the launcher runs the scaffold's CLI by absolute path, which is why
        # it is there), so it identifies exactly one preview and cannot collide
        # with another. The trailing separator matters: without it `section1`
        # would also match `section10`.
        stop_preview_serving(output_dir)

        # Static build ONLY (single build)
        print("\n🏗️  Building static site with Quartz → public/")
        safe_clean_public_dir(output_dir / "public")
        subprocess.run(["node", str(output_dir / "quartz" / "bootstrap-cli.mjs"), "build", "--concurrency", "1"], cwd=output_dir, env=env, check=True)

        public_dir = output_dir / "public"
        if not public_dir.exists():
            print("❌ Quartz build did not emit a 'public' directory — cannot deploy.")
            sys.exit(1)
        # "Static build complete" used to be printed either way. It is the
        # sentence that sent teachers round in a circle: the build said it had
        # finished, `deploy` then said "Built site not found — build first",
        # and they had just built. A build that produced nothing publishable
        # now says so and FAILS, so a publish stops at the build with the
        # reason in front of it instead of at the step that cannot know why.
        if _sync_public_to_host(output_dir, host_output_dir):
            print("✅ Static build complete.")
        else:
            print(f"❌ Nothing to publish for {course_code} Section {section_number}: "
                  f"it has no front page, so no website was produced.")
            print("   Put the front page back — Plantoir offers to do that for "
                  "you — then build again.")
            sys.exit(1)
    else:
        # Preview mode (default): do NOT pre-build. Build+serve once.
        # Quartz's dev server opens TWO ports: the site, and a live-reload
        # websocket (default 3001). Both must be per-preview or two serves
        # collide on the websocket even with distinct site ports.
        ws_port = port + 1000
        kill_existing_quartz(port)
        kill_existing_quartz(ws_port)
        if os.name == "nt":
            # Natively, ports are HOST-GLOBAL and the launcher's probe ran
            # minutes ago, before the build - two folders building at once
            # both get told 8081 and the loser dies on EADDRINUSE. Probe
            # again here, moments before the bind, walking the same
            # 10-apart blocks; the app follows the LAST announced address,
            # so the re-announcement below is the one that counts. (In the
            # container the port is a fixed mapping - never walk it there.)
            import socket

            def _port_is_free(candidate: int) -> bool:
                try:
                    with socket.socket(socket.AF_INET, socket.SOCK_STREAM) as probe:
                        probe.bind(("", candidate))
                    return True
                except OSError:
                    return False

            for candidate in range(port, port + 60, 10):
                if _port_is_free(candidate) and _port_is_free(candidate + 1000):
                    if candidate != port:
                        print(f"Port {port} is busy with another preview; using {candidate} instead.")
                        port = candidate
                        ws_port = port + 1000
                    break
            print(f"Preview will be available at: http://localhost:{port}/")
        print(f"\n🚀 Launching Quartz preview on http://localhost:{port}\n")
        safe_clean_public_dir(output_dir / "public")
        _start_public_sync_watcher(output_dir, host_output_dir)
        subprocess.run(["node", str(output_dir / "quartz" / "bootstrap-cli.mjs"), "build", "--concurrency", "1", "--serve", "--port", str(port), "--wsPort", str(ws_port)], cwd=output_dir, env=env, check=True)

def main():
    parser = argparse.ArgumentParser(description="Build Quartz site for a course section (preview by default; use --build-only for a static build without preview).")
    parser.add_argument("--course", required=True, help="Course code (e.g., ICS3U)")
    parser.add_argument("--section", required=True, type=int, help="Timetable section number (e.g., 1, 3, 4)")
    parser.add_argument("--include-social-media-previews", action="store_true", help="Enable social media preview images via CustomOgImages emitter")
    parser.add_argument("--force-npm-install", action="store_true", help="Force npm install even if dependencies are present")
    parser.add_argument("--full-rebuild", action="store_true", help="Clear the full output folder and re-copy Quartz scaffold")
    # NEW: default is preview; this flag switches to a plain static build
    parser.add_argument("--build-only", action="store_true", help="Build the static site only (no preview server)")
    parser.add_argument("--port", type=int, default=8081, help="Port for the preview server (default 8081)")
    parser.add_argument("--host-os", choices=["windows","mac","linux","unknown"], default="unknown", help="Host OS passed by preview.sh/preview.ps1")
    args = parser.parse_args()
    _HOST_OS = getattr(args, 'host_os', 'unknown')

    build_section_site(
        course_code=args.course,
        section_number=args.section,
        include_social_media_previews=args.include_social_media_previews,
        force_npm_install=args.force_npm_install,
        full_rebuild=args.full_rebuild,
        build_only=args.build_only,
        port=args.port,
    )

if __name__ == "__main__":
    main()
