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
/// with a tick per row — ticked means included, for 717b's Fix with Claude
/// or Codex — sortable by kind, and the repair inline where a problem has
/// one, because the alert no longer comes with every build.
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

    // MARK: - Computed properties

    var store: SectionProblems {
        return SectionProblems.shared
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
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(.background)
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
