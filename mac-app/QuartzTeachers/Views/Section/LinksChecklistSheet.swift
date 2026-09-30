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

    /// The places ticked right now.
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

    var publishButtonTitle: String {
        if ticked.isEmpty {
            return LinksChecklistWording.publishNothingTicked
        }
        return LinksChecklistWording.publishButton(
            count: String(ticked.count), pages: LinksChecklistWording.pageWord(ticked.count)
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
            parts.append(LinksChecklistWording.firstUsedIn(class: LinksChecklistOffer.name(ofPlace: firstUsedIn)))
        } else {
            parts.append(dateLine(for: row))
        }
        if let first = row.linkedFrom.first {
            let name: String = LinksChecklistOffer.name(ofPlace: first)
            if row.linkedFrom.count == 1 {
                parts.append(LinksChecklistWording.linkedFrom(page: name))
            } else {
                parts.append(LinksChecklistWording.linkedFromSeveral(
                    page: name, count: String(row.linkedFrom.count - 1)
                ))
            }
        }
        return parts.joined(separator: " · ")
    }

    func dateLine(for row: LinksChecklistOffer.Row) -> String {
        let claimant: String = LinksChecklistOffer.name(ofPlace: row.claimedBy ?? "")
        switch row.why {
        case .dated:
            return LinksChecklistWording.datedLike(class: claimant)
        case .datedByTheBuild:
            return LinksChecklistWording.alreadyDatedLike(class: claimant)
        case .datedAsTheFirstClass:
            return LinksChecklistWording.datedAsTheFirstClass(
                first: LinksChecklistOffer.name(ofPlace: offer.firstClassPlace ?? "")
            )
        case .keepsItsDate:
            return LinksChecklistWording.keepsItsDate
        case .structuralNeverDated, .noClassToDateFrom, .classNeverDated:
            return LinksChecklistWording.keepsTheDateItHas
        }
    }

    func binding(for row: LinksChecklistOffer.Row) -> Binding<Bool> {
        return Binding(
            get: { [weak self] in
                return self?.ticked.contains(row.place) ?? false
            },
            set: { [weak self] isOn in
                if isOn {
                    self?.ticked.insert(row.place)
                } else {
                    self?.ticked.remove(row.place)
                }
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
                    group(LinksChecklistWording.fromAClassHeading, rows: model.fromAClassRows)
                    group(LinksChecklistWording.notReachedHeading, rows: model.otherRows)
                    group(LinksChecklistWording.classesHeading, rows: model.classRows)
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
            ForEach(outcome.changedSince, id: \.self) { title in
                Text(LinksChecklistWording.pageChangedSince(page: title))
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
    func group(_ heading: String, rows: [LinksChecklistOffer.Row]) -> some View {
        if !rows.isEmpty {
            VStack(alignment: .leading, spacing: 4) {
                Text(heading)
                    .font(.subheadline.weight(.semibold))
                ForEach(rows) { row in
                    Toggle(isOn: model.binding(for: row)) {
                        VStack(alignment: .leading, spacing: 1) {
                            Text(row.title)
                            Text(model.secondLine(for: row))
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }
                    // On the control, never its label: see `CopyPageChecklist.row`.
                    .accessibilityLabel(row.title)
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
                .disabled(model.ticked.isEmpty)
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
