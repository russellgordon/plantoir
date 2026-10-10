# Third-party software Plantoir carries

Plantoir's toolchain includes software written by other people. This file
lists what is carried INSIDE the website builder or copied into a class
website, under which licence, and where the licence text travels. It was
started with #485 E1 (v1.7.0); later pieces add their own entries here
(GeoGebra and PhET with #485 E2 and E3). Versions and hashes are pinned in
`contracts/toolchain.json` → `pins`.

Tools the image installs only to BUILD (Node, Python, Quartz, wrangler,
the Python packages) are not listed: they are not redistributed in a
teacher's site. Fonts a site carries for its own look are described in
`support/fonts/FONT-LICENSES.md`.

## Carried into a class website when a page uses it

| What | Version | Licence | Where its licence travels |
|---|---|---|---|
| **Paged.js** — the print layout for printable pages (#454) | 0.4.3 | MIT | `static/pagedjs/LICENSE.md` beside the file |
| **Latin Modern** — the faces a printed handout is set in (#499) | Debian fonts-lmodern 2.005 | GUST Font License (an instance of the LPPL 1.3c) | `static/pagedjs/fonts/LICENSE-Latin-Modern.txt` |
| **function-plot** — draws a page's ` ```functionplot ` graphs (#485 E1) | 1.25.4 | MIT, © 2015 Mauricio Poppe | `static/function-plot/LICENSE` beside the file |
| **Inside function-plot.js** — it is one bundled file built from d3-axis, d3-color, d3-format, d3-interpolate, d3-scale, d3-selection, d3-shape and d3-zoom (ISC, © Mike Bostock), built-in-math-eval and interval-arithmetic-eval (MIT, © Mauricio Poppe) and events (MIT, © Joyent) | as bundled in function-plot 1.25.4 | ISC and MIT: each asks that its copyright and permission notice travel with copies | function-plot.js carries no notices of its own; this row is where they are named, and the ISC and MIT texts are the standard ones (the MIT text is the `LICENSE` beside the file) |
| **BaKoMa Computer Modern TrueType fonts** — the lettering of a page's ` ```tikz ` diagrams; only the faces the site's diagrams name (#485 E1) | as shipped in node-tikzjax 1.0.5 | BaKoMa Fonts Licence, © 1994, 1995 Basil K. Malyshev: copying and distribution permitted with the notice; embedding in SVG and printing needs no notice | `static/tikz/LICENCE` beside the faces |

## Carried by plantoir.app itself

The Interactive class notes page (`website/pages/interactive.html`, v1.7.0)
draws a live graph and a TikZ diagram the way a class site does, so the site
carries the same files: `website/assets/function-plot.js` (function-plot
1.25.4, byte for byte the file a class site carries, with the bundled
packages named in the row above; licence in `function-plot-LICENSE.txt`
beside it) and the BaKoMa faces `cmmi10.ttf` and `cmr10.ttf` (licence in
`cm-fonts-LICENCE.txt` beside them).

## Carried inside the website builder only

| What | Version | Licence | Notes |
|---|---|---|---|
| **node-tikzjax** — draws ` ```tikz ` diagrams at build time (#485 E1) | 1.0.5 | LPPL-1.3c (a port of TikZJax by Jim Fowler, also LPPL) | Installed from `support/figures/package-lock.json` into `/opt/vendor/tikz-engine` (Windows: `runtime\vendor\tikz-engine`). Never copied into a site: a site receives only the SVG drawings it produces. |
| **The TeX distribution inside node-tikzjax** — `tex.wasm`, `core.dump` and 212 TeX files (pgf/TikZ, pgfplots, circuitikz, chemfig, tikz-cd, the AMS packages and others) | as in node-tikzjax 1.0.5 | Each file carries its own terms, chiefly the LPPL and the GPL (pgf/TikZ is dual LPPL 1.3c / GPL 2) | Unmodified, inside node-tikzjax's own `tex/tex_files.tar.gz`. |
| **node-tikzjax's dependencies** — jsdom, svgo, memfs, @prinsss/dvi2html, tar-fs and the packages under them (133 in all) | as pinned by the lockfile | MIT, ISC, BSD-2-Clause, BSD-3-Clause, Apache-2.0 (each package's own `LICENSE` sits in its folder) | Build-time only. |

## Why the diagrams' engine is not in the site

TikZJax in the browser would hand every student 7.0 MB of script and 4.8 MB
of fonts to draw what the build can draw once; the site carries the drawings
and the few faces they use instead (documentation/02 and 05).
