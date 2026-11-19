import Foundation

/// The `sectionFrontPage` maintainer (`undoJournal.opKinds.recompute`): the
/// section's landing page is kept pointing at its newest visible class by
/// the same rule a publish, a re-date and the start of the year use
/// (`SectionIndexPointer.repointIndex`). Recorded since U1 as a rule rather
/// than as content (plan 3.1, review 13), so an Undo or a Redo re-derives it
/// from the pages as they now stand, whatever else changed it since.
///
/// On the main actor, as `SectionIndexPointer` is. The list registers it
/// through `UndoMaintainers` (U7 registers it with the switch; the tests
/// register it now).
enum UndoSectionFrontPage {

    // MARK: - Functions

    /// Re-derives the landing page the op names. False, writing nothing,
    /// when the op does not name a section's landing page under a course
    /// whose settings can be read.
    @discardableResult
    static func rederive(_ op: UndoOp, root: URL) -> Bool {
        guard let path = op.path, let sectionNumber = op.section else {
            return false
        }
        let parts: [Substring] = path.split(separator: "/", omittingEmptySubsequences: false)
        if parts.count < 3 || parts[0] != "courses" {
            return false
        }
        let code: String = String(parts[1])
        let courseURL: URL = root.appendingPathComponent("courses").appendingPathComponent(code)
        guard let configuration = try? CourseConfiguration(
            contentsOf: courseURL.appendingPathComponent("course_config.json")
        ) else {
            return false
        }
        let course: Course = Course(code: code, directoryURL: courseURL, configuration: configuration)
        let kept: URL = SectionIndexPointer.indexURL(forSection: sectionNumber, in: course).standardizedFileURL
        let named: URL = root.appendingPathComponent(path).standardizedFileURL
        if kept.path != named.path {
            return false
        }
        _ = SectionIndexPointer.repointIndex(forSection: sectionNumber, in: course)
        return true
    }
}
