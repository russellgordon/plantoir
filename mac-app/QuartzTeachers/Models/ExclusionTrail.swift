import Foundation

/// The `item excluded` and `item re-included` lines, worked out from what a
/// write of a course's configuration actually changed —
/// `contracts/shared-rules.json` → `excludedItems.recordedOnSave` (issue
/// #152, from #85's third item).
///
/// **Why at the write, from the file.** The line used to be written on the
/// CLICK, so a Revert — which puts the configuration back and writes nothing
/// — left the trail saying a folder had been excluded when it never was.
/// Compared at the write, every line is something that reached
/// `course_config.json`. And at EVERY write, in `CourseConfiguration.write(to:)`
/// rather than in Course Settings' Save, because six writers save the same
/// in-memory configuration with whatever is pending in it: a removal left
/// unsaved in Settings reaches the file through Add Section just as well, and
/// a comparison made only at Save would then find it already there and
/// record nothing, ever.
///
/// REJECTED: a buffer filled on the click and flushed at Save — a removal and
/// an add-back before Save would write a line each for a file that never
/// changed, and a buffer cannot see what #265's per-key merge actually wrote.
nonisolated enum ExclusionTrail {

    // MARK: - Types

    /// What the name was, as far as the lists and the disk can say.
    enum Kind: String, Sendable {
        case folder
        case file
        case item
    }

    /// One line's worth: a name that entered or left `excluded_items`.
    struct Change: Equatable, Sendable {

        // MARK: - Stored properties

        /// `.itemExcluded` or `.itemReincluded`.
        let event: ActivityTrail.Event
        let scope: FolderScope
        let kind: Kind
        let name: String
    }

    // MARK: - Functions

    /// The changes between `excluded_items` in `before` — the file as it was
    /// before the write — and in `written`, shared scope first, then
    /// per-section; within a scope, exclusions in the written list's order,
    /// then re-inclusions in the earlier list's order.
    ///
    /// The KIND is `folder` when that scope's folder list names the item (the
    /// list before the write, for an exclusion — the name has just left it;
    /// the written list, for a re-inclusion — it has just come back), `file`
    /// when the file list does, and otherwise whatever `courseDirectory` holds
    /// at that name in that scope, or `item` when it holds nothing there (or
    /// no folder is given). A folder added and then removed before saving is
    /// in neither list, and the disk says what it is.
    static func changes(before: [String: Any], written: [String: Any], courseDirectory: URL? = nil) -> [Change] {
        var changes: [Change] = []
        let scopes: [FolderScope] = [FolderScope.shared, FolderScope.perSection]
        for scope in scopes {
            let excludedBefore: [String] = excludedNames(in: before, scope: scope)
            let excludedAfter: [String] = excludedNames(in: written, scope: scope)
            for name in excludedAfter {
                if excludedBefore.contains(name) {
                    continue
                }
                let kind: Kind = kindOf(name, scope: scope, listedIn: before, courseDirectory: courseDirectory)
                changes.append(Change(event: .itemExcluded, scope: scope, kind: kind, name: name))
            }
            for name in excludedBefore {
                if excludedAfter.contains(name) {
                    continue
                }
                let kind: Kind = kindOf(name, scope: scope, listedIn: written, courseDirectory: courseDirectory)
                changes.append(Change(event: .itemReincluded, scope: scope, kind: kind, name: name))
            }
        }
        return changes
    }

    /// The trail's sentence for one change: "excluded shared folder Labs in
    /// ICS3U", "re-included per-section file Notes.md in ICS3U". The words
    /// are this app's; the contract pins the event, scope, kind and name.
    static func line(for change: Change, courseCode: String) -> String {
        var line: String = "excluded "
        if change.event == .itemReincluded {
            line = "re-included "
        }
        switch change.scope {
        case .shared:
            line += "shared "
        case .perSection:
            line += "per-section "
        }
        return line + change.kind.rawValue + " " + change.name + " in " + courseCode
    }

    /// Writes one trail line per change.
    static func record(_ changes: [Change], courseCode: String) {
        for change in changes {
            ActivityTrail.note(change.event, line(for: change, courseCode: courseCode))
        }
    }

    // MARK: - Reading a configuration

    /// `excluded_items.<scope>`, keeping only names — a hand edit can put
    /// anything in a JSON list — each once.
    static func excludedNames(in configuration: [String: Any], scope: FolderScope) -> [String] {
        guard let excluded = configuration["excluded_items"] as? [String: Any] else {
            return []
        }
        guard let entries = excluded[scope.exclusionKey] as? [Any] else {
            return []
        }
        var names: [String] = []
        for entry in entries {
            if let name = entry as? String, !names.contains(name) {
                names.append(name)
            }
        }
        return names
    }

    static func kindOf(
        _ name: String, scope: FolderScope, listedIn configuration: [String: Any], courseDirectory: URL?
    ) -> Kind {
        var filesKey: String = "shared_files"
        if scope == FolderScope.perSection {
            filesKey = "per_section_files"
        }
        if listed(name, in: configuration[scope.configurationKey]) {
            return .folder
        }
        if listed(name, in: configuration[filesKey]) {
            return .file
        }
        guard let courseDirectory else {
            return .item
        }
        return kindOnDisk(name, scope: scope, courseDirectory: courseDirectory)
    }

    static func listed(_ name: String, in value: Any?) -> Bool {
        guard let entries = value as? [Any] else {
            return false
        }
        for entry in entries {
            if let listedName = entry as? String, listedName == name {
                return true
            }
        }
        return false
    }

    /// What is at `name` in the course folder (shared) or in any section
    /// folder (per-section): a folder, a file, or nothing.
    static func kindOnDisk(_ name: String, scope: FolderScope, courseDirectory: URL) -> Kind {
        var locations: [URL] = []
        switch scope {
        case .shared:
            locations.append(courseDirectory.appendingPathComponent(name))
        case .perSection:
            let children: [URL] = (try? FileManager.default.contentsOfDirectory(
                at: courseDirectory, includingPropertiesForKeys: nil
            )) ?? []
            for child in children {
                if GradedFolderChoices.isSectionFolder(child.lastPathComponent) {
                    locations.append(child.appendingPathComponent(name))
                }
            }
        }
        var sawFile: Bool = false
        for location in locations {
            var isDirectory: ObjCBool = false
            if FileManager.default.fileExists(atPath: location.path, isDirectory: &isDirectory) {
                if isDirectory.boolValue {
                    return .folder
                }
                sawFile = true
            }
        }
        if sawFile {
            return .file
        }
        return .item
    }
}
