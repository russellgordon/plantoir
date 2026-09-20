import Foundation

/// One file as it was before a change, and as the change left it.
struct AssistSavedFile: Equatable {

    // MARK: - Stored properties

    let fileURL: URL

    /// The whole file, before — or **nil when there was no file**, because the
    /// change CREATED it. Taking that back means deleting the page again
    /// rather than writing anything.
    ///
    /// Optional rather than an empty string on purpose: an empty page and an
    /// absent one are different states, and a change that created a page it
    /// then left empty must still be undone by deleting it.
    let before: String?

    /// The whole file, after — kept so an undo can tell "nobody has touched
    /// this since" from "the teacher has been editing it in Obsidian".
    ///
    /// Optional for the same reason `before` is, and it is what lets a MOVE be
    /// recorded: a move is two entries, the source with `after: nil` and the
    /// destination with `before: nil`. Until 2026-09-08 this was a plain
    /// `String`, so the source half of a move could not be expressed at all —
    /// the file is gone from there, it reads back as nil, and nil matches no
    /// `String`, so `undo()` skipped it every time. Cutting a section loose
    /// from its website is a move, and Windows' undo has always put the
    /// section back on last year's site; this is what lets the mac do the
    /// same. No logic below changed: `undo()` already compared an optional
    /// `current` against this, and already deletes when `before` is nil.
    let after: String?
}

/// One thing the assistant did, in a form that can be taken straight back.
struct AssistChange: Equatable {

    // MARK: - Stored properties

    /// What was done, as a past-tense clause with no course and no section:
    /// "unpublished Unit 4, Day 23", "added 2 curriculum expectations to
    /// “Journal Checklist”".
    ///
    /// Written to be DROPPED INTO A SENTENCE rather than shown on its own,
    /// which is the whole reason it is stored separately from `description`.
    /// The undo used to read "Undid unpublished 2 pages in ADA1O Section 1." —
    /// a past-tense clause pushed into a slot that wanted a noun, reported by a
    /// teacher. A clause that only ever appears inside a sentence somebody
    /// wrote on purpose cannot come out ungrammatical.
    ///
    /// It names the PAGES while there are few enough to name, because "2
    /// pages" is not what the teacher asked for and not what they will
    /// recognise a minute later — they asked to unpublish Unit 4, Day 23.
    let whatHappened: String

    /// Which section it happened in — so an undo can put that section's
    /// preview back, which it could not do while a change knew only its files.
    let courseCode: String
    let sectionNumber: Int

    /// Whether taking this back should stop and rebuild the section's preview.
    ///
    /// Set to whatever the CHANGE ITSELF did, so an undo costs a teacher the
    /// same rebuild the original cost them and no more. Publishing and hiding
    /// pages rebuild, so their undo rebuilds. Creating a class page does not —
    /// it arrives unpublished, so nothing about the site changes — and neither
    /// should deleting it again. A blanket rebuild would make "undo that" the
    /// slowest thing in the window for the one change that needs it least.
    let rebuildsThePreview: Bool

    let files: [AssistSavedFile]

    // MARK: - Computed properties

    /// The same clause with the section on the end, for anywhere that has not
    /// already said which section it is talking about: "unpublished Unit 4,
    /// Day 23 in ADA1O Section 1".
    var description: String {
        return "\(whatHappened) in \(courseCode) Section \(sectionNumber)"
    }
}

/// How an undo went.
struct AssistUndoResult {

    // MARK: - Stored properties

    /// What was undone, or why nothing was.
    let description: String

    /// The change's own clause, for the sentence the teacher reads.
    let whatHappened: String

    let restored: [URL]

    /// Files left alone because they have changed since — putting the old copy
    /// back would throw away newer work.
    let skipped: [URL]

    let succeeded: Bool
}

/// What this conversation has changed, so it can be taken back.
///
/// Whole-file copies, in memory, for the length of one conversation. That is a
/// deliberately small promise, and it is the right size: it makes `undo that`
/// instant and exact, and everything older is covered by the course backup
/// taken before each change, which lives on disk and outlives the window.
///
/// The rule that matters is the SKIP. A file that has changed since the
/// assistant wrote it is left exactly as it is. A teacher who published a class
/// and then spent ten minutes writing it in Obsidian must not lose those ten
/// minutes to "undo that" — so the undo puts back only what it can prove it
/// still owns, and says plainly what it left behind.
@MainActor
final class AssistChangeHistory {

    // MARK: - Stored properties

    /// Oldest first; the last one is what `undo_last_change` takes back.
    private(set) var changes: [AssistChange] = []

    // MARK: - Computed properties

    var isEmpty: Bool {
        return changes.isEmpty
    }

    /// The change `undo()` would take back, without taking it back.
    ///
    /// Needed because an undo has to stop that section's preview BEFORE it
    /// starts putting files back, and it cannot know which section that is
    /// until it has looked.
    var nextToUndo: AssistChange? {
        return changes.last
    }

    // MARK: - Functions

    func record(_ change: AssistChange) {
        if change.files.isEmpty {
            return
        }
        changes.append(change)
    }

    /// Put the most recent change back.
    func undo() -> AssistUndoResult {
        guard let change = changes.last else {
            return AssistUndoResult(
                description: AssistWording.nothingToUndo,
                whatHappened: "",
                restored: [],
                skipped: [],
                succeeded: false
            )
        }

        var restored: [URL] = []
        var skipped: [URL] = []
        for file in change.files {
            let current: String? = try? String(contentsOf: file.fileURL, encoding: .utf8)
            // Covers the created page too, and covers it correctly: a page the
            // teacher has since deleted themselves reads back as nil, which
            // does not match what the change left, so it is skipped rather
            // than "restored" by deleting something already gone.
            if current != file.after {
                skipped.append(file.fileURL)
                continue
            }
            do {
                if let before = file.before {
                    try before.write(to: file.fileURL, atomically: true, encoding: .utf8)
                } else {
                    // There was no file before this change. Taking it back
                    // means taking the page away again.
                    try FileManager.default.removeItem(at: file.fileURL)
                }
                restored.append(file.fileURL)
            } catch {
                skipped.append(file.fileURL)
            }
        }

        // A change with something left behind stays on the list, so it can be
        // tried again once the teacher has dealt with the file in the way.
        if skipped.isEmpty {
            changes.removeLast()
        }

        return AssistUndoResult(
            description: change.description,
            whatHappened: change.whatHappened,
            restored: restored,
            skipped: skipped,
            succeeded: !restored.isEmpty
        )
    }
}
