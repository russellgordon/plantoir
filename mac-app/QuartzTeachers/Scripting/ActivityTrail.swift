import Foundation

/// The breadcrumb trail: what the teacher was doing, in the order they did it.
///
/// A report made of task records alone answers "what did that publish print?"
/// It does not answer the question support actually starts from — **what were
/// you doing when it went wrong?** — and without that, a record is a page of
/// output with no story round it. A teacher who says "it stopped working after
/// I renamed something" is describing a sequence, and this is where the
/// sequence lives.
///
/// Deliberately coarse. Every line here is a thing the teacher would recognise
/// as something they did, not an internal state change: opening a folder, yes;
/// a view redrawing, no. A trail nobody can read is the same as no trail, and
/// the failure mode of logging-everything is that the one line that mattered
/// is on page forty.
nonisolated enum ActivityTrail {

    // MARK: - Types

    /// Everything the trail is required to record.
    ///
    /// Naming an event is what makes the requirement bite. A feature cannot
    /// be added without its author choosing the line it leaves — either an
    /// event that already fits, or a new case here, which the contract then
    /// makes the OTHER platform account for too. Free-text calls would let a
    /// feature ship silently, which is the whole failure this list exists to
    /// stop.
    ///
    /// The raw value is a stable key for the contract, NOT the words written
    /// to the file: the line a teacher reads is a sentence, and sentences get
    /// reworded. Pinning the key instead means rewording is free and dropping
    /// an event is not.
    enum Event: String, CaseIterable, Sendable {
        case appOpened = "app opened"
        case machine = "machine described"
        case helpers = "helpers described"
        case workingFolderOpened = "working folder opened"
        case settingsSaved = "settings saved"
        case settingsCouldNotBeSaved = "settings could not be saved"
        case taskStarted = "task started"
        case taskFinished = "task finished"
        case askedForACredential = "asked for a publishing credential"
        case assistantOpened = "assistant opened"
        case assistantReady = "assistant ready"
        case assistantWouldNotStart = "assistant would not start"
        case assistantEngineSaid = "assistant engine said"
        /// A teacher put a section back to how it was when an assistant
        /// conversation started ("Restore Section N…"). Carries the course,
        /// the section and the backup's FILE NAME — never a page.
        ///
        /// It is the one line that explains a section whose pages are older
        /// than the conversation that changed them. Without it the trail shows
        /// the assistant's changes and then nothing, which reads as a teacher
        /// who never pressed the button — and "why are my pages back to how
        /// they were on Tuesday?" is exactly the question that arrives a week
        /// later, with the conversation long closed.
        ///
        /// Windows recorded this first (`AssistWindow.xaml.cs`); the mac had
        /// the same button and wrote nothing.
        case sectionRestored = "section restored"
        case assistantAsked = "assistant asked"
        case assistantChoseATool = "assistant chose a tool"
        case assistantCouldNotAnswer = "assistant could not answer"
        /// The engine stopped the assistant part way through an answer, so
        /// Plantoir threw the answer away rather than acting on a fragment.
        ///
        /// Exactly the line a problem report needs and could not have. From a
        /// teacher's side this is a long wait followed by the assistant
        /// declining, which is indistinguishable from a misroute — so a
        /// report of "it thought for ages and then said no" had nothing to
        /// look at. Carries the tool the model had BEGUN to name, because "it
        /// ran away trying to publish" and "it ran away trying to deploy" are
        /// different reports; never what it had begun to write, which is the
        /// teacher's own page titles.
        ///
        /// Not folded into `assistantCouldNotAnswer`, which is for an engine
        /// that FAILED: here the engine answered perfectly and the app
        /// refused the answer, and a line saying it could not answer would
        /// send whoever reads it looking for a crash that did not happen.
        case assistantAnswerWasCutOff = "assistant answer was cut off"
        /// The assistant's whole reply was the teacher's own sentence handed
        /// back, so the turn was refused and taken out of the conversation.
        ///
        /// Measured on 2026-09-19 (issue #215): "hide unit 4, day 21" came
        /// back word for word, date line and all, and then POISONED the rest
        /// of the conversation — the echo stayed in the history and the model
        /// copied the pattern, so the next sentence, one it gets right every
        /// time in a fresh window, echoed too.
        ///
        /// Carries this window's course and section, that nothing was run, and
        /// that the turn was wound back. Never the sentence: `assistant asked`
        /// already has it, on its own marked line, and repeating the echoed
        /// text here would put a teacher's page titles on a second line that
        /// is not marked.
        ///
        /// Not folded into `assistant answer was cut off`. Those two sentences
        /// share a genuine kind — an answer the app refused because it was
        /// unfinished — and this answer was finished; the event's NAME says
        /// "cut off", which would be false, and a line describing something
        /// other than what happened is worse than no line because it will be
        /// believed. Not `assistant could not answer` either: that is for an
        /// engine that FAILED, and here the engine answered perfectly badly.
        case assistantRepeatedTheRequestBack = "assistant repeated the request back"
        /// The model filled in a COURSE that is not the one the window is
        /// for, so the turn was refused and nothing ran.
        ///
        /// Carries this window's course and section, the course the model
        /// named, and the tool it had chosen — never the teacher's sentence
        /// and never the argument VALUES, which are their page titles.
        ///
        /// Both course codes, because the pair IS the evidence. A teacher's
        /// side of this is the assistant declining something they thought
        /// they had asked for plainly, which is indistinguishable from a
        /// misroute, and the pair is the only thing that tells the two apart:
        /// the guard doing its job, or a model slip being refused at the
        /// teacher's expense. The tool name is carried for the same reason
        /// `assistantAnswerWasCutOff` carries one — "it would not publish"
        /// and "it would not read a page" are different reports.
        ///
        /// Not folded into `assistantChoseATool`, which records argument
        /// NAMES and never values, so it cannot say WHICH course was named;
        /// nor into the cut-off line, where the answer was never finished. The
        /// answer here was perfect and the app refused it.
        case assistantWasAskedAboutAnotherCourse = "assistant was asked about another course"
        case assistantMatchedAFixedPhrase = "assistant matched a fixed phrase"
        case settingsPanelOpened = "app settings opened"
        case assistantModelChosen = "assistant model chosen"
        case assistantModelDownloadStarted = "assistant model download started"
        case assistantModelDownloaded = "assistant model downloaded"
        case assistantModelDownloadFailed = "assistant model download failed"
        case assistantModelDownloadStopped = "assistant model download stopped"
        case assistantModelRemoved = "assistant model removed"
        case assistantConfirmationChanged = "assistant confirmation changed"
        /// Why a section stopped saying " — Edited". Without it, a
        /// teacher reporting "it still says Edited after I published"
        /// leaves nothing to look at: the marker is derived, so its
        /// absence and its presence look identical on disk.
        case sectionContentMarkedPublished = "section content marked published"
        /// A rollover started a NEW website for a section: it is no longer
        /// tied to the one it published to last year, and the next publish
        /// will ask what to call the new one. Carries the course, the section
        /// and where last year's details were kept.
        case sectionStartedANewWebsiteOnRollover = "section started a new website"
        /// A rollover kept LAST YEAR'S website, so the next publish replaces
        /// what is already there.
        ///
        /// **Both answers are recorded, and this is the one that matters more
        /// for a report.** A teacher who writes in weeks later saying their old
        /// class site was overwritten is describing THIS branch, so a trail
        /// that recorded only the release could not answer the question anyone
        /// actually reads it for.
        case sectionKeptItsWebsiteOnRollover = "section kept its website"
        /// A folder a feature depends on was missing, renamed or emptied.
        /// Carries the check's NAME, never its wording: the sentence is
        /// product wording and will be reworded, while the name is what
        /// somebody reading the trail months later can match against the
        /// contract. The finding itself is printed into a build console that
        /// is long gone by the time it is reported, and the condition is
        /// invisible on disk — a renamed folder looks exactly like a folder
        /// that was always called that.
        case folderProblemFound = "folder problem found"
        /// A folder a feature depends on was put back, at the teacher's
        /// request. Separate from `folderProblemFound` because it is a
        /// different event: one records that something is wrong, the other that
        /// somebody acted on it — and a trail that could not tell them apart
        /// would leave "did they ever fix it?" unanswerable.
        case folderProblemRepaired = "folder problem repaired"
        /// A repair the teacher ASKED for did not happen. Carries the course,
        /// the section, and what was in the way — never anything from inside
        /// it. Recorded because the trail otherwise shows the problem being
        /// found and then nothing at all, which reads exactly like a teacher
        /// who never pressed the button; and the thing in the way is a folder
        /// they will very likely have moved by the time they report it, so it
        /// cannot be looked for afterwards.
        ///
        /// Named for the OUTCOME rather than for the one cause that writes it
        /// today: only the "a folder is sitting where the front page belongs"
        /// refusal records this, and a repair that simply failed — a read-only
        /// volume, a permissions problem — still records nothing. That gap is
        /// deliberate rather than forgotten, and this event is the line it
        /// joins when it is closed, without a rename on either platform.
        case folderProblemNotRepaired = "folder problem not repaired"

        /// A teacher asked for a class to be duplicated, the room for it was
        /// made, and then no copy appeared.
        ///
        /// **The one refusal here that fires after a change has begun.** The
        /// place for the copy is decided by the planner, which renames and
        /// re-dates every later class BEFORE anything is copied — so a lesson
        /// still sitting where the copy would go is discovered with the
        /// shuffle already done. The teacher sees their classes move and no
        /// new page, and "I duplicated a class, my classes moved, and nothing
        /// was copied" is a report nothing else in this trail could answer:
        /// the tool that ran is recorded, and its conclusion is not.
        ///
        /// The other refusals on that path deliberately record nothing,
        /// because they answer before anything is touched — a page that is not
        /// there, a page with no numbers in its name, a timetable that has run
        /// out. Nothing happened, so there is nothing to explain afterwards.
        ///
        /// Carries the course and the section, and NOT the pages' titles. The
        /// assistant's own `assistantChoseATool` leaves argument values out
        /// for the same reason, and the line answers the report without them.
        ///
        /// Named for the OUTCOME rather than for today's single cause, the way
        /// `folderProblemNotRepaired` is: a second reason a copy is not made
        /// joins this line rather than earning a rename on both platforms.
        case classCopyNotMade = "class copy not made"

        /// A publish set to happen on its own stopped because it needed an
        /// answer.
        ///
        /// The one thing that can happen to a scheduled publish that a teacher
        /// would otherwise never find out about: it runs at half six with the
        /// app closed, so a question it could not ask is asked of nobody and
        /// seen by nobody. Before `--non-interactive` it either waited for
        /// ever — measured at 45 minutes — or took a default and published the
        /// site to an address nobody chose. Without this line the run is
        /// indistinguishable from one that was never scheduled, which is
        /// exactly the shape of "my site did not update on Tuesday and I do
        /// not know why".
        ///
        /// Carries the course, the section and which DESTINATION stopped: a
        /// course can publish to several and only one may have needed
        /// anything, so "it published to the folder and not to Netlify" is the
        /// report a teacher makes. When the BUILD is what stopped there is no
        /// destination to carry, because none was reached, and the line says
        /// that instead — `ScheduledPublishOutcome.Kind.buildNeededAnAnswer`
        /// files here rather than under an event of its own, since a question
        /// going unasked is what happened either way. Dated to when the RUN
        /// wrote its record,
        /// never to when the app read it, or an overnight problem is filed
        /// under the wrong night.
        ///
        /// NEVER the question's own text. That comes from a launcher's
        /// console, and a line naming a credential prompt would put a
        /// teacher's own words on the trail.
        case scheduledPublishNeededAnAnswer = "scheduled publish needed an answer"

        /// A publish set to happen on its own did not finish, for a reason
        /// that was not a question — a revoked token, a network that was
        /// down, a build that failed.
        ///
        /// Separate from `scheduledPublishNeededAnAnswer` because that event's
        /// own wording says a question went unasked, and filing a revoked
        /// token under it would make the trail say something untrue about the
        /// one run a teacher is trying to understand. Both are the same
        /// silence from the teacher's side; only one of them is a question.
        case scheduledPublishDidNotFinish = "scheduled publish did not finish"

        /// A publish set to happen on its own went out.
        ///
        /// The positive case, and it is on the trail for the same reason the
        /// failures are: a scheduled publish that leaves no trace cannot be
        /// told from one that never happened. Without this line the trail can
        /// answer "why did my site not update?" and cannot answer "did it?".
        case scheduledPublishFinished = "scheduled publish finished"

        /// A deploy the teacher had set to happen on its own was turned off by
        /// something OTHER than them asking for it.
        ///
        /// Three things turn one off without being asked: removing the course,
        /// removing the section, and the day it was set for going by — and the
        /// line says WHICH, in the teacher's own terms, carrying the course and
        /// the section. One event with three reasons rather than three events:
        /// somebody reading the trail wants to know their overnight deploy was
        /// turned off and by what, and the difference between two ways of
        /// removing something means nothing to them.
        ///
        /// Without it, a teacher whose site stopped updating has no line
        /// anywhere explaining why — the alarm simply is not there any more,
        /// which reads exactly like one that was never set. That is the same
        /// silence `scheduled publish needed an answer` was built for, one step
        /// further back.
        ///
        /// Says DEPLOY where its three neighbours say publish. A site is
        /// deployed and a page is published (Russell, 2026-09-20), and the
        /// shipped names are left alone rather than renamed here — a new name
        /// carrying the old vocabulary is the expensive mistake, because the
        /// contract pins it on both platforms.
        case scheduledDeployTurnedOff = "scheduled deploy turned off"
        /// A folder or file was removed in Course Settings, excluding it
        /// from previews and deploys.
        case itemExcluded = "item excluded"
        /// A previously excluded folder or file was added back in Course
        /// Settings, returning it to previews and deploys.
        case itemReincluded = "item re-included"
        /// A teacher tried to remove or untick a folder or file that a
        /// feature depends on, and was shown why it cannot go and which
        /// switch to turn off first. Recorded because "I could not remove
        /// the folder" is a report support will receive, and the line says
        /// which rule refused and what the teacher was told.
        case removalBlocked = "removal blocked"
        /// A folder was renamed from inside Plantoir — on disk, in every
        /// section that had one, with the config keys that named it carried
        /// across. Recorded because a rename is invisible afterwards: a folder
        /// called "Class Pages" looks exactly like one that was always called
        /// that, and the question a report will ask months later — "when did
        /// this course stop having a Tasks folder?" — has no other answer.
        case folderRenamed = "folder renamed"
        /// A folder was created on disk because a teacher added its name in
        /// Course Settings. Separate from the rename because it answers a
        /// different question: a folder appearing in a teacher's vault that
        /// they did not make in Obsidian is otherwise unexplained.
        case folderCreated = "folder created"
        /// A course's word for a unit was renamed from inside Plantoir —
        /// every class page in every section, its title, and the links that
        /// pointed at it. Recorded because afterwards a course that says
        /// "Module 2, Day 3" looks exactly like one that always did, and
        /// "when did these pages stop being Units?" — the first question when
        /// the next-class button or the curriculum map starts counting the
        /// wrong pages — has no other answer. Carries the course code, the
        /// old and new words, how many pages and links changed, and the
        /// backup's file name. Never anything from inside a page.
        case unitWordRenamed = "word for a unit renamed"
        /// The working folder just opened is kept in sync by a cloud service
        /// (iCloud Drive, Dropbox, OneDrive, Google Drive…), and the teacher
        /// had not yet been told about this folder. Carries the service's
        /// name and the folder, redacted. Recorded because the effects of a
        /// synced folder — a slow build, a rename that takes minutes, a move
        /// that failed once — arrive weeks later as unrelated reports, and
        /// this one line is what connects them.
        case syncedFolderNoticed = "synced folder noticed"
        /// The teacher read the note about a synced folder and went ahead —
        /// pressed "Use This Folder Anyway" in the picker, or dismissed the
        /// notice in the window. Carries which of the two it was and the
        /// service's name. Separate from `syncedFolderNoticed` because it is
        /// a different fact: one says Plantoir saw it, the other says the
        /// teacher did, and a report of "nobody warned me" is answered by
        /// the second.
        case syncedFolderAccepted = "synced folder accepted"
        /// A course's built website was moved out of the working folder, to
        /// where built sites now live. Carries the course code. Recorded
        /// because it is a one-off change a teacher can SEE: a folder they
        /// may have looked at in Finder is an alias afterwards, their working
        /// folder suddenly weighs much less, and a folder they sync stops
        /// uploading builds. Each of those arrives as a separate report
        /// ("where has my site gone?", "did something delete my files?"), and
        /// this line — dated, per course — is what answers all three at once.
        case builtSiteMovedOutOfTheFolder = "built site moved out of the working folder"
        /// A section's leftover website-builder processes were reclaimed —
        /// after a preview was stopped, a window closed, or a publish was
        /// cancelled. Carries the course, the section, and HOW MANY were
        /// ended. The count is the whole value: nothing else in the trail
        /// distinguishes "the preview had already finished" (nothing to
        /// stop) from "a build was still running and was ended", and those
        /// are the two competing explanations for a teacher reporting that
        /// their publish stopped halfway through. Added when this sweep
        /// began ending a mid-flight BUILD and its driver rather than only a
        /// server — a real change in what a teacher can lose, which had no
        /// line describing it.
        case sectionProcessesReclaimed = "section processes reclaimed"
        /// A preview said its website was up and then never appeared, and
        /// Plantoir stopped waiting for it. Carries the course, the section,
        /// how long it had been saying nothing, and WHICH of the three things
        /// was true: the website builder was serving the site and this Mac
        /// could not reach it, nothing was serving it at all, or the builder
        /// could not be asked and Plantoir does not know.
        ///
        /// This is the line whose absence produced the report it exists for
        /// (issue #225). A teacher built three previews in four minutes, none
        /// appeared, and the trail said only that a task had started and been
        /// stopped on purpose — so the record of the evening read as somebody
        /// changing their mind three times. Which of the two it was is the
        /// whole value of the line: one of them is their pages and one of
        /// them is their Mac, and they are one sentence apart when a teacher
        /// describes it.
        case previewNeverAppeared = "preview did not appear"
        /// The memory came back: a working folder's website builder was
        /// stopped, or — when nothing else on the Mac was using it — the
        /// shared setup underneath them all was stopped too.
        ///
        /// On the trail because until 2026-09-19 it never happened. The app
        /// asked for it at every quit and the request went to programs it had
        /// not told itself where to find, with the answer sent to the null
        /// device, so a teacher whose Mac stayed slow all day had nothing to
        /// show anyone (issue #220). A line saying it happened is what turns
        /// "quitting does not seem to free anything" from a feeling into a
        /// report. Carries the working folder's NAME — never its path, and
        /// never anything from inside it.
        ///
        /// **Two occasions file here, and the name says neither**, on
        /// purpose: quitting, and the last window on a folder closing. They
        /// are the same act on the same container under the same conditions,
        /// and the sentence written says which one it was. An event called
        /// "…at quit" would have been a lie on every window close, which is
        /// the commoner of the two.
        case websiteBuilderStopped = "website builder stopped"
        /// Something was deliberately left running, and why.
        ///
        /// The companion to the line above, and the one support will read
        /// more often, because "quitting did not free anything" is the report
        /// and this is the only thing that can answer it. Two different
        /// reasons file here: a publish or preview for that folder was still
        /// going, so stopping it would have broken work the teacher could not
        /// see; or other software on the Mac shares the same setup, which
        /// rule 7 says is never stopped out from under anybody. Both are
        /// deliberate, and without the line they look identical to the fault
        /// they replaced.
        case websiteBuilderLeftRunning = "website builder left running"
        /// Plantoir could not stop a website builder, and says so rather than
        /// saying nothing.
        ///
        /// Issue #220 was a fault that REPORTED NOTHING: the quit script could
        /// not find the programs it needed, exited 0, and left a teacher with
        /// no evidence at all. This is the line that makes the same failure
        /// visible the next time. Four ways file here: the programs cannot be
        /// found; the shared setup cannot be asked what is running in it; the
        /// stop was asked for and REFUSED; and the whole attempt ran out of
        /// time. That last pair matter most, because each of them would
        /// otherwise be written down as a success — `docker stop` failing and
        /// `docker stop` working are indistinguishable to a script that does
        /// not look.
        ///
        /// Separate from `websiteBuilderLeftRunning` because that one says a
        /// deliberate choice was made, and a choice nobody was able to make is
        /// a different fact.
        case websiteBuilderCouldNotBeStopped = "website builder could not be stopped"
        /// ⌘Q landed while this app was publishing, the teacher was asked
        /// whether to quit anyway, and this is what they chose.
        ///
        /// BOTH answers are recorded, and the "keep working" one matters most:
        /// a teacher who says "I pressed Quit and it would not quit" is
        /// describing that branch, and nothing else would explain it. The
        /// other branch explains a publish that stopped part way through with
        /// no error anywhere — the teacher was told and went ahead, which is a
        /// completely different report from a publish that died on its own.
        /// Carries what was under way, in the words the teacher was shown.
        case quitAskedAboutWorkUnderWay = "quit asked about work under way"

        /// A course was kept for reference: which folder it was given, the
        /// code and school year it shows, how many sections came across, and
        /// which course it was copied from. Never the contents of a page.
        case courseKeptForReference = "course kept for reference"

        /// A reference course's pages were locked again, with the count —
        /// because a backup came back unlocked, or a folder that syncs
        /// cleared the locks while it uploaded, or the folder had been opened
        /// on a Mac that had never heard of reference courses. Written only
        /// when a pass actually did something, so a folder in a steady state
        /// leaves no lines at all.
        case referenceCoursePagesLockedAgain = "reference course pages locked again"

        /// A course was brought in from another folder and kept for
        /// reference: which folder it was read from, the folder it was given
        /// here, the code and school year it shows, and how many sections
        /// came across. The folder it was READ from is the half a copy does
        /// not have, and it is the answer to "where did this ICS4U come
        /// from". Never the contents of a page.
        case courseImportedForReference = "course imported for reference"

        /// One course of an import did not come across, and the rest did.
        /// Carries which course and why — a course code already kept for
        /// reference under that school year, a folder that could not be read,
        /// a disk that filled. Written per COURSE, because "the import
        /// failed" is exactly the report that cannot be looked into: a run of
        /// four courses that imports three is the ordinary shape of this.
        case courseCouldNotBeImportedForReference = "course could not be imported for reference"

        /// The teacher stopped an import part way. Carries the course that
        /// was in hand, which was not kept, and the folder it was coming
        /// from. Its own event rather than a failure: a teacher who stops
        /// something chose to, and a line calling that a failure is a line
        /// that misleads whoever reads it back.
        case courseImportForReferenceStopped = "course import for reference stopped"

        /// A working folder was opened and an unfinished import was found in
        /// it and tidied away. Carries which course it was going to be.
        ///
        /// A reference course is built under a hidden name and renamed into
        /// place last, so a quit or a crash part way leaves a hidden folder
        /// nothing can see — and therefore nothing would ever remove. This
        /// is the one line that says the disk space came back, and it is
        /// also how "my import did not finish and now there is no trace of
        /// it" gets an answer.
        case unfinishedImportForReferenceTidiedAway = "unfinished import for reference tidied away"
    }

    // MARK: - Stored properties

    /// Where lines go. Replaceable so a test can point it somewhere of its own.
    nonisolated(unsafe) static var store: ProblemReportStore = ProblemReportStore.standard

    // MARK: - Functions

    /// Notes one thing that happened.
    ///
    /// `what` is written for somebody reading the trail months later, so it
    /// says what happened in words rather than naming a function: "started
    /// building the preview", not "runScript(preview.sh)".
    /// `wholeLine` is for an entry that already carries its own timestamp and
    /// shape — the assistant's turn record — so it is not stamped twice.
    static func note(
        _ event: Event,
        _ what: String,
        at moment: Date = Date(),
        wholeLine: Bool = false
    ) {
        if wholeLine {
            store.appendActivityLine(what)
            return
        }
        store.appendActivityLine(line(what, at: moment))
    }

    /// The event keys this app actually emits, for the contract to pin.
    static var eventKeys: [String] {
        var keys: [String] = []
        for event in Event.allCases {
            keys.append(event.rawValue)
        }
        return keys
    }

    /// One line, without writing it — the part a test can check.
    static func line(_ what: String, at moment: Date, timeZone: TimeZone = TimeZone.current) -> String {
        return ActivityTrail.formatter(timeZone: timeZone).string(from: moment) + " · " + what
    }

    /// Notes something about one section, so the trail says which course and
    /// section a line belongs to without every caller remembering to.
    static func note(_ event: Event, _ what: String, course: String, section: Int, at moment: Date = Date()) {
        ActivityTrail.note(event, "\(course)/\(section) · " + what, at: moment)
    }

    static func formatter(timeZone: TimeZone = TimeZone.current) -> DateFormatter {
        let formatter: DateFormatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = timeZone
        formatter.dateFormat = "yyyy-MM-dd HH:mm:ss"
        return formatter
    }

    /// The line that opens a session, so a trail spanning several launches
    /// says where each one began — and says which BUILD it was, which is the
    /// first thing to check when a report and the code disagree.
    static func noteLaunch() {
        ActivityTrail.note(.appOpened, "Plantoir opened — " + ProblemReportEnvironment.appDescription)
        ActivityTrail.note(.machine, "running on " + ProblemReportEnvironment.systemDescription)
        ActivityTrail.note(.helpers, "using " + ProblemReportEnvironment.helperDescription)
    }
}
