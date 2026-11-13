import AppKit
import SwiftUI

/// The foot of the Planning tab (#709): share the course's unit plans as a
/// small website of their own on Cloudflare Pages, one for each school year,
/// open to anyone with the address or protected by a username and password.
///
/// What it shows comes from the markers a share leaves behind
/// (`PlanSharing.markers`), never from what the bar remembers, so a share
/// made from Terminal reads the same. The rules are contract cases:
/// whether a share is protected (`modeCases`), when the public-address
/// warning comes first (`warningCases`), and the launcher's arguments
/// (`planShareCases`).
struct PlanShareBar: View {

    // MARK: - Stored properties

    let course: Course

    /// The working folder the launcher runs in.
    let folder: URL

    @State var planRunner: PlanShareRunner = PlanShareRunner()

    /// Every school year this course shares, newest first.
    @State var markers: [PlanSharing.Marker] = []

    /// Before the first share this year: protect it with a password.
    @State var protect: Bool = false

    /// A share without a password: keep the answer keys in.
    @State var includeAnswerKeys: Bool = false

    /// The choice waiting on the public-address warning.
    @State var choiceAwaitingTheWarning: PlanSharing.Choice?

    /// The school year waiting on the Stop Sharing alert.
    @State var markerAwaitingStop: PlanSharing.Marker?

    // MARK: - Computed properties

    var thisYear: Int {
        return PlanSharing.schoolYear(on: CalendarDay.today())
    }

    /// This school year's marker, when the plans are shared.
    var current: PlanSharing.Marker? {
        for marker in markers {
            if marker.year == thisYear {
                return marker
            }
        }
        return nil
    }

    /// Earlier school years still shared, each with its own Stop Sharing.
    var earlierYears: [PlanSharing.Marker] {
        var earlier: [PlanSharing.Marker] = []
        for marker in markers {
            if marker.year != thisYear {
                earlier.append(marker)
            }
        }
        return earlier
    }

    /// Whether the course's class websites go to Netlify, so the bar says
    /// plainly why the plans go to Cloudflare Pages instead.
    var classSitesGoToNetlify: Bool {
        let target: String = course.configuration.deployTarget
        return target.isEmpty || target == "netlify"
    }

    var isBusy: Bool {
        return planRunner.runner.isRunning
    }

    // MARK: - Body

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Divider()
            Group {
                if let marker = current {
                    sharedRow(marker)
                } else {
                    notSharedRow
                }
                ForEach(earlierYears, id: \.year) { (marker: PlanSharing.Marker) in
                    earlierRow(marker)
                }
            }
            .padding(.horizontal, 12)
        }
        .padding(.bottom, 8)
        .accessibilityIdentifier("planShareBar")
        .task {
            lookAgain()
        }
        .onChange(of: planRunner.runner.isRunning) { (_: Bool, isRunning: Bool) in
            if !isRunning {
                planRunner.finished()
                lookAgain()
            }
        }
        .sheet(isPresented: Binding(
            get: { planRunner.isShowingSheet },
            set: { (showing: Bool) in
                planRunner.isShowingSheet = showing
            }
        )) {
            shareSheet
        }
        .alert(
            PlanSharingWording.crawlerWarningTitle,
            isPresented: Binding(
                get: { choiceAwaitingTheWarning != nil },
                set: { (showing: Bool) in
                    if !showing {
                        choiceAwaitingTheWarning = nil
                    }
                }
            )
        ) {
            Button(PlanSharingWording.shareAnyway) {
                if let choice = choiceAwaitingTheWarning {
                    choiceAwaitingTheWarning = nil
                    start(choice)
                }
            }
            Button("Cancel", role: .cancel) {
                choiceAwaitingTheWarning = nil
            }
        } message: {
            Text(PlanSharing.crawlerWarning(includingAnswerKeys: includeAnswerKeys))
        }
        .alert(
            stopTitle,
            isPresented: Binding(
                get: { markerAwaitingStop != nil },
                set: { (showing: Bool) in
                    if !showing {
                        markerAwaitingStop = nil
                    }
                }
            )
        ) {
            Button(PlanSharingWording.stopSharing, role: .destructive) {
                if let marker = markerAwaitingStop {
                    markerAwaitingStop = nil
                    start(.stop, year: marker.year)
                }
            }
            Button("Cancel", role: .cancel) {
                markerAwaitingStop = nil
            }
        } message: {
            Text(PlanSharing.stopMessage(address: markerAwaitingStop?.address ?? ""))
        }
        .alert(
            PlanSharingWording.share,
            isPresented: Binding(
                get: { planRunner.couldNotStart != nil },
                set: { (showing: Bool) in
                    if !showing {
                        planRunner.couldNotStart = nil
                    }
                }
            )
        ) {
            Button("OK") {
                planRunner.couldNotStart = nil
            }
        } message: {
            Text(planRunner.couldNotStart ?? "")
        }
    }

    var stopTitle: String {
        let year: Int = markerAwaitingStop?.year ?? thisYear
        return PlanSharingWording.stopTitle.replacingOccurrences(of: "{year}", with: PlanSharing.yearLabel(year))
    }

    /// Before the first share this school year.
    var notSharedRow: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(PlanSharingWording.sharedThroughCloudflare)
                .font(.callout)
                .foregroundStyle(.secondary)
            if classSitesGoToNetlify {
                Text(PlanSharingWording.netlifyTeacher)
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            HStack(spacing: 12) {
                Toggle(PlanSharingWording.protect, isOn: $protect)
                    .accessibilityIdentifier("planShareProtect")
                if !protect {
                    Toggle(PlanSharingWording.includeAnswerKeys, isOn: $includeAnswerKeys)
                        .accessibilityIdentifier("planShareAnswerKeys")
                }
                Spacer()
                Button(PlanSharingWording.share) {
                    choose(protect ? .shareProtected : .shareOpen)
                }
                .disabled(isBusy)
                .accessibilityIdentifier("planShareButton")
            }
        }
    }

    /// Once shared this school year.
    func sharedRow(_ marker: PlanSharing.Marker) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 8) {
                if let address = URL(string: marker.address) {
                    Link(marker.address, destination: address)
                        .accessibilityIdentifier("planShareAddress")
                } else {
                    Text(marker.address)
                }
                Button(PlanSharingWording.copyLink) {
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(marker.address, forType: .string)
                }
                .accessibilityIdentifier("planShareCopyLink")
                Spacer()
            }
            statusLines(marker)
            if let flood = PlanSharing.floodSentence(for: marker) {
                Text(flood)
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            if let when = marker.lastShared {
                Text(PlanSharingWording.lastShared.replacingOccurrences(
                    of: "{when}", with: when.formatted(date: .abbreviated, time: .shortened)
                ))
                .font(.callout)
                .foregroundStyle(.secondary)
            }
            if !marker.isProtected && marker.answerKeysLeftOut > 0 {
                Text(PlanSharingWording.answerKeysLeftOut.replacingOccurrences(
                    of: "{n}", with: String(marker.answerKeysLeftOut)
                ))
                .font(.callout)
                .foregroundStyle(.secondary)
            }
            HStack(spacing: 8) {
                if !marker.askedForProtection {
                    Toggle(PlanSharingWording.includeAnswerKeys, isOn: $includeAnswerKeys)
                }
                Spacer()
                Button(PlanSharingWording.shareAgain) {
                    choose(.shareAgain)
                }
                .accessibilityIdentifier("planShareAgain")
                if marker.askedForProtection {
                    Button(PlanSharingWording.changePassword) {
                        choose(.changePassword)
                    }
                    .help(PlanSharingWording.changePasswordNote)
                    Button(PlanSharingWording.removePassword) {
                        choose(.removePassword)
                    }
                } else {
                    Button(PlanSharingWording.addPassword) {
                        choose(.addPassword)
                    }
                }
                Button(PlanSharingWording.stopSharing) {
                    markerAwaitingStop = marker
                }
                .accessibilityIdentifier("planShareStop")
            }
            .disabled(isBusy)
        }
    }

    /// What the share is, never more than the site does (barCases): a share
    /// that did not finish may be open, and a Stop Sharing that was not
    /// confirmed may still be answering.
    @ViewBuilder
    func statusLines(_ marker: PlanSharing.Marker) -> some View {
        switch PlanSharing.barStatus(for: marker) {
        case .unfinished:
            Text(PlanSharingWording.lastShareUnfinished)
                .font(.callout)
                .fixedSize(horizontal: false, vertical: true)
                .accessibilityIdentifier("planShareUnfinished")
        case .stopping:
            Text(PlanSharingWording.stopUnconfirmed)
                .font(.callout)
                .fixedSize(horizontal: false, vertical: true)
                .accessibilityIdentifier("planShareStopping")
        case .protected:
            Text(PlanSharingWording.withPassword)
                .font(.callout)
        case .open, .notShared:
            Text(PlanSharingWording.openToAnyone)
                .font(.callout)
        }
        if PlanSharing.showsOldCopies(marker) {
            Text(PlanSharingWording.oldCopyStillThere)
                .font(.callout)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
                .accessibilityIdentifier("planShareOldCopy")
        }
    }

    /// An earlier school year still shared.
    func earlierRow(_ marker: PlanSharing.Marker) -> some View {
        HStack(spacing: 8) {
            VStack(alignment: .leading, spacing: 2) {
                Text(PlanSharingWording.earlierYear
                    .replacingOccurrences(of: "{year}", with: marker.yearLabel)
                    .replacingOccurrences(of: "{address}", with: marker.address))
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .textSelection(.enabled)
                if PlanSharing.barStatus(for: marker) == .stopping || PlanSharing.barStatus(for: marker) == .unfinished
                    || PlanSharing.showsOldCopies(marker) {
                    statusLines(marker)
                }
            }
            Spacer()
            Button(PlanSharingWording.stopSharing) {
                markerAwaitingStop = marker
            }
            .disabled(isBusy)
        }
    }

    /// The console, as a section's deploy shows it, with a Done button once
    /// the launcher has finished.
    var shareSheet: some View {
        VStack(alignment: .leading, spacing: 12) {
            TaskProgressView(
                runner: planRunner.runner,
                title: planRunner.title,
                hidesSiteLink: true,
                onCancel: {
                    planRunner.cancel()
                }
            )
            HStack {
                Spacer()
                Button("Done") {
                    planRunner.isShowingSheet = false
                }
                .keyboardShortcut(.defaultAction)
                .disabled(planRunner.runner.isRunning)
            }
        }
        .padding(16)
        .frame(minWidth: 520, minHeight: 320)
    }

    // MARK: - Functions

    func lookAgain() {
        markers = PlanSharing.markers(courseDirectory: course.directoryURL)
    }

    /// A choice, with the public-address warning first when it is owed.
    func choose(_ choice: PlanSharing.Choice) {
        var asked: Bool?
        if let marker = current {
            asked = marker.askedForProtection
        }
        if PlanSharing.warns(markerAskedForProtection: asked, choice: choice) {
            choiceAwaitingTheWarning = choice
            return
        }
        start(choice)
    }

    func start(_ choice: PlanSharing.Choice, year: Int? = nil) {
        planRunner.start(
            course: course,
            folder: folder,
            choice: choice,
            includeAnswerKeys: includeAnswerKeys,
            year: year ?? thisYear,
            cloudflareAccountID: AppSettings.shared.cloudflareAccountID
        )
    }
}
