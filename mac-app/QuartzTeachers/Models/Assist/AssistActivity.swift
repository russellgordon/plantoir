import Foundation
import Observation

/// Which section has the assistant open, across every window — and there is
/// only ever one.
///
/// **Why one at a time.** The downloaded model is shared: one file per Mac,
/// whatever course or section is being worked on. What is NOT shared is the
/// running copy — each assistant window starts its own engine and loads the
/// weights into memory again. Two windows is twice the memory, which on a
/// 16 GB Mac is most of the machine and undoes the whole point of sizing the
/// model to the hardware.
///
/// It also removes a subtler problem. Two conversations about two sections
/// would evict each other's prompt cache on every alternating turn, since
/// their prefixes differ from the first sentence — so both would feel slower
/// than either alone, for no benefit a teacher asked for.
///
/// The rule is therefore a plain one a teacher can hold in their head: the
/// assistant is a thing you have open, not a thing you have several of.
///
/// **This governs the built-in assistant only.** Claude Code driving the same
/// tools over MCP is unaffected — that is a different client with no engine
/// of its own, so nothing about it multiplies memory.
@MainActor
enum AssistActivity {

    // MARK: - Types

    /// The section an assistant window is open for.
    struct Session: Equatable {
        let folderPath: String
        let courseCode: String
        let sectionNumber: Int
    }

    /// Observable for the same reason `CourseActivity.Store` is: the sidebar
    /// menu has to re-render the moment an assistant opens or closes, or it
    /// shows the answer from whenever the row last drew.
    @Observable
    final class Store {
        var active: Session?

        /// The backups the open conversation can put its section back from —
        /// asked of that window's own tool runner each time, so a copy the
        /// conversation makes mid-way is covered the moment it exists. Nil
        /// while no assistant window is open. See `backupsAnOpenConversationHolds`.
        var heldBackups: (@MainActor () -> [URL])?
    }

    // MARK: - Stored properties

    static let store: Store = Store()

    // MARK: - Computed properties

    /// The section that currently has the assistant, if any.
    static var active: Session? {
        return store.active
    }

    // MARK: - Functions

    /// Records that an assistant window has opened for one section.
    ///
    /// Claiming rather than asking: the window is already on screen by the
    /// time this runs, and the menu is what prevents a second one being
    /// opened. If a claim somehow arrives while another is held, the newer
    /// one wins — a stale claim from a window that failed to release would
    /// otherwise lock the feature out until the app restarted.
    static func begin(folderPath: String, courseCode: String, sectionNumber: Int) {
        store.active = Session(
            folderPath: folderPath,
            courseCode: courseCode,
            sectionNumber: sectionNumber
        )
    }

    /// Records that an assistant window has closed.
    ///
    /// Only clears the claim if it is still THIS window's. Two windows
    /// closing out of order must not leave the survivor unable to be found.
    static func end(folderPath: String, courseCode: String, sectionNumber: Int) {
        let ending: Session = Session(
            folderPath: folderPath,
            courseCode: courseCode,
            sectionNumber: sectionNumber
        )
        if store.active == ending {
            store.active = nil
            store.heldBackups = nil
        }
    }

    /// Says where the open conversation's backups are, so nothing deletes one
    /// while its "Restore Section N…" button is still offered (issue #242).
    ///
    /// Only for the window holding the claim: a stale window's report would
    /// protect backups nobody can restore from, which is harmless, but a claim
    /// that has moved on belongs to somebody else.
    static func holdBackups(
        folderPath: String,
        courseCode: String,
        sectionNumber: Int,
        from report: @escaping @MainActor () -> [URL]
    ) {
        let holding: Session = Session(
            folderPath: folderPath,
            courseCode: courseCode,
            sectionNumber: sectionNumber
        )
        if store.active == holding {
            store.heldBackups = report
        }
    }

    /// The backups an open assistant conversation can restore from.
    ///
    /// **A delete must never remove one of these.** The conversation's banner
    /// still offers "Restore Section N…", and a restore from a zip that is gone
    /// fails after the teacher has already agreed to it. Measured by the plan
    /// review: the "Select the Assistant's" convenience first proposed for the
    /// All Backups pane, followed by one Delete, would remove exactly that
    /// backup — reasoned from the code, not measured.
    static func backupsAnOpenConversationHolds() -> [URL] {
        guard let report = store.heldBackups else {
            return []
        }
        return report()
    }

    /// "Close the assistant for ICS3U Section 2 " followed by `when` — the ONE
    /// place the sentence is built, because a teacher meets it from three:
    /// opening a second assistant and deleting a backup the open conversation
    /// still needs ("…first", `closeTheAssistantFirst`), and removing a
    /// downloaded assistant ("…before removing this.",
    /// `AssistModelLibrary.reasonItCannotBeRemoved`).
    static func closeTheAssistant(_ session: Session, _ when: String) -> String {
        return "Close the assistant for \(session.courseCode) Section \(session.sectionNumber) " + when
    }

    /// "Close the assistant for ICS3U Section 2 first".
    static func closeTheAssistantFirst(_ session: Session) -> String {
        return AssistActivity.closeTheAssistant(session, "first")
    }

    /// Whether the assistant may be opened for this section.
    ///
    /// True when nothing is open, and true for the section that already has
    /// it — asking again simply brings that window forward, which is what a
    /// teacher expects from a menu item naming a window they can see.
    static func mayOpen(folderPath: String, courseCode: String, sectionNumber: Int) -> Bool {
        guard let active = store.active else {
            return true
        }
        return active == Session(
            folderPath: folderPath,
            courseCode: courseCode,
            sectionNumber: sectionNumber
        )
    }

    /// Why the assistant cannot be opened for this section, in a teacher's
    /// words, or nil when it can be.
    ///
    /// Names the section holding it. "Not available" tells somebody they
    /// cannot do the thing; naming the section tells them what to close.
    static func reasonItIsUnavailable(
        folderPath: String,
        courseCode: String,
        sectionNumber: Int
    ) -> String? {
        if mayOpen(folderPath: folderPath, courseCode: courseCode, sectionNumber: sectionNumber) {
            return nil
        }
        guard let active = store.active else {
            return nil
        }
        return AssistActivity.closeTheAssistantFirst(active)
    }
}
