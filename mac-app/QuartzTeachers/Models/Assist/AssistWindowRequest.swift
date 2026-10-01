import Foundation

/// Which section an assistant window is about.
///
/// The value a `WindowGroup` is keyed by, so opening the assistant twice for
/// the same section brings the existing window forward instead of starting a
/// second copy — which would mean a second `llama-server`, a second few
/// gigabytes of the teacher's memory, and two conversations that each think
/// they are the only one making changes.
struct AssistWindowRequest: Hashable, Codable, Identifiable {

    // MARK: - Stored properties

    let courseCode: String
    let sectionNumber: Int
    let workingFolder: URL

    // MARK: - Computed properties

    var id: String {
        return "\(workingFolder.path)#\(courseCode)#\(sectionNumber)"
    }

    // MARK: - Functions

    /// Whether this request names a course kept for reference, and so must
    /// not open a window at all.
    ///
    /// **Decision (d): the local assistant is not offered on a reference
    /// course, and is told nothing about one.** The menu item is not drawn,
    /// which is where a teacher meets it — but a window value can also arrive
    /// from a restored scene or a stale `openWindow(value:)`, and this is what
    /// forecloses that. It is also what closes the deploy approval card as a
    /// door by CONSTRUCTION: the card is shown by the agent, the agent lives
    /// in the window, and the window never opens on one of these.
    ///
    /// Asked of the FOLDER rather than of a loaded workspace, because this
    /// runs while the scene is being built and there is no model yet.
    func namesACourseKeptForReference() -> Bool {
        let configURL: URL = workingFolder
            .appendingPathComponent("courses")
            .appendingPathComponent(courseCode)
            .appendingPathComponent("course_config.json")
        guard let configuration = try? CourseConfiguration(contentsOf: configURL) else {
            return false
        }
        return configuration.keptForReference
    }
}
