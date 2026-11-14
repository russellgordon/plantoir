"""
Breaks a COPY of a built site one way at a time, so the rendered check
(browser-checks/rendered_features.mjs --expect-red) can prove each of its
rows sees what it is for (#597, plan review H4).

    python3 browser-checks/lib/sabotage.py list
    python3 browser-checks/lib/sabotage.py apply <copied site folder> <sabotage name>

The sabotages, what each aims at and which other rows it is allowed to turn
red, are browser-checks/rendered_rows.json -> sabotages; this file is only
HOW each one is done. It refuses a folder that is not a copy (one without
the check's pages, or one inside a course's builds), so it can never be
pointed at a real site. A script it adds is a file of the site's own
(`static/rendered-sabotage/`), never inline: the site's policy refuses an
inline script it has no hash for, and that refusal would be a second fault
on the page.
"""
from __future__ import annotations

import json
import re
import shutil
import sys
from pathlib import Path

ROWS = json.loads((Path(__file__).resolve().parent.parent / "rendered_rows.json").read_text(encoding="utf-8"))
PAGES = ROWS["pages"]


def page_file(site: Path, page: str) -> Path:
    return site / (PAGES[page] + ".html")


def add_to_head(site: Path, page: str, html: str) -> None:
    path = page_file(site, page)
    text = path.read_text(encoding="utf-8")
    if "<head>" not in text:
        raise SystemExit(f"sabotage: {path.name} has no <head>")
    path.write_text(text.replace("<head>", "<head>" + html, 1), encoding="utf-8")


def add_script(site: Path, page: str, name: str, source: str) -> None:
    folder = site / "static" / "rendered-sabotage"
    folder.mkdir(parents=True, exist_ok=True)
    (folder / name).write_text(source, encoding="utf-8")
    depth = PAGES[page].count("/")
    add_to_head(site, page, f'<script src="{"../" * depth}static/rendered-sabotage/{name}"></script>')


def add_style(site: Path, page: str, css: str) -> None:
    add_to_head(site, page, f"<style>{css}</style>")


def write_server_rules(site: Path, rules: dict) -> None:
    (site / ".rendered-sabotage.json").write_text(json.dumps(rules), encoding="utf-8")


def remove_files(paths: list[Path]) -> int:
    removed = 0
    for path in paths:
        if path.is_dir():
            shutil.rmtree(path)
            removed += 1
        elif path.exists():
            path.unlink()
            removed += 1
    return removed


def mermaid_policy(site: Path) -> str:
    headers = site / "_headers"
    text = headers.read_text(encoding="utf-8")
    changed = re.sub(r"(Content-Security-Policy: script-src 'self'[^\n]*?) https://cdnjs\.cloudflare\.com", r"\1", text)
    if changed == text:
        raise SystemExit("sabotage: the site's _headers names no cdnjs in its policy line")
    headers.write_text(changed, encoding="utf-8")
    return "cdnjs taken out of the policy line"


def katex_faces(site: Path) -> str:
    faces = sorted((site / "static" / "katex" / "fonts").glob("KaTeX_Main-*"))
    if remove_files(faces) == 0:
        raise SystemExit("sabotage: no KaTeX_Main faces to remove")
    return f"{len(faces)} KaTeX_Main files removed"


def tikz_size(site: Path) -> str:
    add_style(site, "Diagrams", ".pl-tikz svg { width: 0 !important; height: 0 !important; }")
    return "the drawing given no size"


def graph_engine(site: Path) -> str:
    if remove_files([site / "static" / "function-plot"]) == 0:
        raise SystemExit("sabotage: the site carries no static/function-plot/")
    return "static/function-plot/ removed"


def python_wasm_type(site: Path) -> str:
    found = sorted(site.glob("static/pyodide/pyodide.asm.wasm"))
    if not found:
        raise SystemExit("sabotage: no static/pyodide/pyodide.asm.wasm")
    write_server_rules(site, {"types": {"/static/pyodide/pyodide.asm.wasm": "application/octet-stream"}})
    return "pyodide.asm.wasm sent as application/octet-stream"


def swift_program(site: Path) -> str:
    # Each block's compiled program, named by its source's SHA-256; the
    # runtime that runs them (static/swift/) is left alone.
    programs = sorted((site / "static" / "swift-wasm").glob("*.wasm"))
    if remove_files(programs) == 0:
        raise SystemExit("sabotage: no compiled Swift programs under static/swift-wasm/")
    return f"{len(programs)} compiled Swift programs removed"


def quiz_answers(site: Path) -> str:
    path = page_file(site, "Quiz")
    text = path.read_text(encoding="utf-8")
    changed = re.sub(r' data-quiz="[^"]*"', "", text)
    if changed == text:
        raise SystemExit("sabotage: the Quiz page has no data-quiz")
    path.write_text(changed, encoding="utf-8")
    return "the quiz's answer marks stripped"


def task_key(site: Path) -> str:
    add_script(site, "Tasks", "task-key.js",
               "document.addEventListener('DOMContentLoaded', () => {\n"
               "  for (const box of document.querySelectorAll('input.plantoir-task')) {\n"
               "    box.dataset.taskItem = (box.dataset.taskItem || '') + '-' + Math.random().toString(36).slice(2)\n"
               "  }\n"
               "})\n")
    return "each box's key made new on every load"


def progress_manifest(site: Path) -> str:
    if remove_files([site / "progress-manifest.json"]) == 0:
        raise SystemExit("sabotage: the site has no progress-manifest.json")
    return "progress-manifest.json removed"


def geogebra_file(site: Path) -> str:
    sketches = sorted((site / "Rendered-Check").glob("*.ggb"))
    if not sketches:
        raise SystemExit("sabotage: no .ggb beside the Sketch page")
    for sketch in sketches:
        data = sketch.read_bytes()
        sketch.write_bytes(data[: len(data) // 2])
    return f"{len(sketches)} sketch file cut to half its length"


def geogebra_dialog(site: Path) -> str:
    # The must-fail geogebra_applet.mjs item 10 has used since #755, done
    # by the page itself once the file sketch is open: one of GeoGebra's
    # dialogs is brought up and REMOVED, with its shade, never closed.
    add_script(site, "Sketch", "geogebra-dialog.js", """
(() => {
  const removeTheOldWay = (figure) => {
    const box = figure.querySelector(".pl-geogebra-applet")
    const api = box && window[box.id.replace(/-box$/, "")]
    if (!api || typeof api.evalCommand !== "function") return false
    const watcher = new MutationObserver(() => {
      const dialog = box.querySelector(".dialogComponent")
      if (dialog === null) return
      dialog.remove()
      for (const shade of Array.from(document.querySelectorAll(".gwt-PopupPanelGlass"))) shade.remove()
      watcher.disconnect()
      figure.dataset.renderedSabotage = "dialog removed"
    })
    watcher.observe(box, { childList: true, subtree: true })
    api.setErrorDialogsActive(true)
    api.evalCommand("PlantoirEndOfLine()")
    api.setErrorDialogsActive(false)
    return true
  }
  const timer = setInterval(() => {
    const figure = document.querySelector("figure.pl-geogebra")
    if (figure && figure.classList.contains("pl-geogebra-loaded") && !figure.dataset.renderedSabotage) {
      figure.dataset.renderedSabotage = "started"
      if (removeTheOldWay(figure)) clearInterval(timer)
      else delete figure.dataset.renderedSabotage
    }
  }, 100)
})()
""")
    return "a GeoGebra dialog removed from the open file sketch the way the loader did before #755"


def geogebra_keys(site: Path) -> str:
    # geogebra.inline.ts holds back a person's presses, Space and Enter while a
    # sketch's lines run (holdPresses: capture listeners on the sketch's box).
    # Dropping those listeners as they are added is the state before #792
    # review M1.
    add_script(site, "Sketch", "geogebra-keys.js", """
(() => {
  const held = ["keydown", "keypress", "keyup"]
  const add = EventTarget.prototype.addEventListener
  EventTarget.prototype.addEventListener = function (type, listener, options) {
    if (options === true && held.includes(type) && this instanceof HTMLElement && this.classList.contains("pl-geogebra-applet")) return
    return add.call(this, type, listener, options)
  }
})()
""")
    return "the loader's hold on Space and Enter while lines run dropped"


def geogebra_reset(site: Path) -> str:
    # The loader builds each sketch with `new GGBApplet(params)`, params
    # carrying showResetIcon: true (#792). GGBApplet arrives with the
    # engine's own script, later than this one, so it is caught as it is
    # set and the icon is asked for no more: a press where the icon was
    # then changes nothing.
    add_script(site, "Sketch", "geogebra-reset.js", """
(() => {
  let real
  Object.defineProperty(window, "GGBApplet", {
    configurable: true,
    get() { return real },
    set(given) {
      real = function (params, ...rest) {
        if (params && typeof params === "object") params.showResetIcon = false
        return new given(params, ...rest)
      }
      real.prototype = given.prototype
      Object.assign(real, given)
    },
  })
})()
""")
    return "the sketches asked for without GeoGebra's reset icon"


def pdf_file(site: Path) -> str:
    if remove_files(sorted((site / "Rendered-Check").glob("*.pdf"))) == 0:
        raise SystemExit("sabotage: no PDF beside the Handout page")
    return "the handout's PDF removed"


def print_layout(site: Path) -> str:
    if remove_files([site / "static" / "pagedjs"]) == 0:
        raise SystemExit("sabotage: the site carries no static/pagedjs/")
    return "static/pagedjs/ removed"


def copy_stacking(site: Path) -> str:
    add_style(site, "Wrapped Text",
              "article pre { isolation: auto !important; } article pre > .clipboard-button { z-index: auto !important; }")
    return "the copy button stacked as before #759"


def heading_anchor(site: Path) -> str:
    add_script(site, "Anchor", "heading-anchor.js", "Element.prototype.scrollIntoView = function () {}\n")
    return "scrollIntoView made to do nothing"


def fonts(site: Path) -> str:
    path = page_file(site, "Diagrams")
    text = path.read_text(encoding="utf-8")
    changed = re.sub(r"(fonts\.googleapis\.com/css2\?family=)[^:&\"]+", r"\1Plantoir No Such Family", text, count=1)
    if changed == text:
        raise SystemExit("sabotage: the Diagrams page asks Google Fonts for nothing")
    path.write_text(changed, encoding="utf-8")
    return "the code font's stylesheet asked for a family that does not exist"


def clean_page(site: Path) -> str:
    add_script(site, "Graphs", "throws.js", "throw new Error('plantoir-rendered-sabotage: a script that throws')\n")
    return "a script that throws"


def own_host_picture(site: Path) -> str:
    path = page_file(site, "Quiz")
    text = path.read_text(encoding="utf-8")
    marker = "<article"
    if marker not in text:
        raise SystemExit("sabotage: the Quiz page has no <article>")
    picture = '<img src="https://example.com/plantoir-rendered-sabotage.png" alt="" width="1" height="1">'
    path.write_text(text.replace(marker, picture + marker, 1), encoding="utf-8")
    return "a picture asked of example.com"


def own_host_worker(site: Path) -> str:
    folder = site / "static" / "rendered-sabotage"
    folder.mkdir(parents=True, exist_ok=True)
    (folder / "worker.js").write_text("fetch('https://example.com/plantoir-rendered-from-a-worker').catch(() => {})\n", encoding="utf-8")
    add_script(site, "Tasks", "start-worker.js",
               "new Worker(new URL('worker.js', document.currentScript.src))\n")
    return "a worker asking example.com for a file"


def sabotage_folder(site: Path) -> Path:
    folder = site / "static" / "rendered-sabotage"
    folder.mkdir(parents=True, exist_ok=True)
    return folder


def own_host_frame(site: Path) -> str:
    path = page_file(site, "Quiz")
    text = path.read_text(encoding="utf-8")
    if "<article" not in text:
        raise SystemExit("sabotage: the Quiz page has no <article>")
    frame = '<iframe src="https://example.com/plantoir-rendered-sabotage-frame" width="200" height="100" title="a frame"></iframe>'
    path.write_text(text.replace("<article", frame + "<article", 1), encoding="utf-8")
    return "a frame from example.com on the Quiz page"


def own_host_shared_worker(site: Path) -> str:
    (sabotage_folder(site) / "shared.js").write_text(
        "fetch('https://example.com/plantoir-rendered-from-a-shared-worker', { mode: 'no-cors' }).catch(() => {})\n", encoding="utf-8")
    add_script(site, "Quiz", "start-shared.js", "new SharedWorker(new URL('shared.js', document.currentScript.src))\n")
    return "a shared worker asking example.com for a file"


def own_host_service_worker(site: Path) -> str:
    (sabotage_folder(site) / "service.js").write_text(
        "self.addEventListener('activate', () => { fetch('https://example.com/plantoir-rendered-from-a-service-worker', { mode: 'no-cors' }).catch(() => {}) })\n",
        encoding="utf-8")
    add_script(site, "Quiz", "start-service.js", "navigator.serviceWorker.register(new URL('service.js', document.currentScript.src))\n")
    return "a service worker registered"


def own_host_websocket(site: Path) -> str:
    add_script(site, "Quiz", "socket.js", "try { new WebSocket('wss://example.com/plantoir-rendered-socket') } catch (error) {}\n")
    return "a WebSocket from the page to example.com"


def own_host_worker_websocket(site: Path) -> str:
    (sabotage_folder(site) / "socket-worker.js").write_text(
        "try { new WebSocket('wss://example.com/plantoir-rendered-socket-from-a-worker') } catch (error) {}\n", encoding="utf-8")
    add_script(site, "Quiz", "start-socket-worker.js", "new Worker(new URL('socket-worker.js', document.currentScript.src))\n")
    return "a worker opening a WebSocket to example.com"


def graph_one_curve(site: Path) -> str:
    path = page_file(site, "Graphs")
    text = path.read_text(encoding="utf-8")
    changed = text.replace(",&quot;-x + 4&quot;]", "]", 1).replace(",&quot;y = -x + 4&quot;", "", 1)
    if changed.count("-x + 4") == text.count("-x + 4"):
        raise SystemExit("sabotage: the Graphs page has no second line to take out")
    path.write_text(changed, encoding="utf-8")
    return "the graph's second line taken out"


def katex_source(site: Path) -> str:
    add_script(site, "Diagrams", "katex-source.js",
               "document.addEventListener('DOMContentLoaded', () => {\n"
               "  const all = document.querySelectorAll('article .katex')\n"
               "  const last = all[all.length - 1]\n"
               "  ;(last.closest('.katex-display') || last).replaceWith(document.createTextNode('$$\\\\frac{19 + 23}{2} = 21$$'))\n"
               "})\n")
    return "one formula put back as its TeX"


def katex_wrong_face(site: Path) -> str:
    fonts = site / "static" / "katex" / "fonts"
    replaced = 0
    for face in sorted(fonts.glob("KaTeX_Main-*")):
        donor = fonts / ("KaTeX_Size4-Regular" + face.suffix)
        if donor.is_file():
            shutil.copyfile(donor, face)
            replaced += 1
    if replaced == 0:
        raise SystemExit("sabotage: no KaTeX_Main files with a KaTeX_Size4 file to put in their place")
    return f"{replaced} KaTeX_Main files replaced with KaTeX_Size4's"


def quiz_given_away(site: Path) -> str:
    add_script(site, "Quiz", "given-away.js",
               "document.addEventListener('DOMContentLoaded', () => {\n"
               "  const quiz = document.querySelector('.plantoir-quiz')\n"
               "  for (const choice of quiz.querySelectorAll('.plantoir-quiz-choice')) {\n"
               "    if ((choice.textContent || '').includes('42')) choice.style.background = 'lightgreen'\n"
               "  }\n"
               "  const note = document.createElement('p')\n"
               "  note.textContent = 'Answer: 42'\n"
               "  quiz.after(note)\n"
               "})\n")
    return "the right choice marked out and its answer shown before any press"


def own_host_embeds_page(site: Path) -> str:
    # The four planted embeds pointed at a page of the site's own (so the
    # check needs no network here), then a frame and a request of another
    # host's beside them: the Embeds page is judged like any other, and only
    # frames on the embeds row's allowedFrames may come from elsewhere.
    path = page_file(site, "Embeds")
    text = path.read_text(encoding="utf-8")
    changed, count = re.subn(r'(<iframe[^>]*\ssrc=")https?://[^"]*(")', r"\1../Rendered-Check/Quiz\2", text)
    if count == 0:
        raise SystemExit("sabotage: the Embeds page has no frame")
    frame = '<iframe src="https://example.com/plantoir-rendered-embeds-extra" width="200" height="100" title="another host"></iframe>'
    path.write_text(changed.replace("<article", frame + "<article", 1), encoding="utf-8")
    add_script(site, "Embeds", "embeds-fetch.js", "fetch('https://example.com/plantoir-rendered-embeds-fetch', { mode: 'no-cors' }).catch(() => {})\n")
    return f"{count} embeds pointed at the site, a frame and a request of example.com's added"


def embeds_refused(site: Path) -> str:
    # The YouTube frame pointed at the video's watch page, which YouTube
    # refuses to be framed in (X-Frame-Options: SAMEORIGIN): the frame's
    # document answers 200 and students see a blank box (597b review
    # finding 1). A teacher pasting the address from the address bar makes
    # exactly this. Needs the network: the embeds row runs on deployed sites,
    # or with --site and --host netlify.
    path = page_file(site, "Embeds")
    text = path.read_text(encoding="utf-8")
    changed, count = re.subn(r'(<iframe[^>]*\ssrc=")https://www\.youtube\.com/embed/([A-Za-z0-9_-]+)(")', r"\1https://www.youtube.com/watch?v=\2\3", text)
    if count == 0:
        raise SystemExit("sabotage: the Embeds page has no YouTube frame")
    path.write_text(changed, encoding="utf-8")
    return "the YouTube frame pointed at the video's watch page, which refuses to be framed"


def own_host_off_its_pin(site: Path) -> str:
    # A host the list names, asked from a page and for a path it is not
    # pinned to (597b review finding 2): cdnjs for another library, from the
    # Quiz page.
    add_script(site, "Quiz", "off-pin.js",
               "fetch('https://cdnjs.cloudflare.com/ajax/libs/jquery/3.7.1/jquery.min.js', { mode: 'no-cors' }).catch(() => {})\n")
    return "cdnjs asked for another library from the Quiz page"


def own_host_late(site: Path) -> str:
    add_script(site, "Quiz", "late.js",
               "addEventListener('load', () => setTimeout(() => fetch('https://example.com/plantoir-rendered-late', { mode: 'no-cors' }).catch(() => {}), 4000))\n")
    return "a request asked of example.com 4 s after the page loaded"


def own_host_lazy(site: Path) -> str:
    path = page_file(site, "Quiz")
    text = path.read_text(encoding="utf-8")
    if "</article>" not in text:
        raise SystemExit("sabotage: the Quiz page has no </article>")
    lazy = ('<div style="height: 6000px"></div>'
            '<img loading="lazy" src="https://example.com/plantoir-rendered-lazy.png" alt="" width="10" height="10">')
    path.write_text(text.replace("</article>", lazy + "</article>", 1), encoding="utf-8")
    return "a lazy picture of example.com's 6,000 px below the fold"


def own_host_media(site: Path) -> str:
    add_script(site, "Quiz", "media.js",
               "document.addEventListener('DOMContentLoaded', () => { const a = document.createElement('audio'); a.preload = 'auto'; a.src = 'https://example.com/plantoir-rendered-sound.mp3'; document.body.append(a) })\n")
    return "a sound asked of example.com (never played)"


def own_host_webrtc(site: Path) -> str:
    add_script(site, "Quiz", "webrtc.js",
               "try { const c = new RTCPeerConnection({ iceServers: [{ urls: 'stun:example.com:3478' }] }); c.createDataChannel('x'); c.createOffer().then((o) => c.setLocalDescription(o)) } catch (error) {}\n")
    return "a WebRTC connection asking example.com's STUN server"


def own_host_module_worker_websocket(site: Path) -> str:
    folder = sabotage_folder(site)
    (folder / "socket-dep.mjs").write_text("try { new WebSocket('wss://example.com/plantoir-rendered-socket-from-a-module') } catch (error) {}\nexport const done = true\n", encoding="utf-8")
    (folder / "module-worker.mjs").write_text("import { done } from './socket-dep.mjs'\nself.postMessage(done)\n", encoding="utf-8")
    add_script(site, "Quiz", "start-module-worker.js",
               "new Worker(new URL('module-worker.mjs', document.currentScript.src), { type: 'module' })\n")
    return "a module worker whose imported module opens a WebSocket to example.com"


def tikz_empty(site: Path) -> str:
    add_script(site, "Diagrams", "tikz-empty.js",
               "document.addEventListener('DOMContentLoaded', () => { for (const svg of document.querySelectorAll('.pl-tikz svg')) svg.replaceChildren() })\n")
    return "the drawing's svg emptied, its size kept"


def handout_answers_open(site: Path) -> str:
    path = page_file(site, "Handout")
    text = path.read_text(encoding="utf-8")
    changed, count = re.subn(r'(<blockquote class="callout (?:success|solution|answer)[^"]*?) is-collapsed', r"\1", text)
    if count == 0:
        raise SystemExit("sabotage: the Handout page has no folded answer")
    path.write_text(changed, encoding="utf-8")
    return f"{count} answer(s) left unfolded"


def graph_invisible(site: Path) -> str:
    add_style(site, "Graphs", ".pl-plot svg path.line { stroke: none !important; }")
    return "the graph's curves stroked with nothing"


def cold_visit(site: Path) -> str:
    if not (site / "index.css").is_file():
        raise SystemExit("sabotage: the site has no index.css")
    write_server_rules(site, {"hold": {"/index.css": 8000}})
    return "index.css held for 8 s"


DOERS = {
    "mermaid policy": mermaid_policy,
    "katex faces": katex_faces,
    "tikz size": tikz_size,
    "graph engine": graph_engine,
    "python wasm type": python_wasm_type,
    "swift program": swift_program,
    "quiz answers": quiz_answers,
    "task key": task_key,
    "progress manifest": progress_manifest,
    "geogebra file": geogebra_file,
    "geogebra dialog": geogebra_dialog,
    "geogebra keys": geogebra_keys,
    "geogebra reset": geogebra_reset,
    "pdf file": pdf_file,
    "print layout": print_layout,
    "copy stacking": copy_stacking,
    "heading anchor": heading_anchor,
    "fonts": fonts,
    "clean page": clean_page,
    "own host picture": own_host_picture,
    "own host worker": own_host_worker,
    "own host frame": own_host_frame,
    "own host shared worker": own_host_shared_worker,
    "own host service worker": own_host_service_worker,
    "own host websocket": own_host_websocket,
    "own host worker websocket": own_host_worker_websocket,
    "graph one curve": graph_one_curve,
    "katex source": katex_source,
    "katex wrong face": katex_wrong_face,
    "quiz given away": quiz_given_away,
    "own host embeds page": own_host_embeds_page,
    "own host late": own_host_late,
    "own host lazy": own_host_lazy,
    "own host media": own_host_media,
    "own host webrtc": own_host_webrtc,
    "own host module worker websocket": own_host_module_worker_websocket,
    "tikz empty": tikz_empty,
    "handout answers open": handout_answers_open,
    "graph invisible": graph_invisible,
    "cold visit": cold_visit,
    "embeds refused": embeds_refused,
    "own host off its pin": own_host_off_its_pin,
}


def main(arguments: list[str]) -> int:
    named = [sabotage["name"] for sabotage in ROWS["sabotages"]]
    missing = [name for name in named if name not in DOERS]
    extra = [name for name in DOERS if name not in named]
    if missing or extra:
        print(f"sabotage: rendered_rows.json and sabotage.py disagree: no way to do {missing}, not listed {extra}")
        return 1
    if arguments == ["list"]:
        print(json.dumps(named))
        return 0
    if len(arguments) != 3 or arguments[0] != "apply":
        print("usage: sabotage.py list | apply <copied site folder> <sabotage name>")
        return 2
    site = Path(arguments[1])
    name = arguments[2]
    if name not in DOERS:
        print(f"sabotage: no sabotage called {name!r}")
        return 2
    if not page_file(site, "Diagrams").is_file():
        print(f"sabotage: {site} has none of the rendered check's pages")
        return 1
    if "Application Support/Plantoir/builds" in str(site.resolve()) or "/.merged_output/" in str(site):
        print("sabotage: refuses a course's real site; give it a copy")
        return 1
    print(f"sabotage {name}: {DOERS[name](site)}")
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
