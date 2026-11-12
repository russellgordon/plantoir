import SwiftUI

/// One row of the Problems table, as the table sorts and shows it.
nonisolated struct ProblemsTableRow: Identifiable, Hashable, Sendable {

    // MARK: - Stored properties

    let row: SectionProblemRow
    let state: SectionProblemsRules.RowState
    let kindLabel: String
    let page: String
    let firstFound: Date
    let lastFound: Date

    // MARK: - Computed properties

    var id: String {
        return row.id
    }

    /// What the Problem column says.
    var problem: String {
        if state == .fixedInTheSource {
            return SectionProblemsWording.fixedInTheSource
        }
        if row.item.isEmpty {
            return row.sentence
        }
        return row.item
    }

    /// The whole of what the folder problem says, on hover.
    var help: String {
        if row.detail.isEmpty {
            return row.sentence
        }
        return row.sentence + "\n\n" + row.detail
    }
}

/// A section's Problems tab (#717): one row per problem its last build met,
/// with a tick per row — ticked means included in what Fix with Claude… and
/// Fix with Codex… hand over — sortable by kind, and the repair inline where
/// a problem has one, because the alert no longer comes with every build.
///
/// The two Fix buttons sit under the table (#717 part two,
/// `FixWithAssistant`): each shown only while its assistant is installed
/// (`OutsideAssistantPresence`, never asked while this view draws), never on
/// a course kept for reference, and enabled while a ticked row is still this
/// section's problem.
///
/// Drawn OVER the section's site, which stays mounted underneath (see
/// `DetailTabs`).
struct ProblemsTableView: View {

    // MARK: - Stored properties

    let course: Course
    let sectionNumber: Int
    let folder: URL
    let record: SectionProblemsRecord
    let others: [SectionProblemsRecord]

    /// Puts a fixable problem right, as the alert's button does.
    let repair: (SiteHealthFinding) -> Void

    @State var sortOrder: [KeyPathComparator<ProblemsTableRow>] = [
        KeyPathComparator(\ProblemsTableRow.kindLabel),
    ]

    @Environment(WorkspaceModel.self) var workspace

    /// Why a Fix button's door did not open, for its alert.
    @State var doorProblem: String?

    /// Which door's alert `doorProblem` is.
    @State var doorThatFailed: FixWithAssistant.Assistant = .claude

    /// A Claude or Codex session already open on the course, or the course
    /// busy: the refusal Revise With ▸ makes at the click (#458).
    @State var reviseRefusal: WorkspaceModel.ReviseRefusal?

    // MARK: - Computed properties

    var store: SectionProblems {
        return SectionProblems.shared
    }

    var presence: OutsideAssistantPresence {
        return OutsideAssistantPresence.shared
    }

    /// What a Fix button would hand over now.
    var handover: FixWithAssistant.Handover {
        return FixWithAssistant.handover(record: record, others: others, isTicked: { (rowID: String) -> Bool in
            return store.isTicked(rowID, folder: folder, courseCode: course.code, sectionNumber: sectionNumber)
        })
    }

    var showsClaude: Bool {
        return FixWithAssistant.buttonIsShown(
            assistantIsInstalled: presence.claudeIsInstalled,
            courseIsKeptForReference: course.isKeptForReference
        )
    }

    var showsCodex: Bool {
        return FixWithAssistant.buttonIsShown(
            assistantIsInstalled: presence.codexIsInstalled,
            courseIsKeptForReference: course.isKeptForReference
        )
    }

    /// Every row, in the order the teacher sorted them.
    var tableRows: [ProblemsTableRow] {
        var made: [ProblemsTableRow] = []
        for row in record.rows {
            made.append(ProblemsTableRow(
                row: row,
                state: SectionProblemsRules.state(of: row, in: record, others: others),
                kindLabel: SectionProblemsWording.label(ofKind: row.kind),
                page: SectionProblemsWording.pageColumn(for: row),
                firstFound: row.firstSeen ?? .distantPast,
                lastFound: row.lastSeen ?? .distantPast
            ))
        }
        return made.sorted(using: sortOrder)
    }

    // MARK: - Body

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(SectionProblemsWording.intro(course: course.displayCode, section: String(sectionNumber)))
                .foregroundStyle(.secondary)
                .padding(.horizontal)
                .padding(.top, 10)
            Table(tableRows, sortOrder: $sortOrder) {
                TableColumn(SectionProblemsWording.columnIncluded) { tableRow in
                    Toggle(SectionProblemsWording.columnIncluded, isOn: tickBinding(for: tableRow.id))
                        .labelsHidden()
                        .accessibilityIdentifier("problemTick-\(tableRow.id)")
                }
                .width(54)
                TableColumn(SectionProblemsWording.columnKind, value: \ProblemsTableRow.kindLabel)
                    .width(min: 110, ideal: 150)
                TableColumn(SectionProblemsWording.columnPage, value: \ProblemsTableRow.page)
                    .width(min: 110, ideal: 180)
                TableColumn(SectionProblemsWording.columnProblem) { tableRow in
                    problemCell(tableRow)
                }
                .width(min: 220, ideal: 420)
                TableColumn(SectionProblemsWording.columnFirstFound, value: \ProblemsTableRow.firstFound) { tableRow in
                    Text(dateText(tableRow.firstFound))
                }
                .width(min: 90, ideal: 130)
                TableColumn(SectionProblemsWording.columnLastFound, value: \ProblemsTableRow.lastFound) { tableRow in
                    Text(dateText(tableRow.lastFound))
                }
                .width(min: 90, ideal: 130)
            }
            .accessibilityIdentifier("problemsTable")
            if showsClaude || showsCodex {
                fixButtons
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(.background)
        .alert(
            doorThatFailed == .claude ? ClaudeCodeLauncher.didNotOpenTitle : CodexLauncher.didNotOpenTitle,
            isPresented: Binding(
                get: { doorProblem != nil },
                set: { showing in
                    if !showing {
                        doorProblem = nil
                    }
                }
            )
        ) {
            Button("OK") {
                doorProblem = nil
            }
        } message: {
            Text(doorProblem ?? "")
        }
        .alert(
            reviseRefusal?.title ?? "",
            isPresented: Binding(
                get: { reviseRefusal != nil },
                set: { showing in
                    if !showing {
                        reviseRefusal = nil
                    }
                }
            )
        ) {
            Button("OK") {
                reviseRefusal = nil
            }
        } message: {
            Text(reviseRefusal?.message ?? "")
        }
    }

    /// Fix with Claude… and Fix with Codex…, trailing under the table.
    var fixButtons: some View {
        HStack(spacing: 8) {
            Spacer()
            if showsClaude {
                Button(FixWithAssistant.claudeButtonTitle) {
                    fix(with: .claude)
                }
                .accessibilityIdentifier("fixWithClaude")
                .accessibilityHint(Text(FixWithAssistant.buttonHint(hasRows: handover.hasRows)))
            }
            if showsCodex {
                Button(FixWithAssistant.codexButtonTitle) {
                    fix(with: .codex)
                }
                .accessibilityIdentifier("fixWithCodex")
                .accessibilityHint(Text(FixWithAssistant.buttonHint(hasRows: handover.hasRows)))
            }
        }
        .disabled(!handover.hasRows)
        .padding(.horizontal)
        .padding(.bottom, 10)
    }

    // MARK: - Functions

    @ViewBuilder
    func problemCell(_ tableRow: ProblemsTableRow) -> some View {
        HStack(spacing: 8) {
            if tableRow.state == .fixedInTheSource {
                Text(tableRow.problem)
                    .foregroundStyle(.secondary)
                    .accessibilityIdentifier("problemFixedInTheSource-\(tableRow.id)")
            } else {
                Text(tableRow.problem)
                    .lineLimit(3)
            }
            if tableRow.state == .current, tableRow.row.fixable, !course.isKeptForReference,
               let title = SiteHealthRepair.buttonTitle(for: [finding(for: tableRow.row)]) {
                Button(title) {
                    repair(finding(for: tableRow.row))
                }
                .controlSize(.small)
            }
        }
        .help(tableRow.help)
    }

    /// The folder problem a row is, for the repair: the same name, words and
    /// course the build's own finding has.
    func finding(for row: SectionProblemRow) -> SiteHealthFinding {
        return SiteHealthFinding(
            name: row.kind, sentence: row.sentence, detail: row.detail,
            fixable: row.fixable, course: course.code, section: sectionNumber
        )
    }

    /// Opens `assistant`'s door with the ticked problems in its opening
    /// message, after the refusal Revise With ▸ makes at the click; and, once
    /// it has opened, says so on the trail.
    func fix(with assistant: FixWithAssistant.Assistant) {
        let item: CourseActivity.ReviseItem = assistant == .claude ? .claude : .codex
        if let refusal = workspace.reviseRefusal(item: item, courseCode: course.code, sectionNumber: nil) {
            reviseRefusal = refusal
            return
        }
        let handedOver: FixWithAssistant.Handover = handover
        guard let greeting = FixWithAssistant.greeting(
            rows: handedOver.rows,
            courseCode: course.code,
            courseName: course.configuration.courseName,
            sectionNumber: sectionNumber,
            occasion: record.occasion
        ) else {
            return
        }
        let opened: Bool
        switch assistant {
        case .claude:
            opened = ClaudeCodeLauncher.open(
                workspacePath: folder.path,
                courseCode: course.code,
                courseName: course.configuration.courseName,
                greeting: greeting.text
            )
        case .codex:
            opened = CodexLauncher.open(
                workspacePath: folder.path,
                courseCode: course.code,
                courseName: course.configuration.courseName,
                greeting: greeting.text
            )
        }
        if opened {
            FixWithAssistant.noteOnTheTrail(
                assistant: assistant,
                handover: handedOver,
                greeting: greeting,
                courseCode: course.code,
                sectionNumber: sectionNumber
            )
            return
        }
        doorThatFailed = assistant
        if assistant == .claude {
            doorProblem = ClaudeCodeLauncher.couldNotStartSentence(courseCode: course.code)
        } else {
            doorProblem = CodexLauncher.couldNotStartSentence(courseCode: course.code)
        }
    }

    func tickBinding(for rowID: String) -> Binding<Bool> {
        return Binding(
            get: {
                return store.isTicked(rowID, folder: folder, courseCode: course.code, sectionNumber: sectionNumber)
            },
            set: { ticked in
                store.setTicked(ticked, rowID: rowID, folder: folder, courseCode: course.code, sectionNumber: sectionNumber)
            }
        )
    }

    func dateText(_ date: Date) -> String {
        if date == .distantPast {
            return ""
        }
        return date.formatted(date: .abbreviated, time: .shortened)
    }
}
