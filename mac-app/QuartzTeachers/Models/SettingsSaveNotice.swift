import Foundation

/// What Course Settings says after a Save, and the line the Save leaves on
/// the trail (issue #265).
///
/// A preview and a publish both read the settings once, when their build
/// begins. So a Save made while one of them is running reaches neither, and
/// nothing used to say so: a teacher flipped a sidebar switch, saved, looked
/// at the open preview, and saw no change — which, repeated, reads as the
/// switches having "no correlation" with the site.
///
/// The decision is kept out of the view so it can be tested without one.
struct SettingsSaveNotice: Equatable {

    // MARK: - Stored properties

    /// The sentences to show under the Save button, in order.
    let sentences: [String]

    /// The sections of this course with a preview open, which Preview Again
    /// builds afresh. Empty when the button is not offered.
    let sectionsToPreviewAgain: [Int]

    // MARK: - Functions

    /// What to say after a Save of `courseCode`'s settings, or nil when
    /// nothing is running that the Save could miss.
    ///
    /// A publish running takes precedence, and then Preview Again is NOT
    /// offered: rebuilding a preview while that course is publishing is
    /// refused everywhere else in the app (`rebuildAfterRepair`), so a
    /// button that could only be refused would be worse than none. Once the
    /// publish finishes, the teacher previews from the section as usual.
    static func afterSave(
        folderPath: String,
        courseCode: String,
        previewLeases: [PreviewLeases.Lease],
        publishes: [CourseActivity.PublishRecord]
    ) -> SettingsSaveNotice? {
        let folder: String = standardised(folderPath)

        for publish in publishes {
            if standardised(publish.folderPath) == folder && publish.courseCode == courseCode {
                return SettingsSaveNotice(
                    sentences: [SpecialNames.settingsSavedWhilePublishing],
                    sectionsToPreviewAgain: []
                )
            }
        }

        var previewedSections: [Int] = []
        for lease in previewLeases {
            if standardised(lease.folderPath) == folder && lease.courseCode == courseCode {
                if !previewedSections.contains(lease.sectionNumber) {
                    previewedSections.append(lease.sectionNumber)
                }
            }
        }
        if previewedSections.isEmpty {
            return nil
        }
        previewedSections.sort()
        return SettingsSaveNotice(
            sentences: [SpecialNames.settingsSavedWhilePreviewing],
            sectionsToPreviewAgain: previewedSections
        )
    }

    /// What to say where a preview's progress appears, when it starts while
    /// Course Settings holds changes nobody saved — or nil.
    static func whenPreviewStarts(settingsHaveUnsavedChanges: Bool) -> String? {
        if settingsHaveUnsavedChanges {
            return SpecialNames.previewUsesSavedSettings
        }
        return nil
    }

    /// The "settings saved" line for the trail: which sidebar items this Save
    /// hid or showed (names only — the same names "item excluded" already
    /// records), whether it kept or replaced a change made elsewhere, and
    /// whether a preview or a publish was running. This line would have
    /// settled issue #265 in one read.
    static func trailLine(
        courseCode: String,
        hiddenBefore: [String],
        hiddenAfter: [String],
        result: CourseConfiguration.WriteResult,
        notice: SettingsSaveNotice?
    ) -> String {
        var line: String = "saved the settings for " + courseCode

        var newlyHidden: [String] = []
        for name in hiddenAfter {
            if !hiddenBefore.contains(name) {
                newlyHidden.append(name)
            }
        }
        var newlyShown: [String] = []
        for name in hiddenBefore {
            if !hiddenAfter.contains(name) {
                newlyShown.append(name)
            }
        }
        var sidebarParts: [String] = []
        if !newlyHidden.isEmpty {
            sidebarParts.append("hid " + newlyHidden.joined(separator: ", "))
        }
        if !newlyShown.isEmpty {
            sidebarParts.append("showed " + newlyShown.joined(separator: ", "))
        }
        if !sidebarParts.isEmpty {
            line += " — sidebar: " + sidebarParts.joined(separator: "; ")
        }

        if !result.keptFromElsewhere.isEmpty {
            line += "; kept what another window or a build had changed ("
                + result.keptFromElsewhere.joined(separator: ", ") + ")"
        }
        if !result.replacedChangesFromElsewhere.isEmpty {
            line += "; replaced what another window or a build had changed ("
                + result.replacedChangesFromElsewhere.joined(separator: ", ") + ")"
        }

        if let notice {
            if notice.sentences.contains(SpecialNames.settingsSavedWhilePublishing) {
                line += "; a publish of the course was running, told it uses the earlier settings"
            } else if !notice.sectionsToPreviewAgain.isEmpty {
                var sectionWords: [String] = []
                for section in notice.sectionsToPreviewAgain {
                    sectionWords.append(String(section))
                }
                line += "; a preview was open (section " + sectionWords.joined(separator: ", ")
                    + "), told it shows the earlier settings"
            }
        }
        return line
    }

    // MARK: - Private helpers

    private static func standardised(_ path: String) -> String {
        return URL(fileURLWithPath: path).standardizedFileURL.path
    }
}
