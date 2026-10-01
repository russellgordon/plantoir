import Foundation

/// Obsidian opens a reference course's pages in READING view.
///
/// Measured by Russell on 2026-09-23: typing into a locked page makes
/// Obsidian say it could not save, loudly, and the page stays as it was. That
/// is the better of the two things it could have done — but it is still a
/// refusal a teacher meets only because Obsidian opened the page ready to
/// edit. Obsidian has no read-only mode for a vault. What it has is a
/// per-vault preference, `defaultViewMode` in `.obsidian/app.json`, whose
/// `"preview"` is the reading view (the key and its values were read out of
/// Obsidian's own bundle, `obsidian.asar`, rather than guessed). Set on a
/// reference course, pages open rendered and not editable; a teacher who
/// switches a page to editing still meets the refusal, and nothing is
/// promised that the lock does not keep.
///
/// `.obsidian` is in `ReferenceLock.neverLocked` — Obsidian writes into it
/// the moment a vault opens — which is exactly why this file CAN be written
/// after the lock is on. Every other key the teacher's own settings carry is
/// kept: the file is read, one key is set, and it is written back; a course
/// with no `.obsidian` yet gets the folder and a file holding only this key.
enum ReferenceReadingView {

    // MARK: - Stored properties

    /// Obsidian's own names for the preference and for the reading view.
    static let key: String = "defaultViewMode"
    static let readingView: String = "preview"

    // MARK: - Functions

    /// Set the reading view as the default for the vault at `courseURL`.
    ///
    /// Best effort by design: a settings file Obsidian cannot read, or a
    /// folder that refuses the write, leaves the course exactly as useful as
    /// it was — the lock, not this, is what keeps the pages. Returns whether
    /// the key was written, so a caller can put a line on the trail.
    @discardableResult
    static func makeReadingViewTheDefault(for courseURL: URL) -> Bool {
        let obsidianURL: URL = courseURL.appendingPathComponent(".obsidian", isDirectory: true)
        let settingsURL: URL = obsidianURL.appendingPathComponent("app.json")
        var settings: [String: Any] = [:]
        if let data = try? Data(contentsOf: settingsURL) {
            guard let existing = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
                // Not a settings file Obsidian would read either. Leave it.
                return false
            }
            settings = existing
        }
        if let already = settings[key] as? String, already == readingView {
            return true
        }
        settings[key] = readingView
        do {
            try FileManager.default.createDirectory(
                at: obsidianURL, withIntermediateDirectories: true
            )
            let data: Data = try JSONSerialization.data(
                withJSONObject: settings, options: [.prettyPrinted, .sortedKeys]
            )
            try data.write(to: settingsURL, options: .atomic)
            return true
        } catch {
            return false
        }
    }

    /// Whether the vault at `courseURL` opens in reading view.
    static func isReadingViewTheDefault(for courseURL: URL) -> Bool {
        let settingsURL: URL = courseURL
            .appendingPathComponent(".obsidian", isDirectory: true)
            .appendingPathComponent("app.json")
        guard let data = try? Data(contentsOf: settingsURL),
              let settings = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
        else {
            return false
        }
        return (settings[key] as? String) == readingView
    }
}
