# Use a slim Node+Python base image
FROM python:3.11-slim

# Python packages: frontmatter parsing, and Pillow to draw each
# section's social sharing card.
RUN pip install python-frontmatter Pillow

# Install Node.js (needed for Quartz) and other tools (incl. dos2unix)
# fonts-noto-color-emoji: the colour emoji drawn onto social cards.
RUN apt-get update && apt-get install -y curl git lsof dos2unix fonts-noto-color-emoji rsync \
    && curl -fsSL https://deb.nodesource.com/setup_20.x | bash - \
    && apt-get install -y nodejs \
    && apt-get clean && rm -rf /var/lib/apt/lists/*

# Cloudflare's own deploy CLI, used by deploy.py for the Pages publishing
# target. It is pinned, and deliberately pinned BELOW 4.100: from 4.100 on,
# wrangler requires Node 22, while this image ships Node 20 because that is
# what Quartz v4.5.0 is known-good against. Raising Node to satisfy a newer
# CLI would mean revalidating every teacher's site build, which is a far
# larger risk than staying on the newest Node-20 wrangler. The exact pin also
# keeps the image reproducible and stops an upstream CLI change from breaking
# publishing for a teacher mid-semester.
RUN npm install -g wrangler@4.80.0 && npm cache clean --force

# Clone Quartz v4.5.0 into /opt/quartz
WORKDIR /opt
RUN git clone --branch v4.5.0 https://github.com/jackyzha0/quartz.git quartz

# Pre-install dependencies inside the image so npm install does not run over slow 9P mounts
RUN cd /opt/quartz && npm install --no-audit && npm cache clean --force

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

# Copy Quartz scaffold to /opt/quartz-site
RUN cp -r /opt/quartz /opt/quartz-site

# Copy in setup_course.py, build_site.py, deploy.py
# toolchain_paths.py is the shared path shim: in here its container defaults
# apply untouched; the Windows-native runtime points it elsewhere via
# PLANTOIR_* environment variables.
COPY scripts/toolchain_paths.py /opt/scripts/toolchain_paths.py
COPY scripts/contracts.py /opt/scripts/contracts.py
COPY scripts/site_health.py /opt/scripts/site_health.py
# What a course calls its class pages and which folder they live in. Both
# setup_course.py and build_site.py import it by bare name, which only resolves
# if it is baked in beside them — and setup_course.py is IMPORTED further down
# this file, so a missing copy does not fail at run time, it fails the image
# build. Caught by verify.sh on 2026-09-04, which is the whole reason a
# toolchain change is gated on it: the unit tests were green and the image
# could not be built at all.
COPY scripts/class_pages.py /opt/scripts/class_pages.py
# Which processes belong to a section's preview — the one answer, imported by
# build_site.py before a build for publishing so the preview server cannot
# overwrite what was just built. `preview.sh --stop` does NOT run this copy:
# it pipes the recipe's own copy in over stdin, because stop mode must work
# against a container built from an older image and this file would not be in
# one. See contracts/shared-rules.json -> stopPreview.
COPY scripts/stop_preview.py /opt/scripts/stop_preview.py
COPY scripts/setup_course.py /opt/scripts/setup_course.py
COPY scripts/build_site.py /opt/scripts/build_site.py
COPY scripts/deploy.py /opt/scripts/deploy.py
COPY scripts/social_card.py /opt/scripts/social_card.py
# deploy.py's Netlify ad-badge suppression lives in this sibling module —
# deploy.py imports it by bare name, which only resolves if it is baked in
# beside it.
COPY scripts/netlify_badge.py /opt/scripts/netlify_badge.py

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
RUN python3 -c "import sys; sys.path.insert(0, '/opt/scripts');     import setup_course; setup_course.ensure_quartz_explorer_anchor()"  && grep -q 'CQ4T-OMIT-ANCHOR' /opt/quartz/quartz.layout.ts  && cp /opt/quartz/quartz.layout.ts /opt/quartz-site/quartz.layout.ts

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

