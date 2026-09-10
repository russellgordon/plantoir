import Foundation

/// Something the teacher removed from the sidebar, kept so it can come back.
///
/// The removal writes a zip beside the course's other archives. Two kinds of
/// zip live there: the ones this app writes when a teacher removes a course
/// or section — named after what was removed — and the ones the setup wizard
/// writes automatically before it changes a course, named by timestamp alone.
/// Only the first kind is something a teacher chose to put away, so only that
/// kind is listed as archived.
struct ArchivedItem: Identifiable, Hashable {

    // MARK: - Stored properties

    /// The course this belonged to.
    let courseCode: String

    /// Which section, or nil when the whole course was archived.
    let sectionNumber: Int?

    /// When it was put away.
    let archivedAt: Date

    /// Where the archive is, so it can be revealed or restored.
    let fileURL: URL

    // MARK: - Computed properties

    var id: String {
        return fileURL.path
    }

    /// "IZN2O" or "IZN2O — Section 1".
    var title: String {
        guard let sectionNumber else {
            return courseCode
        }
        return "\(courseCode) — Section \(sectionNumber)"
    }

    /// The same symbol the live sidebar uses, so an archived section looks
    /// like a section and an archived course looks like a course.
    var symbolName: String {
        if sectionNumber == nil {
            return "books.vertical"
        }
        return "doc.richtext"
    }

    /// "Archived 10 August 2026".
    var subtitle: String {
        let formatter: DateFormatter = DateFormatter()
        formatter.dateStyle = .long
        formatter.timeStyle = .none
        return "Archived \(formatter.string(from: archivedAt))"
    }

    // MARK: - Functions

    /// Reads an archive's name, which the archiver builds as
    /// `<CODE>_<timestamp>.zip` or `<CODE>-section<N>_<timestamp>.zip`.
    /// Returns nil for anything else, including the wizard's automatic
    /// backups, which are named `<timestamp>.zip`.
    static func from(fileURL: URL, courseCode: String) -> ArchivedItem? {
        if fileURL.pathExtension.lowercased() != "zip" {
            return nil
        }
        let name: String = fileURL.deletingPathExtension().lastPathComponent
        guard let underscoreIndex = name.firstIndex(of: "_") else {
            return nil
        }
        let subject: String = String(name[name.startIndex..<underscoreIndex])
        let stamp: String = String(name[name.index(after: underscoreIndex)...])

        guard let archivedAt = ArchiveStamp.moment(from: stamp) else {
            return nil
        }

        if subject == courseCode {
            return ArchivedItem(courseCode: courseCode, sectionNumber: nil, archivedAt: archivedAt, fileURL: fileURL)
        }
        let sectionPrefix: String = "\(courseCode)-section"
        if subject.hasPrefix(sectionPrefix) {
            let digits: String = String(subject.dropFirst(sectionPrefix.count))
            if let sectionNumber = Int(digits) {
                return ArchivedItem(courseCode: courseCode, sectionNumber: sectionNumber, archivedAt: archivedAt, fileURL: fileURL)
            }
        }
        return nil
    }
}
