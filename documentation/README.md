# Technical Documentation

**Two things this folder does NOT hold.** What the two apps must AGREE on is data, in [`contracts/`](../contracts/README.md), because both test suites run it — the sentences the assistant says, the arguments the launchers get, the keys `course_config.json` carries, the image pins. And the reasoning behind decisions an implementer needs is in [`WINDOWS-HANDOFF.md`](../WINDOWS-HANDOFF.md) and [`MAC-HANDOFF.md`](../MAC-HANDOFF.md). These pages explain how the toolchain WORKS; those say what must stay true.

**Audience:** computer science teachers who want to understand how this toolchain
actually works under the hood — not just how to use it. (For usage instructions,
see the main [README](../README.md); for the workshop walkthrough, see
[archived workshop handout](../archive/PRESENTATION-2025-08.md).)

This documentation explains the purpose, rationale, and mechanism of every part
of the system, including a complete enumeration of the customizations made to
the stock [Quartz v4.5.0](https://github.com/jackyzha0/quartz/tree/v4.5.0)
static-site generator.

## Reading order

| # | Document | What it covers |
|---|----------|----------------|
| 1 | [Overview & Design Rationale](01-overview.md) | Why this exists, the problems it solves, and the high-level architecture |
| 2 | [The Docker Image](02-docker-image.md) | What is baked into the `teaching-quartz` container and how each machine builds it locally from the recipe |
| 3 | [The Launcher Scripts](03-launcher-scripts.md) | The host-side `setup` / `preview` / `deploy` scripts for macOS and Windows |
| 4 | [Course Setup](04-course-setup.md) | The interactive wizard (`setup_course.py`) and the folder structure it creates |
| 5 | [The Build Pipeline](05-build-pipeline.md) | How `build_site.py` merges content and produces a per-section Quartz site |
| 6 | [Quartz Customizations](06-quartz-customizations.md) | **The complete list** of every change made to stock Quartz v4.5.0, with purpose and mechanism |
| 7 | [Publishing a built section](07-deployment.md) | The three destinations — Netlify (delta deploys against its API), Cloudflare Pages (via wrangler), and a folder on the teacher's own machine |
| 8 | [`course_config.json` Reference](08-course-config-reference.md) | Every key in the per-course configuration file |
| 9 | [The macOS App — Plantoir](09-mac-app.md) | The native GUI (`mac-app/`), how it drives the same scripts, and how it delivers the toolchain itself |
| 10 | [The Local AI Assistant](10-local-ai-assistant.md) | What the on-device model is and how it is configured, with enough background on language models to follow it — and how a typed sentence becomes a Swift function call |
| 11 | [Release Strategy & Production Deployment](11-release-strategy.md) | The packaging, Developer ID code-signing, Apple Notarization, Azure Trusted Signing, Inno Setup, and cross-platform release pipeline |

## The one-paragraph summary

A teacher writes course notes as Markdown files in an
[Obsidian](https://obsidian.md) vault, organized into *shared* folders (content
common to every section of a course) and *per-section* folders. A Docker
container — which bundles Python, Node.js, and a patched copy of Quartz
v4.5.0 — merges the shared and section content into a single content tree,
applies roughly forty targeted patches to Quartz's configuration and
components (colour scheme, fonts, locale, sidebar behaviour, date handling,
and more, all driven by a per-course `course_config.json`), and builds a
static website. The teacher previews the site locally (the launcher prints
the address — each working folder gets its own port block, so several
sections can preview at once), then deploys it to Netlify using a
hash-based delta upload that only transfers files that actually changed.
Most teachers do all of this through the Plantoir app, which also carries
the toolchain itself into each working folder's `.toolchain/`.

## Map of the moving parts

```
HOST (teacher's computer)              CONTAINER (teaching-quartz-<hash8>,
─────────────────────────               one per working folder)
.toolchain/  ◀── recipe, mirrored      ───────────────────────────
             by the Plantoir app
setup.sh / setup.ps1      ──docker exec──▶  /opt/scripts/setup_course.py
preview.sh / preview.ps1  ──docker exec──▶  /opt/scripts/build_site.py
                                            (draws /opt/scripts/social_card.py's card)
deploy.sh / deploy.ps1    ──docker exec──▶  /opt/scripts/deploy.py
                                             │
courses/  ◀──────bind mount──────▶  /teaching/courses/
  ICS3U/                                     │
    course_config.json    ◀── written by setup, read by build
    section1/ … Examples/ …                  │
    .merged_output/  ◀── a SHORTCUT, out of the working folder to
      section1/            ~/Library/Application Support/Plantoir/builds/…
        public/           ◀── built site  ──▶  Netlify API
        course_config.json    (the scaffold and node_modules stay on the
                               container's own storage and never land here)
```
