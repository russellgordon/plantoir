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

/// What kind of change an `AssistChange` was, so an undo from either surface
/// can say which event it was undoing (#96). An enum rather than a Bool, so a
/// third kind is a case rather than a second flag.
nonisolated enum AssistChangeKind: Equatable {

    /// Everything the assistant has always recorded.
    case ordinary

    /// A section got ready for the start of the year, in one act.
    case startOfYear
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

    /// Which kind of change this was. `.ordinary` unless said otherwise.
    let kind: AssistChangeKind

    /// Whether the change belongs to the COURSE rather than to one section —
    /// the How I Teach page (#209), which is one page per course. Such a
    /// change still carries a section number, because an undo entry and a
    /// backup name need one, but `description` does not say it: "wrote the
    /// How I Teach page in ICS4U Section 1" would be wrong about a page that
    /// belongs to every section (#209 plan review, item 6).
    var appliesToTheWholeCourse: Bool = false

    // MARK: - Computed properties

    /// The same clause with the section on the end, for anywhere that has not
    /// already said which section it is talking about: "unpublished Unit 4,
    /// Day 23 in ADA1O Section 1". A change to the whole course names the
    /// course alone.
    var description: String {
        if appliesToTheWholeCourse {
            return "\(whatHappened) in \(courseCode)"
        }
        return "\(whatHappened) in \(courseCode) Section \(sectionNumber)"
    }

    // MARK: - Initializer

    init(whatHappened: String,
         courseCode: String,
         sectionNumber: Int,
         rebuildsThePreview: Bool,
         files: [AssistSavedFile],
         appliesToTheWholeCourse: Bool = false,
         kind: AssistChangeKind = .ordinary) {
        self.whatHappened = whatHappened
        self.courseCode = courseCode
        self.sectionNumber = sectionNumber
        self.rebuildsThePreview = rebuildsThePreview
        self.files = files
        self.appliesToTheWholeCourse = appliesToTheWholeCourse
        self.kind = kind
    }
}

/// What an undo does with one saved file (#555). One rule, asked by the
/// undo itself (`AssistChangeHistory.undo()`) and by the start-of-year undo
/// sheet before the teacher agrees (`StartOfYearPreparation.whatAnUndoWouldDo`),
/// so the sheet can never list a page differently from how the undo treats it.
/// The rows are `contracts/assist-cases.json` → `undoFiles.files`.
enum AssistUndoVerdict: String {

    /// The file is exactly as the change left it, so the copy from before is
    /// written back (or the page the change created is removed again).
    case putBack

    /// The file is ALREADY as it was before the change — an earlier press of
    /// Undo put it back, or the teacher did — so nothing is written, and it
    /// does not hold the change on the list. Until #555 such a file counted
    /// as "edited since", so a change that one press had taken back in part
    /// could never come off the list however the teacher tidied up.
    case alreadyBack

    /// The file is neither: the teacher has changed it since. Left exactly as
    /// it is, because putting the old copy back would throw newer work away.
    case leftAlone

    // MARK: - Functions

    /// Which of the three this file is, read off the disk now.
    ///
    /// **"No file" means the path is GONE**, never "could not be read as
    /// text". A folder, or a file that is not UTF-8, at the path reads back
    /// as nil through `String(contentsOf:)` exactly as an absent file does,
    /// and treating that nil as "absent" would call a created page that is
    /// still there "already back" and take the change off the list with the
    /// page never removed (#555 plan review, S1). So an unreadable file
    /// matches neither copy, and is left alone.
    ///
    /// **Both copies are compared, and "before" wins when both match.** They
    /// can only both match when the change left the file as it found it (an
    /// all-absent row is the plain case). Nothing would be written then, and
    /// checking "after" first would try to remove a file that is not there,
    /// fail, and hold the change on the list for ever (review S2).
    static func of(_ file: AssistSavedFile) -> AssistUndoVerdict {
        let matchesAfter: Bool = AssistUndoVerdict.disk(at: file.fileURL, holds: file.after)
        let matchesBefore: Bool = AssistUndoVerdict.disk(at: file.fileURL, holds: file.before)
        if matchesBefore {
            return .alreadyBack
        }
        if matchesAfter {
            return .putBack
        }
        return .leftAlone
    }

    /// Whether the disk holds this copy: `nil` is "there is nothing at this
    /// path at all", and text is "a readable file with exactly this text".
    private static func disk(at fileURL: URL, holds expected: String?) -> Bool {
        guard let expected else {
            return !FileManager.default.fileExists(atPath: fileURL.path)
        }
        var isFolder: ObjCBool = false
        if !FileManager.default.fileExists(atPath: fileURL.path, isDirectory: &isFolder) {
            return false
        }
        if isFolder.boolValue {
            return false
        }
        guard let current = try? String(contentsOf: fileURL, encoding: .utf8) else {
            return false
        }
        return current == expected
    }
}

/// Which of the assistant's sentences an undo is answered with — chosen in
/// one place so the conversation, the Section menu and the contract rows
/// (`undoFiles.presses`, by these names) agree. The raw values are the
/// `AssistWording` keys.
enum AssistUndoAnswer: String {

    /// There was nothing to take back.
    case nothingToUndo

    /// Nothing was written, because a file the change touched has been
    /// edited since. The change stays on the list.
    case couldNotUndo

    /// The change came off the list: every file is back, whether this press
    /// wrote it or it was back already (#555).
    case undid

    /// Some files went back and an edited one was left alone, so the change
    /// stays on the list and Undo can be pressed again.
    case undidPartly
}

/// How an undo went.
struct AssistUndoResult {

    // MARK: - Stored properties

    /// What was undone, or why nothing was.
    let description: String

    /// The change's own clause, for the sentence the teacher reads.
    let whatHappened: String

    /// Files this press WROTE back — what the trail and the start-of-year
    /// sheet count as "put back".
    let restored: [URL]

    /// Files that were already as they were before the change (#555): not
    /// written, not counted as put back, and not holding the change on the
    /// list.
    let alreadyBack: [URL]

    /// Files left alone because they have changed since — putting the old copy
    /// back would throw away newer work.
    let skipped: [URL]

    let succeeded: Bool

    // MARK: - Computed properties

    /// Which sentence answers this undo.
    var answer: AssistUndoAnswer {
        if restored.isEmpty && skipped.isEmpty && alreadyBack.isEmpty {
            return .nothingToUndo
        }
        if skipped.isEmpty {
            return .undid
        }
        if restored.isEmpty {
            return .couldNotUndo
        }
        return .undidPartly
    }
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
/// still owns, and says plainly what it left behind. A file that is already
/// as it was before the change is neither (#555): see `AssistUndoVerdict`.
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
                alreadyBack: [],
                skipped: [],
                succeeded: false
            )
        }

        var restored: [URL] = []
        var alreadyBack: [URL] = []
        var skipped: [URL] = []
        for file in change.files {
            // Covers the created page too: one the teacher has since deleted
            // themselves is GONE, which is what "before" says, so it is
            // already back — nothing is deleted and nothing holds the change
            // on the list (#555; until then it was skipped, which held the
            // entry for ever). A modified page the teacher deleted matches
            // neither copy and is left alone, on purpose: the change is still
            // there to take back once the teacher has decided about the page.
            let verdict: AssistUndoVerdict = AssistUndoVerdict.of(file)
            if verdict == .alreadyBack {
                alreadyBack.append(file.fileURL)
                continue
            }
            if verdict == .leftAlone {
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
        // tried again once the teacher has dealt with the file in the way. A
        // file already back is not left behind (#555): a second press after
        // the teacher has dealt with it takes the entry off.
        let entryCameOff: Bool = skipped.isEmpty
        if entryCameOff {
            changes.removeLast()
        }

        return AssistUndoResult(
            description: change.description,
            whatHappened: change.whatHappened,
            restored: restored,
            alreadyBack: alreadyBack,
            skipped: skipped,
            succeeded: !restored.isEmpty || entryCameOff
        )
    }
}
