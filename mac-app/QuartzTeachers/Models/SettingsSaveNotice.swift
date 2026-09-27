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

    /// What this Save means for the course's scheduled deploys in this
    /// working folder (#323), kept as FACTS rather than parsed back out of
    /// the sentences, for the trail line.
    var scheduledDeploys: [ScheduledDeployAtSave] = []

    // MARK: - Types

    /// One section's scheduled deploy, as a Save leaves it (GitHub #323).
    struct ScheduledDeployAtSave: Equatable {

        // MARK: - Stored properties

        let section: Int
        let moment: Date

        /// Where the course deploys after the Save, in the teacher's words.
        let destinationsNow: [String]

        /// Why it could not go ahead as set now, or nil when it would.
        let refusal: ScheduledDeployRefusal?

        // MARK: - Functions

        /// The sentence shown under the Save button.
        func sentence(locale: Locale = Locale.current) -> String {
            let moment: String = ScheduledDeploy.dayAndTimeText(self.moment, locale: locale)
            if let refusal {
                return SpecialNames.settingsSaveScheduledDeployCannotGoAheadAsSetNow(
                    section: section, moment: moment, reason: refusal.reasonClause
                )
            }
            return SpecialNames.settingsSaveScheduledDeployGoesWhereTheCourseDeploysNow(
                section: section, moment: moment, destinations: destinationsNow.joined(separator: ", ")
            )
        }
    }

    // MARK: - Functions

    /// What to say after a Save of `courseCode`'s settings, or nil when
    /// there is nothing to say.
    ///
    /// First, when this Save replaced a change to the sidebar list that the
    /// file had and this window had not read (`replacedChangesFromElsewhere`
    /// names `hidden`): the last Save wins, but it is SAID — the review's M2,
    /// ruled by the director for Russell on 2026-09-24. No merge of the two
    /// lists. Only the sidebar list, because that is the one a teacher reads
    /// back as "the switches do nothing"; a build no longer writes it, so
    /// "somewhere else" is another window or a hand edit.
    ///
    /// Then what was running. A publish takes precedence, and then Preview
    /// Again is NOT offered: rebuilding a preview while that course is
    /// publishing is refused everywhere else in the app
    /// (`rebuildAfterRepair`), so a button that could only be refused would
    /// be worse than none. Once the publish finishes, the teacher previews
    /// from the section as usual.
    ///
    /// Then, since #323, one sentence per section whose scheduled deploy this
    /// Save affects (`scheduledDeploys`, from `scheduledDeploysAtSave`) —
    /// BEFORE the early return for a running publish, so a Save made while
    /// publishing still says it.
    static func afterSave(
        folderPath: String,
        courseCode: String,
        previewLeases: [PreviewLeases.Lease],
        publishes: [CourseActivity.PublishRecord],
        replacedChangesFromElsewhere: [String],
        scheduledDeploys: [ScheduledDeployAtSave] = [],
        locale: Locale = Locale.current
    ) -> SettingsSaveNotice? {
        let folder: String = standardised(folderPath)

        var sentences: [String] = []
        if replacedChangesFromElsewhere.contains("hidden") {
            sentences.append(SpecialNames.settingsSaveReplacedSidebarChange)
        }
        for scheduled in scheduledDeploys {
            sentences.append(scheduled.sentence(locale: locale))
        }

        for publish in publishes {
            if standardised(publish.folderPath) == folder && publish.courseCode == courseCode {
                sentences.append(SpecialNames.settingsSavedWhilePublishing)
                return SettingsSaveNotice(
                    sentences: sentences, sectionsToPreviewAgain: [], scheduledDeploys: scheduledDeploys
                )
            }
        }

        let previewedSections: [Int] = sectionsPreviewed(
            folderPath: folderPath, courseCode: courseCode, previewLeases: previewLeases
        )
        if !previewedSections.isEmpty {
            sentences.append(SpecialNames.settingsSavedWhilePreviewing)
        }
        if sentences.isEmpty {
            return nil
        }
        return SettingsSaveNotice(
            sentences: sentences, sectionsToPreviewAgain: previewedSections, scheduledDeploys: scheduledDeploys
        )
    }

    /// This course's deploys set to happen on its own IN THIS WORKING FOLDER
    /// that are still to come (#323) — found by the folder scan, so another
    /// working folder's deploy of the same section is never spoken about
    /// (#237).
    static func scheduledDeploysStillToCome(
        courseCode: String,
        workingFolder: URL,
        now: Date = Date()
    ) -> [(section: Int, when: Date)] {
        var result: [(section: Int, when: Date)] = []
        let agents: [ScheduledDeploy.Agent] = ScheduledDeploy.agents(
            inWorkingFolder: workingFolder, courseCode: courseCode, sectionNumber: nil
        )
        for agent in agents {
            if let when = agent.scheduledFor, when > now {
                result.append((section: agent.sectionNumber, when: when))
            }
        }
        return result
    }

    /// Which of this course's scheduled deploys a Save should speak about
    /// (GitHub #323), and what to say.
    ///
    /// `scheduled` is this WORKING FOLDER's deploys of the course that are
    /// still to come (#237: another folder's deploy of the same section is
    /// another alarm, and nothing this Save does reaches it). A deploy is
    /// spoken about when it could not go ahead as the course is set NOW
    /// (changed or not), or when the Save CHANGED where the course deploys —
    /// "changed" meaning the file as it was before this Save (`before`) and
    /// as it was written (`saved`), never what the deploy was set to go to,
    /// which would repeat the sentence on every later Save (plan review M4).
    static func scheduledDeploysAtSave(
        before: CourseConfiguration?,
        saved: Course,
        scheduled: [(section: Int, when: Date)],
        cloudflareAccountID: String
    ) -> [ScheduledDeployAtSave] {
        var destinationsBefore: [CourseConfiguration.DeployDestination] = []
        if let before {
            destinationsBefore = before.allDeployDestinations
        }
        let destinationsAfter: [CourseConfiguration.DeployDestination] = saved.configuration.allDeployDestinations
        let changed: Bool = before != nil && destinationsBefore != destinationsAfter
        var descriptions: [String] = []
        for destination in destinationsAfter {
            descriptions.append(DeployCommand.destinationDescription(for: destination))
        }

        var result: [ScheduledDeployAtSave] = []
        for entry in scheduled {
            let refusal: ScheduledDeployRefusal? = ScheduledDeploy.destinationRefusal(
                course: saved, sectionNumber: entry.section, cloudflareAccountID: cloudflareAccountID
            )
            if refusal == nil && !changed {
                continue
            }
            result.append(ScheduledDeployAtSave(
                section: entry.section, moment: entry.when, destinationsNow: descriptions, refusal: refusal
            ))
        }
        return result
    }

    /// This notice once Preview Again has been pressed: the preview sentence
    /// is answered and goes, with the button; any sentence about the Save
    /// itself stays. Nil when nothing is left to say.
    func withoutPreviewAgain() -> SettingsSaveNotice? {
        var remaining: [String] = []
        for sentence in sentences {
            if sentence != SpecialNames.settingsSavedWhilePreviewing {
                remaining.append(sentence)
            }
        }
        if remaining.isEmpty {
            return nil
        }
        return SettingsSaveNotice(
            sentences: remaining, sectionsToPreviewAgain: [], scheduledDeploys: scheduledDeploys
        )
    }

    /// The sections of `courseCode` with a preview leased in this folder,
    /// in order.
    static func sectionsPreviewed(
        folderPath: String,
        courseCode: String,
        previewLeases: [PreviewLeases.Lease]
    ) -> [Int] {
        let folder: String = standardised(folderPath)
        var previewedSections: [Int] = []
        for lease in previewLeases {
            if standardised(lease.folderPath) == folder && lease.courseCode == courseCode {
                if !previewedSections.contains(lease.sectionNumber) {
                    previewedSections.append(lease.sectionNumber)
                }
            }
        }
        previewedSections.sort()
        return previewedSections
    }

    /// Of the sections the notice offered to preview again, the ones Preview
    /// Again can still reach NOW: a preview still leased in this folder, and
    /// a section window on screen whose preview is running
    /// (`previewIsRunning` answers nil when no window is registered for the
    /// section). The notice is worked out at the Save and stays up, so its
    /// preview can stop, or its window close, before the button is pressed —
    /// and then the button did nothing and said nothing (the review's L2).
    /// Empty means the button is disabled and
    /// `settingsPreviewAgainNothingOpen` is shown instead.
    static func sectionsStillPreviewed(
        offered: [Int],
        folderPath: String,
        courseCode: String,
        previewLeases: [PreviewLeases.Lease],
        previewIsRunning: (Int) -> Bool?
    ) -> [Int] {
        let leased: [Int] = sectionsPreviewed(
            folderPath: folderPath, courseCode: courseCode, previewLeases: previewLeases
        )
        var reachable: [Int] = []
        for section in offered {
            if !leased.contains(section) {
                continue
            }
            if previewIsRunning(section) == true {
                reachable.append(section)
            }
        }
        return reachable
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
            // What this Save means for a scheduled deploy (#323) — from the
            // notice's facts, not from its sentences, which are templated.
            for scheduled in notice.scheduledDeploys {
                if let refusal = scheduled.refusal {
                    line += "; Section \(scheduled.section)’s scheduled deploy could not go ahead as set now ("
                        + refusal.reasonClause + ")"
                } else {
                    line += "; Section \(scheduled.section)’s scheduled deploy now goes to "
                        + scheduled.destinationsNow.joined(separator: ", ")
                }
            }
            if notice.sentences.contains(SpecialNames.settingsSaveReplacedSidebarChange) {
                line += "; told the teacher this save replaced a sidebar change made elsewhere"
            }
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

    /// One folder, one spelling: links, `/private`, case and Unicode form
    /// all resolved the way the disk spells the folder (`FolderIdentity`,
    /// #189), so a lease taken under another spelling is still this folder's.
    private static func standardised(_ path: String) -> String {
        return FolderIdentity.canonicalPath(URL(fileURLWithPath: path).standardizedFileURL.path)
    }
}
