# wrangler 4.156.0's first-ever upload on Windows (2026-11-10, #719)

The Windows counterpart of `2026-10-31-first-upload.md` (the mac's, 4.80.0
and 4.156.0). Windows has the "after" half only: the director ruled out a
second pair of real sites for a 4.80.0 "before" run, which #719 did not ask
for.

**Conditions.** `verify-deploy.ps1 -FirstPublish` against
`C:\Users\lenov\Desktop\plantoir-deploy-verify` ICS3U section 1, on a Lenovo
20QES70500 (Intel Core i5-8365U, 16 GB, Windows 11 Pro 26200), wired
Ethernet, Ontario, from the worktree on `issue/719-wrangler-runtime-harness`
at 74855ccfe (only documentation uncommitted). The runtime was that
checkout's own fresh fetch (`windows-app\Vendor\runtime`, Node 22.23.4,
wrangler 4.156.0), passed to the launchers as `PLANTOIR_RUNTIME`. The
harness ran under Claude Code: its environment carried `CLAUDECODE` and
`AI_AGENT`, which wrangler 4.108+ reads when it decides whether to hand a NEW
project to Cloudflare Workers, and on Windows `deploy.py` runs natively, so
those variables reached wrangler (on the mac `docker exec` passes six named
variables only). `-FirstPublish` moved the section's surname and site
records aside, so `deploy.py` made a NEW Cloudflare Pages project through the
API (`ensure_pages_project`) and then ran
`wrangler pages deploy <public> --project-name=… --branch=main
--commit-dirty=true`, which was that project's first upload.

| | |
|---|---|
| Checkout | `issue/719-…` at 74855ccfe |
| wrangler / Node | 4.156.0 / 22.23.4 |
| Project | `ics3u-s1-2026-vdaqkcxetu` (and the Netlify site of the same name) |
| verify-deploy.ps1 -FirstPublish | 170 passed, 0 failed, 0 skipped (881 s) |
| First upload | 271 files, 4.09 s; the leg 53 s, 29,378 KiB sent |
| Second upload (same project, pairing 3) | `Uploaded 0 files (271 already uploaded) (0.30 sec)`; the leg 70 s, 579 KiB |
| Workers delegation | none: every Cloudflare leg passed `Check-NoDelegation` |
| A brand-new site's files (#743) | "no file needed asking again" on both new sites, every leg |

Both sites are left on the accounts (this harness deletes nothing; the mac's
does since #712).

**What wrangler printed** differs from the mac's 4.156.0 transcript only in
the counts (this course builds 271 files, the mac's ADA1O 278) and, on the
later legs, a banner naming `update available 4.160.0` (4.160.0 had been
published since the pin was chosen on 2026-10-31; the pin stays exact). The
first upload's success line has no `(N already uploaded)` part, which
`Measure-Deploy`'s count needed until this piece.

The transcript below is `deploy.py`'s and wrangler's lines from the PtyDriver
log, from the project being made to the end of the publish. The production
build in between is elided, and the progress spinner's frames are reduced to
one line per count. **Redacted: nothing needed it.** The log was checked for
32-hex account ids and for token, bearer, key and account words before it
was copied (0 of each); deploy.py reads the token from Windows Credential
Manager and never prints it, and the account id appears only in the API calls
deploy.py makes, which it does not echo. `C:\Users\lenov\AppData\Local\Plantoir\builds\f5278ed9\…`
is this PC's builds folder for that working folder, not a secret.

```
Deploying ICS3U S1 from this PC ...
 Deploying from local build: C:\Users\lenov\AppData\Local\Plantoir\builds\f5278ed9\ICS3U\section1\public
 Timestamp TZ offset: -0500
 Cloudflare project ready: ics3u-s1-2026-vdaqkcxetu
 Updating Quartz baseUrl to 'ics3u-s1-2026-vdaqkcxetu.pages.dev' and rebuilding for production…
…(the production build, elided)…
✅ Static build complete.
✅ Production build complete.
 Setting up 35 page(s) so their code can ask students for input as it runs…
 Uploading the built site to Cloudflare…

 ⛅️ wrangler 4.156.0
────────────────────
Uploading... (0/271)
Uploading... (90/271)
Uploading... (180/271)
✨ Success! Uploaded 271 files (4.09 sec)
✨ Uploading _headers
🌎 Deploying...
✨ Deployment complete! Take a peek over at https://1075d3ca.ics3u-s1-2026-vdaqkcxetu.pages.dev
 Live URL: https://ics3u-s1-2026-vdaqkcxetu.pages.dev

✅ Deploy complete.
```

The second upload to the same project (pairing 3, Netlify primary then
Cloudflare):

```
 ⛅️ wrangler 4.156.0 (update available 4.160.0)
✨ Success! Uploaded 0 files (271 already uploaded) (0.30 sec)
✨ Uploading _headers
🌎 Deploying...
✨ Deployment complete! Take a peek over at https://606d5706.ics3u-s1-2026-vdaqkcxetu.pages.dev
 Live URL: https://ics3u-s1-2026-vdaqkcxetu.pages.dev
```
