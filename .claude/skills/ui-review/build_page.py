#!/usr/bin/env python3
"""Build the v2.0.0 interface review page from content.json and the shots manifest.

Usage: python3 build_page.py
Writes index.html beside this file, and files.json: the map of published
path -> source path for every picture the page uses.
"""
import html
import json
import os
import re

HERE = os.path.dirname(os.path.abspath(__file__))
SHOTS = os.path.join(HERE, "shots")


def esc(text):
    return html.escape(str(text), quote=True)


def inline(text):
    """Escape, then turn `code` into <code> and **bold** into <strong>."""
    out = esc(text)
    out = re.sub(r"`([^`]+)`", r"<code>\1</code>", out)
    out = re.sub(r"\*\*([^*]+)\*\*", r"<strong>\1</strong>", out)
    return out


# ---------------------------------------------------------------- the data

features = json.load(open(os.path.join(HERE, "content.json"), encoding="utf-8"))
if isinstance(features, dict):
    features = features.get("features", [])

manifest_path = os.path.join(SHOTS, "manifest.json")
scenes = []
if os.path.exists(manifest_path):
    raw = json.load(open(manifest_path, encoding="utf-8"))
    scenes = raw if isinstance(raw, list) else raw.get("scenes", raw.get("shots", []))

notes_path = os.path.join(HERE, "observations.json")
observations = json.load(open(notes_path, encoding="utf-8")) if os.path.exists(notes_path) else {}

# Which feature a scene belongs to: the manifest's own `feature` text is
# matched against these words.
FEATURE_WORDS = [
    ("sharing-unit-plans", ["share", "sharing", "709"]),
    ("planning-tab", ["planning", "plan", "708", "803"]),
    ("coverage-tab", ["coverage", "793"]),
    ("reference-shelf", ["reference", "shelf", "group", "replace", "wizard", "import", "572"]),
    ("deploy-held-elsewhere", ["deploy", "greyed", "grey", "lease", "729"]),
    ("geogebra-sketches", ["geogebra", "sketch", "756", "792"]),
    ("quiet-changes", ["name", "add-on", "obsidian", "scheduled", "768", "780", "742", "748"]),
    ("marking-proposal", ["marking", "launcher", "750"]),
]


def feature_of(scene):
    explicit = str(scene.get("featureId", "")).strip()
    if explicit:
        return explicit
    named = str(scene.get("feature", "")).lower()
    for fid, words in FEATURE_WORDS:
        for word in words:
            if word in named:
                return fid
    hay = " ".join(str(scene.get(k, "")) for k in ("feature", "issue", "title", "file")).lower()
    for fid, words in FEATURE_WORDS:
        for word in words:
            if word in hay:
                return fid
    return "quiet-changes"


def pick(scene, kind, mode):
    """The file for a scene in one kind (raw|annotated) and mode (light|dark), or None."""
    candidates = []
    caps = scene.get("captures")
    if isinstance(caps, dict) and isinstance(caps.get(mode), dict) and caps[mode].get(kind):
        candidates.append(caps[mode][kind])
    for key in (f"{kind}{mode.capitalize()}", f"{kind}_{mode}", f"{mode}{kind.capitalize()}"):
        if scene.get(key):
            candidates.append(scene[key])
    block = scene.get(kind)
    if isinstance(block, dict) and block.get(mode):
        candidates.append(block[mode])
    block = scene.get(mode)
    if isinstance(block, dict) and block.get(kind):
        candidates.append(block[kind])
    files = scene.get("files")
    if isinstance(files, dict):
        inner = files.get(mode) or files.get(kind)
        if isinstance(inner, dict):
            got = inner.get(kind) or inner.get(mode)
            if got:
                candidates.append(got)
    if isinstance(block := scene.get(kind), str) and (scene.get("mode") in (None, mode)):
        candidates.append(block)
    if kind == "raw" and scene.get("file") and scene.get("mode") in (None, mode):
        candidates.append(scene["file"])
    for name in candidates:
        if isinstance(name, str) and os.path.exists(os.path.join(SHOTS, name)):
            return name
    return None


used_files = {}


def shot_figure(scene):
    variants = {}
    for kind in ("annotated", "raw"):
        for mode in ("dark", "light"):
            name = pick(scene, kind, mode)
            if name:
                variants[(kind, mode)] = name
    if not variants:
        return ""
    # Fill gaps so every (kind, mode) shows something.
    def best(kind, mode):
        for k, m in ((kind, mode), (kind, "dark" if mode == "light" else "light"),
                     ("raw" if kind == "annotated" else "annotated", mode),
                     ("raw" if kind == "annotated" else "annotated", "dark" if mode == "light" else "light")):
            if (k, m) in variants:
                return variants[(k, m)]
        return None

    imgs = []
    title = scene.get("title") or scene.get("whatItShows") or "Screenshot"
    for kind in ("annotated", "raw"):
        for mode in ("light", "dark"):
            name = best(kind, mode)
            if not name:
                continue
            used_files["shots/" + name] = os.path.join(SHOTS, name)
            imgs.append(
                f'<img class="shot shot-{kind} shot-{mode}" src="shots/{esc(name)}" '
                f'alt="{esc(title)} ({kind}, {mode} appearance)" loading="lazy">'
            )
    labels = scene.get("labels") or []
    label_html = ""
    if labels:
        label_html = '<ul class="labels">' + "".join(f"<li>{esc(l)}</li>" for l in labels) + "</ul>"
    caption = esc(scene.get("whatItShows") or "")
    reached = scene.get("howReached")
    reached_html = f'<p class="reached">How to get here: {inline(reached)}</p>' if reached else ""
    fault = "fault" in str(scene.get("feature", "")).lower() or str(title).startswith("FAULT")
    shown_title = re.sub(r"^FAULT:\s*", "", str(title))
    shown_title = shown_title[:1].upper() + shown_title[1:]
    badge = '<span class="faultbadge">Layout fault</span>' if fault else ""
    return (
        f'<figure class="shotfig{" shotfault" if fault else ""}">'
        f'<div class="shotframe">{"".join(imgs)}</div>'
        f'<figcaption>{badge}<strong>{esc(shown_title)}</strong>'
        f'{("<span>" + caption + "</span>") if caption else ""}{label_html}{reached_html}</figcaption>'
        "</figure>"
    )


by_feature = {}
for scene in scenes:
    by_feature.setdefault(feature_of(scene), []).append(scene)


# ---------------------------------------------------------------- sections

def section(feature):
    fid = feature["id"]
    parts = []
    issues = "".join(
        f'<a class="chip" href="https://github.com/russellgordon/plantoir/issues/{n}">#{n}</a>'
        for n in feature.get("issues", [])
    )
    proposal = fid == "marking-proposal"
    parts.append(
        f'<header class="fhead"><div class="chips">{issues}'
        f'{"<span class=\"chip chip-warn\">Proposal, not merged</span>" if proposal else ""}</div>'
        f'<h2 id="{esc(fid)}">{esc(feature["title"])}</h2>'
        f'<p class="lede">{inline(feature.get("oneLine", ""))}</p>'
        f'<p class="where"><span class="tag">Where it lives</span>{inline(feature.get("whereItLives", ""))}</p></header>'
    )

    shots = by_feature.get(fid, [])
    if shots:
        parts.append('<div class="shots">' + "".join(shot_figure(s) for s in shots) + "</div>")
    else:
        parts.append('<p class="noshot">No picture of this was captured. The words below describe it.</p>')

    steps = feature.get("howItWorks") or []
    if steps:
        parts.append('<h3>How it works</h3><ol class="steps">' + "".join(f"<li>{inline(s)}</li>" for s in steps) + "</ol>")

    states = feature.get("states") or []
    if states:
        rows = []
        for st in states:
            sentence = st.get("sentence")
            key = st.get("sentenceKey")
            said = ""
            if sentence:
                said = f'<q class="said">{esc(sentence)}</q>'
                if key:
                    said += f'<code class="key">{esc(key)}</code>'
            rows.append(
                f'<tr><th scope="row">{esc(st.get("name", ""))}</th>'
                f'<td>{inline(st.get("whatTheTeacherSees", ""))}{said}</td></tr>'
            )
        parts.append(
            '<h3>Every state a teacher can meet</h3><div class="tablewrap"><table class="states">'
            '<thead><tr><th scope="col">State</th><th scope="col">What the teacher sees</th></tr></thead>'
            f'<tbody>{"".join(rows)}</tbody></table></div>'
        )

    decisions = feature.get("designDecisions") or []
    if decisions:
        cards = []
        for d in decisions:
            rejected = d.get("rejected")
            cards.append(
                '<article class="decision">'
                f'<h4>{inline(d.get("decision", ""))}</h4>'
                f'<p><span class="tag">Why</span>{inline(d.get("why", ""))}</p>'
                + (f'<p class="rejected"><span class="tag">Rejected</span>{inline(rejected)}</p>' if rejected else "")
                + "</article>"
            )
        parts.append('<h3>Design decisions</h3><div class="decisions">' + "".join(cards) + "</div>")

    sentences = feature.get("sentences") or []
    if sentences:
        items = "".join(
            f'<li><q class="said">{esc(s.get("text", ""))}</q><code class="key">{esc(s.get("key", ""))}</code></li>'
            for s in sentences
        )
        parts.append(
            '<details class="wording"><summary>The exact words a teacher reads '
            f'<span class="count">{len(sentences)}</span></summary><ul>{items}</ul></details>'
        )

    access = feature.get("accessibility")
    not_measured = feature.get("notMeasured") or []
    if access or not_measured:
        cols = []
        if access:
            cols.append(f'<div><h3>Keyboard and VoiceOver</h3><p>{inline(access)}</p></div>')
        if not_measured:
            cols.append(
                '<div class="unmeasured"><h3>Not yet checked in the real window</h3><ul>'
                + "".join(f"<li>{inline(n)}</li>" for n in not_measured)
                + "</ul></div>"
            )
        parts.append('<div class="twocol">' + "".join(cols) + "</div>")

    questions = feature.get("questionsForRussell") or []
    if questions:
        parts.append(
            '<aside class="judge"><h3>For you to judge</h3><ul>'
            + "".join(f"<li>{inline(q)}</li>" for q in questions)
            + "</ul></aside>"
        )
    return f'<section class="feature" aria-labelledby="{esc(fid)}">{"".join(parts)}</section>'


nav = "".join(
    f'<li><a href="#{esc(f["id"])}">{esc(f["title"].split(":")[0])}</a></li>' for f in features
)

all_questions = sum(len(f.get("questionsForRussell") or []) for f in features)
all_unmeasured = sum(len(f.get("notMeasured") or []) for f in features)
shot_count = len(scenes)

obs_html = ""
if observations.get("awkward"):
    obs_html = (
        '<section class="observed"><h2 id="observed">Seen while driving the app</h2>'
        '<p class="lede">Things that looked wrong or awkward to the agent that took the pictures. '
        "Each is an observation, not a fix.</p><ul>"
        + "".join(f"<li>{inline(o)}</li>" for o in observations["awkward"])
        + "</ul></section>"
    )
missing_html = ""
if observations.get("notCaptured"):
    missing_html = (
        '<section class="observed"><h2 id="missing">Not pictured</h2><ul>'
        + "".join(f"<li>{inline(o)}</li>" for o in observations["notCaptured"])
        + "</ul></section>"
    )

faults_html = ""
if observations.get("faults"):
    faults_html = (
        '<aside class="faults"><h2>Two layout faults found while taking these pictures</h2><ol>'
        + "".join(f"<li>{inline(o)}</li>" for o in observations["faults"])
        + "</ol></aside>"
    )

build = observations.get("build", "")

PAGE = r"""<title>__TITLE__</title>
<meta name="claude:viewport-fit-sides" content="cover">
<link rel="stylesheet" href="https://fonts.googleapis.com/css2?family=Bricolage+Grotesque:opsz,wght@12..96,500;12..96,700&family=Inter:wght@400;500;600&family=JetBrains+Mono:wght@400;500&display=swap">
<style>
/* Layout: a reading column of feature chapters beside a sticky contents rail;
   pictures break out wider than the text because they are the evidence. */
:root {
  --bg: #f6f7f3;
  --surface: #ffffff;
  --sunk: #ecefe7;
  --ink: #1c231d;
  --muted: #566257;
  --line: #d5dbcf;
  --accent: #2f6b3f;
  --accent-soft: #e2efe3;
  --mark: #d0312d;
  --mark-soft: #fbe9e7;
  --warn: #8a5a00;
  --warn-soft: #fbf0d6;
  --show-light: block;
  --show-dark: none;
  --display: "Bricolage Grotesque", "Avenir Next", "Segoe UI", sans-serif;
  --body: "Inter", system-ui, -apple-system, "Segoe UI", sans-serif;
  --mono: "JetBrains Mono", ui-monospace, "SF Mono", Menlo, monospace;
}
@media (prefers-color-scheme: dark) {
  :root:not([data-theme="light"]) {
    --bg: #141815; --surface: #1c221d; --sunk: #232a24; --ink: #e7ece4; --muted: #a3ad9f;
    --line: #333d34; --accent: #8fcf9c; --accent-soft: #21372a; --mark: #ff6f66; --mark-soft: #3a1f1d;
    --warn: #f0c466; --warn-soft: #3a2f14; --show-light: none; --show-dark: block; color-scheme: dark;
  }
}
:root[data-theme="dark"] {
  --bg: #141815; --surface: #1c221d; --sunk: #232a24; --ink: #e7ece4; --muted: #a3ad9f;
  --line: #333d34; --accent: #8fcf9c; --accent-soft: #21372a; --mark: #ff6f66; --mark-soft: #3a1f1d;
  --warn: #f0c466; --warn-soft: #3a2f14; --show-light: none; --show-dark: block; color-scheme: dark;
}
* { box-sizing: border-box; }
body {
  background: var(--bg); color: var(--ink); font-family: var(--body); font-size: 16px; line-height: 1.6;
  padding-left: max(16px, env(safe-area-inset-left, 0px)); padding-right: max(16px, env(safe-area-inset-right, 0px));
  padding-block: 32px 80px;
}
a { color: var(--accent); }
a:focus-visible, button:focus-visible, summary:focus-visible { outline: 3px solid var(--accent); outline-offset: 2px; }
code { font-family: var(--mono); font-size: 0.86em; background: var(--sunk); padding: 0.1em 0.35em; border-radius: 4px; overflow-wrap: anywhere; }
.wrap { max-width: 1180px; margin: 0 auto; display: grid; grid-template-columns: 210px minmax(0, 1fr); gap: 48px; }
.rail { position: sticky; top: calc(env(safe-area-inset-top, 0px) + 24px); align-self: start; font-size: 14px; }
.rail p { margin: 0 0 8px; font-weight: 600; letter-spacing: 0.06em; text-transform: uppercase; font-size: 12px; color: var(--muted); }
.rail ol { list-style: none; margin: 0; padding: 0; display: flex; flex-direction: column; gap: 2px; }
.rail a { display: block; padding: 6px 10px; border-radius: 6px; text-decoration: none; color: var(--ink); }
.rail a:hover { background: var(--sunk); }
.switch { margin-top: 24px; display: flex; flex-direction: column; gap: 6px; }
.switch button {
  font: inherit; font-size: 13px; text-align: left; padding: 7px 10px; border-radius: 6px; cursor: pointer;
  border: 1px solid var(--line); background: var(--surface); color: var(--ink);
}
.switch button[aria-pressed="true"] { border-color: var(--mark); background: var(--mark-soft); font-weight: 600; }
main { min-width: 0; display: flex; flex-direction: column; gap: 72px; }
.top h1 { font-family: var(--display); font-weight: 700; font-size: clamp(2rem, 4.6vw, 3.1rem); line-height: 1.05; margin: 0 0 16px; text-wrap: balance; letter-spacing: -0.01em; }
.top .lede, .lede { font-size: 1.12rem; color: var(--ink); max-width: 66ch; margin: 0; }
.facts { display: flex; flex-wrap: wrap; gap: 8px 28px; margin: 24px 0 0; padding: 16px 0 0; border-top: 1px solid var(--line); font-size: 14px; color: var(--muted); }
.facts b { color: var(--ink); font-variant-numeric: tabular-nums; }
.howto { margin-top: 20px; max-width: 66ch; color: var(--muted); font-size: 15px; }
.legend { display: inline-block; background: var(--mark); color: #fff; font-weight: 700; padding: 0 6px; border-radius: 3px; font-size: 0.85em; }
.feature { display: flex; flex-direction: column; gap: 22px; scroll-margin-top: 24px; }
.fhead { display: flex; flex-direction: column; gap: 10px; border-top: 3px solid var(--ink); padding-top: 18px; }
.chips { display: flex; flex-wrap: wrap; gap: 6px; }
.chip { font-family: var(--mono); font-size: 12px; padding: 2px 8px; border-radius: 999px; background: var(--accent-soft); color: var(--accent); text-decoration: none; }
.chip-warn { background: var(--warn-soft); color: var(--warn); font-family: var(--body); font-weight: 600; }
h2 { font-family: var(--display); font-weight: 700; font-size: clamp(1.5rem, 3vw, 2.1rem); line-height: 1.12; margin: 0; text-wrap: balance; scroll-margin-top: 24px; }
h3 { font-family: var(--display); font-weight: 500; font-size: 1.15rem; margin: 10px 0 0; }
h4 { font-family: var(--body); font-weight: 600; font-size: 1rem; margin: 0; line-height: 1.4; }
.where { margin: 0; max-width: 72ch; color: var(--muted); font-size: 15px; }
.tag { display: inline-block; font-size: 11px; font-weight: 600; letter-spacing: 0.07em; text-transform: uppercase; color: var(--muted); margin-right: 8px; }
.shots { display: grid; grid-template-columns: repeat(auto-fit, minmax(min(100%, 460px), 1fr)); gap: 24px; }
.shotfig { margin: 0; display: flex; flex-direction: column; gap: 10px; min-width: 0; }
.shotframe { background: var(--sunk); border: 1px solid var(--line); border-radius: 10px; padding: 10px; }
.shot { width: 100%; height: auto; border-radius: 6px; display: none; }
:root:not([data-shots="raw"]) .shot-annotated.shot-light { display: var(--show-light); }
:root:not([data-shots="raw"]) .shot-annotated.shot-dark { display: var(--show-dark); }
:root[data-shots="raw"] .shot-raw.shot-light { display: var(--show-light); }
:root[data-shots="raw"] .shot-raw.shot-dark { display: var(--show-dark); }
figcaption { font-size: 14px; color: var(--muted); display: flex; flex-direction: column; gap: 6px; }
figcaption strong { color: var(--ink); font-size: 15px; }
.labels { list-style: none; margin: 0; padding: 0; display: flex; flex-wrap: wrap; gap: 6px; }
.labels li { background: var(--mark); color: #fff; font-weight: 700; font-size: 12px; padding: 1px 7px; border-radius: 3px; }
.reached { margin: 0; font-size: 13px; }
.shotfault .shotframe { border-color: var(--mark); border-width: 2px; }
.faultbadge { align-self: flex-start; background: var(--mark-soft); color: var(--mark); font-weight: 700; font-size: 12px; letter-spacing: 0.05em; text-transform: uppercase; padding: 2px 8px; border-radius: 4px; }
.faults { background: var(--mark-soft); border-radius: 10px; padding: 18px 20px; margin-top: 24px; max-width: 76ch; }
.faults h2 { font-size: 1.2rem; color: var(--mark); margin: 0 0 8px; }
.faults ol { margin: 0; padding-left: 1.3em; display: flex; flex-direction: column; gap: 8px; }
.noshot { margin: 0; padding: 12px 14px; background: var(--sunk); border-radius: 8px; color: var(--muted); font-size: 14px; }
.steps { margin: 0; padding-left: 1.4em; max-width: 72ch; display: flex; flex-direction: column; gap: 8px; }
.tablewrap { overflow-x: auto; border: 1px solid var(--line); border-radius: 10px; background: var(--surface); }
table.states { border-collapse: collapse; width: 100%; min-width: 520px; font-size: 15px; }
.states th, .states td { text-align: left; vertical-align: top; padding: 12px 14px; border-bottom: 1px solid var(--line); }
.states thead th { font-size: 12px; letter-spacing: 0.06em; text-transform: uppercase; color: var(--muted); background: var(--sunk); }
.states tbody tr:last-child th, .states tbody tr:last-child td { border-bottom: 0; }
.states tbody th { width: 26%; font-weight: 600; }
.said { display: block; margin-top: 8px; padding-left: 12px; border-left: 3px solid var(--accent); font-style: normal; quotes: "\201C" "\201D"; }
.key { display: inline-block; margin-top: 4px; font-size: 11.5px; color: var(--muted); background: transparent; padding: 0; }
.decisions { display: grid; grid-template-columns: repeat(auto-fit, minmax(min(100%, 340px), 1fr)); gap: 16px; }
.decision { background: var(--surface); border: 1px solid var(--line); border-radius: 10px; padding: 16px 18px; display: flex; flex-direction: column; gap: 10px; min-width: 0; }
.decision p { margin: 0; font-size: 14.5px; }
.decision .rejected { color: var(--muted); }
.wording { border: 1px solid var(--line); border-radius: 10px; background: var(--surface); }
.wording summary { cursor: pointer; padding: 12px 16px; font-weight: 600; }
.wording .count { font-family: var(--mono); font-weight: 400; color: var(--muted); margin-left: 6px; font-size: 13px; }
.wording ul { list-style: none; margin: 0; padding: 0 16px 16px; display: flex; flex-direction: column; gap: 14px; }
.wording .said { margin-top: 0; }
.twocol { display: grid; grid-template-columns: repeat(auto-fit, minmax(min(100%, 320px), 1fr)); gap: 24px; }
.twocol > div { min-width: 0; }
.twocol p, .twocol ul { margin: 8px 0 0; font-size: 15px; }
.twocol ul { padding-left: 1.2em; display: flex; flex-direction: column; gap: 6px; }
.unmeasured h3 { color: var(--warn); }
.judge { background: var(--warn-soft); border-radius: 10px; padding: 18px 20px; }
.judge h3 { margin: 0 0 8px; color: var(--warn); }
.judge ul { margin: 0; padding-left: 1.2em; display: flex; flex-direction: column; gap: 8px; max-width: 76ch; }
.observed { display: flex; flex-direction: column; gap: 12px; border-top: 3px solid var(--ink); padding-top: 18px; }
.observed ul { margin: 0; padding-left: 1.2em; display: flex; flex-direction: column; gap: 8px; max-width: 76ch; }
@media (max-width: 860px) {
  .wrap { grid-template-columns: minmax(0, 1fr); gap: 28px; }
  .rail { position: static; }
  .rail ol { flex-direction: row; flex-wrap: wrap; }
  .switch { flex-direction: row; flex-wrap: wrap; }
  main { gap: 56px; }
}
@media (prefers-reduced-motion: no-preference) { html { scroll-behavior: smooth; } }
</style>

<div class="wrap">
  <nav class="rail" aria-label="Contents">
    <p>In this review</p>
    <ol>__NAV__</ol>
    <div class="switch" role="group" aria-label="Pictures">
      <button type="button" id="show-annotated" aria-pressed="true">Pictures with labels</button>
      <button type="button" id="show-raw" aria-pressed="false">Pictures as captured</button>
    </div>
  </nav>
  <main>
    <header class="top">
      <h1>__HEADLINE__</h1>
      <p class="lede">Every new control a teacher meets in this release: where it sits, what it says, each state it can be in, and why it was built this way and not another.</p>
      <p class="howto">A <span class="legend">red label</span> on a picture names something new in 1.10. Sentences marked with a green rule are copied from the contract both apps are tested against, with the key beside each. Yellow panels are judgement calls waiting for you.</p>
      __FAULTS__
      <div class="facts">
        <span><b>__FEATURES__</b> areas</span>
        <span><b>__SHOTS__</b> pictures from the real app</span>
        <span><b>__QUESTIONS__</b> calls for you to judge</span>
        <span><b>__UNMEASURED__</b> things not yet checked in the real window</span>
        <span>Build: __BUILD__</span>
      </div>
    </header>
    __SECTIONS__
    __OBSERVED__
    __MISSING__
  </main>
</div>
<script>
(function () {
  var root = document.documentElement;
  var a = document.getElementById("show-annotated");
  var r = document.getElementById("show-raw");
  function set(kind) {
    if (kind === "raw") { root.setAttribute("data-shots", "raw"); } else { root.removeAttribute("data-shots"); }
    a.setAttribute("aria-pressed", kind === "raw" ? "false" : "true");
    r.setAttribute("aria-pressed", kind === "raw" ? "true" : "false");
    try { localStorage.setItem("plantoir-review-shots", kind); } catch (e) {}
  }
  a.addEventListener("click", function () { set("annotated"); });
  r.addEventListener("click", function () { set("raw"); });
  try { if (localStorage.getItem("plantoir-review-shots") === "raw") { set("raw"); } } catch (e) {}
})();
</script>
"""

page = (
    PAGE.replace("__NAV__", nav)
    .replace("__TITLE__", esc(observations.get("title", "Plantoir Interface Review")))
    .replace("__HEADLINE__", esc(observations.get("headline", "What this release adds to the window")))
    .replace("__FEATURES__", str(len(features)))
    .replace("__SHOTS__", str(shot_count))
    .replace("__QUESTIONS__", str(all_questions))
    .replace("__UNMEASURED__", str(all_unmeasured))
    .replace("__BUILD__", esc(build))
    .replace("__FAULTS__", faults_html)
    .replace("__SECTIONS__", "\n".join(section(f) for f in features))
    .replace("__OBSERVED__", obs_html)
    .replace("__MISSING__", missing_html)
)

with open(os.path.join(HERE, "index.html"), "w", encoding="utf-8") as f:
    f.write(page)
with open(os.path.join(HERE, "files.json"), "w", encoding="utf-8") as f:
    json.dump(used_files, f, indent=1)

placed = sum(len(v) for v in by_feature.values())
print(f"{len(features)} features, {shot_count} scenes in the manifest, {placed} placed, {len(used_files)} picture files used")
for fid, items in by_feature.items():
    print(f"  {fid}: {len(items)}")
print(f"page: {len(page) // 1024} KiB")
