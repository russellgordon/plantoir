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

    var plan: ScheduledDeployPlan {
        return ScheduledDeploy.plan(
            course: course,
            sectionNumber: sectionNumber,
            when: when,
            now: Date(),
            cloudflareAccountID: AppSettings.shared.cloudflareAccountID,
            inWorkingFolder: workspaceURL
        )
    }

    // MARK: - Body

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Schedule a deploy")
                .font(.title2)
                .accessibilityIdentifier("scheduleDeployTitle")

            DatePicker(
                "Deploy at",
                selection: $when,
                in: Date()...,
                displayedComponents: [.date, .hourAndMinute]
            )
            .accessibilityIdentifier("scheduleDeployDatePicker")

            Divider()

            ScrollView {
                Text(plan.description)
                    .font(.callout)
                    .foregroundStyle(plan.isSchedulable ? Color.primary : Color.orange)
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
                .buttonStyle(.borderedProminent)
                .disabled(!plan.isSchedulable)
                .accessibilityIdentifier("scheduleDeployConfirmButton")
            }
        }
        .padding(20)
        .frame(width: 520)
    }

    // MARK: - Functions

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
        // Checked again here, not only in the button's disabled state: the
        // clock moves while the sheet is open, so a time that was in the
        // future when it opened may not be by the time it is used.
        if let problem = plan.problem {
            failure = problem
            return
        }
        if let problem = ScheduledDeploy.scheduleDeploy(
            course: course,
            sectionNumber: sectionNumber,
            when: when,
            workspaceURL: workspaceURL,
            cloudflareAccountID: AppSettings.shared.cloudflareAccountID
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
}
