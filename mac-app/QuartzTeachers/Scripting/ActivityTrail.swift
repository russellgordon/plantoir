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
        /// Plantoir reopened a working folder by itself at launch — the last
        /// working folder, or a window's own (#311). Carries the redacted
        /// path, which of the two it was, and the old path when the folder
        /// was found where it had been moved. Distinct from "opened" so the
        /// trail can tell the teacher's choice from the app's.
        case workingFolderReopened = "working folder reopened"
        /// A remembered working folder could not be reopened (#311): carries
        /// the reason (gone, inTrash, driveNotConnected, unreadable,
        /// privacyDenied, outsideHome, coursesOutsideHome) and the redacted path — the two
        /// facts that cannot be looked for afterwards, once the drive is
        /// plugged back in or the Trash emptied.
        case workingFolderNotReopened = "working folder not reopened"
        /// A folder chosen in the picker was refused because the website
        /// builder cannot reach it (#290): carries the redacted path and
        /// whether it was the folder or its courses that lead outside the
        /// home folder. A refused folder leaves nothing else behind.
        case workingFolderRefused = "working folder refused"
        case settingsSaved = "settings saved"
        case settingsCouldNotBeSaved = "settings could not be saved"
        /// Course Settings held changes that could not be saved because they
        /// moved where the course publishes and that destination has a
        /// problem (#373). Written once per visit, on the change into that
        /// state; carries the course and WHICH check (deploy folder,
        /// cloudflare account id, additional destination) — never the path
        /// or the ID.
        case settingsSaveHeldBack = "settings save held back"
        /// A preview started while Course Settings held changes nobody had
        /// saved, and the teacher was told it uses the saved settings (#265).
        case previewStartedWithUnsavedSettings = "preview started with unsaved settings"
        /// A deploy, or setting one, went ahead from the SAVED settings while
        /// Course Settings held changes nobody had saved (#335): carries which
        /// act, and whether the unsaved destination differed from the saved
        /// one — by kind only, never a path or a site name.
        case deployUsedTheSavedSettings = "deploy used the saved settings"
        /// Preview Again, pressed beside the sentence Course Settings shows
        /// after a Save that an open preview could not see (#265).
        case previewAgainAfterSettingsSaved = "preview again after settings saved"
        case taskStarted = "task started"
        case taskFinished = "task finished"
        case askedForACredential = "asked for a publishing credential"
        case assistantOpened = "assistant opened"
        /// A Claude or Codex session opened from Plantoir's door is holding the course
        /// it was opened from (#458): written by `Plantoir --mcp-stdio` when
        /// it takes its `assist` lease. Carries the course only. It answers
        /// "why is Rename greyed?" — `assistant opened` says a door was
        /// opened, never which course its server went on to hold.
        case outsideSessionHeldACourse = "outside session held a course"
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
        /// A teacher added a section to a course ("Add Section…"). Carries
        /// the course, the new section, and how many pages shared by every
        /// section were given a date and a published-or-hidden setting for
        /// it, and how many of those were kept hidden because the setting
        /// they would copy could not be read — never which pages.
        ///
        /// Adding a section writes into pages the teacher did not open: every
        /// course-level page that carries per-section keys gains a pair for
        /// the new section, copied from the lowest existing one. When that
        /// went wrong it went wrong silently — a page hidden in section 1 but
        /// fenced in a way the old finder missed was PUBLISHED in the new
        /// section (GitHub #175) — and the trail had nothing at all about the
        /// section being added, so "why is this page showing in section 2?"
        /// had no line to start from.
        case sectionAdded = "section added"
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
        ///
        /// Three causes, and the line names which: stopped part way by the
        /// engine, finished with arguments that could not be read, or — since
        /// issue #198 — finished having written NOTHING for a tool that needs
        /// more than the window supplies ("wrote nothing for …").
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
        /// The model named a tool that exists but was not among those it was
        /// OFFERED in this window, so the turn was refused and nothing ran
        /// (#327).
        ///
        /// Carries the tool, in words — the one fact about this that is not
        /// already on the turn's own line, which records what the model
        /// chose without saying it was never on the menu. Never the sentence
        /// and never the arguments. Its own event rather than `assistant
        /// repeated the request back`, whose name would be false here: the
        /// teacher reads the same sentence for both, and only this line
        /// tells the router reaching past its list apart from an echo.
        case assistantNamedAToolItWasNotOffered = "assistant named a tool it was not offered"
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
        /// A folder a feature depends on was missing, renamed or emptied — or,
        /// since #246, a PAGE whose settings the build could not read and so
        /// hid (`pageSettingsUnreadable`). The name is kept because the event
        /// is the site-health family; the line still names the check, never
        /// the pages, which are the teacher's own names.
        /// Carries the check's NAME, never its wording: the sentence is
        /// product wording and will be reworded, while the name is what
        /// somebody reading the trail months later can match against the
        /// contract. The finding itself is printed into a build console that
        /// is long gone by the time it is reported, and the condition is
        /// invisible on disk — a renamed folder looks exactly like a folder
        /// that was always called that.
        ///
        /// Two writers, one sentence (`SiteHealthFinding.trailSentence`): a
        /// build the app runs, as its output arrives; and a SCHEDULED publish,
        /// from its own log at the end of the run
        /// (`ScheduledDeploy.recordFolderProblems`, #153) — dated to the run,
        /// not to whenever somebody next opens the section.
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

        /// A preview or a publish rewrote some of the teacher's own pages
        /// with the date of their class: the front page takes the date of the
        /// class it shows, and a page a class brings takes the date of the
        /// earliest visible class that brings it (#275, #276). Carries the
        /// course, the section, how many, and their NAMES — never anything
        /// written on them. Read from the build's `PLANTOIR_DATED:` line
        /// (`PagesDatedByTheBuild`), which is printed only when something was
        /// rewritten, so a build whose dates were already right adds nothing.
        /// Recorded because this is a change to the teacher's files nobody
        /// asked for in so many words, and "why did this page's date change?"
        /// is asked long after the console that said so has gone.
        case pagesDatedByTheBuild = "pages dated by the build"

        /// The curriculum coverage maps a build wrote (#128): one per
        /// curriculum folder the course declares, each with its title, the
        /// folder it came from and how many expectations it shows — or that it
        /// wrote none. Read from the build's `PLANTOIR_MAPS:` line
        /// (`CoverageMapsBuilt`), printed on every build whose section wants
        /// the map, so "my second map is missing" has an answer. Course
        /// structure only, never anything written on a page.
        case coverageMapsBuilt = "curriculum maps built"

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

        /// A teacher copied one or more pages out of one course and into
        /// another ("Copy a Page from This Course…").
        ///
        /// Carries the course the pages came FROM by its folder name — the
        /// thing that tells last year's ICS4U from this year's — the course
        /// and folder they landed in, how many pages and pictures were
        /// created, reused, brought in under a new name and left alone, and
        /// the backup's file name. NEVER a page's title and never anything
        /// from inside one: `classCopyNotMade`'s own doc comment draws that
        /// line for the same kind of act, and `sectionRestored` already
        /// carries a backup's file name for the same reason this one does.
        ///
        /// One event for every outcome, written once at the END of a copy
        /// rather than one per page. A copy that stopped part way through
        /// says so in the same line, because the counts already show it — and
        /// every extra event is an entry the Windows app has to account for.
        ///
        /// Without it, a page appearing in a course a teacher did not write
        /// it in has no explanation anywhere: on disk a copied page looks
        /// exactly like one they typed, and "where did this come from?" is a
        /// question nothing else in this trail could answer. The refusals
        /// record nothing — they answer before anything is touched.
        case pagesCopiedFromAnotherCourse = "pages copied from another course"

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
        ///
        /// A BUILD that failed outright files here too
        /// (`ScheduledPublishOutcome.Kind.buildDidNotFinish`, #137), with a
        /// line that says the pages could not be built and names no
        /// destination, because none was reached — the way
        /// `buildNeededAnAnswer` files under the event above.
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
        /// the section. A fourth since a course could be kept for reference,
        /// and a fifth since issue #195: a new deploy set in its place that
        /// macOS then refused — the old one is booted out and its plist
        /// overwritten first, so the refusal leaves neither, and the line
        /// carries when the lost one was set for. One event with several
        /// reasons rather than one event each: somebody reading the trail
        /// wants to know their overnight deploy was
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
        /// A scheduled deploy was set for a section that already had one, and
        /// the old one was replaced (issue #195). Carries the section, the
        /// moment the old one was set for, and the moment the new one is set
        /// for.
        ///
        /// Scheduling a section again removes the deploy already set for it —
        /// on purpose, one per section per working folder (per Mac until #237)
        /// — and the old job leaves nothing
        /// behind once it is gone, so "it went on Saturday, I set it for
        /// Friday" had no answer anywhere. The card now says so beforehand;
        /// this is what says so afterwards. Written in
        /// `ScheduledDeploy.scheduleDeploy`, the one function the sheet, the
        /// assistant and an outside assistant all reach. Not written when the
        /// old job was set for the same minute (nothing a teacher would notice
        /// changed) or had already gone by (it was not a promise any more).
        case scheduledDeployReplaced = "scheduled deploy replaced"
        /// A scheduled deploy was asked for and could not be set: its files
        /// could not be written, or macOS would not accept it. Carries the
        /// section, the moment asked for, and — when the section already had
        /// one — whether that one still stands (issue #195's fix review).
        ///
        /// "I set it for Friday and it never went" is otherwise answered only
        /// by the refusal on screen at the time, which nobody quotes a week
        /// later. And the two failures leave DIFFERENT things behind: a failed
        /// write leaves the old deploy's plist on disk, so it is handed back to
        /// macOS and the line says it still stands; a refusal from macOS after
        /// the new plist was written has overwritten it, so the old one is
        /// gone and `scheduled deploy turned off` says so beside this line.
        /// Saying "turned off" for the first would be false — the old job
        /// would still fire — which is why they are told apart.
        ///
        /// Since GitHub #322 also written when the deploy was REFUSED before
        /// anything was written — at the schedule sheet's button, or by
        /// `schedule_deploy` from either assistant — carrying the destination
        /// it was refused for (by kind: Netlify, Cloudflare Pages or a
        /// folder) and the refusal's first sentence. #322 took a code read to
        /// diagnose; with this line the trail would have shown "never deployed
        /// to Netlify" just under a Save that made the course a folder. Not
        /// written by the approval card or `plan_scheduled_deploy`, which are
        /// advisory and repeat.
        case scheduledDeployCouldNotBeSet = "scheduled deploy could not be set"
        /// A scheduled publish read the course's settings when it fired and
        /// something differed from what the teacher was told (GitHub #323):
        /// it went ahead to where the course deploys NOW, somewhere other than
        /// it was set to go; or it could not deploy the way the course is set
        /// now and stood down, with the reason. Carries where it was set to
        /// deploy (when that was recorded), where the course deploys now, and
        /// the reason for a stand-down — never a credential.
        ///
        /// Written only when something differs, never on every run:
        /// `scheduled publish finished` already names where a run went. What
        /// it adds is that this was not where the teacher was told — the one
        /// thing a teacher asking "why did it go THERE?" needs, and the thing
        /// #323's stale deploys hid. Named "read" rather than "followed"
        /// because it also carries the runs that stood down (plan review L3).
        case scheduledPublishReadTheSettings = "scheduled publish read the course's settings"
        /// A folder or file was removed in Course Settings, excluding it
        /// from previews and deploys. Written on the CLICK, saved or not —
        /// Russell's decision of 2026-09-06
        /// (overnight/issues/09-item-excluded-trail-on-click.md): the attempt
        /// must leave a trace even if the teacher crashes before saving.
        /// Carries the scope and whether it was a folder or a file.
        case itemExcluded = "item excluded"
        /// A previously excluded folder or file was added back in Course
        /// Settings, returning it to previews and deploys. Written on the
        /// click, and only for a name that WAS excluded.
        case itemReincluded = "item re-included"
        /// A Revert in Course Settings took back unsaved exclusion changes —
        /// the other half of the decision above, so a removal that never
        /// reached the file is followed by a line saying it was taken back.
        /// Carries HOW MANY, never the names (issue #152).
        case exclusionsReverted = "exclusions reverted"
        /// A teacher tried to remove or untick a folder or file that a
        /// feature depends on, and was shown why it cannot go and which
        /// switch to turn off first. Recorded because "I could not remove
        /// the folder" is a report support will receive, and the line says
        /// which rule refused and what the teacher was told — and, since
        /// #171, which course and which screen: "new course SNC4M: …" in the
        /// New Course wizard, "SNC4M: …" in Course Settings (`RemovalTrail`).
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
        /// The LAUNCHERS write it once more, in words the contract pins
        /// (`launcherLineWhenASecondCopyIsClearedAway`, GitHub #189): when a
        /// launcher handed another spelling of the folder clears away the
        /// second workspace or builds folder that spelling made before #189,
        /// filed under the course/section it ran for (or "setup"). The app
        /// never writes that one; it sweeps nothing.
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
        /// could not be asked and Plantoir does not know. Or — with no
        /// silence waited out and nobody asked — that its website started and
        /// no address for it was ever announced, so there was nothing to open
        /// (issue #235; before it, a guessed address was tried instead).
        /// The launcher writes this event too, in words the contract pins
        /// (`launcherLine`): when `preview.sh` cannot find out the address at
        /// all it stops before building and says so on the trail itself —
        /// the ending a teacher will actually meet, since the app's own
        /// no-address stop only fires if a launcher ever announced nothing.
        /// Since issue #280 the launchers write it on one more ending, in
        /// words pinned as `launcherLineWhenEveryAddressIsTaken`: every
        /// address Plantoir can use for a preview was taken, so no workspace
        /// could be made for the folder — from a preview, a publish, or
        /// setup (which files it under the word "setup", having no course
        /// yet). Deliberately not a new event: to a teacher it is the same
        /// outcome, a preview that never appeared. Since issue #234
        /// `preview.sh` writes it on a third ending, in words pinned as
        /// `launcherLineWhenThisMacCannotReachTheBuilder`: before building,
        /// a connection to the address it was about to announce was refused
        /// on every try, so it stopped rather than build a preview this Mac
        /// could not open — the fault #225 names after a build, found first.
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
        /// The website builder began being got ready in the background, at a
        /// first launch or the first launch of a new version (bundle B,
        /// `BuilderWarmUp`). Carries the version. With the three below, it is
        /// what answers "why was my first preview slow?" — or why it was not.
        case builderWarmUpStarted = "builder got ready in the background: started"
        /// The background run finished and the builder is ready. Carries how
        /// many seconds it took, the number the feature exists to hide.
        case builderWarmUpFinished = "builder got ready in the background: finished"
        /// The background run ended without the builder being ready — a
        /// failed download, a builder that would not start. Carries how it
        /// ended and after how long. Nothing is said to the teacher: the
        /// first preview gets it ready the old way.
        case builderWarmUpDidNotFinish = "builder got ready in the background: did not finish"
        /// The background run was not started because the Mac was offline or
        /// in Low Data Mode. Carries which. The other reasons not to start
        /// (already ready, a headless run, the test suite) leave no line,
        /// because they are true on nearly every launch.
        case builderWarmUpSkipped = "builder got ready in the background: skipped"
        /// ⌘Q landed while this app was publishing or building a preview
        /// (the latter since issue #232), the teacher was asked whether to
        /// quit anyway, and this is what they chose.
        ///
        /// BOTH answers are recorded, and the "keep working" one matters most:
        /// a teacher who says "I pressed Quit and it would not quit" is
        /// describing that branch, and nothing else would explain it. The
        /// other branch explains a publish that stopped part way through with
        /// no error anywhere — the teacher was told and went ahead, which is a
        /// completely different report from a publish that died on its own.
        /// Carries what was under way, in the words the teacher was shown.
        case quitAskedAboutWorkUnderWay = "quit asked about work under way"

        /// A teacher made a new course, and WHICH starting content it began
        /// from: the ready-made pages written for its code, the subject's
        /// skeleton, or empty folders. Carries the course code and nothing
        /// else — not the name they typed, not where it publishes.
        ///
        /// Written because "my new course came out empty" is a report that
        /// today's trail cannot answer at all. Until 2026-09-21 the only
        /// line a creation left was "started setup.sh", whose arguments are
        /// empty for a course creation — so the trail did not even carry
        /// the code, let alone what the course was supposed to start as.
        /// Adding one folder to a list has recorded more than making a
        /// whole course did (`folder created`). That asymmetry is what
        /// GitHub issue #248 was reported against: a teacher declined the
        /// ready-made pages, got empty folders, and nothing on the trail
        /// said which of those two things had happened.
        ///
        /// A club (#267) says so, with its page word and class folder —
        /// "created CODING as a club, with pages named “Week 1” in “All
        /// Meetings”" — because those are what decide whether any of its
        /// pages are seen at all.
        case courseCreated = "course created"

        /// A course was kept for reference: which folder it was given, the
        /// code and school year it shows, how many sections came across, and
        /// which course it was copied from. Since #255 it also names the
        /// Obsidian add-ons the copy was made without, by folder name — only
        /// when there were any, so a course with none leaves the same line as
        /// before (`ObsidianAddOns.trailClause`). Never the contents of a
        /// page, and never anything read from inside an add-on.
        case courseKeptForReference = "course kept for reference"

        /// "Keep a Copy for Reference…" was pressed and no copy was made
        /// (#287): which course it was copied from, the folder it was to be
        /// given, and why — being made in another window or copy of Plantoir,
        /// a folder of that name already there, or the copy could not be
        /// made (the system's reason, which may name a file; never a page's
        /// contents). Its own event rather than the import's, because
        /// nothing was imported. A disabled button writes nothing — the sheet
        /// refuses a name or a school year by greying Keep a Copy out, and
        /// that is not a press.
        case courseCouldNotBeKeptForReference = "course could not be kept for reference"

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
        /// from". For a MODERN course it also names the Obsidian add-ons left
        /// behind, by folder name and only when there were any (#255); the
        /// older layouts say theirs on their own second line. Never the
        /// contents of a page.
        case courseImportedForReference = "course imported for reference"

        /// A class kept in the OLDER layout (a folder per class, #254) came
        /// across. Written right after `courseImportedForReference`, and
        /// carries what that line cannot: the class folder's name, the shared
        /// folder its pages and pictures came from and HOW it was found (by
        /// its name, chosen by hand, or none), how many of the shared folders
        /// and pages the class used were brought across out of how many and
        /// the names of any that are missing, how many of the class's links
        /// the shared folder's real entries REPLACED, how many things were
        /// left out as a LOSS with each one's path (a link below the top or
        /// inside a shared entry, a name the course uses for itself), how
        /// many Obsidian add-on entries were left behind, and whether an empty
        /// Media folder was made. "Where are this course's pictures" is the
        /// question a report about one of these will ask. Names and paths
        /// only — never what is written on a page, and never anything read
        /// from the add-ons.
        case courseImportedFromTheOlderLayout = "course imported from the older layout"

        /// A class kept in the 2024–25 layout — a whole website folder per
        /// class, often reached through a Finder shortcut — came across
        /// (#256). Written right after `courseImportedForReference`, and
        /// carries what that line cannot: where the pages were read from (a
        /// path from the home folder) and the shortcut's name when one was
        /// followed, the section and HOW it was told (its front page, its
        /// folder's name, or being the only one) with any disagreement, the
        /// course pages folder the files came from and how many, the word
        /// its class pages use and how many placeholder pages were set aside,
        /// and then as two separate clauses what was LEFT BEHIND by kind with
        /// counts (the website's own program files, links replaced, editing
        /// folders and other sections by name, add-ons) and what was LOST, by
        /// name (a link that showed somewhere unexpected also says where it
        /// pointed, from the home folder). S1's and S2's copies of the pages differ, so "which copy did
        /// this come from, and what did not come" is a real question, and
        /// only this line answers it. Names and counts only — never what is
        /// written on a page.
        case courseImportedFromAClassWebsiteFolder = "course imported from a class website folder"

        /// One course of an import did not come across, and the rest did.
        /// Carries which course and why, as the sentence the summary showed —
        /// already on the shelf under that school year (also a second course
        /// of the same code in one run), a folder of that name already there
        /// (both #287), already being imported in another window or another
        /// copy of Plantoir, or something an earlier unfinished attempt left
        /// behind could not be cleared (both #245), a folder that could not
        /// be read, a disk that filled. Written for EVERY course the summary
        /// lists as not imported; never for one the teacher stopped. Written
        /// per COURSE, because "the import
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

        /// A reference course was filed under a different school year — the
        /// one thing about a frozen course a teacher can still change.
        /// Carries the code they read, the folder, and both years.
        case referenceCourseSchoolYearChanged = "reference course school year changed"

        /// Backups were deleted — one from the sidebar, or several from All
        /// Backups (#242). Carries the course code or codes, how many, what
        /// they took when every size is known, each file's NAME (a course code,
        /// a moment and who made it — never anything on a page), and any the
        /// open assistant conversation still needed and so kept.
        ///
        /// A teacher's own backups are never pruned, so a backup that is gone
        /// was deleted by a person — and "my backup is gone" is answered by
        /// this line and by nothing else. There was no line for it at all
        /// before, for one delete or many.
        case backupsDeleted = "backups deleted"

        /// A build of a course was declined because ANOTHER program on this
        /// Mac holds a build, publish or preview lease on it (#156) — Preview
        /// or Deploy in the window, the in-app assistant's rebuild or deploy,
        /// or an outside assistant's (`--mcp-stdio`). Carries the course, the
        /// section asked about, what was asked for, what the other holds and
        /// its process id. Never anything on a page.
        ///
        /// Recorded because the other program is invisible from here: a
        /// teacher who reports "Preview said somebody else was using it"
        /// can be answered only by the process id — carried on the lease
        /// file and on this line. The app's own "app opened" line names it
        /// too when the other program is a copy of the app; the
        /// `--mcp-stdio` and scheduled processes write no opening line.
        case buildDeclinedBusyElsewhere = "build declined, course busy elsewhere"
        /// An outside assistant (Claude or Codex) changed a course, asked for
        /// a rebuild, or deployed, while a preview of that course was open in
        /// Plantoir (#433). A change or a rebuild left the open preview
        /// exactly as it was — not rebuilt; a deploy went ahead and may have
        /// closed it. Carries the course and section and which of those it
        /// was — never anything written on a page. It answers "Claude said it
        /// changed the page and my preview still shows the old one".
        case outsideChangeLeftThePreviewAlone = "outside assistant worked while a preview was open"
        /// A preview that was serving ended because another program on this
        /// Mac built the course for a deploy — its server killed the way a
        /// deploy's build stops a section's preview — and was shown as
        /// "Closed for a deploy", not as a failure (#433's stack review).
        /// Carries the course and section; never anything on a page.
        case previewClosedForADeploy = "preview closed for a deploy"

        /// A publish set for later found the course being built or published
        /// by another program and WAITED (#156): it polls every fifteen
        /// seconds for up to ten minutes. Carries the course, the section, how
        /// long it waited, the other's process id, and whether it then went
        /// ahead or stood down (the stand-down also leaves the section's
        /// `courseWasBusy` record). Recorded because a publish that ran ten
        /// minutes late, or not at all, looks from outside exactly like one
        /// that misfired.
        case scheduledPublishWaitedForTheCourse = "scheduled publish waited for the course"
        /// A newly set deploy found a run of the SAME section still working
        /// (GitHub #439): setting the section again had ended that run's app,
        /// and its script carried on as a leftover. The new run waits for it —
        /// every fifteen seconds, up to thirty minutes — before it starts its
        /// own, because two deploys of one section at once is the fault the
        /// launchers' guard refuses. Carries the course, the section, how long
        /// it waited, and whether it then went ahead or stood down (the
        /// stand-down also leaves the section's `earlierDeployStillWorking`
        /// record). Recorded because a deploy that went out half an hour late,
        /// or not at all, looks from outside exactly like one that misfired.
        case scheduledDeployWaitedForItsEarlierDeploy = "scheduled deploy waited for its earlier deploy"
        /// A section's deploy set for later was set again while that
        /// section's run was still working (GitHub #439, #409). Setting it
        /// again ends the run's app, but the deploy it had started goes on and
        /// finishes on its own — without the app's after-work: the section is
        /// not marked deployed, the run writes no trail line of its own and
        /// sends no notification. This line is the only place that says the
        /// earlier deploy is still going. Carries the course and section.
        case scheduledDeploySetAgainWhileItsDeployWorked = "scheduled deploy set again while its deploy worked"
        /// A launcher had to remake a working folder's workspace and found
        /// something running in it (GitHub #94). Carries where the run was
        /// for — course and section, or the word "setup" — and which of
        /// three it was: it WAITED for a build or publish to finish, and for
        /// how long; it stopped because a preview from the folder was still
        /// open, and which one; or it stopped because something was still
        /// being built or published after ten minutes.
        ///
        /// Written by the app, from the line the launcher prints
        /// (`WorkspaceInUseReport`): `ScriptRunner` reads it from a run's
        /// console, `ScheduledDeploy` from the log of a publish launchd ran.
        /// On the trail because each of the three is a new way for a run to
        /// be slow or not to happen — "my publish did not go out last night",
        /// "it told me to close a preview" — and the app otherwise shows a
        /// refusal only as a run that did not finish. A remake with nothing
        /// running writes nothing. Mac only, permanently: Windows builds
        /// natively and has no workspace.
        ///
        /// Since GitHub #378 the lines name WHAT was waited for and who had
        /// started it ("a deploy of MPM2D section 2 started by Revise with
        /// Claude"), and no longer say "workspace". The key keeps its old
        /// name so trails already on disk stay readable.
        case workspaceWasInUse = "workspace was in use"
        /// A launcher setting a folder up again ended work left running in
        /// it by a program that had since closed (GitHub #378, decision 2) —
        /// a deploy a closed session left waiting at a question, a build a
        /// force-quit app left behind, an orphaned preview. Carries where the
        /// run was for and each piece of work ended, by kind with its course
        /// and section; never a command line, a path or a process number.
        ///
        /// Written by the app from the launcher's `PLANTOIR_LEFTOVER_STOPPED:`
        /// line (`LeftoverWorkReport`), in the same two places as
        /// `workspaceWasInUse`. On the trail because ending somebody's work
        /// must never be silent: "why did my deploy from Claude not go out?"
        /// is answered by this line. Mac only, permanently.
        case leftoverWorkStopped = "left-over work stopped"
        /// A section's Cloudflare project was made again under the same name,
        /// because it was not in the Cloudflare account any more — deleted in
        /// Cloudflare's dashboard, say — and a publish would otherwise have
        /// failed (2026-09-30). Carries where the publish was for, the
        /// project's name and the address the website answers at now; never
        /// the account ID or the token.
        ///
        /// Written by the app from the shared `deploy.py`'s
        /// `PLANTOIR_CLOUDFLARE_REMADE:` line (`CloudflareProjectRemadeReport`),
        /// in the same two places as `leftoverWorkStopped`. On the trail
        /// because it changes things a teacher sees weeks later: the address
        /// can change, and a custom domain went with the deleted project.
        case cloudflareProjectMadeAgain = "cloudflare project made again"
        /// A preview's address was held by something else on this Mac
        /// (GitHub #310, found in the #204 rehearsal with two macOS accounts
        /// signed in). Carries where the preview was for, the address — a
        /// number on this Mac — and which of four it was: a STOPPED
        /// workspace's address was in use, so it was set up again on free
        /// addresses before it started; the address a running workspace was
        /// about to announce was held by another account or by macOS itself,
        /// so it was set up again once; it was STILL held after that, so the
        /// preview stopped before building; or the look was not made, because
        /// the run was pointed at an engine other than the one Plantoir sets
        /// up (a developer's DOCKER_HOST; the app never sets one).
        ///
        /// Written by the app, from the line `preview.sh` prints
        /// (`PreviewAddressHeldReport`), which `ScriptRunner` reads from a
        /// run's console. On the trail because each outcome arrives later as a
        /// report that reads like something else: a slow preview for no
        /// reason, a preview that would not start, or somebody else's site.
        /// Mac only, permanently: Windows serves a preview on the PC itself,
        /// with no forward to lose.
        case previewAddressHeldByAnotherAccount = "preview address held by another account"
        /// Plantoir installed one or more of the website builder's helper
        /// programs into its tools folder (GitHub #312): which ones, at which
        /// pinned versions, whether from inside Plantoir or downloaded, why
        /// (not yet on this Mac, other versions, a damaged copy, or copies
        /// from before Plantoir kept a record of them), and for a download
        /// why Plantoir's own copy was not used.
        ///
        /// Written by the app, from the line the launchers print
        /// (`HelperBootstrapReport`), which `ScriptRunner` reads from a run's
        /// console and `ScheduledDeploy` from the log of a publish launchd
        /// ran. On the trail because a silent fallback to downloading is the
        /// failure that reports success: the first run works, only slower.
        /// Mac only, permanently: Windows carries its runtime and installs no
        /// helper programs.
        case helperProgramsInstalled = "helper programs installed"
        /// The website builder was created on this Mac for the first time
        /// (GitHub #312): how many seconds it took, and where its starting
        /// disk came from — inside Plantoir, downloaded, or downloaded
        /// because starting from Plantoir's copy was refused or failed. Read
        /// from the launchers' line by `HelperBootstrapReport`, as above. On
        /// the trail because "the first run took forever" is the report #312
        /// exists for, and the seconds from the teacher's own Mac are what
        /// the next decision needs. Mac only, permanently.
        case websiteBuilderCreated = "website builder created"

        /// Whether the teacher was told, with a macOS notification, how a
        /// scheduled publish went (#212) — or why not: notifications turned
        /// off for Plantoir, never allowed yet, or macOS would not take it.
        /// Also the question, when a teacher first schedules from the window,
        /// and their answer. Carries the course and the section, and NEVER the
        /// notification's text.
        ///
        /// "I never got told" is answerable only if the trail says whether the
        /// notice went out: a notification that was sent and one that was
        /// blocked look identical from the teacher's side.
        case scheduledPublishNotification = "scheduled publish notification"
        /// Plantoir left some pages' settings exactly as they were, because
        /// the settings at the top of those pages have no place a new line
        /// can safely go (#186's shape — indented, or written as a list).
        /// Carries the course and section, WHAT was being done, and HOW MANY
        /// pages — never which, because a page's name is the teacher's own
        /// words. Written by a section restore since #182, and by publishing,
        /// hiding, re-dating and making room since #186; the teacher is told
        /// in the same breath, and this is the line that is still there next
        /// week, when "why is this page still showing?" arrives.
        case pageSettingsLeftAsTheyWere = "page settings left as they were"
        /// Making room for a class could not finish some of its writes — a
        /// rename whose new name was taken or whose save failed, a date, a
        /// page's links, a new class whose name was still taken (#425,
        /// adopted from Windows' #422). Counts by kind, never names.
        case makingRoomDidNotFinishEveryPage = "making room did not finish every page"
        /// The assistant asked to publish or hide pages and named none this
        /// section has (#197): only a word meaning every page ("all"), or
        /// names that match no page. Nothing was changed and the teacher was
        /// told so. Carries the course and section, the act, and either the
        /// word (one of the contract's closed list) or how MANY names matched
        /// nothing — never the names, which are page titles the model wrote.
        ///
        /// Without it the trail shows only "assistant chose a tool:
        /// publish_pages (course, section, pages)", and a teacher reporting
        /// "it said it needed to know which pages" cannot be looked into: the
        /// "all" was measured 3 in 3 on one course and 0 in 108 on six others,
        /// and only the field can say how often it happens.
        case assistantNamedNoPage = "assistant named no page it could find"
        /// An outside assistant read a course's How I Teach page through
        /// Plantoir (#209), or found there was none: carries the course, and
        /// the word count and whether it was cut short — never the words.
        /// Present means read THROUGH PLANTOIR; its absence does not prove
        /// the page was never read, because an agent's own file tools can
        /// open it from the working folder and leave no line.
        case howITeachPageRead = "How I Teach page read"
        /// An outside assistant saved a course's How I Teach page (#209):
        /// created or replaced, word counts before and after, and the backup
        /// made first. Answers "did I write this, or did an assistant?".
        case howITeachPageWritten = "How I Teach page written"
        /// A build dropped a How I Teach page the course's settings had
        /// LISTED for the website (#209) — one earlier builds published.
        /// Read from the build's `PLANTOIR_KEPT_OFF:` line.
        case howITeachPageKeptOff = "How I Teach page kept off the website"
        /// Course Settings made an EMPTY How I Teach page (#329) — or could
        /// not, and why: carries the course. A page the teacher did not
        /// write appears in the course folder, and the assistant then calls
        /// it "not written yet"; this is the only record the button made it.
        /// Opening a page that is there writes nothing.
        case howITeachPageStarted = "How I Teach page started"
        /// The assistant saved a copy of a course (#351) — its first write in
        /// a conversation, or the `back_up_course` tool: the course, the
        /// section the copy is named for, the backup's FILE NAME, its size
        /// and how long it took; or that it could not, and why. Answers "the
        /// window hung after I approved" and "where did this zip come from".
        /// The once-per-conversation reuse writes nothing: one line per real
        /// zip.
        case assistantBackedUpACourse = "assistant backed up a course"
        /// A section was got ready for the start of the year (#96): every
        /// class after the first, and the pages only later classes use, put
        /// into draft in one act. Carries the course and section, where it
        /// was asked from (the app, the assistant, an outside assistant),
        /// how many classes and how many other pages went into draft — the
        /// other pages counted by reason — how many were left as they were,
        /// the backup's FILE NAME, and whether the preview was rebuilt.
        /// Never a page's name: the backup is how anyone finds the pages.
        ///
        /// The single largest change the app makes to a teacher's files on
        /// one press, usually weeks before anybody looks at the site. "Why is
        /// everything after Day 1 gone?" arrives in September, and without
        /// this line the trail shows a teacher who never pressed anything.
        case sectionMadeReadyForTheStartOfTheYear = "section made ready for the start of the year"
        /// That change taken back (#96), from the app's own undo or an
        /// outside assistant's. Carries where from, how many pages were put
        /// back, and how many were left as they are because they had changed
        /// since — an undo that skips files is a partial undo, and "some came
        /// back and some did not" needs the count on record.
        case startOfTheYearChangeUndone = "start of the year change undone"
        /// The links checklist was put in front of the teacher (#379).
        /// Carries how many pages in each group (used by a class, linked from
        /// other pages, classes), how many are listed under another page and
        /// how many would be published as offered — rows that GO or that a ticked class brings (#398),
        /// not rows whose own tick is on (#385) — and the occasion: after a preview, after
        /// publishing, on opening after a deploy Plantoir did not watch
        /// (scheduled, the assistant, outside), or from the menu. #333's alert
        /// was shown and nobody could tell afterwards whether it had been seen;
        /// "why did it ask me to publish 40 pages?" is answered by the counts.
        case linksChecklistOffered = "offered to publish pages that links lead to"
        /// Pages published from the links checklist (#379). Carries how many
        /// were published, dated from a class, dated as the first class, kept
        /// their date, classes published, pages those classes brought, left
        /// unticked, left with the page they come under (#385); since #398, how many were
        /// rows written only because a ticked class brought them; and the PLACES of the published pages, at most ten then
        /// "and N more" — names, never anything written on them. It changes
        /// what students will see and rewrites dates in the teacher's files,
        /// and "why is this page visible / why did its date change" is asked
        /// weeks later.
        case pagesPublishedFromLinksChecklist = "published pages that links led to"
        /// The teacher left pages hidden that links lead to (#379): Not Now,
        /// or Publish with some unticked. Carries every page left hidden and,
        /// of those, how many only because the page they come under was
        /// (#385). When a student
        /// reports a dead link, the trail shows the teacher was offered it
        /// and chose.
        case linksChecklistSetAside = "left pages hidden that links lead to"
        /// Getting a section ready was asked for and NOTHING was written
        /// (#96). Carries where from and the reason: changedSinceShown,
        /// backupFailed, writeFailed, noFirstClass, missingPlanCode, or
        /// nothingToDo — the last only from an outside assistant, since the
        /// app's button is not offered when there is nothing to do. "I
        /// pressed the button and nothing happened" leaves no changed file,
        /// so without this line nothing records that it was pressed.
        case startOfTheYearNotDone = "start of the year not done"
        /// Plantoir found a new version of itself (#204) — once per version
        /// per launch, and "found" rather than "offered", because the updater
        /// may hold its window back until the app is next in front. Carries
        /// both versions, whether the teacher asked, and whether it is marked
        /// important.
        case updateFound = "update found"
        /// The teacher checked and nothing was newer (#204). Only when the
        /// TEACHER asked: the daily check is not an action of theirs.
        case updateCheckFoundNothingNew = "update check found nothing new"
        /// What the teacher answered in the update window (#204): what tells
        /// "never offered" from "offered and skipped".
        case updateAnswered = "update answered"
        /// The teacher pressed Install while work was under way, and the
        /// install waits (#204) — the same words they were shown.
        case updateHeldWhileWorkIsUnderWay = "update held while work is under way"
        /// The last line the OLD version writes (#204): from and to, and
        /// whether it opens again.
        case updateInstalling = "update installing"
        /// A quit with an update ready and work still going cancelled the
        /// install rather than letting it happen on the way out (#204).
        case updateSetAside = "update set aside"
        /// The updater could not go on (#204), in a plain category with its
        /// number. It says nothing to the teacher about a failed daily check
        /// or a refused administrator password, so this is the only record.
        case updateStopped = "update stopped"
        /// The first launch of a version different from the last (#204), by
        /// its own updater or by hand.
        case appUpdated = "app updated"
        /// The teacher pressed Show on Front Page at Preview (#397): the
        /// section's front page now shows today's class — from and to, as
        /// file names.
        case putTodaysClassOnTheFrontPage = "put today's class on the front page"
        /// The front page was offered today's class and not changed (#397):
        /// Not Today, already right, changed while asked, or not saved.
        case frontPageLeftAsItWas = "left the front page as it was"
        /// A remembered timetable holding a date that cannot be a class date
        /// was read as nothing remembered (#377, from Windows #144): the
        /// course, the section and that date. Without it, a problem report
        /// shows class dates on disk and an app that asked for them anyway.
        case rememberedTimetableSetAside = "remembered timetable set aside"
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

    /// The words for `pageSettingsLeftAsTheyWere`: what was being done, and
    /// how many pages — never which.
    static func pageSettingsLeftAsTheyWereLine(act: String, pages: Int) -> String {
        let counted: String = pages == 1 ? "1 page" : "\(pages) pages"
        return "left the settings of \(counted) as they were while \(act): no room at the top for a new setting"
    }

    /// The words for `assistantBackedUpACourse`: the copy's file name — a
    /// course code, a moment and who made it, never anything written on a
    /// page — its size in megabytes and the seconds it took, one decimal
    /// each, so a reader can tell 0.4 s from two minutes without a threshold
    /// anybody had to guess.
    static func assistantBackedUpLine(fileName: String, bytes: Int64, seconds: Double) -> String {
        let megabytes: String = String(format: "%.1f", Double(bytes) / 1_000_000)
        let took: String = String(format: "%.1f", seconds)
        return "assistant backed up the course as \(fileName) (\(megabytes) MB, \(took) s)"
    }

    /// The words for an assistant backup that could not be made.
    static func assistantCouldNotBackUpLine(reason: String) -> String {
        return "assistant could not back up the course: \(reason)"
    }

    /// Where a start-of-the-year act was asked from, in the trail's words.
    static func startOfYearSource(_ source: String) -> String {
        switch source {
        case "app":
            return "from the app"
        case "mcp":
            return "from an outside assistant"
        default:
            return "from the assistant"
        }
    }

    /// The words for `sectionMadeReadyForTheStartOfTheYear` (#96): counts and
    /// the backup's file name, never a page.
    static func sectionMadeReadyLine(
        source: String,
        classes: Int,
        otherPagesByReason: [String: Int],
        leftAsTheyWere: Int,
        backupFileName: String,
        previewRebuilt: Bool
    ) -> String {
        var other: Int = 0
        for (_, count) in otherPagesByReason {
            other += count
        }
        let firstUsedLater: Int = otherPagesByReason["firstUsedLater"] ?? 0
        let unseen: Int = (otherPagesByReason["onlyHiddenPagesLinkToIt"] ?? 0)
            + (otherPagesByReason["onlyAFolderListsIt"] ?? 0)
            + (otherPagesByReason["nothingLinksToIt"] ?? 0)
        let classWord: String = classes == 1 ? "1 class" : "\(classes) classes"
        let otherWord: String = other == 1 ? "1 other page" : "\(other) other pages"
        return "made ready for the start of the year \(startOfYearSource(source)) — \(classWord) and "
             + "\(otherWord) put into draft (\(firstUsedLater) first used later, \(unseen) that nothing "
             + "students can see links to), \(leftAsTheyWere) left as they were; backup \(backupFileName); "
             + (previewRebuilt ? "preview rebuilt" : "preview not rebuilt")
    }

    /// The words for `startOfTheYearChangeUndone` (#96).
    static func startOfYearUndoneLine(source: String, putBack: Int, leftAsTheyAre: Int) -> String {
        let pages: String = putBack == 1 ? "1 page" : "\(putBack) pages"
        return "undid getting ready for the start of the year \(startOfYearSource(source)) — \(pages) put "
             + "back, \(leftAsTheyAre) left as they are because they had changed since"
    }

    /// The words for `startOfTheYearNotDone` (#96).
    static func startOfYearNotDoneLine(source: String, reason: String) -> String {
        return "did not get ready for the start of the year \(startOfYearSource(source)) — nothing was "
             + "changed (\(reason))"
    }

    /// The words for `assistantNamedNoPage`: what was being done, and which
    /// of the two shapes — never a page's name.
    static func namedNoPageLine(act: String, everyPageWord: String?, unknownCount: Int) -> String {
        if let word = everyPageWord {
            return "named no page while \(act): a word for every page (“\(word)”), so nothing was changed"
        }
        let counted: String = unknownCount == 1 ? "1 name that matches" : "\(unknownCount) names that match"
        return "named no page while \(act): \(counted) no page, so nothing was changed"
    }

    static func formatter(timeZone: TimeZone = TimeZone.current) -> DateFormatter {
        let formatter: DateFormatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = timeZone
        formatter.dateFormat = "yyyy-MM-dd HH:mm:ss"
        return formatter
    }

    /// The lines that open a session, so a trail spanning several launches
    /// says where each one began — and says which BUILD it was, which is the
    /// first thing to check when a report and the code disagree.
    ///
    /// The third launch line, the helpers, is `noteHelpers` — written a
    /// moment later, once the helper programs have been ASKED which versions
    /// they are (issue #222). Writing it here would mean writing the pinned
    /// versions as though they were measured, which is what it used to do.
    static func noteLaunch() {
        ActivityTrail.note(.appOpened, "Plantoir opened — " + ProblemReportEnvironment.appDescription)
        ActivityTrail.note(.machine, "running on " + ProblemReportEnvironment.systemDescription)
    }

    /// The helper programs this launch found, as measured.
    static func noteHelpers(_ description: String) {
        ActivityTrail.note(.helpers, "using " + description)
    }
}
