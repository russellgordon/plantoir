import SwiftUI
import Observation

/// Everything the links checklist shows and does, apart from the drawing — so
/// it can be tested without a window (`LinksChecklistTests`), the arrangement
/// `StartOfYearSheetModel` uses (#379).
@Observable
@MainActor
final class LinksChecklistSheetModel: Identifiable {

    // MARK: - Types

    enum Stage: Equatable {
        case choosing
        case done(LinksChecklistPublisher.Outcome)
        case problem(String)
    }

    // MARK: - Stored properties

    let course: Course
    let sectionNumber: Int
    let workspaceURL: URL
    let offer: LinksChecklistOffer
    let occasion: LinksChecklistGate.Occasion

    /// The rows still worth offering — checked against the pages as they are
    /// now, not as the build found them.
    let rows: [LinksChecklistOffer.Row]

    /// How many hidden pages each class row would bring if ticked, by place.
    let broughtByClass: [String: Int]

    /// How the sheet names pages — #362's builder, over the whole section
    /// (#385).
    let naming: LinksChecklistNaming

    /// The places whose OWN tick is on right now. What is shown ticked, and
    /// published, is `going` (#385).
    var ticked: Set<String>

    private(set) var stage: Stage = .choosing

    // MARK: - Computed properties

    var id: String {
        return "\(course.code)-section\(sectionNumber)-\(offer.buildId ?? "offer")"
    }

    var title: String {
        return LinksChecklistWording.sheetTitle(course: course.displayCode, section: String(sectionNumber))
    }

    var fromAClassRows: [LinksChecklistOffer.Row] {
        return rowsIn(.fromAClass)
    }

    var otherRows: [LinksChecklistOffer.Row] {
        return rowsIn(.notReachedByAClass)
    }

    var classRows: [LinksChecklistOffer.Row] {
        return rowsIn(.aClass)
    }

    /// The rows that go: shown ticked, counted on the button, written by
    /// Publish (`linksChecklist.followingARow`).
    var going: Set<String> {
        return LinksChecklistGate.going(rows, ticked: ticked)
    }

    var publishButtonTitle: String {
        let count: Int = going.count
        if count == 0 {
            return LinksChecklistWording.publishNothingTicked
        }
        return LinksChecklistWording.publishButton(
            count: String(count), pages: LinksChecklistWording.pageWord(count)
        )
    }

    // MARK: - Initializer

    init(course: Course,
         sectionNumber: Int,
         workspaceURL: URL,
         offer: LinksChecklistOffer,
         answered: LinksChecklistAnswered?,
         occasion: LinksChecklistGate.Occasion,
         problem: String? = nil) {
        self.course = course
        self.sectionNumber = sectionNumber
        self.workspaceURL = workspaceURL
        self.offer = offer
        self.occasion = occasion
        let graph: AssistSectionGraph = AssistSectionGraph.read(
            forSection: sectionNumber, in: course, workspaceURL: workspaceURL
        )
        let pages: [String: AssistSectionPage] = LinksChecklistPublisher.pagesByPlace(graph, in: course)
        let stillOffered: [LinksChecklistOffer.Row] = LinksChecklistPublisher.rowsStillOffered(offer, pages: pages)
        self.rows = stillOffered
        self.naming = LinksChecklistNaming(
            graph: graph, pagesByPlace: pages, rows: offer.rows,
            courseDirectoryURL: course.directoryURL, courseCode: course.code
        )
        var brought: [String: Int] = [:]
        var startingTicks: Set<String> = []
        for row in stillOffered {
            if LinksChecklistGate.startsTicked(row, answered: answered) {
                startingTicks.insert(row.place)
            }
            if row.group == .aClass, let classPage = pages[row.place.precomposedStringWithCanonicalMapping] {
                var hidden: Int = 0
                for page in graph.reachFollowingLinks(from: [classPage]).pages {
                    if !(page.isVisibleToStudents && page.visibilityIsCertain) {
                        hidden += 1
                    }
                }
                brought[row.place] = hidden
            }
        }
        self.broughtByClass = brought
        self.ticked = startingTicks
        if let problem {
            stage = .problem(problem)
        } else if stillOffered.isEmpty {
            stage = .problem(LinksChecklistWording.nothingLeftToPublish)
        }
    }

    // MARK: - Functions

    func rowsIn(_ group: LinksChecklistOffer.Group) -> [LinksChecklistOffer.Row] {
        var found: [LinksChecklistOffer.Row] = []
        for row in rows where row.group == group {
            found.append(row)
        }
        return found
    }

    /// The rows listed under one heading, each with how far in it is shown:
    /// a row reached only through another is listed under it (#385).
    func shownRows(in group: LinksChecklistOffer.Group) -> [LinksChecklistGate.ShownRow] {
        var found: [LinksChecklistGate.ShownRow] = []
        for shown in LinksChecklistGate.shownOrder(rows) where shown.group == group {
            found.append(shown)
        }
        return found
    }

    /// True when the row comes under rows none of which is going: shown
    /// unticked, and it cannot be ticked until one of them is.
    func isLocked(_ row: LinksChecklistOffer.Row) -> Bool {
        return LinksChecklistGate.isLocked(row, going: going)
    }

    /// What the row is called: the page's title, with its folder when another
    /// page in the section has the same title (#385).
    func rowTitle(for row: LinksChecklistOffer.Row) -> String {
        return naming.rowTitle(of: row)
    }

    /// What a row says under its title: what date it will have, or why it
    /// starts unticked, and where it is linked from.
    func secondLine(for row: LinksChecklistOffer.Row) -> String {
        var parts: [String] = []
        if row.group == .aClass {
            parts.append(LinksChecklistWording.classRow)
            if ticked.contains(row.place), let count = broughtByClass[row.place], count > 0 {
                parts.append(LinksChecklistWording.comesWith(
                    count: String(count), pages: LinksChecklistWording.pageWord(count)
                ))
            }
            return parts.joined(separator: " · ")
        }
        if let firstUsedIn = row.firstUsedIn, !ticked.contains(row.place) {
            parts.append(LinksChecklistWording.firstUsedIn(name: naming.name(ofPlace: firstUsedIn)))
        } else {
            parts.append(dateLine(for: row))
        }
        if let first = row.dependsOn.first {
            // Reached only through other rows (#385): say which, and that it
            // goes with them, instead of every page that links it.
            let name: String = naming.name(ofPlace: first)
            let more: Int = row.dependsOn.count - 1
            if more == 0 {
                parts.append(LinksChecklistWording.linkedFromRow(name: name))
            } else {
                parts.append(LinksChecklistWording.linkedFromSeveralRows(
                    name: name, count: String(more), pages: LinksChecklistWording.pageWord(more)
                ))
            }
        } else if let first = row.linkedFrom.first {
            let name: String = naming.name(ofPlace: first)
            if row.linkedFrom.count == 1 {
                parts.append(LinksChecklistWording.linkedFrom(name: name))
            } else {
                parts.append(LinksChecklistWording.linkedFromSeveral(
                    name: name, count: String(row.linkedFrom.count - 1)
                ))
            }
        }
        return parts.joined(separator: " · ")
    }

    func dateLine(for row: LinksChecklistOffer.Row) -> String {
        let claimant: String = naming.name(ofPlace: row.claimedBy ?? "")
        switch row.why {
        case .dated:
            return LinksChecklistWording.datedLike(name: claimant)
        case .datedByTheBuild:
            return LinksChecklistWording.alreadyDatedLike(name: claimant)
        case .datedAsTheFirstClass:
            return LinksChecklistWording.datedAsTheFirstClass(
                name: naming.name(ofPlace: offer.firstClassPlace ?? "")
            )
        case .keepsItsDate:
            return LinksChecklistWording.keepsItsDate
        case .structuralNeverDated, .noClassToDateFrom, .classNeverDated:
            return LinksChecklistWording.keepsTheDateItHas
        }
    }

    /// Shows whether the row GOES; changes only its OWN tick (#385).
    func binding(for row: LinksChecklistOffer.Row) -> Binding<Bool> {
        return Binding(
            get: { [weak self] in
                return self?.going.contains(row.place) ?? false
            },
            set: { [weak self] isOn in
                guard let self else {
                    return
                }
                self.ticked = LinksChecklistGate.toggled(self.ticked, place: row.place, isOn: isOn)
            }
        )
    }

    /// Press Publish.
    func publish() {
        let result: LinksChecklistPublisher.Result = LinksChecklistPublisher.publish(
            offer: LinksChecklistOffer(
                course: offer.course, section: offer.section, buildId: offer.buildId,
                firstClassPlace: offer.firstClassPlace, rows: rows
            ),
            ticked: ticked, course: course, sectionNumber: sectionNumber, workspaceURL: workspaceURL
        )
        switch result {
        case .published(let outcome):
            stage = .done(outcome)
        case .refused(let sentence):
            stage = .problem(sentence)
        }
    }

    /// Press Not Now.
    func notNow() {
        LinksChecklistPublisher.setAside(
            offer: LinksChecklistOffer(
                course: offer.course, section: offer.section, buildId: offer.buildId,
                firstClassPlace: offer.firstClassPlace, rows: rows
            ),
            ticked: ticked, course: course, sectionNumber: sectionNumber
        )
    }
}

/// The links checklist (#379): hidden pages that links on visible pages lead
/// to, each with a checkbox, grouped the way the build found them. Replaces
/// #333's alert, which had only OK.
struct LinksChecklistSheet: View {

    // MARK: - Stored properties

    @State var model: LinksChecklistSheetModel

    /// Called after Publish wrote something, so the window can refresh its
    /// " — Edited" marker.
    var onPublished: () -> Void = {
    }

    @Environment(\.dismiss) var dismiss

    /// How far in a row listed under another is drawn, per level. Capped at
    /// three levels so a long chain cannot push the text off the sheet.
    static let indentPerLevel: CGFloat = 18

    // MARK: - Computed properties

    /// The same cap Copy a Page's checklist uses (#365), and for the same
    /// reason: a sheet that grows without limit puts its buttons off the
    /// bottom of the screen. 100 rows measure within 620 pt
    /// (`LinksChecklistSheetSizeTests`).
    static var tallestList: CGFloat {
        return 380
    }

    // MARK: - Body

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(model.title)
                .font(.headline)
            content
            buttons
        }
        .padding(20)
        .frame(width: 560)
        .fixedSize(horizontal: false, vertical: true)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("linksChecklistSheet")
    }

    // MARK: - Parts

    @ViewBuilder
    var content: some View {
        switch model.stage {
        case .choosing:
            Text(LinksChecklistWording.intro)
                .fixedSize(horizontal: false, vertical: true)
            CappedScrollArea(cap: LinksChecklistSheet.tallestList) {
                VStack(alignment: .leading, spacing: 10) {
                    group(LinksChecklistWording.fromAClassHeading, rows: model.shownRows(in: .fromAClass))
                    group(LinksChecklistWording.notReachedHeading, rows: model.shownRows(in: .notReachedByAClass))
                    group(LinksChecklistWording.classesHeading, rows: model.shownRows(in: .aClass))
                }
            }
            if !model.classRows.isEmpty {
                Text(LinksChecklistWording.frontPageStaysPut)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Text(LinksChecklistWording.nothingChangesUntilYouDeploy)
                .foregroundStyle(.secondary)
        case .done(let outcome):
            let count: Int = outcome.publishedPlaces.count
            Text(LinksChecklistWording.published(count: String(count), pages: LinksChecklistWording.pageWord(count)))
                .fixedSize(horizontal: false, vertical: true)
            ForEach(outcome.changedSince, id: \.self) { name in
                Text(LinksChecklistWording.pageChangedSince(name: name))
                    .foregroundStyle(.orange)
                    .fixedSize(horizontal: false, vertical: true)
            }
            if !outcome.declined.isEmpty {
                Text(AssistPublishPlan.sayingPagesWithNoRoomForAKey(named: outcome.declined))
                    .foregroundStyle(.orange)
                    .fixedSize(horizontal: false, vertical: true)
            }
        case .problem(let sentence):
            Text(sentence)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    @ViewBuilder
    func group(_ heading: String, rows: [LinksChecklistGate.ShownRow]) -> some View {
        if !rows.isEmpty {
            VStack(alignment: .leading, spacing: 4) {
                Text(heading)
                    .font(.subheadline.weight(.semibold))
                ForEach(rows, id: \.row.place) { shown in
                    let row: LinksChecklistOffer.Row = shown.row
                    Toggle(isOn: model.binding(for: row)) {
                        VStack(alignment: .leading, spacing: 1) {
                            Text(model.rowTitle(for: row))
                            Text(model.secondLine(for: row))
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }
                    .disabled(model.isLocked(row))
                    .padding(.leading, CGFloat(min(shown.depth, 3)) * LinksChecklistSheet.indentPerLevel)
                    // On the control, never its label: see `CopyPageChecklist.row`.
                    .accessibilityLabel(model.rowTitle(for: row))
                    .accessibilityValue(model.secondLine(for: row))
                    .accessibilityIdentifier("linksChecklistRow-\(row.place)")
                }
            }
        }
    }

    @ViewBuilder
    var buttons: some View {
        HStack {
            Spacer()
            switch model.stage {
            case .choosing:
                Button(LinksChecklistWording.notNow, role: .cancel) {
                    model.notNow()
                    dismiss()
                }
                .keyboardShortcut(.cancelAction)
                .accessibilityIdentifier("linksChecklistNotNow")
                Button(model.publishButtonTitle) {
                    model.publish()
                    onPublished()
                }
                .keyboardShortcut(.defaultAction)
                .disabled(model.going.isEmpty)
                .accessibilityIdentifier("linksChecklistPublish")
            case .done, .problem:
                Button("Done") {
                    dismiss()
                }
                .keyboardShortcut(.defaultAction)
            }
        }
    }
}
