import Foundation

/// Every sentence the assistant says to a teacher about deploying, previewing
/// and agreeing to things — written once, here.
///
/// **Why a table rather than the sentences where they are used.** They were
/// where they were used, and the same sentence existed four times: in the
/// Swift that says it, in the Swift test that pins it, in `GUI-IMPROVEMENTS.md`
/// where it is specified, and in `WINDOWS-HANDOFF.md` where Windows is told to
/// copy it. Three of those four were already drifting — "the output is in that
/// section's console" against "…that section's window", the same failure told
/// two ways depending on which of two functions ran it. A sentence a teacher
/// reads is a specification, and a specification kept in four places is three
/// places to be wrong.
///
/// **Why the parameters are Strings.** `section` is an `Int` everywhere else,
/// and it is a `String` here so the CONTRACT GENERATOR can call these same
/// functions with `{course}` and `{section}` and get the template out. That is
/// the whole trick: the file Windows tests against is produced by running this
/// table, so it cannot describe wording the mac does not actually say.
/// See `AssistContract` and `contracts/README.md`.
///
/// **What belongs here.** Sentences BOTH platforms say — the approval card,
/// the cancels, what a deploy or a preview reports. Not the model's own words,
/// not anything composed from a list (a plan naming eleven pages is written
/// where the pages are known), and nothing platform-specific.
nonisolated enum AssistWording {

    // MARK: - Agreeing to something

    /// The deploy approval card, said before "Shall I deploy?".
    ///
    /// Twice cut. It began as a label with the warnings stapled on — "the one
    /// thing that changes what students see, and Plantoir cannot take it back
    /// for you. Looking the preview over first is the safer order" — which
    /// announces a limitation of the app to somebody who has already decided,
    /// and second-guesses the order they work in. The middle draft named the
    /// act, "OK, I'll deploy CIA4U Section 1 to Netlify.", and read oddly
    /// against the question that follows it: agreeing to do a thing and then
    /// asking permission for it. What is left is the consequence and one piece
    /// of advice a teacher can act on.
    static let deployApproval: String =
        "Students will see what is deployed. Be certain to review changes you have made."

    /// The question under the deploy card. The act is named HERE, which is why
    /// the sentence above does not name it.
    static let deployQuestion: String = "Shall I deploy?"

    /// The question under a plan card.
    static let planQuestion: String = "Shall I go ahead?"

    /// What the teacher's own bubble says when they press the deploy card's Go.
    static let deployAccepted: String = "Deploy"

    /// The same, for a plan.
    static let planAccepted: String = "Go"

    /// The same, for either card's Cancel.
    static let cancelled: String = "Cancel"

    /// A cancelled DEPLOY. The fact, and nothing else: a teacher who has just
    /// pressed Cancel knows nothing was changed, and being reassured of it
    /// reads as the assistant explaining itself.
    static let deployWasCancelled: String = "Deploy cancelled."

    /// A cancelled PLAN — and here the reassurance IS the answer, because the
    /// plan described changes to pages and whether they happened is the part
    /// genuinely in doubt.
    static let planWasCancelled: String = "Left as it was — nothing was changed."

    // MARK: - Deploying

    static func deployed(course: String, section: String) -> String {
        return "\(course) Section \(section) is deployed. Students can reach it now."
    }

    static func couldNotBuildBeforeDeploying(course: String, section: String) -> String {
        return "\(course) Section \(section) could not be built, so nothing was sent to students. "
             + AssistWording.whereTheOutputIs
    }

    static func deployDidNotFinish(course: String, section: String) -> String {
        return "The deploy of \(course) Section \(section) did not finish. " + AssistWording.whereTheOutputIs
    }

    /// Said only when a course has MORE THAN ONE deploy destination
    /// configured and every one of them succeeded — a course with exactly
    /// one destination (the overwhelming majority) always uses `deployed`
    /// above instead, unchanged, so nothing about a teacher's experience
    /// changes unless they opted into redundancy.
    static func deployedToMultipleDestinations(course: String, section: String, destinationCount: Int) -> String {
        return "\(course) Section \(section) is deployed to all \(destinationCount) destinations you "
             + "configured. Students can reach it now."
    }

    /// Said when a multi-destination deploy finished with SOME destinations
    /// succeeding and others not. `failedDestinations` is already joined
    /// into words ("Cloudflare Pages" or "Cloudflare Pages and your
    /// folder") by the caller, which is the one place that knows the list —
    /// this table only ever holds whole sentences, never list-joining logic.
    static func deployPartiallySucceeded(course: String, section: String, failedDestinations: String) -> String {
        return "\(course) Section \(section) deployed to some of its destinations, but not "
             + "\(failedDestinations). " + AssistWording.whereTheOutputIs
    }

    /// Said when a multi-destination deploy finished and NONE of its
    /// destinations succeeded.
    static func deployToMultipleDestinationsDidNotFinish(course: String, section: String) -> String {
        return "The deploy of \(course) Section \(section) did not finish, on any of its destinations. "
             + AssistWording.whereTheOutputIs
    }

    /// Said when the section's own window is already running something. The
    /// Deploy button is simply greyed out then; the assistant reaches this by
    /// pressing a button a teacher could not have pressed, and needs a
    /// sentence rather than nothing happening.
    static func sectionIsBusy(course: String, section: String) -> String {
        return "\(course)-S\(section) is already busy in Plantoir. Wait for that to finish, then deploy."
    }

    /// Said when any of the course's sections is previewing or publishing and
    /// there is no window to press.
    ///
    /// A whole sentence on purpose. `CourseActivity.busyDescription` returns
    /// "Available once preview completed", which is written to sit under a
    /// greyed-out menu item and says nothing about what was asked for when it
    /// is read out on its own in a conversation.
    static func courseIsBusy(course: String) -> String {
        return "\(course) is busy in Plantoir — a preview or a deploy is running. "
             + "Wait for that to finish, then ask again."
    }

    // MARK: - Previewing

    /// A section window is open, so its own Preview is what runs.
    static func previewIsRebuilding(course: String, section: String) -> String {
        return "The preview for \(course) Section \(section) is rebuilding now, and will appear in "
             + "that section's window when it is ready."
    }

    /// No window is open, so the site is brought up to date on disk and the
    /// answer says so rather than claiming a preview nobody can see.
    static func builtWithNoWindowOpen(course: String, section: String) -> String {
        return "Rebuilt the site for \(course) Section \(section). Open that section in Plantoir and "
             + "press Preview to look it over — no window is showing it at the moment."
    }

    static func rebuiltForACallerWithNoWindow(course: String, section: String) -> String {
        return "Rebuilt the preview for \(course) Section \(section). Open that section in Plantoir "
             + "to look it over."
    }

    static func previewDidNotBuild(course: String, section: String) -> String {
        return "The preview for \(course) Section \(section) did not finish building. "
             + AssistWording.whereTheOutputIs
    }

    // MARK: - Taking something back

    /// Every one of these is a whole sentence with a subject and a verb, and
    /// that is the point of them being here rather than assembled at the call
    /// site.
    ///
    /// They used to be built by pushing a stored clause into a slot —
    /// `"Undid \(description)."` — which produced **"Undid unpublished 2 pages
    /// in ADA1O Section 1."** for a teacher who had asked to unpublish one
    /// class. Three things were wrong with it at once: it was ungrammatical,
    /// it counted files rather than naming what the teacher had asked for, and
    /// the same slot was reused for a refusal, so a REFUSAL to undo anything
    /// also came out reading like a report of success.
    ///
    /// `whatHappened` is always a past-tense clause naming what was done —
    /// "unpublished Unit 4, Day 23" — so it can only ever land inside a
    /// sentence written on purpose.

    /// The undo worked, and everything went back.
    static func undid(_ whatHappened: String) -> String {
        return "Earlier, you \(whatHappened). Then you asked me to undo that, and I have done so."
    }

    /// The undo worked, but some files had been edited since and were left as
    /// they are — so this must NOT read like a clean success.
    static func undidPartly(_ whatHappened: String, leftAlone: Int) -> String {
        let pages: String = leftAlone == 1 ? "one page" : "\(leftAlone) pages"
        return "Earlier, you \(whatHappened). You have asked me to undo that, and I have put back "
             + "everything I still recognised — but I left \(pages) alone, because they have been "
             + "edited since."
    }

    /// Nothing could go back, because every file has been edited since.
    ///
    /// The one that most needed writing. It used to fall through to the
    /// success sentence, so a teacher was told their change had been undone
    /// when not one file had moved.
    static func couldNotUndo(_ whatHappened: String, leftAlone: Int) -> String {
        let pages: String = leftAlone == 1 ? "that page has" : "those \(leftAlone) pages have"
        return "Earlier, you \(whatHappened), and you have asked me to undo that — but I have not "
             + "changed anything, because \(pages) been edited since. Putting my old copy back "
             + "would throw away that newer work."
    }

    /// Why a partly-done undo is still on the list.
    static let undoIsStillAvailable: String =
        "That change is still on the list, so you can ask me to undo it again once you have "
        + "dealt with the pages I left alone."

    /// There is nothing on the list at all.
    ///
    /// "No PAGES", not "nothing", and the distinction is load-bearing. The old
    /// sentence said "I have not changed anything in this conversation yet",
    /// which was a lie in two situations: after creating a class page (now
    /// undoable, so it no longer arises) and after remembering a timetable,
    /// which writes a course's settings and touches no page at all and is
    /// deliberately not on the list. Narrowing the claim to pages makes it
    /// true in every case without making it longer.
    static let nothingToUndo: String =
        "There is nothing on my undo list — I have not changed any pages in this conversation yet. "
        + "Anything older is in Plantoir's Backups list."

    /// Said when a class page is created, because a teacher has to know
    /// whether the way out is "Undo that" or the Finder.
    ///
    /// This sentence used to say the opposite — "“Undo that” does not take
    /// away a page it created — delete it in Obsidian if it isn't wanted" —
    /// which was true of the old undo list and is now wrong. A line describing
    /// what a feature USED to do is worse than no line, because it is believed.
    static let aCreatedPageCanBeTakenBack: String =
        "“Undo that” takes the page away again, as long as you have not written anything in it yet. "
        + "Once you have, it is yours and I will leave it alone."

    /// The standing caveat: an undo reaches the teacher's own files and their
    /// preview, and stops there.
    static let undoDoesNotReachTheLiveSite: String =
        "If you had already deployed this section, undoing it here does not change what students "
        + "see. Deploy again when you want the live site to match."

    // MARK: - Asking for the class dates

    /// The question that stands in front of the schedule sheet.
    ///
    /// The sheet used to open the moment something discovered it needed
    /// dates, ON TOP of the sentence explaining why — so a teacher was handed
    /// a form before they had read the request, and the request was behind it.
    /// A form that arrives unasked is a demand. This makes it an offer, which
    /// is the same courtesy every other write in the window already gets.
    static let mayIAskForYourDates: String = "May I ask you for your class dates?"

    /// What the teacher is told after saying no.
    ///
    /// Deliberately does not re-ask or explain again. They declined a
    /// question they had just read; repeating it is how an assistant becomes
    /// something to get past.
    static let datesNotGivenYet: String =
        "Right you are. I will not be able to date new classes until I have them — "
        + "say “I have a revised list of class dates” whenever you would like to give them."

    // MARK: - Shared fragments

    /// One phrasing for "go and look at what happened", because it was two:
    /// the same failure said "in that section's console in Plantoir" from one
    /// function and "in that section's window in Plantoir" from another,
    /// depending only on whether a window happened to be open. The window is
    /// the thing a teacher opens; the console is a part of it.
    static let whereTheOutputIs: String = "The output is in that section's window in Plantoir."

    /// The model answered with neither a tool nor anything to say.
    static let nothingToDo: String = "I am not sure what to do with that."
}
