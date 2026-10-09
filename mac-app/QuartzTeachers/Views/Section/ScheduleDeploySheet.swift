import SwiftUI

/// "Deploy tomorrow's class at 6:30 AM."
///
/// Picking the time and reading the plan happen here; the plan itself is
/// `ScheduledDeploy.plan(...)`, which changes nothing, so the teacher sees
/// exactly what would be set up before anything is. Their "Schedule"
/// consents to setting the alarm, not to a deploy happening now.
struct ScheduleDeploySheet: View {

    // MARK: - Stored properties

    let course: Course
    let sectionNumber: Int
    let workspaceURL: URL

    /// Called once an agent really has been set, so the sidebar can redraw
    /// with its clock.
    let onScheduled: () -> Void

    @State var when: Date = ScheduleDeploySheet.defaultMoment()

    /// Why scheduling failed, when it did. Refusals are shown live under
    /// the picker; this is for the rarer case of launchd itself saying no.
    @State var failure: String?

    @Environment(\.dismiss) var dismiss

    // MARK: - Computed properties

    /// What the sheet shows, read from the SAVED settings at every redraw
    /// (#335) — see `whatTheSheetShows`.
    var shown: (plan: ScheduledDeployPlan?, unreadable: String?, notice: String?) {
        return ScheduleDeploySheet.whatTheSheetShows(
            windowCourse: course,
            sectionNumber: sectionNumber,
            when: when,
            now: Date(),
            cloudflareAccountID: AppSettings.shared.cloudflareAccountID,
            workspaceURL: workspaceURL,
            anyCopyUnsaved: course.configuration.hasUnsavedChanges
                || WorkspaceModel.anyCopyHasUnsavedChanges(configFileURL: course.configFileURL)
        )
    }

    // MARK: - Body

    var body: some View {
        let shown: (plan: ScheduledDeployPlan?, unreadable: String?, notice: String?) = self.shown
        VStack(alignment: .leading, spacing: 12) {
            Text("Schedule a deploy")
                .font(.title2)
                .accessibilityIdentifier("scheduleDeployTitle")

            if let notice = shown.notice {
                HStack(alignment: .firstTextBaseline) {
                    Image(systemName: "info.circle")
                        .foregroundStyle(.secondary)
                    Text(notice)
                        .font(.callout)
                        .fixedSize(horizontal: false, vertical: true)
                    Spacer()
                }
                .accessibilityIdentifier("scheduleDeployUsesSavedSettings")
            }

            DatePicker(
                "Deploy at",
                selection: $when,
                in: Date()...,
                displayedComponents: [.date, .hourAndMinute]
            )
            .accessibilityIdentifier("scheduleDeployDatePicker")

            Divider()

            ScrollView {
                Text(shown.plan?.description ?? shown.unreadable ?? "")
                    .font(.callout)
                    .foregroundStyle(shown.plan?.isSchedulable == true ? Color.primary : Color.orange)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .textSelection(.enabled)
                    .accessibilityIdentifier("scheduleDeployPlan")
            }
            .frame(minHeight: 160)

            if let failure {
                Text(failure)
                    .font(.callout)
                    .foregroundStyle(.red)
                    .accessibilityIdentifier("scheduleDeployFailure")
            }

            HStack {
                Spacer()
                Button("Cancel", role: .cancel) {
                    dismiss()
                }
                .accessibilityIdentifier("scheduleDeployCancelButton")

                Button("Schedule") {
                    schedule()
                }
                // Return presses it, and it is grey while it cannot be
                // pressed (#457, the HIG sweep: it was dim blue, and Return
                // did nothing).
                .defaultButton(isEnabled: shown.plan?.isSchedulable == true)
                .accessibilityIdentifier("scheduleDeployConfirmButton")
            }
        }
        .padding(20)
        .frame(width: 520)
    }

    // MARK: - Functions

    /// What the sheet shows (#335): the plan worked out from the course as
    /// its settings file says it is NOW, why it cannot be worked out when the
    /// file cannot be read, and the sentence to show when any window holds
    /// unsaved Course Settings edits.
    ///
    /// **Never from `windowCourse`'s settings.** Since #323 the run reads the
    /// file when it fires, so a sheet that followed unsaved edits could
    /// promise a folder while the run went to Netlify, or refuse over a
    /// destination nobody had saved. Read on every redraw — one small file —
    /// and never cached, because a cache is #322's bug.
    static func whatTheSheetShows(
        windowCourse: Course,
        sectionNumber: Int,
        when: Date,
        now: Date,
        cloudflareAccountID: String,
        workspaceURL: URL,
        anyCopyUnsaved: Bool
    ) -> (plan: ScheduledDeployPlan?, unreadable: String?, notice: String?) {
        let notice: String? = SettingsSaveNotice.whenSchedulingOpens(settingsHaveUnsavedChanges: anyCopyUnsaved)
        let saved: Course
        do {
            saved = try windowCourse.asSavedNow()
        } catch {
            return (
                plan: nil,
                unreadable: SpecialNames.settingsCouldNotBeReadToDeploy(course: windowCourse.displayCode),
                notice: notice
            )
        }
        let plan: ScheduledDeployPlan = ScheduledDeploy.plan(
            course: saved,
            sectionNumber: sectionNumber,
            when: when,
            now: now,
            cloudflareAccountID: cloudflareAccountID,
            inWorkingFolder: workspaceURL
        )
        return (plan: plan, unreadable: nil, notice: notice)
    }

    /// Tomorrow at 6:30 AM — before the first class, and after the Mac has
    /// usually been left on overnight.
    static func defaultMoment(from now: Date = Date(), calendar: Calendar = Calendar.current) -> Date {
        let tomorrow: Date = calendar.date(byAdding: .day, value: 1, to: now) ?? now
        let sixThirty: Date? = calendar.date(
            bySettingHour: 6,
            minute: 30,
            second: 0,
            of: tomorrow
        )
        return sixThirty ?? tomorrow
    }

    func schedule() {
        failure = nil
        let anyCopyUnsaved: Bool = course.configuration.hasUnsavedChanges
            || WorkspaceModel.anyCopyHasUnsavedChanges(configFileURL: course.configFileURL)
        if let problem = ScheduleDeploySheet.scheduleFromTheSavedSettings(
            windowCourse: course,
            sectionNumber: sectionNumber,
            when: when,
            workspaceURL: workspaceURL,
            cloudflareAccountID: AppSettings.shared.cloudflareAccountID,
            anyCopyUnsaved: anyCopyUnsaved
        ) {
            failure = problem
            return
        }
        // The first time a teacher schedules from the window, ask whether
        // Plantoir may tell them how it went (#212). Never at launch — most
        // teachers never schedule anything — and never from the run itself,
        // which has nobody to ask. Does nothing once asked.
        let courseCode: String = course.code
        let section: Int = sectionNumber
        Task {
            await ScheduledPublishNotice.askPermissionIfNotAskedYet(course: courseCode, section: section)
        }
        onScheduled()
        dismiss()
    }

    /// The press, free of the view so it can be tested (#335). Returns nil
    /// once a deploy is set, or what to say instead.
    ///
    /// **The file is read AGAIN here**, not taken from the plan the sheet
    /// drew: a Save can land between drawing and pressing, and what is
    /// written must be what the file says at the press.
    static func scheduleFromTheSavedSettings(
        windowCourse: Course,
        sectionNumber: Int,
        when: Date,
        workspaceURL: URL,
        cloudflareAccountID: String,
        anyCopyUnsaved: Bool,
        runner: LaunchControlRunning = LaunchControl()
    ) -> String? {
        let saved: Course
        do {
            saved = try windowCourse.asSavedNow()
        } catch {
            return SpecialNames.settingsCouldNotBeReadToDeploy(course: windowCourse.displayCode)
        }
        // Checked again here, not only in the button's disabled state: the
        // clock moves while the sheet is open, so a time that was in the
        // future when it opened may not be by the time it is used.
        let plan: ScheduledDeployPlan = ScheduledDeploy.plan(
            course: saved,
            sectionNumber: sectionNumber,
            when: when,
            now: Date(),
            cloudflareAccountID: cloudflareAccountID,
            inWorkingFolder: workspaceURL
        )
        if let problem = plan.problem {
            // On the trail since #322: a refusal at the button is a teacher
            // who tried to schedule and could not.
            ScheduledDeploy.noteRefusedBeforeAnythingWasWritten(plan: plan, course: saved)
            return problem
        }
        if let problem = ScheduledDeploy.scheduleDeploy(
            course: saved,
            sectionNumber: sectionNumber,
            when: when,
            workspaceURL: workspaceURL,
            cloudflareAccountID: cloudflareAccountID,
            runner: runner
        ) {
            return problem
        }
        if anyCopyUnsaved {
            SettingsSaveNotice.noteDeployUsedTheSavedSettings(
                act: "set a deploy for \(ScheduledDeploy.dayAndTimeText(when))",
                saved: saved, windowCourse: windowCourse, sectionNumber: sectionNumber
            )
        }
        return nil
    }
}
