import Foundation
import Observation

/// Which courses are doing something right now, across every window:
/// previewing (known via `PreviewLeases`) or publishing (recorded here).
///
/// Re-running the course setup rewrites a course's folders and files, so
/// actions like "Add Section…" must decline while one of the course's
/// sections is previewing or publishing — the setup run and the build
/// could stomp on each other's files.
@MainActor
enum CourseActivity {

    // MARK: - Types

    struct PublishRecord: Equatable {
        let folderPath: String
        let courseCode: String
        let sectionNumber: Int
    }

    /// The backing store is observable for the same reason as
    /// `PreviewLeases.Store`: views reading `courseIsBusy` must
    /// re-render the moment a publish begins or ends.
    @Observable
    final class Store {
        var activePublishes: [PublishRecord] = []
    }

    // MARK: - Stored properties

    static let store: Store = Store()

    // MARK: - Computed properties

    /// The publishes currently running, across all windows.
    static var activePublishes: [PublishRecord] {
        return store.activePublishes
    }

    // MARK: - Functions

    /// Records that a publish of one section has begun.
    static func beginPublish(folderPath: String, courseCode: String, sectionNumber: Int) {
        let record: PublishRecord = PublishRecord(
            folderPath: folderPath,
            courseCode: courseCode,
            sectionNumber: sectionNumber
        )
        store.activePublishes.append(record)
    }

    /// Records that a publish has finished, however it finished.
    static func endPublish(folderPath: String, courseCode: String, sectionNumber: Int) {
        let finished: PublishRecord = PublishRecord(
            folderPath: folderPath,
            courseCode: courseCode,
            sectionNumber: sectionNumber
        )
        var remaining: [PublishRecord] = []
        var didRemoveOne: Bool = false
        for existing in activePublishes {
            if existing == finished && !didRemoveOne {
                didRemoveOne = true
                continue
            }
            remaining.append(existing)
        }
        store.activePublishes = remaining
    }

    /// True while any section of the course is PUBLISHING — previews do not
    /// count.
    ///
    /// `courseIsBusy` answers "previewing or publishing", which is right for
    /// disabling a menu item and wrong for anything that needs to know whether
    /// somebody is publishing. Asking the wrong one of these made the repair
    /// dialog's "Preview Again" refuse whenever a preview was running, which is
    /// every time it is offered.
    static func coursePublishIsRunning(folderPath: String, courseCode: String) -> Bool {
        for publish in activePublishes {
            if publish.folderPath == folderPath && publish.courseCode == courseCode {
                return true
            }
        }
        return false
    }

    /// True while any section of the course is previewing or publishing.
    static func courseIsBusy(folderPath: String, courseCode: String) -> Bool {
        return busyDescription(folderPath: folderPath, courseCode: courseCode) != nil
    }

    /// A short reason the course is busy — naming whichever activity is
    /// in the way — or nil when it isn't. Menu-length on purpose: it
    /// sits under a disabled menu item.
    static func busyDescription(folderPath: String, courseCode: String) -> String? {
        var isPreviewing: Bool = false
        for lease in PreviewLeases.active {
            if lease.folderPath == folderPath && lease.courseCode == courseCode {
                isPreviewing = true
            }
        }
        let isPublishing: Bool = coursePublishIsRunning(
            folderPath: folderPath, courseCode: courseCode
        )
        if isPreviewing && isPublishing {
            return "Available once preview and deploy completed"
        }
        if isPreviewing {
            return "Available once preview completed"
        }
        if isPublishing {
            return "Available once deploy completed"
        }
        return nil
    }

    /// Starts from nothing — for tests.
    static func reset() {
        store.activePublishes = []
    }
}
