# An Even Faster Workflow for Publishing Teaching Materials

> 🗄️ **Historical artifact**
>
> This document was this repository's README from the August 2025 CEMC Summer
> Conference workshop through the 1.0.0 release, and is preserved as presented.
> For current instructions, teachers should visit [plantoir.app](https://plantoir.app)
> and developers should start with the [README](README.md).

> ℹ️ **Note**
> 
> This software was discussed in person on Thursday, August 14, 2025 at the [Summer Conference for Computer Studies and Mathematics Educators](https://cemc.uwaterloo.ca/workshops/educator-development/summer-conference-educators), organized by the [Centre for Education in Mathematics and Computing](https://www.cemc.uwaterloo.ca/).

**Workshop Description:**

Content management systems such as Edsby, Brightspace, Google Classroom... the list of third-party platforms we depend on as teachers to share information with our students is long. The user interfaces of these systems? Questionable, often requiring a time-consuming series of clicks and selections to publish even the simplest information. Further, it is often difficult to move your valuable content out of these systems.

In this session, the presenter will share a pre-configured publishing system that you control, can take away from the conference, and then run on your own computer to build modern, standards-compliant class websites.

In the session, optionally complete a series of “quests” to learn how to use this publishing workflow and get assistance from the presenter in setting up your own website on the spot. You will learn how to use Markdown-formatted text files to quickly publish a deeply linked, searchable website, with pages that can include “pretty-print” mathematical formulae and equations, code snippets, diagrams, animations, images, videos, PDF files, or any other type of document.

> 🏗️ **Tip**
>
> You can browse [an example of the type of output produced by this workflow here](https://exc2o-s1-2024-gordon.netlify.app). That site represents half of the author's Grade 10 Digital Tech course materials for the most recent school year.

> ℹ️ **Note**
> 
> For those with good memories, this is an update of the 2023 session titled “[A Rapid Workflow for Publishing CS Teaching Materials](https://teaching.russellgordon.ca/cemc/sccst-2023/a-rapid-workflow-for-publishing-cs-teaching-materials/)”, with new software, much less work involved to get a site up and running, and a better end-product. This new session is suitable for and useful for both mathematics and computer science teachers.

> 📘 **Info**  
> Initial drafts of this documentation were generated using ChatGPT 4o and ChatGPT 5, and later edited by Russell Gordon.

---

## 🚀 Quick Start (For Teachers)

### ✅ Prerequisites

**On macOS, none.** Everything the toolchain needs on the host — the container
runtime, the Docker command-line tools, and the image builder — installs itself
into `~/Library/Application Support/Plantoir/tools` the first time you set up or
preview a site (no Homebrew, no administrator password). The first run needs an
internet connection and a few minutes; after that everything is cached.

**On Windows, one thing: WSL2, installed once.** Installing it needs an
Administrator PowerShell and a reboot, which is why the scripts cannot do it for
you — see Step 1 below. Everything after that, including the Docker engine
inside WSL, the scripts install and start themselves.

### 1. Set up the container runtime (one-time)

**macOS (bash/zsh):**

Nothing to do. The first time you run `./setup.sh` or `./preview.sh`, the script
downloads [Colima](https://github.com/abiosoft/colima) — a free, open-source
container runtime — along with the Docker tools, and starts it for you. It stays
started; you never have to launch it by hand.

> 💡 **Tip**
>
> Already using Colima for other development work? No problem — the scripts share the running VM as-is and never shut it down. If another toolchain created the VM with its own CPU/RAM settings, those are respected.
>
> If you use Homebrew and would rather manage the runtime yourself, `brew install colima docker` is all you need: the scripts use whatever is already on the machine and download only what is missing.

**Windows (PowerShell):**

Install WSL2 (Windows Subsystem for Linux) by running this in an **Administrator** PowerShell, then **reboot**:
```powershell
wsl --install
```

After rebooting, finish the short Linux username/password setup that appears.
That is the whole of it: the first time you run `.\setup.bat` or
`.\preview.bat`, the script offers to install the Docker engine inside WSL and
then starts it for you.

> 💡 **Tip**
>
> This is one-time setup. From now on, the launcher scripts start the Docker engine inside WSL automatically whenever it is not running.

### 2. Get the toolchain

The easiest way is the **macOS app** or the **Windows app**, which set up a
working folder for you and keep it up to date. Working from the command line
instead, copy this repository (or the launcher scripts plus the `.toolchain/` folder from an
existing working folder) into the folder where your courses will live.

Either way, the website-builder image is **built locally on your machine**
from the recipe in the folder — the first run takes a few minutes and needs
an internet connection; after that it is cached until the toolchain updates.

---

### 3. Set up your course

On macOS:
```bash
./setup.sh
```

On Windows:
```powershell
.\setup.bat
```

This will:
- Offer to install an example course (recommended for first-time users)
- If you do not install the example course, it will:
   - Prompt you for the course code, name, and number of sections
   - Offer **ready-made content for that course code** where it exists —
     dozens of Ontario codes (37 today) ship with a full working course,
     including the Ministry's expectations as linkable pages. Accepting it
     settles the structure completely: the pages were written for that exact
     layout, so no folder questions are asked
   - Otherwise offer a **starting skeleton shaped for the subject** — a
     drama course opens with Conventions and Warm-Ups, a chemistry course
     with Investigations and lab safety — with four units of class pages to
     rename and placeholder pages saying what belongs where
   - If you declined the ready-made content, let you adjust the shared
     folders it suggests (e.g., “Exercises”, “Examples”)
   - Let you choose a colour scheme for each section with a live swatch
     preview — this and the other cosmetic choices are asked either way
   - Create everything under `./courses/<CourseCode>` ready for editing

---

### 4. Edit content in Obsidian

Open the `courses/` folder in Obsidian or your favorite Markdown editor.

Structure:
```
courses/
  ICS3U/
    section1/
    section2/
    Examples/
    Exercises/
    ...
```

---

### 5. Preview your site

> ℹ️ **Note**
>
> **`ICS3U`** is used as an example in the command given below – be sure to replace the course code with whatever course you set up in Step 2 above.

On macOS:
```bash
./preview.sh ICS3U 1
```

On Windows:
```powershell
.\preview.bat ICS3U 1
```

This will:
- Combine content from shared folders and `section1`
- Build a live Quartz site into `courses/ICS3U/.merged_output/section1`
- Launch a local preview at the address the script prints, normally:

👉 [http://localhost:8081](http://localhost:8081)

---

### 6. Publish your site (Deploy)

> ℹ️ **Note**
>
> **`ICS3U`** is used as an example in the command given below – be sure to replace the course code with whatever course you set up in Step 2 above.

Once you’re happy with your preview, you can publish the site so students and others can see it.

On macOS:
```bash
./deploy.sh ICS3U 1
```

On Windows:
```powershell
.\deploy.bat ICS3U 1
```

This will:
- Package the built site for the chosen section
- Allow you to deploy the site to **Netlify**, which will host your site publicly

> ℹ️ Netlify is the default, but not the only choice. Add
> `--target cloudflare` to publish to **Cloudflare Pages** instead (free,
> with unmetered bandwidth; it asks once for an API token and your account
> ID, and refuses individual files over 25 MB). Add
> `--to-folder <path>` to copy the finished site into a folder on your own
> machine instead — useful if your school or university already gives you
> web space. The apps offer the same three choices as a menu, per course.


---

## 🧼 File Structure

```
plantoir/
├── .toolchain/                 # The image recipe and support files
├── courses/                    # Teacher-created content goes here
│   └── ICS3U/
│       ├── section1/
│       ├── section2/
│       ├── Examples/
│       ├── Exercises/
│       └── Media/              # Images, videos, PDFs (created for you)
├── preview.sh / preview.bat    # Build + preview a section site
├── setup.sh / setup.bat        # Run course setup wizard
├── deploy.sh / deploy.bat      # Deploy a built site
└── README.md
```

---

## 🛠️ Troubleshooting

| Problem | Solution |
|--------|----------|
| **Colour picker not showing correct colours** | If on macOS, make sure you are using [iTerm2](https://iterm2.com) instead of the default Terminal app for full colour support. |
| **macOS: "Colima did not become ready"** | Run `colima stop --force && colima start`, then re-run the script. This state can occur after the Mac sleeps or shuts down uncleanly. |
| **Windows: "The Docker engine inside WSL did not become ready"** | Run `wsl -u root -e sh -c "service docker start"`, then re-run the script. If WSL itself misbehaves, `wsl --shutdown` followed by re-running the script often helps. |

---

## 🧑‍💻 Contributing

Working on the toolchain or the macOS and Windows apps themselves? Start with
[CLAUDE.md](CLAUDE.md) — the single entry point: setup on a new machine (the
Xcode project is generated, not committed), what gates what, the conventions
this repository follows, and where everything else lives.

---

## 🙏 Credits

- [Quartz](https://github.com/jackyzha0/quartz) by [Jacky Zhao](https://jzhao.xyz/)
- Docker integration and teacher-friendly workflow by [Russell Gordon](https://github.com/russellgordon)

---

## 📣 License

MIT License. Use, remix, and share freely — especially with other educators.
