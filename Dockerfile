# Use a slim Node+Python base image
#
# PINNED BY DIGEST (the multi-architecture index, so arm64 and amd64 Macs and
# PCs each get their own image from the one line), decided with #334 on
# 2026-09-26. The tag alone moves under us: teachers who built at different
# times held different Debian and Python patch releases, and a build could
# change beneath a teacher with no change to this recipe at all. This digest
# is the one this recipe was measured and verified on - Python 3.11.15,
# Debian 13 (trixie), built 2026-08-05 - and the one BuildKit already resolved
# for every build since, so pinning it re-downloads nothing for a Mac that
# has it. The cost is that the packages the BASE ITSELF installed keep their
# security fixes only until someone bumps it: `docker buildx imagetools
# inspect python:3.11-slim` names the current index digest; bump it
# deliberately, and run verify.sh. A package an apt line below NAMES comes
# from Debian's live trixie-security instead, but only when that line's layer
# is rebuilt - which a cached layer never is. The certificate store is the
# one that cannot wait for either, so it has a late layer of its own (#639,
# below the tikz engine).
FROM python:3.11-slim@sha256:90744cff8f32887f075c47d747a173ff333e9e98801667af93c357fa9f5e28ff

# Python packages: frontmatter parsing, and Pillow to draw each
# section's social sharing card.
#
# PINNED, and python-frontmatter's own PyYAML is pinned with it, because
# whether a teacher's page reaches their students is decided by what PyYAML
# makes of the line they typed. `publish: no` hides a page ONLY because PyYAML
# reads YAML 1.1's spellings of no as the boolean false; PyYAML 7 is expected
# to move to YAML 1.2, where `no` is the string "no" and that same page would
# be published. Both apps and `contracts/file-formats.json` ->
# `pageVisibility.readingCases` now state the 1.1 table as fact, so an
# unpinned upgrade would flip real pages in a teacher's course with nothing
# failing anywhere. These are the versions the image already had on
# 2026-09-18, read off `pip freeze` rather than chosen — so the pin changes
# nothing about what is installed today.
RUN pip install python-frontmatter==1.3.0 PyYAML==6.0.3 Pillow==12.3.0

# Install Node.js (needed for Quartz) and other tools (incl. dos2unix)
# fonts-noto-color-emoji: the colour emoji drawn onto social cards.
#
# Node 22.23.4, PINNED EXACTLY (#640, v1.9.0). Node 20 has been end-of-life
# since 2026-04-30, and an unpinned `setup_20.x` let the image and Windows'
# runtime drift to different patch releases (#636). An `=` pin is safe here,
# unlike the certificate store's floor below: NodeSource keeps its history
# (measured 2026-10-23, every 22.x from 22.5.0 on arm64, back past 22.22.0 on
# amd64), so this line does not break a first build the day 22.23.5 ships.
# `setup_22.x` pins NodeSource above Debian (Pin-Priority 600), so the version
# resolves from NodeSource. Quartz v4.5.0 was revalidated on it: an identical
# npm tree, and the same 336 files for the EXC2O example as on Node 20.
# Node 22 is itself end-of-life on 2027-04-30, so Quartz 5 (#512) or Node 24
# has to land before then. contracts/toolchain.json -> pins -> node and
# documentation/02 -> "Node 22 (#640)" carry what was measured and rejected.
RUN apt-get update && apt-get install -y curl git lsof dos2unix fonts-noto-color-emoji rsync \
    && curl -fsSL https://deb.nodesource.com/setup_22.x | bash - \
    && apt-get install -y nodejs=22.23.4-1nodesource1 \
    && apt-get clean && rm -rf /var/lib/apt/lists/*

# Cloudflare's own deploy CLI, used by deploy.py for the Pages publishing
# target. It is pinned, and deliberately pinned BELOW 4.87: 4.87.0 is the
# first wrangler whose engines need Node 22 (`npm view`, 2026-10-23: 4.80.0
# to 4.86.0 say >=20.3.0, 4.87.0 on say >=22.0.0; this comment said 4.100
# until #640, thirteen minors late). This image runs Node 22 now,
# but the pin is shared with Windows, whose runtime stays on Node 20 until its
# own issue lands - so the pin stays below the first version Windows cannot run.
# Moving wrangler is its own piece, once both platforms run Node 22. The
# exact pin also keeps the image reproducible and stops an upstream CLI
# change from breaking publishing for a teacher mid-semester.
RUN npm install -g wrangler@4.80.0 && npm cache clean --force

# Clone Quartz v4.5.0 into /opt/quartz
#
# Depth 1 (#334): the tag's one commit, not Quartz's whole history. Measured
# 2026-09-26, per container on this Mac: 2.3 MB against 42.0 MB, which is
# ~40 MB off every new teacher's ~382 MB first download, and 38 MB less .git
# that build_site.py stages into EVERY section's output folder at its first
# build. Nothing reads Quartz's history: build_site.py already takes "git"
# out of CreatedModifiedDate's priority, and the one-commit clone is still a
# repository.
WORKDIR /opt
RUN git clone --depth 1 --branch v4.5.0 https://github.com/jackyzha0/quartz.git quartz

# Pre-install dependencies inside the image so npm install does not run over slow 9P mounts
RUN cd /opt/quartz && npm install --no-audit && npm cache clean --force

# KaTeX 0.16.21 is what Quartz's lockfile installs and renders every formula
# with; since #494 every site also carries ITS stylesheet, copy-tex and woff2
# faces (build_site.install_katex_assets copies them from here), instead of
# linking 0.16.11's from cdn.jsdelivr.net. This fails the image build if the
# lockfile ever resolves another version (measured: npm ls katex@0.16.22
# exits 1), so the pin in contracts/toolchain.json cannot drift unnoticed.
RUN cd /opt/quartz && npm ls katex@0.16.21

# Paged.js, the print layout for pages whose settings say `printable: true`
# (#454). Into /opt/vendor, NOT into the Quartz scaffold's static/: a site
# carries it only when one of its pages asks for it (build_site.py copies it
# into that section's quartz/static then, and takes it out again when no page
# does), so a course that never prints ships none of its 502,617 bytes.
# Fetched from the npm registry by exact version and checked against the
# tarball's SHA-256, so a changed upload fails the image build rather than
# reaching a teacher; contracts/toolchain.json -> pins carries the why. MIT
# licensed; the licence travels beside the file.
RUN curl -fsSL -o /tmp/pagedjs.tgz https://registry.npmjs.org/pagedjs/-/pagedjs-0.4.3.tgz \
 && echo "a79baaa94d15cf952e6327950fa886ba7533bdce92194b677d9d1b4cce6c17c5  /tmp/pagedjs.tgz" | sha256sum -c - \
 && mkdir -p /tmp/pagedjs /opt/vendor/pagedjs \
 && tar -xzf /tmp/pagedjs.tgz -C /tmp/pagedjs package/dist/paged.min.js package/LICENSE.md \
 && cp /tmp/pagedjs/package/dist/paged.min.js /tmp/pagedjs/package/LICENSE.md /opt/vendor/pagedjs/ \
 && rm -rf /tmp/pagedjs /tmp/pagedjs.tgz

# Latin Modern, the faces a printed handout is set in (#499: the look of the
# teacher's LaTeX handouts, 11pt article with lmodern). Six faces, 631,940
# bytes, beside Paged.js so the same gate carries them: a site holds them only
# when a page asks to print, and a browser fetches them only when it prints.
# From Debian's own fonts-lmodern (2.005), through the same apt as every other
# package here, rather than a download from the font's home page: a font host
# that is down must never stop a teacher's first build. The package is taken
# out again once the six files are copied; its copyright file, which carries
# the GUST Font License, travels with them. The files are UNMODIFIED - the
# licence asks that a changed font be renamed, and woff2 (283,148 bytes for
# the six, measured) would be a change. Their SHA-256s are pinned in
# contracts/toolchain.json and checked by verify.sh, not here, so a Debian
# point release that touched them shows up in a check rather than failing a
# teacher's build.
RUN apt-get update && apt-get install -y --no-install-recommends fonts-lmodern \
 && mkdir -p /opt/vendor/pagedjs/fonts \
 && cd /usr/share/texmf/fonts/opentype/public/lm \
 && cp lmroman10-regular.otf lmroman10-bold.otf lmroman10-italic.otf lmroman10-bolditalic.otf \
       lmsans10-bold.otf lmmono10-regular.otf /opt/vendor/pagedjs/fonts/ \
 && cp /usr/share/doc/fonts-lmodern/copyright /opt/vendor/pagedjs/fonts/LICENSE-Latin-Modern.txt \
 && apt-get purge -y fonts-lmodern && apt-get autoremove -y && apt-get clean && rm -rf /var/lib/apt/lists/*

# Graphs drawn from a page's ```functionplot fence (#485 E1): function-plot
# 1.25.4, the evaluator and drawing code the site's own script calls in the
# student's browser. Into /opt/vendor beside Paged.js, under the same gate: a
# section's site carries it (static/function-plot) only while a page students
# can see has a graph that can be drawn, so a course without graphs ships none
# of its 202,953 bytes. The build ALSO checks every graph with this very file
# (support/figures/plantoir-figures.mjs), so a graph the site would refuse is
# reported before it reaches a student. Fetched by exact version and checked
# against the tarball's SHA-256, like Paged.js; contracts/toolchain.json ->
# pins carries the why. MIT; the licence travels beside the file.
RUN curl -fsSL -o /tmp/function-plot.tgz https://registry.npmjs.org/function-plot/-/function-plot-1.25.4.tgz \
 && echo "33974ca53165365f585601f3e304e882107b44aa8a360d0b2b089ab9daf24a77  /tmp/function-plot.tgz" | sha256sum -c - \
 && mkdir -p /tmp/function-plot /opt/vendor/function-plot \
 && tar -xzf /tmp/function-plot.tgz -C /tmp/function-plot package/dist/function-plot.js package/LICENSE \
 && cp /tmp/function-plot/package/dist/function-plot.js /tmp/function-plot/package/LICENSE /opt/vendor/function-plot/ \
 && rm -rf /tmp/function-plot /tmp/function-plot.tgz

# Python that runs in the student's browser, for a page's ```python run
# blocks (#455): Pyodide 314.0.7, CPython 3.14.2 compiled to WebAssembly.
# Into /opt/vendor beside the other engines, under the same gate: a section's
# site carries it (static/pyodide, with support/gated/pyodide/plantoir-worker.js
# laid over it) only while a page students can see opts in with a runnable
# block, so a course without one ships none of its 13,531,207 bytes. The core
# tarball is fetched by exact version and checked against its SHA-256; five of
# its files are kept - pyodide.mjs (the module a module worker imports: #455
# review B1), pyodide.asm.mjs, pyodide.asm.wasm, python_stdlib.zip and
# pyodide-lock.json - with a README naming the licence, MPL-2.0 (the tarball
# carries no LICENSE file). `python3 -m tarfile`, because the slim base has no
# bzip2. Before the tikz-engine COPY, so editing a script never downloads it
# again; contracts/toolchain.json -> pins carries the why.
RUN curl -fsSL -o /tmp/pyc.tar.bz2 https://github.com/pyodide/pyodide/releases/download/314.0.7/pyodide-core-314.0.7.tar.bz2 \
 && echo "2abdcc2e35208af406e07724cffa85bc582ced97e9028383ecf5462541393f95  /tmp/pyc.tar.bz2" | sha256sum -c - \
 && python3 -m tarfile -e /tmp/pyc.tar.bz2 /tmp/pyx && mkdir -p /opt/vendor/pyodide \
 && cd /tmp/pyx/pyodide \
 && cp pyodide.mjs pyodide.asm.mjs pyodide.asm.wasm python_stdlib.zip pyodide-lock.json /opt/vendor/pyodide/ \
 && printf 'Pyodide 314.0.7 (MPL-2.0). Source: https://github.com/pyodide/pyodide/tree/314.0.7\n' > /opt/vendor/pyodide/README.txt \
 && rm -rf /tmp/pyx /tmp/pyc.tar.bz2

# TikZ diagrams drawn at BUILD time from a page's ```tikz fence (#485 E1):
# node-tikzjax 1.0.5, whose TeX engine (tex.wasm, core.dump and all 212 TeX
# files) is byte for byte the one the Obsidian TikZJax plugin carries, so a
# fence draws the same picture in Obsidian and on the site and students
# download no engine at all. Installed from the LOCKFILE beside its
# package.json, which pins every one of the 133 packages under it - load-
# bearing, because node-tikzjax itself floats jsdom ^23, svgo ^3 and memfs
# ^4, and svgo shapes the drawing. 39 MB, 5,445 files, 14.4 MB compressed.
# Into its own folder, /opt/vendor/tikz-engine, NOT into Quartz's
# node_modules (hoisting could move Quartz's own versions) and NOT named
# `tikz`, which is the name of a site's FONTS folder: this one is never copied
# into a site. Before the patches and scripts below, so editing a script
# never downloads it again. LPPL-1.3c; THIRD_PARTY_LICENSES.md.
COPY support/figures/package.json support/figures/package-lock.json /opt/vendor/tikz-engine/
RUN cd /opt/vendor/tikz-engine \
 && npm ci --omit=dev --no-audit --no-fund \
 && npm ls node-tikzjax@1.0.5 \
 && npm cache clean --force

# Debian's certificate store, at least 20250419+deb13u1 (#639): the version
# that stops trusting "AAA Certificate Services" (Comodo) and "emSign ECC Root
# CA - G3" (eMudhra), the roots above the intermediates compromised in
# October 2026. Python's urllib - every Netlify publish, and deploy.py's own
# Cloudflare calls - trusts this store, and OpenSSL checks no revocation, so
# distrusting the roots is the protection. The base's own copy is frozen at
# 20250419 by its digest, and the apt line above is cached on every Mac that
# has built before; trixie-security is in the base's sources, so this
# upgrades it without moving the digest. A FLOOR, not an `=` pin: Debian's
# security archive serves only its newest version, so an exact pin would break
# every first build the day deb13u2 ships, and a later version only distrusts
# more. The floor is written in this line, so raising it re-runs the layer,
# and a store older than it fails the build rather than shipping. Its own
# layer, late, so a teacher who has built before re-runs only this (~10 MB,
# seconds), not apt, wrangler, Quartz and npm (~330 MB). verify.sh checks
# the version and both subjects; contracts/toolchain.json -> pins ->
# caCertificates and documentation/02 -> "The certificate store" carry why.
RUN apt-get update \
 && apt-get install -y --no-install-recommends ca-certificates \
 && dpkg --compare-versions "$(dpkg-query -W -f='${Version}' ca-certificates)" ge 20250419+deb13u1 \
 && apt-get clean && rm -rf /var/lib/apt/lists/*

# GeoGebra (#578): the engine a class site's ```geogebra sketches run on,
# GeoGebra Math Apps 5.4.933.1, prepared into /opt/vendor/geogebra beside the
# other engines and under the same gate - a section's site carries it
# (static/geogebra, 27 MB) only while a page students can see has a sketch.
# scripts/geogebra_engine.py is the ONE recipe (Windows runs it too): it checks
# the zip's SHA-256 again, keeps the web3d codebase, leaves out the 83 language
# files, and makes six exact text replacements so the engine loads under a
# published site's content security policy - each must match exactly once or
# the build fails here, never on a teacher's page. download.geogebra.org is
# FLAKY (4 of 8 connections timed out, 2026-10-23) and keeps no old versions,
# so the download is retried, then fetched from plantoir.app's mirror of the
# SAME zip, and checked against the same SHA-256 whichever answered. Late, its
# own layer, after the certificate store it downloads through; the recipe is
# copied to /tmp only (never baked), so editing any other script never
# downloads it again.
# Non-commercial licence with attribution; contracts/toolchain.json -> pins ->
# geogebra and THIRD_PARTY_LICENSES.md carry the why.
ARG GEOGEBRA_VERSION=5.4.933.1
ARG GEOGEBRA_URL=https://download.geogebra.org/installers/5.4/geogebra-math-apps-bundle-5-4-933-1.zip
ARG GEOGEBRA_MIRROR=https://plantoir.app/mirror/geogebra/geogebra-math-apps-bundle-5-4-933-1.zip
COPY scripts/geogebra_engine.py /tmp/geogebra_engine.py
RUN test "$(python3 /tmp/geogebra_engine.py version)" = "$GEOGEBRA_VERSION" \
 && { curl -fsSL --retry 6 --retry-all-errors --retry-delay 5 --connect-timeout 30 --speed-limit 1024 --speed-time 60 -o /tmp/ggb.zip "$GEOGEBRA_URL" \
      || { echo "GeoGebra's own download did not answer; trying plantoir.app's copy of the same file" \
           && curl -fsSL --retry 6 --retry-all-errors --retry-delay 5 --connect-timeout 30 --speed-limit 1024 --speed-time 60 -o /tmp/ggb.zip "$GEOGEBRA_MIRROR"; }; } \
 && echo "409095947e065bce5bde20b8a6d56a60e2b3cb3cce6947e817a802513515ec0c  /tmp/ggb.zip" | sha256sum -c - \
 && python3 /tmp/geogebra_engine.py adapt /tmp/ggb.zip /opt/vendor/geogebra \
 && rm -f /tmp/ggb.zip /tmp/geogebra_engine.py

# Copy patched Quartz components into place
COPY patches/Explorer.tsx /opt/quartz/quartz/components/Explorer.tsx
COPY patches/FolderContent.tsx /opt/quartz/quartz/components/pages/FolderContent.tsx
COPY patches/explorer.inline.ts /opt/quartz/quartz/components/scripts/explorer.inline.ts
# Whether a page reaches the built site is decided by `publish:`, not `draft:`
# — the teacher's word, and the polarity they actually use.
COPY patches/publish.ts /opt/quartz/quartz/plugins/filters/publish.ts
COPY patches/filters-index.ts /opt/quartz/quartz/plugins/filters/index.ts
COPY patches/Head.tsx /opt/quartz/quartz/components/Head.tsx
COPY patches/build.ts /opt/quartz/quartz/build.ts

# Copy in setup_course.py, build_site.py, deploy.py
# toolchain_paths.py is the shared path shim: in here its container defaults
# apply untouched; the Windows-native runtime points it elsewhere via
# PLANTOIR_* environment variables.
COPY scripts/toolchain_paths.py /opt/scripts/toolchain_paths.py
COPY scripts/contracts.py /opt/scripts/contracts.py
# How long a machine line may be (#666): site_health, build_site and
# how_i_teach print their list-carrying lines through it.
COPY scripts/machine_line.py /opt/scripts/machine_line.py
COPY scripts/site_health.py /opt/scripts/site_health.py
# What a course calls its class pages and which folder they live in. Both
# setup_course.py and build_site.py import it by bare name, which only resolves
# if it is baked in beside them — and setup_course.py is IMPORTED further down
# this file, so a missing copy does not fail at run time, it fails the image
# build. Caught by verify.sh on 2026-09-04, which is the whole reason a
# toolchain change is gated on it: the unit tests were green and the image
# could not be built at all.
COPY scripts/class_pages.py /opt/scripts/class_pages.py
# Where a page's CODE is, so a link written inside code is not read as one
# (#313) — imported by build_site.py and setup_course.py; the rule is
# contracts/shared-rules.json → readingALink.whatIsCode.
COPY scripts/markdown_code.py /opt/scripts/markdown_code.py
# One home for "does the built site show this page?" — read by build_site.py
# and setup_course.py, and pinned by contracts/file-formats.json.
COPY scripts/page_visibility.py /opt/scripts/page_visibility.py
# Pages that print (#454): which pages opt in, a teacher's own PDF, the gate
# that puts the print engine only into sites that use it, and the corners of a
# printed page. Both imported by build_site.py by bare name.
COPY scripts/page_features.py /opt/scripts/page_features.py
COPY scripts/print_settings.py /opt/scripts/print_settings.py
# Diagrams and graphs (#485 E1): finds the fences, draws and checks them
# through support/figures/plantoir-figures.mjs, caches, and gates what the site
# carries. Imported by build_site.py by bare name.
COPY scripts/figures.py /opt/scripts/figures.py
# GeoGebra sketches (#578): reads the ```geogebra fences, finds and checks
# each sketch's file, and gates the engine the site carries. Imported by
# build_site.py by bare name.
COPY scripts/geogebra.py /opt/scripts/geogebra.py
# Runnable Swift (#493): which blocks the launcher must compile (`plan`, run by
# preview.sh through docker exec before the build) and what the build gives
# the site (`prepare`). Imported by build_site.py by bare name.
COPY scripts/swift_blocks.py /opt/scripts/swift_blocks.py
# Windows' half of runnable Swift (#570): getting Swift ready on a PC and the
# compile wrapper. Never run in this image - swift_blocks.py imports them
# only for a Windows toolchain id - but baked because it names them
# (test_baked_modules.py: a module a baked script imports is baked).
COPY scripts/swift_windows_fetch.py /opt/scripts/swift_windows_fetch.py
COPY scripts/swift_windows_compile.py /opt/scripts/swift_windows_compile.py
# Self-check quizzes (#563): the folder check that reads every `> [!quiz]` by
# the site's own rules and writes the words the site's quizzes use. Imported
# by build_site.py by bare name (test_baked_modules.py).
COPY scripts/quizzes.py /opt/scripts/quizzes.py
# My Progress (#545): whether a section gets the page, the page, its Key
# Links entry and the plan the site's emitter reads. Imported by build_site.py
# by bare name (test_baked_modules.py).
COPY scripts/my_progress.py /opt/scripts/my_progress.py
# What the SITE found (#567): a runnable block it showed as plain code, said
# as one folder problem. build_site.py imports it by bare name to write the
# side file, and the site's emitter (plantoirSiteSaid.ts) runs it as a file
# with the build's own Python (test_baked_modules.py).
COPY scripts/site_said.py /opt/scripts/site_said.py
# The teacher's How I Teach page is never on the website (#209): build_site.py
# asks this at discovery, preflight, the copy lists and a final sweep. Imported
# by bare name, so it must be baked beside it (test_baked_modules.py).
COPY scripts/how_i_teach.py /opt/scripts/how_i_teach.py
# Which processes belong to a section's preview — the one answer, imported by
# build_site.py before a build for publishing so the preview server cannot
# overwrite what was just built. `preview.sh --stop` does NOT run this copy:
# it pipes the recipe's own copy in over stdin, because stop mode must work
# against a container built from an older image and this file would not be in
# one. See contracts/shared-rules.json -> stopPreview.
COPY scripts/stop_preview.py /opt/scripts/stop_preview.py
COPY scripts/setup_course.py /opt/scripts/setup_course.py
COPY scripts/build_site.py /opt/scripts/build_site.py
# Is this course kept for reference, and therefore never deployed? deploy.py
# imports it by bare name, which only resolves if it is baked in beside it —
# and `test_baked_modules.py` fails the image build rather than letting a
# missing copy turn into an ImportError at a teacher's publish.
COPY scripts/reference_course.py /opt/scripts/reference_course.py
COPY scripts/deploy.py /opt/scripts/deploy.py
COPY scripts/social_card.py /opt/scripts/social_card.py
# deploy.py's Netlify ad-badge suppression lives in this sibling module —
# deploy.py imports it by bare name, which only resolves if it is baked in
# beside it.
COPY scripts/netlify_badge.py /opt/scripts/netlify_badge.py
# Live input (#583): which pages a publish isolates, and the _headers block
# that does it - deploy.py imports it by bare name, so it is baked beside it
# (test_baked_modules.py).
COPY scripts/isolation_headers.py /opt/scripts/isolation_headers.py
# Page addresses on Netlify (#628): a Netlify publish lower-cases each page
# link's path in memory as it uploads - deploy.py imports it by bare name, so
# it is baked beside it (test_baked_modules.py).
COPY scripts/netlify_paths.py /opt/scripts/netlify_paths.py

# Bake the Explorer's hide filter into the image.
#
# The filter — a `filterFn` carrying the CQ4T-OMIT-ANCHOR marker — is what
# makes a teacher's hidden pages actually hidden. `build_site.py` can only
# rewrite the CONTENTS of the `omit` Set inside it; it cannot create the
# filter. And `/opt/quartz` is the scaffold every section's site is copied
# from, so if the filter is not here, it is not in the built site either.
#
# It used to be established only by `setup_course.py` patching the RUNNING
# container at course-creation time. That made it container state rather than
# image state, and any container recreation — which is the documented
# behaviour whenever the recipe hash changes, i.e. after most toolchain
# updates — silently threw it away. The next build then published every page
# the teacher had hidden: Private Notes, Curriculum, Learning Goals. Baking it
# here means a container has it from birth, and setup's identical patch
# becomes a harmless no-op instead of the only source of truth.
#
# Same function, imported rather than copied, so the two cannot drift.
RUN python3 -c "import sys; sys.path.insert(0, '/opt/scripts');     import setup_course; setup_course.ensure_quartz_explorer_anchor()"  && grep -q 'CQ4T-OMIT-ANCHOR' /opt/quartz/quartz.layout.ts

# Copy course metadata lookup & other support files into container
COPY support/ /opt/support/

# The Plantoir contract, read by the scripts themselves (scripts/contracts.py).
# It must be baked in: the container's only bind mount is `courses`, so neither
# the working folder's .toolchain/ nor the app bundle is reachable from in
# here. A contract edit therefore changes the image hash and forces a rebuild —
# accepted deliberately, because the alternative is a shared rule the container
# cannot read.
COPY contracts/ /opt/contracts/

# --- Bake launcher scripts for export ---
RUN mkdir -p /opt/export
COPY setup.sh preview.sh deploy.sh /opt/export/
COPY setup.bat preview.bat deploy.bat /opt/export/
COPY setup.ps1 preview.ps1 deploy.ps1 /opt/export/
# Ensure .sh are executable (no-op on .bat)
RUN chmod +x /opt/export/*.sh || true
# Convert Windows launchers to CRLF line endings
RUN unix2dos /opt/export/*.bat
RUN unix2dos /opt/export/*.ps1

# --- Helper command to export scripts to a mounted folder ---
# Usage (macOS/Linux):   docker run --rm -v "$PWD":/out <image> export-scripts
# Usage (Windows PowerShell): docker run --rm -v "${PWD}:/out" <image> export-scripts
RUN cat >/usr/local/bin/export-scripts <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
DEST="/out"
if [ ! -d "$DEST" ]; then
  echo "❌ No /out mount found. Run with:  -v \"$PWD\":/out"
  exit 1
fi
cp -f /opt/export/* "$DEST"/
chmod +x "$DEST"/*.sh || true
echo "✅ Exported scripts to $DEST:" && ls -1 "$DEST" | sed 's/^/   - /'
EOF
RUN chmod +x /usr/local/bin/export-scripts

# Set default working directory
WORKDIR /teaching

# Default command
CMD ["/bin/bash"]

