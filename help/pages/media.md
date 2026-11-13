---
id: media
checked: 2.0.0
covers:
- support/agent_guidance/skills/plantoir-page-authoring/SKILL.md
- contracts/shared-rules.json
- contracts/app-rules.json
- scripts/build_site.py
keywords:
- picture
- pictures
- image
- images
- photo
- photos
- PDF
- attach a file
- file
- Media folder
- video file
- picture not showing
- file too large
- 25 MB
description: Put pictures, PDFs and other files in the Media folder, then show or link them from a page.
---
Pictures, PDFs and video files of your own go in the course's Media folder. A page then shows a file or links to it. This page gives the steps and the forms to type.

## Put a file on a page

1. Copy the file into the Media folder. Use only letters, digits, spaces and hyphens in the file's name.
2. In Obsidian, open the page and type one of the forms listed below.
3. In Plantoir, preview the section and look at the page. If a preview is already running, choose {{menu:rebuildPreview}}.

{{picture:media-1}}
alt: A page in Obsidian showing a picture that is kept in the Media folder, with the Media folder marked in the file list.

## The forms to type

- `![[name.png]]` shows a picture.
- `![[name.png|300]]` shows the picture at a width, here 300 pixels.
- `![description](Media/name.png)` shows the picture and carries a description of it.
- `![[name.pdf]]` shows a PDF in a frame on the page.
- `[[name.pdf|words]]` is a link to the PDF. Students see the words.
- `![[clip.mp4]]` shows a video file of your own.

The description is for students who cannot see the picture.

## What to know about the Media folder

- **Every file in Media goes to the website.** Keep a file out of Media if students should not have it.
- **Media is not in the website's sidebar.** Plantoir looks after the folder itself. Students reach a file through the page that shows it or links to it.
- **Copy the file in.** Do not point a page at a picture on another website, or at a file somewhere else on your Mac. Copy the picture into Media and show it from there.
- **Do not remove or rename the folder.** If Media goes missing, pictures stop appearing on the website, and the section's {{control:problemsTab}} tab says so. See [The Problems tab](page:problems).

## Large files

Cloudflare Pages refuses any single file larger than 25 MB. A deploy to Cloudflare Pages that holds such a file is refused, with a sentence that names the file.

Make the file smaller, or take it out of Media, and deploy again. A video can go on YouTube instead of in Media: see [Put a video on a page](page:videos).

## If it does not work

- **The picture is missing from the preview.** Check that the file is in Media and that the name on the page matches the file's name, with its ending.
- **The picture shows in the preview but students do not see it.** The section has not been deployed since you added it. See [Deploy a section](page:deploy).
- **The page itself is missing.** It is not published for that section. See [Show or hide pages for a section](page:publish-pages).
