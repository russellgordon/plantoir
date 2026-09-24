import Foundation

/// Every sentence the assistant says to a teacher about deploying, previewing,
/// agreeing to things and changing the class pages themselves — written once,
/// here.
///
/// **Why a table rather than the sentences where they are used.** They were
/// where they were used, and the same sentence existed four times: in the
/// Swift that says it, in the Swift test that pins it, in `GUI-IMPROVEMENTS.md`
/// where it is specified, and in documentation/10-local-ai-assistant.md where Windows is told to
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
/// the cancels, what a deploy or a preview reports, and since 2026-09-19 what
/// duplicating a class says and refuses. Not the model's own words, not
/// anything composed from a list (a plan naming eleven pages is written where
/// the pages are known), and nothing platform-specific.
///
/// The class-change sentences came in from the other direction, and it is
/// worth saying which: Windows gathered them in a `ClassChangeWording` of its
/// own precisely BECAUSE the mac worded them inline and a generated file
/// cannot gain keys from that side. Both apps said nearly the same eight
/// sentences with nothing holding them together, which is the drift this table
/// exists to stop.
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
    ///
    /// **"This happens now." was added in front of those two, and it is the
    /// only thing this sentence says about TIME.** The two approval cards were
    /// asymmetric exactly where a misroute lands: `schedule_deploy`'s names the
    /// whole moment, and this one named no time at all — so a teacher who
    /// asked for 6:30 tomorrow and was routed to an immediate deploy read a
    /// card that was perfectly true and said nothing to contradict them
    /// (measured: ten trials out of ten on the smaller assistant, issue #168).
    /// It says WHEN rather than WHAT, so it does not reinstate the naming of
    /// the act that was cut above, and it is first because the word that
    /// contradicts the teacher has to be the one they read first.
    ///
    /// The property is pinned rather than the sentence:
    /// `contracts/shared-rules.json` → `assistantConfirmation.`
    /// `theImmediateDeployCardSaysItIsImmediate`, which asks only that the
    /// sentence carry the word. This will be reworded again; the rule is meant
    /// to outlive the wording.
    static let deployApproval: String =
        "This happens now. Students will see what is deployed. "
      + "Be certain to review changes you have made."

    /// The question under the deploy card. The act is named HERE, which is why
    /// the sentence above does not name it.
    static let deployQuestion: String = "Shall I deploy?"

    /// The question under a SCHEDULED deploy's card (issue #184).
    ///
    /// Its own sentence because `deployQuestion` reads as "now", and the card
    /// above it has just named a moment that is not now — so the question
    /// contradicted the card it sat under. It mattered more once "deploy at
    /// <time>" was matched in code (#168) and scheduling stopped being the rare
    /// path. It must never carry the word "now", and it must differ from
    /// `deployQuestion`; a test pins both rather than the words.
    ///
    /// A FIRST DRAFT for Russell's wording pass. It names "the deploy" rather
    /// than saying "it", because the card above ends on a sentence about this
    /// Mac, and "it" would read as the Mac.
    static let scheduleQuestion: String = "Shall I schedule the deploy?"

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

    // MARK: - Rolling a section over to a new year

    /// The question a rollover asks, and the only one it asks.
    ///
    /// **Neither answer is guessed**, which is the whole decision (Russell,
    /// 2026-09-08). A teacher who keeps one address across years has every
    /// link anybody saved still working; a teacher who starts fresh leaves
    /// last year's site up for last year's students. Both are ordinary things
    /// to want, and the sentence says nothing about which is better.
    static let rolloverWebsiteQuestion: String =
        "Should this be a new website, or the same one students used last year?"


    /// Confirming a new website, when the section had one to be cut loose from.
    ///
    /// It carries the CONSEQUENCE rather than only the fact, because the next
    /// thing that happens to this teacher is a publish that asks them
    /// something new.
    ///
    /// **Naming the file is a considered exception to rule 1, not an
    /// oversight.** A filename is machinery, and plain words are the standing
    /// rule. But the folder it sits in is HIDDEN, so "kept in your course
    /// folder" points a teacher at something Finder will not show them — less
    /// use than a precise string they can search for, and this sentence exists
    /// for the teacher who wants last year's website back. Windows says the
    /// same thing in the same shape, so a shared sentence stays shared.
    static func rolloverStartedANewWebsite(keptAs: String) -> String {
        return rolloverIsOnANewWebsite + " Last year's details are "
             + "kept at \(keptAs), so you can go back to it. The next time you publish this "
             + "section, Plantoir will ask what to call the new website."
    }

    /// The half of that sentence with no filename in it.
    ///
    /// **Named so a contract case can assert it.** The whole sentence carries
    /// the kept file's name, which has a timestamp in it, so no fixed string
    /// can ever match the whole thing — and a test that cannot name the
    /// sentence ends up matching prose it typed itself, which is the copy that
    /// keeps passing after the product's words change.
    static let rolloverIsOnANewWebsite: String =
        "This section is no longer tied to last year's website." 

    /// Confirming a new website for a section that had never been published.
    static let rolloverHadNoWebsiteYet: String =
        "This section had not been published anywhere yet, so there was no website to move away "
        + "from. The first time you publish it, Plantoir will ask what to call it."

    /// Confirming the same website.
    static let rolloverKeptTheSameWebsite: String =
        "This section still publishes to the same website as last year, so every link anybody "
        + "saved keeps working. Nothing goes out until you publish."

    /// What a teacher is told when the question was never answered.
    ///
    /// **The honest half of the feature, and the reason it is a sentence
    /// rather than silence.** The re-dating has already happened by the time
    /// the question appears, so an offer a teacher ignores — or one that
    /// cannot appear at all, which is every request arriving over MCP — must
    /// not leave them believing the website was dealt with. Saying plainly
    /// that it was NOT is what stops this feature quietly recreating the
    /// defect it was built to fix.
    static let rolloverWebsiteNotDecided: String =
        "I have not changed which website this section publishes to — publishing it will still "
        + "go to last year's website. Ask me to roll it over again if you would like to choose."

    /// A destination that could not be released, so the section is still
    /// pinned to it.
    ///
    /// **Its own sentence because the alternative said the opposite.** A
    /// marker that exists and cannot be moved used to produce the same empty
    /// result as one that was never there, so a teacher was told "this section
    /// had not been published anywhere yet" about a section that is still
    /// publishing over last year's site. That is a lie about the one fact this
    /// whole feature turns on.
    static func rolloverCouldNotStartANewWebsite(stillPinned: String) -> String {
        return "I could not move this section off \(stillPinned), so publishing it will still "
             + "replace last year's website there. Try again, or check whether that file is "
             + "locked or open somewhere else."
    }

    /// Added when releasing a website turned off a publish that was set to
    /// happen on its own.
    ///
    /// A section cut loose has nowhere agreed to publish TO, and the scheduled
    /// run has no one to ask, so it would silently create a website nobody
    /// named while the address students actually read stopped updating. The
    /// same shape as renaming a course, which turns the schedule off and says
    /// so for the same reason.
    static let rolloverTurnedOffTheScheduledPublish: String =
        "This section was set to publish on its own. Starting a new website turned that off — "
        + "set it again from the section's menu once you have published the new website for the "
        + "first time."

    /// When turning that scheduled publish off did NOT work.
    ///
    /// The dangerous state, and so the one that must not be described by the
    /// sentence above. A publish still set to run has nobody to ask what the
    /// new website should be called, so it would go ahead and make one — the
    /// exact outcome turning it off exists to prevent. Renaming a course says
    /// the same thing for the same reason.
    static let rolloverCouldNotTurnOffTheScheduledPublish: String =
        "This section was also set to publish on its own, and Plantoir could not turn that off. "
        + "It may still try to publish, and it has no way to ask what the new website should be "
        + "called — turn it off from the section's menu."

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

    // MARK: - Duplicating a class

    /// The one line a teacher reads in the chat when a copy is made.
    static func duplicated(page: String, as copy: String) -> String {
        return "Duplicated “\(page)” as “\(copy)”."
    }

    /// What the copy is, where it landed, and that nobody can see it yet.
    ///
    /// **The date is a String here, and it is a literal in the generated
    /// contract rather than a placeholder.** Windows formats a real date
    /// before it ever reaches its own sentence, so "{date}" is a shape that
    /// side cannot produce; a real date is the only form both apps can render.
    /// `backedUpCourse` set that precedent with a real file name.
    static func copiedTo(page: String, as copy: String, on date: String) -> String {
        return "“\(page)” was copied to “\(copy)”, dated \(date). It is hidden, so nothing changed "
             + "on the site — write it, then publish when it is ready."
    }

    /// The same fact in the future tense, for the plan a teacher agrees to.
    static func wouldBeCopiedTo(page: String, as copy: String, on date: String) -> String {
        return "“\(page)” would be copied to “\(copy)”, dated \(date)."
    }

    /// Said in the plan, because "hidden" is the part a teacher would
    /// otherwise have to ask about.
    static let theCopyStartsHidden: String =
        "The copy starts hidden, so nothing changes on the site until you publish it."

    /// What a plan says about the classes that would move along to make room.
    ///
    /// **`moving` is the UNION of renamed and re-dated pages, not the rename
    /// count** — `ClassInsertionPlan.otherClassesMoving`. Renames happen only
    /// WITHIN the unit being changed, so duplicating the last day of a unit
    /// renames nothing while re-dating every class of every later unit. Keyed
    /// on renames alone, this line was not printed at all in that case, and a
    /// teacher agreed to a plan smaller than what ran.
    ///
    /// Two branches rather than two names, because a caller never has to
    /// choose: the numbers decide. Both are in the contract, since one
    /// rendering cannot show the other.
    ///
    /// - Parameter moving: how many other class pages move, counted once each.
    /// - Parameter renaming: how many of those are also renamed.
    static func otherClassesWouldMove(moving: Int, renaming: Int) -> String {
        let verb: String = moving == 1 ? "class moves" : "classes move"
        if renaming > 0 {
            return "\(moving) later \(verb) a day along to make room, and the links that point at "
                 + "them are rewritten to match."
        }
        // Nothing is renamed, so nothing links anywhere new — but the dates
        // still move, and that is the half a rename count leaves out.
        let theirs: String = moving == 1 ? "Its name does" : "Their names do"
        return "\(moving) later \(verb) onto a later class day to make room. \(theirs) not change."
    }

    /// Said after a change that shuffled other classes: the undo list cannot
    /// take this back, and the backup is what can.
    ///
    /// A partial undo — the copy deleted, every later class left renamed and
    /// re-dated — is worse than no undo at all, so the way back is named
    /// instead. Windows' `ClassChangeWording.OtherClassesMoved` has a second
    /// form that names the backup's file; this is the form both apps say, and
    /// theirs is a platform extra measured against this one.
    static let otherClassesMoved: String =
        "Because other classes moved, “Undo that” will not take this back. The copy made before "
        + "any of it is in Plantoir's Backups list."

    /// A page that is not "Unit N, Day N" has no next day to become.
    static func notANumberedClassPage(page: String) -> String {
        return "“\(page)” isn’t a numbered class page, so there is no next day for it to become."
    }

    /// The copy's place is still occupied, so nothing was written over it.
    ///
    /// **The one refusal here that has to admit to half a job.** It is
    /// answered AFTER the room has been made, so later classes may already
    /// have been renamed and re-dated when a teacher reads it — saying only
    /// "nothing was copied" would be true and would leave them believing
    /// nothing happened. Nothing else in this table fires after a change has
    /// begun, which is why this is the only sentence that says so.
    ///
    /// Two forms, the way Windows' has two: the backup is named when there is
    /// a name for it, because a teacher looking at a list of five backups is
    /// better off with the file than with the category.
    static func thePlaceForTheCopyIsStillTaken(page: String, backupNamed name: String?) -> String {
        var wayBack: String = "The copy of the course made before any of this is "
        if let name {
            wayBack += "\(name), in Plantoir's Backups list."
        } else {
            wayBack += "in Plantoir's Backups list."
        }
        return "“\(page)” is still there — the class that had to move out of the way did not, and "
             + "I will not write over a lesson. Nothing was copied, but other classes may already "
             + "have moved. \(wayBack) Look the section over in Plantoir."
    }

    /// The copy could not be made certainly hidden, so it was not made at all.
    ///
    /// **Reachable, and only where the page being copied is one this app
    /// cannot read well enough to answer about** — a tab used as indentation
    /// in the settings at the top of the page, or a value that runs on below
    /// its own line. Measured: both are pages the BUILD refuses too, so the
    /// honest answer is to stop rather than to guess, and a copy of a lesson
    /// students can already see is the one thing that must not be guessed at.
    ///
    /// Said after the room has been made, like its sibling
    /// `thePlaceForTheCopyIsStillTaken`, so it carries the same two facts that
    /// sentence carries and one of its own: other classes may already have
    /// moved, the backup is the way back — and a blank class page is standing
    /// on the day the copy was meant to have, because the planner wrote it
    /// before any of this was known. Leaving that unsaid would let a teacher
    /// read "was not copied" as "nothing happened", twice over.
    static func theCopyCouldNotBeMadeHidden(
        page: String, as copy: String, backupNamed name: String?
    ) -> String {
        var wayBack: String = "The copy of the course made before any of this is "
        if let name {
            wayBack += "\(name), in Plantoir's Backups list."
        } else {
            wayBack += "in Plantoir's Backups list."
        }
        return "“\(page)” was not copied — I could not be certain the copy would start hidden, "
             + "and a lesson students can already see must not turn up somewhere new where they "
             + "can read it. A blank class page called “\(copy)” is waiting on that day instead, "
             + "and it is hidden. Other classes may already have moved. \(wayBack) "
             + "Look the section over in Plantoir."
    }

    // MARK: - Publishing stops at a class

    /// Said when publishing followed a link onto another class and left it
    /// alone.
    ///
    /// A teacher who is not told this reads a plan quietly smaller than the one
    /// they pictured, and has no way to tell "it decided" from "it missed it".
    /// The class is NAMED rather than counted: "1 class was left alone" is a
    /// number about a lesson.
    ///
    /// **Only about a class students cannot already see.** Said about a class
    /// that is already published it is simply false — it would tell a teacher
    /// to publish a page that is already published — and the sentence exists to
    /// explain a link students cannot follow yet. `AssistPublishPlan` decides
    /// which classes reach this.
    ///
    /// Two branches rather than two names, because a caller never has to
    /// choose: the count decides. Both are in the contract, since one rendering
    /// cannot show the other.
    ///
    /// - Parameter listing: the classes, already quoted and joined — "“a” and
    ///   “b”".
    /// - Parameter count: how many classes that listing names.
    static func linkedClassesWereLeftAlone(_ listing: String, count: Int) -> String {
        if count == 1 {
            return "\(listing) is a class of its own, so it stays as it is — publish it when you "
                 + "get to that class."
        }
        return "\(listing) are classes of their own, so they stay as they are — publish each one "
             + "when you get to it."
    }

    // MARK: - What publishing means here

    /// The two acts, in a teacher's words, said once.
    ///
    /// **The one thing a Claude Code session is never told.** The local model
    /// is given this in `AssistAgent.systemPrompt`, whose own comment says the
    /// paragraph "is not padding … saying plainly that they are different is
    /// what stops 'publish tomorrow's class' turning into a live site". The
    /// mac's MCP server sends no `instructions` in its `initialize` result, so
    /// a session driving it had no way to learn the distinction at all.
    static let whatPublishingMeans: String =
        "Publishing a page decides whether students can see it in this section's website. "
        + "Deploying sends the whole website out to the web. They are different acts: a page "
        + "can be published for days and still not be online, and deploying puts everything "
        + "already published in front of students straight away. Plantoir opens the preview "
        + "after a change so the teacher can look it over first, which is the safer order."

    /// Said instead when this section has already been told.
    ///
    /// **Written for the TEACHER, who is who reads it.** The first draft was
    /// addressed to a model — "carry on with what the teacher asked rather than
    /// saying it twice" — and a teacher who typed the phrasing twice read an
    /// instruction to a robot in their own conversation. A tool result is
    /// rendered as an ordinary assistant bubble; there is no channel here that
    /// only a model sees.
    static func publishingAlreadyExplained(course: String, section: String) -> String {
        return "I explained that for \(course) Section \(section) earlier in this conversation."
    }

    // MARK: - Backing a course up

    /// Where the copy went.
    static func backedUpCourse(course: String, to name: String) -> String {
        return "Backed up \(course) to \(name). It is in Plantoir's Backups list, and restoring "
             + "from it puts the whole course back as it is right now."
    }

    // MARK: - Listing what is here

    /// A working folder with nothing in it yet.
    ///
    /// Says what to do next rather than only what is absent: a Claude Code
    /// session that reads "no courses" and stops has left the teacher exactly
    /// where they were.
    static let noCoursesYet: String =
        "This working folder has no courses in it yet. Add one in Plantoir, and it will appear here."

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

    // MARK: - When the answer did not finish

    /// The engine stopped the assistant part way through its answer, so
    /// whatever it had begun to ask for was thrown away unread.
    ///
    /// Three things it has to do, in this order. **Say the answer did not
    /// finish**, because the teacher has just waited for one. **Say that
    /// nothing changed**, which is the fact genuinely in doubt — the same
    /// reasoning as `planWasCancelled`, and the opposite of
    /// `deployWasCancelled`, where the teacher already knew. And **say
    /// something they can act on**: the shape that causes this is a long
    /// list, so "fewer pages at a time" addresses the cause rather than
    /// shrugging politely. The advice is followable because the abandoned
    /// turn is wound out of the conversation as well — a shorter retry sent
    /// with the runaway request still in front of it would meet the same
    /// wall. See `AssistAgent.sayTheAnswerDidNotFinish`.
    ///
    /// **"I haven't changed anything" is true on every path that can reach
    /// this, and it was checked rather than assumed.** A turn only comes back
    /// to the model for another lap when a tool said to
    /// (`AssistToolOutcome.shouldContinue`), and that is true for exactly
    /// three outcomes — `read`, `couldNotRead` and `planned`. Every write
    /// answers `wrote` or `refused`, `read(` is built only by the tools that
    /// read (listing pages, reading a page, explaining publishing, listing
    /// courses, listing curriculum expectations), and a `planned` outcome is
    /// held behind the approval card and never reaches a second lap. So an
    /// answer cut off on a second lap follows a READ, and the sentence stays
    /// true there too.
    ///
    /// Says nothing about why. A teacher cannot act on a limit they cannot
    /// see, and naming it would be exactly the machinery rule 1 keeps out of
    /// the interface.
    static let answerWasCutOff: String =
        "I didn't get to the end of that, so I haven't changed anything. Ask me again — "
        + "a shorter sentence, or fewer pages at a time."

    // MARK: - When the answer was the question again

    /// The assistant's whole reply was the teacher's own sentence, handed
    /// back.
    ///
    /// **Measured, twice over** (issue #215, 2026-09-19). Asked to "hide unit
    /// 4, day 21", the smaller assistant chose no tool and replied with the
    /// sentence it had just been given, date line and all — five phrasings out
    /// of five. Worse: that reply was kept in the conversation, and the model
    /// then copied the pattern it could see. "Unpublish Unit 4, Day 20", a
    /// sentence it gets right every time in a fresh conversation, came
    /// straight back as an echo too. One unrecognised phrase made the window
    /// useless until it was closed and opened again.
    ///
    /// Three things this sentence has to do, and they are the three
    /// `answerWasCutOff` does. **Say it did not follow**, because the teacher
    /// is looking at a reply that said nothing. **Say nothing changed**, which
    /// is the fact genuinely in doubt — and which is true on every path that
    /// can reach here, by the same walk `answerWasCutOff` records: a turn only
    /// comes back for another lap when a tool said to, and no write ever does.
    /// And **say something followable**.
    ///
    /// **Deliberately general, and that is the whole of the second sentence.**
    /// An earlier draft offered three verbs to start with — publish, unpublish
    /// or hide — and named the page. That is wrong advice for most of the
    /// sentences this fires on: the guard catches an echo of ANY request the
    /// model answers with plain words, including a deploy, a request to make
    /// room for a class, and a question about dates, none of which begin with
    /// a verb about publishing or name a page at all. A sentence that will be
    /// believed and is false in a whole class of cases is worse than a vaguer
    /// true one. The working phrasings belong in
    /// `documentation/10-local-ai-assistant.md`, not in a sentence said to
    /// everybody.
    ///
    /// **Never the echoed text.** Handing a teacher their own sentence back is
    /// the fault being fixed; repeating it inside an apology would be the same
    /// fault, politely.
    static let didNotFollowThat: String =
        "I didn't follow that, so I haven't changed anything. Try saying it again in "
        + "different words."

    // MARK: - A request that named another course

    /// The model filled in a COURSE that is not the one this window is for,
    /// and that course is here in the working folder.
    ///
    /// The window is opened for one section of one course, and the section is
    /// simply taken back from whatever the model answered — a fact the app
    /// already knows is not worth asking a model for. The COURSE is not, and
    /// the difference is the whole of this sentence: taking the course back
    /// too means "publish MCV4U's class", typed in an ICS3U window, quietly
    /// succeeding on ICS3U. A failure that reports success is the one failure
    /// a teacher cannot catch, so the request is refused and nothing runs.
    ///
    /// Three things it has to do. **Say which course this window is for**,
    /// because the teacher is looking at one window among several and the
    /// answer is not otherwise in front of them. **Say that nothing was
    /// done** — the fact genuinely in doubt, by the same test
    /// `planWasCancelled` passes and `deployWasCancelled` fails: somebody who
    /// asked for a publish and was refused does not know whether something
    /// happened in the wrong place. "Nothing was DONE" rather than "nothing
    /// was CHANGED", deliberately: the refusal fires on the four reading
    /// tools as well, and "I haven't changed anything" answers a question
    /// nobody asked of "what pages does MCV4U have?". And **say what to do
    /// next**, which is followable here precisely because that course is in
    /// this working folder — see `askedAboutACourseThatIsNotHere` for the
    /// case where it is not, and where this sentence would be a lie.
    ///
    /// Windows refuses the same request today from an inline literal of its
    /// own (`AssistWorkspace.cs`), whose session is locked to one course.
    /// That literal says "Start again from {wanted} in Plantoir", and it is
    /// replaced by this key so the two apps say the same thing about the same
    /// refusal. "Session" and "can't be reached from here" are dropped on the
    /// way across: rule 1, plain words about courses and windows rather than
    /// about how the assistant is wired.
    static func askedAboutAnotherCourse(course: String, otherCourse: String) -> String {
        return "This window is for \(course), so nothing was done for \(otherCourse). "
             + "Open \(otherCourse)'s section in Plantoir and ask me there."
    }

    /// The model filled in a course code that names NO course in this working
    /// folder — a typo, or a code it invented.
    ///
    /// A separate sentence rather than a second use of the one above, because
    /// that one ends by telling the teacher to open the course, and a teacher
    /// cannot open a course that is not there. Advice that cannot be followed
    /// is worse than no advice: it sends somebody looking in the sidebar for
    /// something they will not find.
    ///
    /// **Refused rather than bound to this window**, which is the decision
    /// worth writing down, because binding it is what the old code did and it
    /// looks harmless: a code matching nothing cannot reach another course.
    /// But "publish MCV4U's class" mistyped in an ICS3U window would then
    /// publish an ICS3U class and say it had — the very fault this change
    /// exists to fix, arriving through the one door left open. The measured
    /// cost of refusing instead is negligible: with the real course code
    /// written into the tool descriptions, which is what the app always does,
    /// the model wrote a course that was not this window's **0 times in 686
    /// recorded responses**. Every wrong course value in `research/ai-assist/`
    /// — 19 of them — sits in the one results file whose arms were shown a
    /// PLACEHOLDER code in the schema, and echoed it back.
    static func askedAboutACourseThatIsNotHere(course: String, otherCourse: String) -> String {
        return "There is no course called \(otherCourse) in this working folder, so nothing "
             + "was done. This window is for \(course)."
    }

    // MARK: - A course kept for reference

    /// A deploy was asked for on a course that is kept for reference.
    ///
    /// **The same string the shared Python says**, pinned against
    /// `contracts/shared-rules.json` → `referenceCourses.refusal.sentence` by
    /// a test on each side — because the launchers and `deploy.py` have to say
    /// it too, and `scripts/contracts.py` can read that file and not
    /// `assist-wording.json`. A teacher who is refused at the button and again
    /// at the Terminal must not read two different explanations of one rule.
    ///
    /// `course` is the code a TEACHER reads — `ICS3U`, never the folder name.
    ///
    /// **It does not tell them to copy anything**, and that was decided
    /// rather than overlooked. It stayed decided when Plantoir gained "Copy a
    /// Page from This Course…" (issue #207, same release): this is a refusal
    /// about DEPLOYING, the way out it names is the course they are actually
    /// teaching, and a refusal that advertises an unrelated feature is one a
    /// teacher has to read twice. The menu item is on the course's own row,
    /// where they will meet it.
    static func deployRefusedForAReferenceCourse(course: String) -> String {
        return "\(course) is kept for reference, so it is never deployed. "
             + "Deploy the course you are teaching instead."
    }

    /// The model named a course that is kept for reference.
    ///
    /// A third sentence rather than a second use of `askedAboutAnotherCourse`,
    /// which ends "Open that course's section in Plantoir and ask me there."
    /// — advice that cannot be followed here, because the assistant is not
    /// offered on a reference course at all.
    static func askedAboutAReferenceCourse(course: String, otherCourse: String) -> String {
        return "\(otherCourse) is kept for reference, so I can't work in it. "
             + "This window is for \(course)."
    }

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
