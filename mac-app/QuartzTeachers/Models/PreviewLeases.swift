import Foundation
import Observation

/// Hands out preview ports, one per running preview, across every window.
///
/// The container publishes ports 8081–8084, so up to four previews can run
/// at once — a teacher comparing sections side by side. Each preview leases
/// a port when it starts and returns it when it stops; the same section can
/// only be previewed in one place, because two builds of one section would
/// race over the same output folder.
///
/// A preview here is also a `preview` lease on disk (#156), derived by
/// `WorkLeaseRegistry` from this list, so that a build started by ANOTHER
/// process declines rather than ending the page the teacher is reading.
@MainActor
enum PreviewLeases {

    // MARK: - Types

    struct Lease: Equatable {
        let port: Int
        let folderPath: String
        let courseCode: String
        let sectionNumber: Int
    }

    /// Why a preview could not start, in words a teacher can act on.
    enum Problem: LocalizedError {
        case sectionAlreadyPreviewed(String, Int)
        case allPortsBusy

        var errorDescription: String? {
            switch self {
            case .sectionAlreadyPreviewed(let code, let section):
                return "Section \(section) of \(code) is already being previewed in another window. Stop that preview first, or work with it there."
            case .allPortsBusy:
                return "Four previews of this folder are already running, which is the most that can run at once. Stop one, then try again."
            }
        }
    }

    /// The backing store is observable so that views deciding what to
    /// offer — like the sidebar disabling "Add Section…" for a busy
    /// course — re-render the moment a preview starts or stops. A plain
    /// static array would leave such views showing yesterday's answer.
    @Observable
    final class Store {
        var active: [Lease] = []
    }

    // MARK: - Stored properties

    /// The ports the container publishes.
    static let availablePorts: [Int] = [8081, 8082, 8083, 8084]

    static let store: Store = Store()

    // MARK: - Computed properties

    /// The previews currently running, across all windows.
    static var active: [Lease] {
        return store.active
    }

    // MARK: - Functions

    /// Leases a port for a preview of one section, refusing politely when
    /// the section is already live elsewhere or every port is taken.
    ///
    /// Two leases are in the same folder however either was spelled (#189):
    /// the folder's one workspace publishes the ports, so a second spelling
    /// counted as another folder would be handed a port already in use.
    static func lease(folderPath: String, courseCode: String, sectionNumber: Int) throws -> Lease {
        let wantedFolder: String = FolderIdentity.canonicalPath(folderPath)
        for existing in active {
            let samePlace: Bool = FolderIdentity.canonicalPath(existing.folderPath) == wantedFolder
                && existing.courseCode == courseCode
                && existing.sectionNumber == sectionNumber
            if samePlace {
                throw Problem.sectionAlreadyPreviewed(courseCode, sectionNumber)
            }
        }

        // Ports are per-container, and each folder has its own container —
        // so only previews in the SAME folder contend for them.
        var takenPorts: [Int] = []
        for existing in active {
            if FolderIdentity.canonicalPath(existing.folderPath) == wantedFolder {
                takenPorts.append(existing.port)
            }
        }
        for port in availablePorts {
            if !takenPorts.contains(port) {
                let lease: Lease = Lease(
                    port: port,
                    folderPath: folderPath,
                    courseCode: courseCode,
                    sectionNumber: sectionNumber
                )
                store.active.append(lease)
                WorkLeaseRegistry.reconcile()
                return lease
            }
        }
        throw Problem.allPortsBusy
    }

    /// Returns a lease when its preview stops, whatever the reason.
    static func release(_ lease: Lease) {
        var remaining: [Lease] = []
        for existing in active {
            if existing != lease {
                remaining.append(existing)
            }
        }
        store.active = remaining
        WorkLeaseRegistry.reconcile()
    }

    /// Starts from nothing — for tests.
    static func reset() {
        store.active = []
        WorkLeaseRegistry.reconcile()
    }
}
