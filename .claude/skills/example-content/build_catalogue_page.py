"""Render the bundled Ontario course-code catalogue as a browsable page.

Reads the three things that decide what a teacher gets when they type a
code into Add Course — the code lookup, the example-content payloads, and
the skeleton families — and writes one self-contained HTML file.

    python3 .claude/skills/example-content/build_catalogue_page.py <out.html>

The page is published as an Artifact, and the URL never changes:

    https://claude.ai/code/artifact/cfb0ce4b-3691-4aaa-93a8-4d848254510f

Re-run this and re-publish to that same URL whenever a payload, a skeleton
family, or the course lookup changes — otherwise the page quietly claims a
smaller Plantoir than the one that ships.
"""

import html
import json
import pathlib
import sys

REPO = pathlib.Path(__file__).resolve().parents[3]
CATALOGUE = REPO / "support" / "ontario_secondary_courses.json"
PAYLOADS = REPO / "support" / "example_content"
FAMILIES = REPO / "support" / "skeletons" / "families.json"

ARTIFACT_URL = "https://claude.ai/code/artifact/cfb0ce4b-3691-4aaa-93a8-4d848254510f"


def read_sources() -> tuple:
    with open(CATALOGUE) as source_file:
        catalogue = json.load(source_file)

    built = set()
    for manifest in sorted(PAYLOADS.glob("*/manifest.json")):
        built.add(manifest.parent.name)

    with open(FAMILIES) as families_file:
        families = json.load(families_file)

    return catalogue, built, families


def family_for(code: str, families: dict) -> str:
    """The starter structure a code adopts.

    Exactly the rule both the app (`SkeletonCatalog.familyName(forCode:)`)
    and the installer (`find_skeleton_dir`) apply: match the three-letter
    prefix, or fall back to the generic family. Any cleverer guess here
    would put a subject on the page that a teacher never receives.
    """
    prefixes = families["prefixes"]
    if code[:3] in prefixes:
        return prefixes[code[:3]]
    return families["default"]


def pretty(family: str) -> str:
    return family.replace("-", " ").capitalize()


def build_rows(catalogue: dict, built: set, families: dict) -> tuple:
    rows = []
    letters_seen = []
    for code in sorted(catalogue):
        entry = catalogue[code]
        formal = entry.get("formal_name", "")
        short = entry.get("short_name", "")
        family = pretty(family_for(code, families))

        anchor = ""
        if code[0] not in letters_seen:
            letters_seen.append(code[0])
            anchor = f' id="letter-{code[0]}"'

        has_example = code in built
        example_flag = ' data-example="1"' if has_example else ""
        badge = (' <span class="badge" title="A complete ready-made course '
                 'ships with Plantoir">example content</span>') if has_example else ""
        searchable = (code + " " + formal + " " + short + " " + family).lower()
        if has_example:
            searchable += " example content"

        rows.append(
            f'<tr{anchor}{example_flag} data-search="{html.escape(searchable, quote=True)}">'
            f'<td class="code">{html.escape(code)}{badge}</td>'
            f"<td>{html.escape(formal)}</td>"
            f'<td class="short">{html.escape(short)}</td>'
            f'<td class="family">{html.escape(family)}</td>'
            f"</tr>"
        )
    return rows, letters_seen


PAGE = """<title>Ontario Course Codes in Plantoir</title>
<style>
  :root {
    --paper: #fbfaf7;
    --ink: #20262b;
    --accent: #2f6b4f;
    --muted: #5c6660;
    --rule: #e3e1da;
    --chip: #eef3ef;
    --highlight: #f3efdf;
  }
  @media (prefers-color-scheme: dark) {
    :root:not([data-theme="light"]) {
      --paper: #161a18;
      --ink: #e6e8e4;
      --accent: #7fbf9d;
      --muted: #9aa49d;
      --rule: #2a2f2c;
      --chip: #1f2622;
      --highlight: #24291f;
    }
  }
  :root[data-theme="dark"] {
    --paper: #161a18;
    --ink: #e6e8e4;
    --accent: #7fbf9d;
    --muted: #9aa49d;
    --rule: #2a2f2c;
    --chip: #1f2622;
    --highlight: #24291f;
  }
  body {
    background: var(--paper);
    color: var(--ink);
    font-family: system-ui, -apple-system, "Segoe UI", sans-serif;
    line-height: 1.45;
    margin: 0;
  }
  header {
    position: sticky;
    top: 0;
    background: var(--paper);
    border-bottom: 1px solid var(--rule);
    padding: 1.1rem 1.5rem 0.9rem;
    z-index: 2;
  }
  .head-inner, main { max-width: 66rem; margin: 0 auto; }
  h1 {
    font-size: 1.25rem;
    font-weight: 650;
    margin: 0 0 0.15rem;
    text-wrap: balance;
  }
  .subtitle { color: var(--muted); font-size: 0.85rem; margin: 0 0 0.75rem; max-width: 54rem; }
  .subtitle code {
    font-family: ui-monospace, "SF Mono", Menlo, monospace;
    font-size: 0.8rem;
    background: var(--chip);
    border-radius: 4px;
    padding: 0.05rem 0.3rem;
  }
  .controls { display: flex; gap: 0.75rem; align-items: baseline; flex-wrap: wrap; }
  input[type="search"] {
    background: var(--chip);
    color: var(--ink);
    border: 1px solid var(--rule);
    border-radius: 6px;
    font: inherit;
    font-size: 0.9rem;
    padding: 0.4rem 0.7rem;
    width: 20rem;
    max-width: 100%;
  }
  input[type="search"]:focus { outline: 2px solid var(--accent); outline-offset: 1px; }
  .badge {
    display: inline-block;
    background: var(--accent);
    color: var(--paper);
    font-size: 0.62rem;
    font-weight: 700;
    letter-spacing: 0.05em;
    text-transform: uppercase;
    border-radius: 999px;
    padding: 0.1rem 0.5rem;
    margin-left: 0.45rem;
    vertical-align: 1px;
    white-space: nowrap;
  }
  label.example-filter {
    font-size: 0.8rem;
    color: var(--muted);
    display: inline-flex;
    gap: 0.35rem;
    align-items: center;
    cursor: pointer;
  }
  .count {
    color: var(--muted);
    font-size: 0.8rem;
    font-variant-numeric: tabular-nums;
  }
  nav.letters { display: flex; flex-wrap: wrap; gap: 0.15rem; margin-top: 0.6rem; }
  nav.letters a {
    color: var(--accent);
    text-decoration: none;
    font-size: 0.75rem;
    font-weight: 600;
    letter-spacing: 0.04em;
    padding: 0.1rem 0.4rem;
    border-radius: 4px;
  }
  nav.letters a:hover, nav.letters a:focus-visible { background: var(--chip); outline: none; }
  main { padding: 1rem 1.5rem 3rem; }
  .table-wrap { overflow-x: auto; }
  table { border-collapse: collapse; width: 100%; font-size: 0.88rem; }
  th {
    text-align: left;
    font-size: 0.7rem;
    text-transform: uppercase;
    letter-spacing: 0.08em;
    color: var(--muted);
    font-weight: 600;
    padding: 0.5rem 0.9rem 0.5rem 0;
    border-bottom: 1px solid var(--rule);
  }
  td { padding: 0.32rem 0.9rem 0.32rem 0; border-bottom: 1px solid var(--rule); }
  td.code {
    font-family: ui-monospace, "SF Mono", Menlo, monospace;
    font-size: 0.82rem;
    font-weight: 600;
    color: var(--accent);
    white-space: nowrap;
  }
  td.short { color: var(--muted); }
  td.family { color: var(--muted); white-space: nowrap; }
  tr:target { background: var(--highlight); }
  .no-results { color: var(--muted); padding: 2rem 0; display: none; }
</style>
<header><div class="head-inner">
  <h1>Ontario course codes recognized by Plantoir</h1>
  <p class="subtitle">All __COUNT__ Ministry course codes in the Add Course lookup
  (<code>support/ontario_secondary_courses.json</code>). A recognized code fills in the
  formal and short course names, and brings a starter structure chosen for its
  subject — folders, sidebar, a curriculum page, and a term's worth of empty
  class pages to write into. <span id="exampleCountProse">0</span> of them go further and arrive as a
  complete course, already written. Any code not listed here is treated as a club
  or custom course.</p>
  <div class="controls">
    <input type="search" id="filter" placeholder="Filter by code, name, or subject&hellip;" aria-label="Filter courses">
    <span class="count" id="count">__COUNT__ courses</span>
    <label class="example-filter"><input type="checkbox" id="exampleOnly">
      only courses that arrive fully written (<span id="exampleCount">0</span>)</label>
  </div>
  <nav class="letters" aria-label="Jump to first code starting with letter">__LETTERS__</nav>
</div></header>
<main>
  <div class="table-wrap">
    <table>
      <thead><tr><th>Code</th><th>Formal name</th><th>Short name</th><th>Starter structure</th></tr></thead>
      <tbody id="rows">
__ROWS__
      </tbody>
    </table>
  </div>
  <p class="no-results" id="noResults">No courses match that search.</p>
</main>
<script>
  const filterField = document.getElementById("filter");
  const exampleOnly = document.getElementById("exampleOnly");
  const countLabel = document.getElementById("count");
  const noResults = document.getElementById("noResults");
  const allRows = Array.from(document.querySelectorAll("#rows tr"));
  const total = allRows.length;
  function applyFilters() {
    const query = filterField.value.trim().toLowerCase();
    let shown = 0;
    for (const row of allRows) {
      let matches = query === "" || row.dataset.search.includes(query);
      if (exampleOnly.checked && row.dataset.example !== "1") { matches = false; }
      row.style.display = matches ? "" : "none";
      if (matches) { shown += 1; }
    }
    countLabel.textContent = shown === total ? total + " courses" : shown + " of " + total + " courses";
    noResults.style.display = shown === 0 ? "block" : "none";
  }
  filterField.addEventListener("input", applyFilters);
  // Counted from the table rather than written by hand: this page shipped
  // twice with a stale figure because the badges were updated and a separate
  // hard-coded number was not.
  const withExample = document.querySelectorAll('tr[data-example="1"]').length;
  document.getElementById("exampleCount").textContent = String(withExample);
  document.getElementById("exampleCountProse").textContent = String(withExample);

  exampleOnly.addEventListener("change", applyFilters);
</script>
"""


def main():
    if len(sys.argv) != 2:
        print(__doc__)
        raise SystemExit(2)

    catalogue, built, families = read_sources()
    rows, letters_seen = build_rows(catalogue, built, families)
    letter_links = ""
    for letter in letters_seen:
        letter_links += f'<a href="#letter-{letter}">{letter}</a>'

    page = PAGE
    page = page.replace("__COUNT__", f"{len(catalogue):,}")
    page = page.replace("__LETTERS__", letter_links)
    page = page.replace("__ROWS__", "\n".join(rows))

    output = pathlib.Path(sys.argv[1])
    output.write_text(page, encoding="utf-8")
    print(f"{len(catalogue)} codes, {len(built)} with example content, "
          f"{len(set(families['prefixes'].values()))} skeleton families "
          f"-> {output}")
    print(f"publish to {ARTIFACT_URL}")


if __name__ == "__main__":
    main()
