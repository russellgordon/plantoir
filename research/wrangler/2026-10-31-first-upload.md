# wrangler's first-ever upload, before and after #699 (2026-10-31, #712)

**Conditions.** Both runs are `./verify-deploy.sh --first-publish
~/plantoir-640-vd ADA1O 1` on an M4 Pro, Colima (arm64), home network,
Ontario, with `CLAUDECODE` and `AI_AGENT` set in the harness's own
environment (it ran under Claude Code). `--first-publish` moved the section's
surname and site records aside, so each run created a NEW Cloudflare Pages
project (`ensure_pages_project`, through the API) and then made its first
upload to it, which is what this file is for: the plain run reuses a project
and never shows one. deploy.py ran wrangler as it always does,
`wrangler pages deploy <public> --project-name=… --branch=main
--commit-dirty=true` with `CI=1` and `WRANGLER_SEND_METRICS=false`, inside the
container (`docker exec`, six named variables only).

| | Before | After |
|---|---|---|
| Checkout | `issue/699-…` at c0914cd2f (dev's recipe; only verify-deploy.sh changed) | 72d80ae2d (the change) |
| Image | `teaching-quartz:src-ef50b96c` | `teaching-quartz:src-63d46fd0` |
| wrangler / Node | 4.80.0 / 22.23.4 | 4.156.0 / 22.23.4 |
| Project | `ada1o-s1-2026-testingjjawtn` | `ada1o-s1-2026-testingcnfwll` |
| verify-deploy.sh | 173 passed, 1 failed, 0 skipped | 175 passed, 0 failed, 0 skipped |
| First upload | 278 files, 5.82 s; leg 18 s, 30,690 KiB sent | 278 files, 4.36 s; leg 20 s, 30,128 KiB sent |
| Second upload (same project) | `Uploaded 232 files (46 already uploaded)` | the same |

The one failure before was a Netlify link on the brand-new Netlify site
(`/portfolios/showing-growth`, HTTP 404), which answered 200 when fetched by
hand minutes later; nothing on the Cloudflare side. Both projects (and both
Netlify sites) were deleted by the run itself at its end (HTTP 200 and 204).

**What changed in what wrangler prints:** the banner (4.80.0 announced
`update available 4.156.0`), and nothing else. Neither run printed the
Pages-to-Workers delegation notice; every Cloudflare leg passed
verify-deploy.sh's check for it. The first upload's success line has no
`(N already uploaded)` part in either version, which verify-deploy.sh's
upload-count pattern used to require (#712's fix to it).

The transcripts below are deploy.py's and wrangler's lines from the log,
from the project being made to the end of the publish. The production build
in between is elided; the expect harness's log carries every line twice, and
each is kept once; the progress spinner's frames are reduced to one line per
count. `ð` in the log is wrangler's 🌎, mangled by the log's double encoding,
and is written as 🌎 here. No credential is in either: the token is piped,
never printed, and the account id appears only on the harness's own command
line, which is left out.

## Before: wrangler 4.80.0

```
 Cloudflare project ready: ada1o-s1-2026-testingjjawtn
…(the production build, elided)…
 Setting up 1 page(s) so their code can ask students for input as it runs…
 Uploading the built site to Cloudflare…
 ⛅️ wrangler 4.80.0 (update available 4.156.0)
──────────────────────────────────────────────
Uploading... (0/278)
Uploading... (92/278)
Uploading... (185/278)
✨ Success! Uploaded 278 files (5.82 sec)
✨ Uploading _headers
🌎 Deploying...
✨ Deployment complete! Take a peek over at https://5572e91b.ada1o-s1-2026-testingjjawtn.pages.dev
 Live URL: https://ada1o-s1-2026-testingjjawtn.pages.dev
✅ Deploy complete.

```

## After: wrangler 4.156.0

```
 Cloudflare project ready: ada1o-s1-2026-testingcnfwll
…(the production build, elided)…
 Setting up 1 page(s) so their code can ask students for input as it runs…
 Uploading the built site to Cloudflare…
 ⛅️ wrangler 4.156.0
────────────────────
Uploading... (0/278)
Uploading... (92/278)
Uploading... (185/278)
✨ Success! Uploaded 278 files (4.36 sec)
✨ Uploading _headers
🌎 Deploying...
✨ Deployment complete! Take a peek over at https://2f1aac57.ada1o-s1-2026-testingcnfwll.pages.dev
 Live URL: https://ada1o-s1-2026-testingcnfwll.pages.dev
✅ Deploy complete.

```
