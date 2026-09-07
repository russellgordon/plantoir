import Foundation

/// The twenty-two tools that exist, and the thirteen of them the local model
/// is shown.
///
/// It was fifteen when routing accuracy was measured, and the seven that came
/// after — reading and recording a section's timetable, adding the next class
/// page, and re-dating a whole section — were added on purpose, knowing the
/// cost. A small local model routes worse the more it is shown, so the number
/// is worth re-measuring rather than assuming the old figure still holds.
/// `localTools` is the answer to that pressure: nine of the twenty-two are
/// never NAMED by the model, so they are not put in front of it.
///
/// **Keep these three numbers right.** They are 22, 13 and 9 as this is
/// written, pinned by `AssistToolRunnerTests` and
/// `AssistCurriculumMentionsTests`, and they were 20, 13 and 7 in this comment
/// for long enough that the same stale figure reached `CLAUDE.md` and two
/// documents. A count nobody can check is a count that gets quoted.
///
/// The descriptions are the Windows server's own, put through the same
/// shortening rule the narrowed surface uses there: keep the `TEACHERS SAY:`
/// clause whole, then the first sentence of the rest, and nothing else.
///
/// The `TEACHERS SAY` phrasings are load-bearing rather than decorative — they
/// are what took routing from 69% to 91% — so they are COPIED, not improved.
/// The temptation to reword one is the temptation to spend a measurement
/// somebody else already paid for.
///
/// Two deliberate departures from the Windows schema, both forced by the shape
/// of the tool surface here:
///
/// * Lists of page names are semicolon-separated strings. The schema this
///   client speaks has strings, integers and booleans and no arrays — and a
///   COMMA-separated list would cut "Unit 2, Day 3" in half, which is the name
///   nearly every class page in these courses has.
/// * There is no `preview` flag. On Windows a batch of edits can be made with
///   the preview suppressed and rebuilt once at the end; here every change
///   rebuilds, which is what the assistant's own system prompt promises a
///   teacher, and it is one fewer boolean on a surface where booleans are the
///   thing that goes wrong.
///
/// There is now no boolean anywhere on this surface at all. The last one was
/// `includeLinked`, and it asked the MODEL how far a publish or an unpublish
/// should reach — the exact reasoning this design exists to keep out of a
/// router. The rules live in `AssistPublishPlanner` instead, where they can be
/// written down once and tested.
extension AssistToolRunner {

    // MARK: - The surface

    /// Every tool either client may call, narrowed from the Windows server's
    /// much larger surface.
    static let tools: [AssistToolDefinition] = [
        listPagesTool,
        readPageTool,
        checkSectionTool,
        planPublishClassOnTool,
        publishClassOnTool,
        planPublishPagesTool,
        publishPagesTool,
        planUnpublishPagesTool,
        unpublishPagesTool,
        rebuildPreviewTool,
        undoLastChangeTool,
        deploySectionTool,
        planScheduledDeployTool,
        scheduleDeployTool,
        cancelScheduledDeployTool,
        readRememberedTimetableTool,
        planRememberTimetableTool,
        rememberTimetableTool,
        planAddNextClassTool,
        addNextClassTool,
        planReDateClassesTool,
        reDateClassesTool,
    ]

    /// The tools the LOCAL model is actually shown.
    ///
    /// Everything above still RUNS; this is only what the model is asked to
    /// choose between, and every schema in the list costs it context and
    /// accuracy. Two kinds are left out, and neither loses a teacher anything:
    ///
    /// * **The seven `plan_` twins.** Plan mode calls them IN CODE —
    ///   `AssistAgent.showPlan` builds the call itself from the write the model
    ///   already chose — so the model never has to name one. They were about a
    ///   third of the prompt and bought nothing.
    /// * **`remember_timetable`.** Dates the MODEL supplies are dates it may
    ///   have invented, and a wrong one silently schedules a class on the wrong
    ///   day. The schedule sheet owns recording them now.
    ///   `read_remembered_timetable` stays: reading back what a teacher already
    ///   said invents nothing.
    static let localTools: [AssistToolDefinition] = narrowedForTheLocalModel(tools)

    /// Names kept off the local list even though they are not plans.
    ///
    /// `re_date_classes` is here for a second reason worth stating: the
    /// phrasings that reach it are matched in code, so the model never needs
    /// to see it — and re-dating two hundred pages is far too large a change
    /// to reach through a router that is right four times in five. It stays on
    /// the MCP surface, where the client can hold a bigger list and a person
    /// is reading every step.
    static let hiddenFromTheLocalModel: Set<String> = ["remember_timetable", "re_date_classes"]

    /// The list above, with the plans and the hidden names taken out.
    private static func narrowedForTheLocalModel(
        _ all: [AssistToolDefinition]
    ) -> [AssistToolDefinition] {
        var shown: [AssistToolDefinition] = []
        for tool in all {
            if tool.name.hasPrefix("plan_") {
                continue
            }
            if hiddenFromTheLocalModel.contains(tool.name) {
                continue
            }
            shown.append(tool)
        }
        return shown
    }

    /// The tools the MCP client is offered ON TOP of the local surface.
    ///
    /// Kept apart because the local surface is a MEASUREMENT: routing accuracy
    /// was counted against exactly the tools a teacher asks for, and a small
    /// local model routes worse the more it is shown. Claude Code, on the other
    /// end of the MCP server, is not that model — it can hold a larger surface
    /// and it can do the one thing these tools need doing, which is deciding
    /// what a curriculum expectation MEANS. So the fuller surface is served
    /// there and nowhere else.
    static let mcpOnlyTools: [AssistToolDefinition] = [
        listCurriculumExpectationsTool,
        planCurriculumMentionsTool,
        addCurriculumMentionsTool,
    ]

    /// Everything the MCP client may call: every tool that exists, plus the
    /// ones only it is offered.
    ///
    /// Wider than the local list on purpose. Claude Code has no plan mode, so
    /// it needs the `plan_` twins by name to show a teacher what a write would
    /// do — and it is a model that can be trusted with a date, so
    /// `remember_timetable` is there too.
    static let mcpTools: [AssistToolDefinition] = tools + mcpOnlyTools

    // MARK: - Shared argument wording

    private static let courseHelp: AssistSchemaProperty = AssistSchemaProperty(
        kind: .string, description: "The course code, for example ICS3U."
    )

    private static let sectionHelp: AssistSchemaProperty = AssistSchemaProperty(
        kind: .integer, description: "The section number, for example 1."
    )

    private static let dateHelp: String =
        "A date as YYYY-MM-DD, for example 2026-09-15. Leave empty for no limit."

    private static let classDateHelp: AssistSchemaProperty = AssistSchemaProperty(
        kind: .string,
        description: "The day the class is taught, as YYYY-MM-DD. For \"tomorrow\" or \"today\", work out "
                   + "the date first — the tool matches it exactly against each class's own date."
    )

    private static let whenHelp: AssistSchemaProperty = AssistSchemaProperty(
        kind: .string,
        description: "When to deploy, as YYYY-MM-DD HH:MM in 24-hour time — for example "
                   + "\"2026-09-09 06:30\"."
    )

    /// Semicolons, because "Unit 2, Day 3" is a page name and a comma-separated
    /// list of those names is a list of nonsense.
    private static func pagesHelp(_ verb: String) -> AssistSchemaProperty {
        return AssistSchemaProperty(
            kind: .string,
            description: "The page titles to \(verb), separated by semicolons — for example "
                       + "\"Unit 2, Day 3; Unit 2, Day 4\". May be empty if you give dates instead."
        )
    }

    private static let onOrAfterHelp: AssistSchemaProperty = AssistSchemaProperty(
        kind: .string, description: "Only classes on or after this date. " + dateHelp
    )

    private static let beforeHelp: AssistSchemaProperty = AssistSchemaProperty(
        kind: .string, description: "Only classes strictly before this date. " + dateHelp
    )

    // MARK: - Looking around

    private static let listPagesTool: AssistToolDefinition = AssistToolDefinition(
        name: "list_pages",
        description: "List the pages in one section of a course, as paths relative to the working folder.",
        parameters: [
            "course": courseHelp,
            "section": sectionHelp,
            "matching": AssistSchemaProperty(
                kind: .string,
                description: "Only list pages whose path contains this text. Leave empty to list everything."
            ),
        ],
        required: ["course", "section"],
        readOnly: true,
        needsApproval: false
    )

    private static let readPageTool: AssistToolDefinition = AssistToolDefinition(
        name: "read_page",
        description: "Read one page's Markdown, including its frontmatter.",
        parameters: [
            "course": courseHelp,
            "section": sectionHelp,
            "page": AssistSchemaProperty(
                kind: .string,
                description: "The page title as it appears in the sidebar, for example \"Unit 2, Day 3\"."
            ),
        ],
        required: ["course", "section", "page"],
        readOnly: true,
        needsApproval: false
    )

    private static let checkSectionTool: AssistToolDefinition = AssistToolDefinition(
        name: "check_section",
        description: "TEACHERS SAY: \"what do students see right now?\", \"is anything broken?\", "
                   + "\"what's live?\". Check a section's website as students would meet it, "
                   + "changing nothing.",
        parameters: [
            "course": courseHelp,
            "section": sectionHelp,
        ],
        required: ["course", "section"],
        readOnly: true,
        needsApproval: false
    )

    // MARK: - The commonest request of all

    private static let planPublishClassOnTool: AssistToolDefinition = AssistToolDefinition(
        name: "plan_publish_class_on",
        description: "TEACHERS SAY: \"what would publishing tomorrow's class do?\", \"show me before you "
                   + "put Monday up\". Work out what publishing the class taught on a given day would do, "
                   + "WITHOUT changing anything.",
        parameters: [
            "course": courseHelp,
            "section": sectionHelp,
            "date": classDateHelp,
        ],
        required: ["course", "section", "date"],
        readOnly: true,
        needsApproval: false
    )

    private static let publishClassOnTool: AssistToolDefinition = AssistToolDefinition(
        name: "publish_class_on",
        description: "TEACHERS SAY: \"publish tomorrow's class\", \"put up Monday's lesson\", \"put Unit 2, "
                   + "Day 3 up\", \"make Friday's class visible\", \"post next class\", \"put the class live "
                   + "for students\". Publish the class taught on a given day, along with the pages it links "
                   + "to, then rebuild the section's preview.",
        parameters: [
            "course": courseHelp,
            "section": sectionHelp,
            "date": classDateHelp,
        ],
        required: ["course", "section", "date"],
        readOnly: false,
        needsApproval: false
    )

    // MARK: - Publishing, and its own separate opposite

    private static let planPublishPagesTool: AssistToolDefinition = AssistToolDefinition(
        name: "plan_publish_pages",
        description: "Work out exactly what publishing pages would do, WITHOUT changing anything.",
        parameters: [
            "course": courseHelp,
            "section": sectionHelp,
            "pages": pagesHelp("publish"),
            "onOrAfter": onOrAfterHelp,
            "before": beforeHelp,
        ],
        required: ["course", "section"],
        readOnly: true,
        needsApproval: false
    )

    private static let publishPagesTool: AssistToolDefinition = AssistToolDefinition(
        name: "publish_pages",
        // Left deliberately as it is. An attempt to steer a typo'd "publsh
        // tomorows class" away from here — by adding "NOT for one day's
        // class, use publish_class_on" — was MEASURED and made things worse:
        // it fixed that one probe and broke three, sending "Publish Unit 2,
        // Day 3" (a named page, no date at all) to publish_class_on 10 times
        // out of 10 and dropping the window's own suggestions from 110/110 to
        // 90/110. A small model reads a sentence naming another tool as a
        // recommendation rather than a boundary. The over-publish it was
        // meant to prevent is handled in code instead — see
        // `AssistToolRunner`'s refusal of an open-ended range — which cannot
        // cost accuracy because it changes nothing the model reads.
        description: "Make pages visible to students, along with every page they link to, then rebuild "
                   + "the section preview. The linked pages come by themselves — there is nothing to ask "
                   + "for and no way to leave them out, because a published page whose links lead nowhere "
                   + "is the one thing this must never make.",
        parameters: [
            "course": courseHelp,
            "section": sectionHelp,
            "pages": pagesHelp("publish"),
            "onOrAfter": onOrAfterHelp,
            "before": beforeHelp,
        ],
        required: ["course", "section"],
        readOnly: false,
        needsApproval: false
    )

    private static let planUnpublishPagesTool: AssistToolDefinition = AssistToolDefinition(
        name: "plan_unpublish_pages",
        description: "TEACHERS SAY: \"what happens if I take that down?\", \"check before you hide Unit 3, "
                   + "Day 2\". Work out exactly what unpublishing pages from students would do, WITHOUT "
                   + "changing anything.",
        parameters: [
            "course": courseHelp,
            "section": sectionHelp,
            "pages": pagesHelp("unpublish"),
            "onOrAfter": onOrAfterHelp,
            "before": beforeHelp,
        ],
        required: ["course", "section"],
        readOnly: true,
        needsApproval: false
    )

    private static let unpublishPagesTool: AssistToolDefinition = AssistToolDefinition(
        name: "unpublish_pages",
        description: "TEACHERS SAY: \"take Unit 4, Day 5 back down\", \"students shouldn't see it yet\", "
                   + "\"hide that page\", \"I posted it by mistake\", \"make it a draft again\", \"pull that "
                   + "lesson\", \"un-publish it\". Unpublish pages, so students no longer see them, along "
                   + "with any page ONLY they link to; a page another class still links to stays put, and "
                   + "the result says which stayed and why.",
        parameters: [
            "course": courseHelp,
            "section": sectionHelp,
            "pages": pagesHelp("unpublish"),
            "onOrAfter": onOrAfterHelp,
            "before": beforeHelp,
        ],
        required: ["course", "section"],
        readOnly: false,
        needsApproval: false
    )

    // MARK: - Preview and undo

    private static let rebuildPreviewTool: AssistToolDefinition = AssistToolDefinition(
        name: "rebuild_preview",
        description: "TEACHERS SAY: \"preview the site\", \"show me the preview\", \"start the preview\", "
                   + "\"open the preview\", \"rebuild the preview\", \"refresh what I'm looking at\", "
                   + "\"update the preview\", \"build it again\". Build a section's preview and put it on "
                   + "screen, without changing any page.",
        parameters: [
            "course": courseHelp,
            "section": sectionHelp,
        ],
        required: ["course", "section"],
        readOnly: false,
        needsApproval: false
    )

    private static let undoLastChangeTool: AssistToolDefinition = AssistToolDefinition(
        name: "undo_last_change",
        description: "TEACHERS SAY: \"undo that\", \"put it back\", \"that was wrong, revert it\", \"never "
                   + "mind, undo\". Take back the most recent change this conversation made — the fix for "
                   + "publishing the wrong class in a hurry.",
        parameters: [:],
        required: [],
        readOnly: false,
        needsApproval: false
    )

    // MARK: - The one act that asks for a button

    private static let deploySectionTool: AssistToolDefinition = AssistToolDefinition(
        name: "deploy_section",
        description: "TEACHERS SAY: \"deploy the site\", \"put it online\", \"push it live\", \"send it to "
                   + "the website\", \"make it live for students\", \"upload the site\". Put a section's "
                   + "website where students can actually reach it.",
        parameters: [
            "course": courseHelp,
            "section": sectionHelp,
        ],
        required: ["course", "section"],
        readOnly: false,
        // Deploying is the one act that puts something in front of students
        // immediately and that Plantoir cannot undo for them.
        needsApproval: true
    )

    // MARK: - Deploying later

    private static let planScheduledDeployTool: AssistToolDefinition = AssistToolDefinition(
        name: "plan_scheduled_deploy",
        description: "TEACHERS SAY: \"what happens if I schedule it for 6:30?\", \"check before you set "
                   + "that up\". Work out what scheduling a deploy would mean, scheduling nothing.",
        parameters: [
            "course": courseHelp,
            "section": sectionHelp,
            "when": whenHelp,
            "classes": AssistSchemaProperty(
                kind: .string,
                description: "The class pages this deploy is meant to publish, separated by semicolons. "
                           + "Checked for whether they are published yet."
            ),
        ],
        required: ["course", "section", "when"],
        readOnly: true,
        needsApproval: false
    )

    private static let scheduleDeployTool: AssistToolDefinition = AssistToolDefinition(
        name: "schedule_deploy",
        description: "TEACHERS SAY: \"deploy tomorrow's class at 6:30 AM\", \"put it live before school\", "
                   + "\"send it out at 7am\", \"schedule the deploy for Monday morning\". Ask this computer "
                   + "to deploy a section at a set time.",
        parameters: [
            "course": courseHelp,
            "section": sectionHelp,
            "when": whenHelp,
        ],
        required: ["course", "section", "when"],
        readOnly: false,
        // A deploy that runs while nobody is watching is still a deploy.
        needsApproval: true
    )

    private static let cancelScheduledDeployTool: AssistToolDefinition = AssistToolDefinition(
        name: "cancel_scheduled_deploy",
        description: "TEACHERS SAY: \"cancel that scheduled deploy\", \"don't send it in the morning after "
                   + "all\", \"call it off\". Call off a deploy that was scheduled for a section.",
        parameters: [
            "course": courseHelp,
            "section": sectionHelp,
        ],
        required: ["course", "section"],
        readOnly: false,
        needsApproval: false
    )

    // MARK: - When this class meets
    //
    // Asked once, kept, and read back with WHERE IT CAME FROM. A teacher
    // answers "when does this class meet?" by finding a spreadsheet, working
    // out which column is their block and reading it out; without somewhere to
    // put that answer, every conversation asks again. Reading it back names the
    // source so a stale answer can be recognised and replaced.

    private static let readRememberedTimetableTool: AssistToolDefinition = AssistToolDefinition(
        name: "read_remembered_timetable",
        description: "TEACHERS SAY: \"when does this class meet?\", \"what dates do you have for us?\", "
                   + "\"do you know our timetable?\", \"how many class days are left?\". Read back the class "
                   + "dates recorded for a section, and where the teacher said they came from, changing "
                   + "nothing.",
        parameters: [
            "course": courseHelp,
            "section": sectionHelp,
        ],
        required: ["course", "section"],
        readOnly: true,
        needsApproval: false
    )

    /// Semicolons for the same reason the page lists use them, and because one
    /// separator on this surface is easier to get right than two.
    private static let datesHelp: AssistSchemaProperty = AssistSchemaProperty(
        kind: .string,
        description: "Every day this class meets, as YYYY-MM-DD, separated by semicolons — for example "
                   + "\"2026-09-08; 2026-09-10; 2026-09-14\". Give the dates themselves; this tool does not "
                   + "open timetable files or work dates out from a pattern."
    )

    private static let timetableSourceHelp: AssistSchemaProperty = AssistSchemaProperty(
        kind: .string,
        description: "Where the dates came from, in the teacher's own words — for example "
                   + "\"timetable.xlsx, block H\" or \"typed in by hand\". Read back later, so a stale "
                   + "answer can be recognised. Leave empty if they did not say."
    )

    private static let planRememberTimetableTool: AssistToolDefinition = AssistToolDefinition(
        name: "plan_remember_timetable",
        description: "Work out what recording these class dates would do, WITHOUT changing anything. Says "
                   + "how many days it would remember, the first and the last, and what it would replace.",
        parameters: [
            "course": courseHelp,
            "section": sectionHelp,
            "dates": datesHelp,
            "source": timetableSourceHelp,
        ],
        required: ["course", "section", "dates"],
        readOnly: true,
        needsApproval: false
    )

    private static let rememberTimetableTool: AssistToolDefinition = AssistToolDefinition(
        name: "remember_timetable",
        description: "TEACHERS SAY: \"here are the days we meet\", \"remember our timetable\", \"these are "
                   + "our class dates\", \"save these dates\". Write down the days a section meets, so "
                   + "nothing has to ask for them again. Changes no page.",
        parameters: [
            "course": courseHelp,
            "section": sectionHelp,
            "dates": datesHelp,
            "source": timetableSourceHelp,
        ],
        required: ["course", "section", "dates"],
        readOnly: false,
        // Writes a note inside the course folder, nothing a student can see,
        // and recording the right dates over the wrong ones is the whole cure.
        needsApproval: false
    )

    // MARK: - The page for the next class

    private static let planAddNextClassTool: AssistToolDefinition = AssistToolDefinition(
        name: "plan_add_next_class",
        description: "TEACHERS SAY: \"what would the next class page be?\", \"which day comes next?\", "
                   + "\"show me before you add it\". Work out which page adding the next class would create "
                   + "and which day it would fall on, WITHOUT changing anything.",
        parameters: [
            "course": courseHelp,
            "section": sectionHelp,
        ],
        required: ["course", "section"],
        readOnly: true,
        needsApproval: false
    )

    private static let planReDateClassesTool: AssistToolDefinition = AssistToolDefinition(
        name: "plan_re_date_classes",
        description: "Work out what re-dating a whole section onto its recorded class dates would do, "
                   + "and change nothing. Shows every page that would move and why.",
        parameters: [
            "course": courseHelp,
            "section": sectionHelp,
        ],
        required: ["course", "section"],
        readOnly: true,
        needsApproval: false
    )

    private static let reDateClassesTool: AssistToolDefinition = AssistToolDefinition(
        name: "re_date_classes",
        description: "TEACHERS SAY: \"re-date my classes\", \"roll this section over to a new year\", "
                   + "\"put my classes on this year's dates\". Re-date every class in a section onto the "
                   + "class dates on file, by POSITION — the first class takes the first date — and move "
                   + "the pages each class uses onto that class's day with it. Pages this section's Key "
                   + "Links points at move to the first day of class. Curriculum pages are left alone, "
                   + "because Plantoir dates those itself on every build.",
        parameters: [
            "course": courseHelp,
            "section": sectionHelp,
        ],
        required: ["course", "section"],
        readOnly: false,
        // Not a deploy — nothing reaches students — but it rewrites the date
        // on every page in the section, so it goes through the plan gate like
        // every other write and is undoable in one step.
        needsApproval: false
    )

    private static let addNextClassTool: AssistToolDefinition = AssistToolDefinition(
        name: "add_next_class",
        description: "TEACHERS SAY: \"add an entry for the next class\", \"add tomorrow's class page\", "
                   + "\"start the next class\", \"add the next class\", \"make a page for our next class\", "
                   + "\"set up next day's lesson\". Create the next class page in a section: it continues "
                   + "the unit the last class was in, and takes its date from the section's remembered "
                   + "timetable. Work out no numbers and no dates yourself — this tool does both. It starts "
                   + "unpublished, so students see nothing until the teacher publishes it.",
        parameters: [
            "course": courseHelp,
            "section": sectionHelp,
        ],
        required: ["course", "section"],
        readOnly: false,
        // Creates one unpublished page and writes over nothing, so it happens
        // when asked. Only deploying — the one act that reaches students and
        // that Plantoir cannot undo for them — waits for a button.
        needsApproval: false
    )

    // MARK: - Pointing a page at the curriculum
    //
    // The tools find the expectations and read out their FULL WORDING; which
    // ones fit a lesson is a judgement about meaning, and that judgement is
    // left to whoever is driving. Code cannot make it, and a tool that guessed
    // would put a teacher's name to a claim they never agreed to.

    private static let pageTitleHelp: AssistSchemaProperty = AssistSchemaProperty(
        kind: .string, description: "The page title, for example \"Movement Concepts\"."
    )

    private static let codesHelp: AssistSchemaProperty = AssistSchemaProperty(
        kind: .string,
        description: "The expectation codes to add, separated by commas — for example \"A1.1, A2.2\"."
    )

    private static let listCurriculumExpectationsTool: AssistToolDefinition = AssistToolDefinition(
        name: "list_curriculum_expectations",
        description: "List this course's curriculum expectations with their FULL WORDING, changing nothing. "
                   + "Call this when a teacher asks you to point a page at the expectations it covers. Read "
                   + "the page first, then read these, then decide which genuinely fit — that judgement is "
                   + "yours to make and the tools cannot make it. Propose the codes to the teacher with your "
                   + "reasons and let them choose; do not add expectations they have not agreed to.",
        parameters: [
            "course": courseHelp,
            "section": sectionHelp,
            "matching": AssistSchemaProperty(
                kind: .string,
                description: "Only list expectations whose code or wording contains this. Leave empty for all."
            ),
        ],
        required: ["course", "section"],
        readOnly: true,
        needsApproval: false
    )

    private static let planCurriculumMentionsTool: AssistToolDefinition = AssistToolDefinition(
        name: "plan_curriculum_mentions",
        description: "Work out what adding curriculum transclusions to a page would do, changing nothing. "
                   + "Show the teacher what it says — it quotes each expectation's wording so they can tell "
                   + "whether it fits their lesson without looking it up — then wait for them to agree.",
        parameters: [
            "course": courseHelp,
            "section": sectionHelp,
            "page": pageTitleHelp,
            "codes": codesHelp,
        ],
        required: ["course", "section", "page", "codes"],
        readOnly: true,
        needsApproval: false
    )

    private static let addCurriculumMentionsTool: AssistToolDefinition = AssistToolDefinition(
        name: "add_curriculum_mentions",
        description: "Add transclusions of curriculum expectations to a page, inside the curriculum markers "
                   + "so a course installed without curriculum still builds. Call plan_curriculum_mentions "
                   + "FIRST and get the teacher's agreement to the specific codes. Changes nothing else on "
                   + "the page, and changes no page's visibility. The course is backed up first.",
        parameters: [
            "course": courseHelp,
            "section": sectionHelp,
            "page": pageTitleHelp,
            "codes": codesHelp,
        ],
        required: ["course", "section", "page", "codes"],
        readOnly: false,
        // Backed up before it writes and taken straight back by
        // `undo_last_change`, so it happens when asked. Only deploying — the
        // one act that reaches students and that Plantoir cannot undo for
        // them — waits for a button.
        needsApproval: false
    )

}
