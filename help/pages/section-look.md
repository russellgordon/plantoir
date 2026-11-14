---
id: section-look
checked: 2.0.0
covers:
- mac-app/QuartzTeachers/Views/CourseSettings/SectionSettingsView.swift
- mac-app/QuartzTeachers/Views/CourseSettings/ColourSchemePickerView.swift
- mac-app/QuartzTeachers/Views/CourseSettings/FontChoiceEditorView.swift
- mac-app/QuartzTeachers/Views/CourseSettings/CourseSettingsView.swift
- mac-app/QuartzTeachers/Views/Wizard/NewCourseWizardView.swift
keywords:
- look
- appearance
- colour
- colours
- color
- colors
- colour scheme
- theme
- font
- fonts
- emoji
- site title
- grade in the title
description: Change one section's header emoji, colour scheme, fonts and site title, in that section's part of the course's settings.
---
Each section's website has a look of its own: an emoji, a colour scheme, fonts, and what its title says. You change it in that section's part of the course's settings.

When a course is made, the {{control:newCourseOrClub}} sheet sets one look for every section. After that, each section can differ.

## Steps

1. In the sidebar, select the course. Its settings show.
2. Scroll to the end of the form. After {{control:courseSettingsSidebarVisibilityPart}} there is one part for each section, headed with the section's number.
3. At the top of the section's part, set the emoji and what the site's title says:
   - {{control:sectionSettingsHeaderEmoji}}: the emoji in the website's header.
   - {{control:sectionSettingsShowSectionMarker}}: adds a short marker for the section, such as S1, beside the code.
   - {{control:sectionSettingsShowTheGrade}}: puts the grade before the name. An orange warning shows if the name already says the grade.
4. Choose a {{control:sectionSettingsColourScheme}}. A sample beside the word Preview shows the scheme you have chosen.

{{picture:section-look-1}}
alt: One section's part of the course's settings, with the Colour scheme choice and its sample beside the word Preview.

5. Choose the fonts. Each shows a sample sentence.
   - {{control:sectionSettingsHeaderAndBodyFonts}}: the fonts for headings and for ordinary text.
   - {{control:sectionSettingsCodeFont}}: the font for code.

{{picture:section-look-2}}
alt: The Header & body fonts and Code font choices in a section's part, each with a sample sentence.

6. Press {{control:courseSettingsSaveButton}} at the bottom of the form.

## See the change

The new look shows the next time the section is previewed.

- If a preview of the course is open when you save, a notice appears. Press its {{control:courseSettingsPreviewAgain}} button.
- Otherwise, select the section and press {{control:previewButton}}.

Students see the new look after the section is next deployed.

## The other things in a section's part

Each section's part ends with a fold-down named {{control:sectionSettingsAdvanced}}. It holds the field for a domain of your own. [Choose where a section deploys](page:destinations) explains it.

The rest of the form applies to the whole course. See [Change a course's settings](page:course-settings).

## If it does not work

- **The preview still shows the old look.** A preview uses the settings as they were last saved, and a running preview keeps the settings it started with. Save, then preview again.
- **The website students see has not changed.** Deploy the section.
- **You changed the wrong section.** Each part is headed with its section's number. Press {{control:courseSettingsRevertButton}} before saving to put the form back.
