---
id: missing-page
checked: 2.0.0
covers:
- contracts/file-formats.json
- contracts/shared-rules.json
- mac-app/QuartzTeachers/Models/SectionProblemsWording.swift
- mac-app/QuartzTeachers/Models/SpecialNames.swift
- mac-app/Tests/Goldens/menu-bar.txt
keywords:
- page missing
- missing page
- page not showing
- not on the site
- students cannot see
- students can't see
- hidden
- not published
- publish
- deploy
- settings cannot be read
description: The reasons students do not see a page you wrote, in the order to check them.
---
When students do not see a page you wrote, one of six things is the cause. Check them in this order.

## Check these in order

1. **Is the page published for that section?** A shared page is published for one section at a time. It can be hidden in the section you are looking at and shown in another. Select the section and choose {{menu:publishPages}}, which lists the pages that are hidden in that section. See [Show or hide pages for a section](page:publish-pages). For the lines themselves, see [Which classes see a page](page:page-settings).
2. **Can the page's settings be read?** When the settings at the top of a page cannot be read, the page is hidden in every section. The section's {{control:problemsTab}} tab names the page, in a row of the kind {{control:problemsTabKindPageSettings}}. Correct the settings in Obsidian.

{{picture:missing-page-1}}
alt: A section's Problems tab, with a row that names a page whose settings cannot be read.

3. **Are you looking at an old preview?** A preview shows the pages as they were when it was made. While a preview is running, choose {{menu:rebuildPreview}} ({{key:rebuildPreview}}). Otherwise press {{control:previewButton}}. See [Preview a section](page:preview).
4. **Has the section been deployed since?** Publishing a page changes what the preview shows. Students see the page only after the section is next deployed. See [Deploy a section](page:deploy).
5. **Was the page's folder removed in Course Settings?** A folder removed there stays off the website, even if you make it again in Obsidian. The folder's own page carries a note that says so. Add the folder back in Course Settings. See [Shared folders and section folders in Course Settings](page:course-folders).
6. **Does a link lead to it?** A page students can see may link to a page that is hidden. The {{control:problemsTab}} tab names such a link, in a row of the kind {{control:problemsTabKindLinkToAHiddenPage}}. See [Publish the pages a class page links to](page:links-checklist).

## Publishing and deploying are two acts

The first cause and the fourth are the two halves of one rule. A page reaches students when it is published for their section and that section has been deployed since. [Publishing and deploying](page:publish-and-deploy) explains the rule, and {{menu:publishingAndDeploying}} shows the same explanation in the app.

[The Problems tab](page:problems) says how to read the rows named above.
