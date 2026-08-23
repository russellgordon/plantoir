# TODO — today

Found on 2026-08-23 while clearing stale containers after the UI-test
stub work. Not caused by that branch; it wants its own piece of work.

## Docker images leak forever — nothing in the repo ever removes one

`docker system df` on this Mac, 2026-08-23:

```
Images       139 total   50.09 GB   17.95 GB reclaimable
Containers    23 total    0.65 GB    0.64 GB reclaimable
Build cache 1301 entries 14.30 GB   14.25 GB reclaimable
```

About **115 `teaching-quartz:src-*` tags**. I grepped every `.sh`, `.ps1`,
`.py`, `.swift` and `.cs` in the repository for `docker rmi`, `image prune`
and `dangling`: **zero hits**. Nothing has ever removed an image.

**Containers are NOT the problem, and are already handled.** Each launcher
removes its own container by name before recreating it (`preview.sh:622-644`,
same in `setup.sh` and `deploy.sh`), and the name is a hash of the working
folder, so it is one container per folder, replaced in place. The stale ones
found today were ten DISTINCT working folders, all throwaway test folders on
this dev machine ("Thursday morning 2", "BC Courses", "more deploy testing").
A teacher has one working folder, maybe two, forever. 654 MB for all 23
containers. Do not spend effort here.

**Images are the problem, and it is not only a dev artifact.** The tag is a
hash of the build recipe, so every recipe change mints a new tag and orphans
the previous one permanently. The 115 tags here came from twelve days of
toolchain edits — that part is dev-only — but the MECHANISM reaches teachers:
their recipe changes every time they install a new Plantoir version, so a
school year of releases leaves a pile of orphaned images that nothing ever
removes. Layer sharing softens it (139 images are 50 GB, not 300), but the
deltas never come back. School Macs are commonly 256 GB, and the teacher has
no way to connect "my disk is full" to Plantoir — they have never heard of an
image.

### What a fix probably looks like

After building a new tag, remove older `teaching-quartz:src-*` tags that no
container references. Low risk, because an image is reproducible from the
bundled recipe: deleting one costs a rebuild, not data.

### The constraint that makes this easy to get wrong

**Colima is shared** (CLAUDE.md rule 7), and that rule applies to images as
much as to the VM. A bare `docker image prune -a` or `docker system prune`
would delete the Supabase images this machine also hosts. Any cleanup must
filter to `teaching-quartz:src-*` AND skip anything a container references.
This is exactly the sort of thing that looks obvious and goes wrong once.

Two more things worth deciding rather than assuming:

- **How many to keep.** Keeping the current tag plus one previous makes a
  Plantoir downgrade cheap; keeping only the current one reclaims more. No
  measurement behind either yet.
- **The build cache is the bigger number here** (14.25 GB, all reclaimable)
  and is NOT addressed by removing images. `docker builder prune` is global,
  so decide deliberately whether the launchers should ever touch it, or
  whether it stays a thing the developer clears by hand.

### Gate

This is a toolchain change, so it needs `verify.sh` behind it, and per
CLAUDE.md rule 3 a note for Windows.

~~their launchers have the same gap~~ — **WRONG, corrected 2026-08-23.**
Windows dropped Docker entirely on 2026-08-19 for the native runtime, so there
is no image, no tag and no container on that side to leak. Nobody should port
a cleanup for images that do not exist. Left visible rather than deleted
because this file was read as the brief for the work.

### ✅ DONE — 2026-08-23

Fixed on `issue/prune-old-toolchain-images`: `prune_superseded_images()` in all
three bash launchers, gated by `verify.sh` §3c. Written up in
`GUI-IMPROVEMENTS.md` row 352 and `WINDOWS-HANDOFF.md`; the build-cache
decision (deliberately NOT addressed, and why) is in `TODO.md`.
