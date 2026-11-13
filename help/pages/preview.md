---
id: preview
checked: 2.0.0
covers:
- mac-app/QuartzTeachers/Views/Section/SectionDetailView.swift
- mac-app/QuartzTeachers/Models/PreviewStartPage.swift
- mac-app/QuartzTeachers/Views/Settings/PreviewSettingsView.swift
- mac-app/QuartzTeachers/Models/SubjectMenuRules.swift
- contracts/shared-rules.json
- contracts/app-rules.json
- mac-app/Tests/Goldens/menu-bar.txt
keywords:
- preview
- see the site
- view site
- look before deploying
- stop preview
- rebuild
- rebuild preview
- refresh
- reload
- change not showing
- preview not updating
- open in browser
- Safari
- Chrome
- last viewed
description: Preview shows a section's website on your Mac, with the pages published for that section, before anything is deployed.
---
A preview shows a section's website on your Mac, as its students would see it. It holds the pages that are published for that section. Nothing is sent anywhere.

## Start a preview

1. In the sidebar, select the section.
2. Press {{control:previewButton}} in the toolbar, or choose {{menu:preview}} ({{key:preview}}). Plantoir says what it is doing while it makes the website. The first preview on a Mac takes longer than later ones: see [The first preview is slow](page:slow-first-build).

{{picture:preview-2}}
alt: The section's window while a preview is made, with a line that says what is happening now.

3. Read the website when it appears in the section's window. If the window shows tabs, the website is on the {{control:websiteTab}} tab.

{{picture:preview-1}}
alt: A section's preview in its window, with Back, Reload, Stop Preview and Open in Browser marked in the toolbar.

## Move around in the preview

- {{control:back}}, {{control:forward}} and {{control:reload}} in the toolbar work as they do in a web browser. The same commands are {{menu:viewBack}} ({{key:viewBack}}), {{menu:viewForward}} ({{key:viewForward}}) and {{menu:viewReloadPage}} ({{key:viewReloadPage}}).
- {{control:openInBrowser}} in the toolbar, or {{menu:sectionOpenInBrowser}}, opens the page you are looking at in your web browser.

## See a change you made

A preview shows the pages as they were when it was made. A change you make to a page in Obsidian afterwards is not in it.

1. Choose {{menu:rebuildPreview}} ({{key:rebuildPreview}}). Plantoir makes the website again and shows it, starting at the front page.

{{control:reload}} does not show the change. It loads the same copy of the website again.

## Stop the preview

While a preview runs, the {{control:previewButton}} button and menu item are named {{control:stopPreview}}. Press it to end the preview. The window then says {{control:noPreviewRunning}}.

Deploying the section also stops its preview.

## Choose where a preview opens

A preview opens on the website's front page. You can have it open on the page you last viewed in that section instead.

1. Choose {{menu:settings}} and open the {{control:previewPane}} pane.
2. Under {{control:previewOpensSetting}}, choose {{control:frontPageChoice}} or {{control:lastViewedChoice}}.

{{picture:preview-3}}
alt: The Preview pane of Settings, with the two choices for where a preview opens.

To do the other one once, hold Option as you press {{control:previewButton}}. The pane says:

{{say:shared-rules#previewStartPage.wording.optionNote}}

With the front page as your setting, the other name is {{control:previewAtLastViewed}} ({{key:previewAtLastViewedMenu}}).

Plantoir remembers the last page for each section, and keeps it when you quit. Only pages you click to in Plantoir's own window count. A page you opened in your web browser does not. If the remembered page no longer exists, the preview opens on the front page.

## If it does not work

- **A page is missing from the preview.** It is not published for this section. See [Show or hide pages for a section](page:publish-pages).
- **The preview does not finish.** The section's window says what went wrong.
- **{{menu:rebuildPreview}} is greyed.** It is live only while a preview is running. Press {{control:previewButton}} instead.
- **A sheet titled {{control:rebuildPreviewTitle}} appears.** The preview could not be made again at that moment, and the sheet says why.
- **{{control:openInBrowser}} is greyed.** No preview is running.
- **The preview does not show a change to the course's settings.** A preview uses the settings as they were last saved, and a notice says so. Save them, then preview again.
