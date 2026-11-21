import Foundation

#if DEBUG
/// The one way a test through the real window can make a change go in part
/// way (#899, U3c; Russell's ruling of 2026-11-20, night, is tested with a
/// real window). Debug builds only, and only with `--state-dir`, so an
/// isolated launch is the only launch that can ask for it: a teacher's app
/// never reads the flag.
///
/// `--ui-test-edit-races-the-swap <file name>` makes the FIRST swap of a
/// file with that name behave as another program editing it in place as
/// the swap goes in, with the put-back then failing: the change goes in and
/// what the file held a moment before is kept beside it under its hidden
/// name (`JournaledStepError.leftPartWay`). Every later swap is untouched.
nonisolated enum UndoUITestSeam {

    // MARK: - Stored properties

    static let flag: String = "--ui-test-edit-races-the-swap"

    /// Whether the race has been run once: it is never run again.
    final class Once: @unchecked Sendable {

        // MARK: - Stored properties

        var racedIndex: Int? = nil
        var done: Bool = false
    }

    // MARK: - Functions

    /// Sets the kill points when the arguments ask for it (with
    /// `--state-dir` beside it); otherwise does nothing.
    static func installIfAsked(arguments: [String]) {
        guard arguments.contains(RealHome.stateDirectoryFlag),
              let flagIndex = arguments.firstIndex(of: UndoUITestSeam.flag),
              flagIndex + 1 < arguments.count else {
            return
        }
        let fileName: String = arguments[flagIndex + 1]
        let once: Once = Once()
        UndoKillPoints.beforeTheRename = { index, url in
            if once.done || url.lastPathComponent != fileName {
                return
            }
            guard let handle = try? FileHandle(forWritingTo: url) else {
                return
            }
            _ = try? handle.seekToEnd()
            try? handle.write(contentsOf: Data("\nEdited in Obsidian as the change went in.\n".utf8))
            try? handle.close()
            once.racedIndex = index
        }
        UndoKillPoints.putBackFailsAt = { index in
            if once.done || once.racedIndex != index {
                return false
            }
            once.done = true
            return true
        }
    }
}
#endif
