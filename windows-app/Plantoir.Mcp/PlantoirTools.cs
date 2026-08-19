using System.ComponentModel;
using System.Text;
using System.Text.Json.Nodes;
using ModelContextProtocol;
using ModelContextProtocol.Protocol;
using ModelContextProtocol.Server;
using Plantoir.Core.Assist;
using Plantoir.Core.Models;

namespace Plantoir.Mcp;

/// <summary>
/// The tools an assistant may call.
///
/// Four rules shape this surface. The first three are measured (research/ai-assist/HISTORY.md
/// has the numbers); the fourth came from watching a real teacher use it.
///
/// 1. **Nothing destructive exists.** No delete, no archive, no rename. In
///    testing the model reliably declined "delete the Unit 1 folder" — not
///    from judgement, but because it had no tool for it. Absence is the
///    strongest guardrail available, so it is the one relied on.
///
/// 2. **Publishing and unpublishing are separate tools, not a flag.** The one
///    genuinely dangerous failure observed was polarity inversion: asked to
///    HIDE a page, the model called publish with "include everything it links
///    to" set. A boolean is a coin flip under pressure; a verb is not.
///
/// 3. **Every write has a matching plan_ tool that changes nothing**, and the
///    plan is written to be read aloud to the teacher.
///
/// 4. **The write tools take a LIST, and take any page.** Single-page tools
///    turned one logical change into 26 deploys, and could not express "hide
///    these classes but leave the safety contract up" at all — a shared page
///    linked from both a protected class and a unpublished one is the normal shape
///    of a course.
///
/// Instance methods get a fresh instance per call, so the workspace comes from
/// the injected singleton rather than any state kept here.
/// </summary>
[McpServerToolType]
public sealed class PlantoirTools(AssistWorkspace workspace)
{
    // ---- Looking around --------------------------------------------------

    [McpServerTool(Name = "list_courses", Title = "List courses", ReadOnly = true, Destructive = false)]
    [Description("List the teacher's courses in this working folder: code, name, sections, and where each one publishes to. " +
                 "Call this first when the teacher mentions a course but you are not certain of its exact code.")]
    public string ListCourses()
    {
        var courses = workspace.Courses();
        if (courses.Count == 0) return "This working folder has no courses yet.";

        var text = new StringBuilder();
        foreach (var course in courses)
        {
            var configuration = course.Configuration;
            string destination = configuration.DeploysToLocalFolder ? "a folder on this computer"
                : configuration.DeploysToCloudflare ? "Cloudflare Pages" : "Netlify";
            text.AppendLine($"{course.Code} — {configuration.CourseName}");
            text.AppendLine($"  sections: {string.Join(", ", course.SectionNumbers)}");
            text.AppendLine($"  publishes to: {destination}");
        }
        return text.ToString().TrimEnd();
    }

    /// <summary>
    /// A course runs to a couple of hundred pages — the sample course alone
    /// has 198, most of them curriculum expectations nobody is asking about.
    /// Returning all of them buries the answer and, for a small local model,
    /// fills the context before the question is even considered.
    /// </summary>
    private const int MostPagesListed = 60;

    [McpServerTool(Name = "list_pages", Title = "List pages in a section", ReadOnly = true, Destructive = false)]
    [Description("List the pages in one section of a course, as paths relative to the working folder. " +
                 "Use this to find the exact title of a page before acting on it. " +
                 "Courses hold hundreds of pages, so pass `matching` to narrow the list — for example \"Unit 2\" " +
                 "for that unit's classes.")]
    public CallToolResult ListPages(
        [Description("The course code, for example ICS3U.")] string course,
        [Description("The section number, for example 1.")] int section,
        [Description("Only list pages whose path contains this text. Leave empty to list everything.")]
        string matching = "")
        => Guarded(() =>
        {
            var found = workspace.Course(course);
            int number = workspace.Section(found, section);
            var pages = workspace.Pages(found, number);

            string filter = matching.Trim();
            if (filter.Length > 0)
                pages = pages.Where(p => p.Contains(filter, StringComparison.OrdinalIgnoreCase)).ToList();

            string where = $"{found.Code} Section {number}";
            if (pages.Count == 0)
                return Answering($"Nothing matched in {where}.",
                                 filter.Length > 0
                                     ? $"No page in {where} matches “{filter}”."
                                     : $"{where} has no pages.");

            var shown = pages.Take(MostPagesListed).ToList();
            var text = new StringBuilder(string.Join("\n", shown));
            if (pages.Count > shown.Count)
                text.Append($"\n\n…and {pages.Count - shown.Count} more of {pages.Count}. " +
                            "Pass `matching` to narrow this down.");

            // A list of paths is the MODEL's answer to "which page did they
            // mean". What the teacher asked has a number for an answer.
            string word = pages.Count == 1 ? "page" : "pages";
            return Answering($"Found {pages.Count} {word} in {where}.", text.ToString());
        });

    [McpServerTool(Name = "read_page", Title = "Read a page", ReadOnly = true, Destructive = false)]
    [Description("Read one page's Markdown, including its frontmatter. Use this to see what a class page's agenda links to, " +
                 "and to see which key governs the page: a page under section1/ carries `publish:`, while a course-level " +
                 "page such as a Concept carries `publishForSection1:` and `publishForSection2:` — one flag per section. " +
                 "Older courses carry `draft:` and `draftSection1:` instead, which mean the OPPOSITE — `draft: true` is a " +
                 "page students cannot see. Both are understood; report what you find without rewriting it yourself.")]
    public CallToolResult ReadPage(
        [Description("The course code, for example ICS3U.")] string course,
        [Description("The section number, for example 1.")] int section,
        [Description("The page title as it appears in the sidebar, for example \"Unit 2, Day 3\".")] string page)
        => Guarded(() =>
        {
            var found = workspace.Course(course);
            int number = workspace.Section(found, section);
            string path = workspace.Page(found, number, page);

            // The page itself is for the MODEL, which was asked a question
            // about it. A lesson's whole Markdown in the chat window answers
            // nothing the teacher asked and buries everything said before it.
            return Answering($"Read “{Path.GetFileNameWithoutExtension(path)}”.",
                             workspace.ReadPage(found, number, page));
        });

    [McpServerTool(Name = "deploy_section", Title = "Deploy a section's website",
                   Destructive = false, Idempotent = true)]
    [Description("TEACHERS SAY: \"deploy the site\", \"put it online\", \"push it live\", \"send it to the website\", " +
                 "\"make it live for students\", \"upload the site\". " +
                 "Put a section's website where students can actually reach it. This is the one thing that changes " +
                 "what students see, so treat it as a big step. " +
                 "\n\nBEFORE calling this, tell the teacher plainly to look over the preview in Plantoir first, and " +
                 "wait for them to say they have. Publishing a page only rebuilds their preview; this is what makes " +
                 "it real. If they have not looked, say so and offer to wait rather than going ahead. " +
                 "\n\nThis takes several minutes.")]
    public async Task<string> DeploySection(
        [Description("The course code, for example ICS3U.")] string course,
        [Description("The section number, for example 1.")] int section,
        IProgress<ProgressNotificationValue> progress,
        CancellationToken cancellation)
    {
        try
        {
            var result = await workspace.Deploy(course, section, Relay(progress), cancellation);
            return result.Message;
        }
        catch (AssistRefusal refusal) { return refusal.Message; }
        catch (OperationCanceledException) { return "The deploy was stopped before it finished."; }
    }

    [McpServerTool(Name = "explain_publishing", Title = "Explain what publishing means here",
                   Destructive = false, Idempotent = true)]
    [Description("Call this FIRST, before doing anything else with a section. It returns a short explanation of " +
                 "what publishing and deploying mean in Plantoir — say it to the teacher word for word. " +
                 "It only returns the explanation the first time for a given section; after that it says so and " +
                 "you should get straight on with what they asked. Never re-explain a section you have been told " +
                 "is already covered.")]
    public string ExplainPublishing(
        [Description("The course code, for example ICS3U.")] string course,
        [Description("The section number, for example 1.")] int section)
        => Guarded(() =>
        {
            var found = workspace.Course(course);
            int number = workspace.Section(found, section);
            if (Briefing.AlreadyExplained(workspace.FolderPath, found.Code, number))
                return $"{found.Code} Section {number} has had this explained already. " +
                       "Don’t repeat it — carry on with what the teacher asked.";

            // The SAME answer a deploy gives, so the briefing cannot promise
            // one destination while the deploy uses another — and a folder is
            // named rather than described, since "the folder you publish into"
            // tells a teacher with two courses nothing at all.
            Briefing.MarkExplained(workspace.FolderPath, found.Code, number);
            return Briefing.Words(found.Code, number, AssistWorkspace.DestinationOf(found));
        });

    /// <summary>How many of each kind to name before summarising.</summary>
    private const int MostListed = 15;

    [McpServerTool(Name = "check_section", Title = "Check what students would see",
                   ReadOnly = true, Destructive = false)]
    [Description("TEACHERS SAY: \"what do students see right now?\", \"what would students see in this section right now?\", " +
                 "\"is anything broken?\", \"what's live?\". " +
                 "Check a section's website as students would meet it, changing nothing. Reports two things that " +
                 "publishing and unpublishing tools cannot see for themselves: links on visible pages that lead to a hidden " +
                 "page (students click and find nothing), and pages nothing links to — which are still published and " +
                 "still listed in the site's explorer, so students can see them even though no class points there. " +
                 "Use this before a term starts, and after any bulk change.")]
    public string CheckSection(
        [Description("The course code, for example ICS3U.")] string course,
        [Description("The section number, for example 1.")] int section)
        => Guarded(() =>
        {
            var found = workspace.Course(course);
            int number = workspace.Section(found, section);
            var (graph, isHidden) = workspace.Inspect(found, number);

            var dangling = graph.DanglingLinks(isHidden);

            // A class page reached from nothing is a class page, not an
            // orphan — see LinkGraph.Unreferenced for what leaving this out
            // did to a real course.
            var classPages = workspace.ClassPages(found, number)
                .Select(Path.GetFullPath)
                .ToHashSet(StringComparer.OrdinalIgnoreCase);
            var orphans = graph.Unreferenced(classPages: classPages)
                .Where(p => !isHidden(p)).ToList();

            int visible = graph.Pages.Count(p => !isHidden(p));
            string pageWord = visible == 1 ? "page" : "pages";

            var paragraphs = new List<string>
            {
                $"Students would see {visible} {pageWord} in {found.Code} Section {number}."
            };

            if (dangling.Count == 0)
            {
                paragraphs.Add("None of the visible pages link to unpublished pages, ensuring " +
                               "that all links are functional and point to published content.");
            }
            else
            {
                var lines = new List<string>();
                string word = dangling.Count == 1 ? "link" : "links";
                lines.Add($"{dangling.Count} {word} would take a student to a page that isn’t there:");
                foreach (var link in dangling.Take(MostListed))
                    lines.Add($"• {workspace.Relative(link.From)}  →  {Path.GetFileNameWithoutExtension(link.To)}  (hidden)");
                if (dangling.Count > MostListed)
                    lines.Add($"…and {dangling.Count - MostListed} more.");
                lines.Add("Either publish the page each one points at, or take the link off the page that points at it.");
                paragraphs.Add(string.Join("\n", lines));
            }

            if (orphans.Count > 0)
            {
                var lines = new List<string>();
                string word = orphans.Count == 1 ? "page is" : "pages are";
                lines.Add($"{orphans.Count} visible {word} linked from nowhere. Students can still reach these through the site’s " +
                          "explorer, and no publish or hide rule that follows links will ever touch them:");
                foreach (string page in orphans.Take(MostListed))
                    lines.Add("• " + workspace.Relative(page));
                if (orphans.Count > MostListed)
                    lines.Add($"…and {orphans.Count - MostListed} more.");
                paragraphs.Add(string.Join("\n", lines));
            }

            // What the preview is DOING decides which of three things is worth
            // saying — and for one of them, that nothing is.
            //
            // Read off the LEASE FILES, not PreviewLeases. That list is an
            // in-memory static belonging to the app, and this code runs in
            // plantoir-mcp, a separate process where it is permanently empty —
            // so a teacher who had just pressed Preview was told "Nothing is
            // being previewed at the moment", every time, whatever was on
            // screen. The app already writes the cross-process leases for
            // precisely this (SectionDetailView: "an assistant is a separate
            // process and cannot see the in-memory lease"); nothing here was
            // reading them.
            //
            // The build lease is dropped the moment the server answers, so
            // build-then-preview reads as two states rather than one, which is
            // the distinction the sentences turn on.
            var doing = WorkLease.HeldBy(workspace.FolderPath, found.Code);
            string these = visible == 1 ? "this page" : $"these {visible} pages";

            if (doing.Contains(WorkLease.Building))
            {
                paragraphs.Add($"The preview is building now, and will show {these} when it finishes.");
            }
            else if (!doing.Contains(WorkLease.Previewing))
            {
                paragraphs.Add("Nothing is being previewed at the moment. Say “Preview” if you would like to look the section over.");
            }
            // Nothing when a preview is showing: they are looking at it.

            return string.Join("\n\n", paragraphs);
        });

    // ---- Rolling a course onto a real timetable --------------------------

    private const string TimetableHelp =
        "A link to the timetable spreadsheet, or the path to a CSV of it on this computer. " +
        "A Google Sheets link works if the sheet is shared so anyone with the link can view it.";

    private const string BlockHelp =
        "The block or section letter the teacher is timetabled in, for example F.";

    private const string WhenHelp =
        "When to deploy, as YYYY-MM-DD HH:MM in 24-hour time — for example \"2026-09-09 06:30\".";

    [McpServerTool(Name = "plan_scheduled_deploy", Title = "Plan a deploy for later",
                   ReadOnly = true, Destructive = false)]
    [Description("TEACHERS SAY: \"what happens if I schedule it for 6:30?\", \"check before you set that up\". " +
                 "Work out what scheduling a deploy would mean, scheduling nothing. Use this for \"deploy " +
                 "tomorrow's class at 6:30 AM\". Pass the class pages the teacher has in mind as `classes` and " +
                 "it will check whether they are actually PUBLISHED — a deploy that runs perfectly and ships a " +
                 "site without tomorrow's class is the failure worth catching while somebody is awake. " +
                 "Read the whole thing to the teacher, including what has to be true of their computer.")]
    public CallToolResult PlanScheduledDeploy(
        [Description("The course code, for example ICS3U.")] string course,
        [Description("The section number, for example 1.")] int section,
        [Description(WhenHelp)] string when,
        [Description("The class pages this deploy is meant to publish, separated by commas. Checked for whether they are published yet.")]
        string classes = "")
        => Guarded(() =>
        {
            if (!DateTime.TryParse(when, out var moment))
                throw new AssistRefusal($"“{when}” isn't a time I can read. Use YYYY-MM-DD HH:MM.");
            return Proposing(workspace.PlanScheduledDeploy(course, section, moment,
                classes.Split(',', StringSplitOptions.RemoveEmptyEntries | StringSplitOptions.TrimEntries))
                .Describe());
        });

    [McpServerTool(Name = "schedule_deploy", Title = "Deploy at a set time",
                   Destructive = false, Idempotent = true)]
    [Description("TEACHERS SAY: \"deploy tomorrow's class at 6:30 AM\", \"put it live before school\", " +
                 "\"send it out at 7am\", \"schedule the deploy for Monday morning\". " +
                 "Ask this computer to deploy a section at a set time. Call plan_scheduled_deploy FIRST and " +
                 "read it out — especially that the computer must be ON and AWAKE at that moment, plugged in " +
                 "if it is a laptop, with the lid open. Plantoir does not wake it. Replaces any deploy already " +
                 "scheduled for the same section. Use cancel_scheduled_deploy to call it off.")]
    public CallToolResult ScheduleDeploy(
        [Description("The course code, for example ICS3U.")] string course,
        [Description("The section number, for example 1.")] int section,
        [Description(WhenHelp)] string when)
        => Guarded(() =>
        {
            if (!DateTime.TryParse(when, out var moment))
                throw new AssistRefusal($"“{when}” isn't a time I can read. Use YYYY-MM-DD HH:MM.");

            var plan = workspace.PlanScheduledDeploy(course, section, moment);
            var deployArgs = DeployCommand.Arguments(plan.CourseCode, plan.SectionNumber, workspace.Course(plan.CourseCode).Configuration);
            if (TaskScheduling.Schedule(plan.TaskName, workspace.FolderPath,
                                        plan.CourseCode, plan.SectionNumber, moment, deployArgs) is { } problem)
                throw new AssistRefusal($"Nothing was scheduled. {problem}");

            // The caution about the computer being awake is on the card the
            // teacher agreed to, before this ran. Repeating it afterwards is
            // the assistant explaining itself to somebody who just read it.
            string summary = $"Scheduled: {plan.CourseCode} Section {plan.SectionNumber} deploys to " +
                             $"{plan.Destination} at {moment:dddd d MMMM, h:mm tt}.";
            return Answering(summary, summary + "\n\n" +
                             "Remember this computer has to be on and awake then — plugged in if it is a laptop, " +
                             "lid open. Plantoir cannot wake it up. Say the word and I'll cancel it.");
        });

    [McpServerTool(Name = "cancel_scheduled_deploy", Title = "Call off a scheduled deploy",
                   Destructive = false, Idempotent = true)]
    [Description("TEACHERS SAY: \"cancel that scheduled deploy\", \"don't send it in the morning after all\", " +
                 "\"call it off\". " +
                 "Call off a deploy that was scheduled for a section. Safe to call when nothing is scheduled.")]
    public CallToolResult CancelScheduledDeploy(
        [Description("The course code, for example ICS3U.")] string course,
        [Description("The section number, for example 1.")] int section)
        => Guarded(() =>
        {
            var found = workspace.Course(course);
            int number = workspace.Section(found, section);
            string name = $"Plantoir deploy {found.Code} section {number}";

            if (!TaskScheduling.Exists(name))
                return Answering($"There is no deploy scheduled for {found.Code} Section {number}.",
                                 $"There is no deploy scheduled for {found.Code} Section {number}, " +
                                 "so there was nothing to call off.");

            return TaskScheduling.Cancel(name) is { } problem
                ? Answering($"That could not be cancelled: {problem}")
                : Answering($"Cancelled the scheduled deploy for {found.Code} Section {number}.");
        });

    [McpServerTool(Name = "list_curriculum_expectations", Title = "List curriculum expectations",
                   ReadOnly = true, Destructive = false)]
    [Description("List this course's curriculum expectations with their FULL WORDING, changing nothing. " +
                 "Call this when a teacher asks you to point a page at the expectations it covers. Read the " +
                 "page first, then read these, then decide which genuinely fit — that judgement is yours to " +
                 "make and the tools cannot make it. Propose the codes to the teacher with your reasons and " +
                 "let them choose; do not add expectations they have not agreed to.")]
    public string ListCurriculumExpectations(
        [Description("The course code, for example ADA1O.")] string course,
        [Description("The section number, for example 1.")] int section,
        [Description("Only list expectations whose code or wording contains this. Leave empty for all.")]
        string matching = "")
        => Guarded(() =>
        {
            var found = workspace.Course(course);
            int number = workspace.Section(found, section);
            var expectations = workspace.CurriculumExpectations(found, number);

            string filter = matching.Trim();
            if (filter.Length > 0)
                expectations = expectations
                    .Where(e => e.Code.Contains(filter, StringComparison.OrdinalIgnoreCase) ||
                                e.Text.Contains(filter, StringComparison.OrdinalIgnoreCase))
                    .ToList();

            if (expectations.Count == 0)
                return filter.Length > 0
                    ? $"No curriculum expectation in {found.Code} matches “{filter}”."
                    : $"{found.Code} has no curriculum expectations — this course was installed without them.";

            var text = new StringBuilder();
            foreach (var expectation in expectations)
                text.AppendLine($"{expectation.Code}  {expectation.Text}");
            return text.ToString().TrimEnd();
        });

    [McpServerTool(Name = "plan_curriculum_mentions", Title = "Plan pointing a page at the curriculum",
                   ReadOnly = true, Destructive = false)]
    [Description("Work out what adding curriculum transclusions to a page would do, changing nothing. " +
                 "Show the teacher what it says — it quotes each expectation's wording so they can tell " +
                 "whether it fits their lesson without looking it up — then wait for them to agree.")]
    public string PlanCurriculumMentions(
        [Description("The course code, for example ADA1O.")] string course,
        [Description("The section number, for example 1.")] int section,
        [Description("The page title, for example \"Movement Concepts\".")] string page,
        [Description("The expectation codes to add, separated by commas — for example \"A1.1, A2.2\".")]
        string codes)
        => Guarded(() => workspace.PlanCurriculumMentions(course, section, page,
                             codes.Split(',', StringSplitOptions.RemoveEmptyEntries | StringSplitOptions.TrimEntries))
                         .Describe());

    [McpServerTool(Name = "add_curriculum_mentions", Title = "Point a page at curriculum expectations",
                   Destructive = false, Idempotent = true)]
    [Description("Add transclusions of curriculum expectations to a page, inside the curriculum markers so a " +
                 "course installed without curriculum still builds. Call plan_curriculum_mentions FIRST and get " +
                 "the teacher's agreement to the specific codes. Changes nothing else on the page, and changes " +
                 "no page's visibility. The course is backed up first.")]
    public string AddCurriculumMentions(
        [Description("The course code, for example ADA1O.")] string course,
        [Description("The section number, for example 1.")] int section,
        [Description("The page title, for example \"Movement Concepts\".")] string page,
        [Description("The expectation codes to add, separated by commas — for example \"A1.1, A2.2\".")]
        string codes)
        => Guarded(() =>
        {
            var plan = workspace.PlanCurriculumMentions(course, section, page,
                codes.Split(',', StringSplitOptions.RemoveEmptyEntries | StringSplitOptions.TrimEntries));
            return workspace.ApplyCurriculumMentions(plan).Message;
        });

    private const string UnitHelp = "The unit number these classes belong to, for example 2.";

    [McpServerTool(Name = "plan_make_room_for_classes", Title = "Plan making room for classes",
                   ReadOnly = true, Destructive = false)]
    [Description("Work out what would happen if a class were inserted part-way through a unit, changing nothing. " +
                 "Use this for \"duplicate Unit 2, Day 2 and make it the third class, pushing everything back\", " +
                 "or \"give this unit another day\". Later days of the SAME unit are renamed; every class after " +
                 "the insertion point, later units included, moves onto a later day the class actually meets. " +
                 "\n\nThis is the most far-reaching change there is — it renames pages other pages link to — so " +
                 "read the whole plan to the teacher, word for word, and wait. The link count especially: they " +
                 "cannot check that themselves without opening every page in the course.")]
    public string PlanMakeRoomForClasses(
        [Description("The course code, for example ICS3U.")] string course,
        [Description("The section number, for example 1.")] int section,
        [Description(UnitHelp)] int unit,
        [Description("The day number the new class takes. Existing days from here on are renumbered.")] int atDay,
        [Description("How many classes to make room for. 1 unless the teacher asked for more.")] int howMany = 1)
        => Guarded(() => workspace.PlanInsertClasses(course, section, unit, atDay, howMany).Describe());

    [McpServerTool(Name = "make_room_for_classes", Title = "Make room for classes",
                   Destructive = false, Idempotent = false)]
    [Description("Insert one or more classes part-way through a unit: rename the later days of that unit, " +
                 "update every link that pointed at them, move the classes that follow onto later class days, " +
                 "and create the new pages unpublished. " +
                 "\n\nCall plan_make_room_for_classes FIRST and show the teacher what it said. The course is " +
                 "backed up first and undo_last_change reverses the whole thing. Afterwards, tell them to look " +
                 "the section over in Plantoir before deploying — many pages moved at once.")]
    public string MakeRoomForClasses(
        [Description("The course code, for example ICS3U.")] string course,
        [Description("The section number, for example 1.")] int section,
        [Description(UnitHelp)] int unit,
        [Description("The day number the new class takes. Existing days from here on are renumbered.")] int atDay,
        [Description("How many classes to make room for. 1 unless the teacher asked for more.")] int howMany = 1)
        => Guarded(() =>
        {
            var plan = workspace.PlanInsertClasses(course, section, unit, atDay, howMany);
            return workspace.ApplyInsertClasses(plan).Message;
        });

    [McpServerTool(Name = "plan_add_classes", Title = "Plan adding class pages",
                   ReadOnly = true, Destructive = false)]
    [Description("Work out which class pages would be created for a unit and what dates they would fall on, " +
                 "changing nothing. Use this for \"add placeholder pages for the next unit, seven days\" or " +
                 "\"add Unit 2 Days 1 through 10\". Dates come from the section's remembered timetable, skipping " +
                 "days already taken by an existing class, so the new unit follows on from the work already there. " +
                 "Show the teacher what it says, word for word, then wait.")]
    public string PlanAddClasses(
        [Description("The course code, for example ICS3U.")] string course,
        [Description("The section number, for example 1.")] int section,
        [Description(UnitHelp)] int unit,
        [Description("How many class pages to add.")] int howMany,
        [Description("The day number to start at within the unit. 1 unless the earlier days already exist.")]
        int firstDay = 1)
        => Guarded(() => workspace.PlanAddClasses(course, section, unit, firstDay, howMany).Describe());

    [McpServerTool(Name = "add_classes", Title = "Add class pages", Destructive = false, Idempotent = false)]
    [Description("Create the class pages for a unit, dated to the days the section actually meets. " +
                 "Call plan_add_classes FIRST and show the teacher what it said. " +
                 "\n\nThe pages are created UNPUBLISHED — empty skeletons for the teacher to write, which stay out " +
                 "of the site until they publish them. An existing page is never written over. The course is " +
                 "backed up first, and undo_last_change removes what this created.")]
    public string AddClasses(
        [Description("The course code, for example ICS3U.")] string course,
        [Description("The section number, for example 1.")] int section,
        [Description(UnitHelp)] int unit,
        [Description("How many class pages to add.")] int howMany,
        [Description("The day number to start at within the unit. 1 unless the earlier days already exist.")]
        int firstDay = 1)
        => Guarded(() =>
        {
            var plan = workspace.PlanAddClasses(course, section, unit, firstDay, howMany);
            return workspace.ApplyAddClasses(plan).Message;
        });

    [McpServerTool(Name = "plan_add_next_class", Title = "Plan adding the next class",
                   ReadOnly = true, Destructive = false)]
    [Description("Work out what the next class page would be called and what date it would land on, " +
                 "changing nothing. Use this for \"add the next class\" or \"start a new unit for the next class\". " +
                 "The title continues the highest unit's count; the date is the next unused day in the section's timetable.")]
    public CallToolResult PlanAddNextClass(
        [Description("The course code, for example ICS3U.")] string course,
        [Description("The section number, for example 1.")] int section,
        [Description("Pass \"next\" to start a new unit. Leave empty to continue the current unit.")]
        string unit = "",
        [Description("Pass a number to add that many days to the specified unit number. Leave 0 for a single class.")]
        int days = 0)
        => Guarded(() =>
        {
            var plan = workspace.PlanAddNextClass(course, section, unit, days > 0 ? days : null);
            return plan.ChangesNothing
                ? Answering("The next class page already exists.", plan.Describe())
                : Proposing(plan.Describe());
        });

    [McpServerTool(Name = "add_next_class", Title = "Add the next class page", Destructive = false, Idempotent = false)]
    [Description("Create the next class page, dated to the day the section next meets. " +
                 "Call plan_add_next_class FIRST and show the teacher what it said. " +
                 "The page starts UNPUBLISHED — an empty skeleton for the teacher to write, which stays out of the site " +
                 "until they publish it. An existing page is never written over.")]
    public CallToolResult AddNextClass(
        [Description("The course code, for example ICS3U.")] string course,
        [Description("The section number, for example 1.")] int section,
        [Description("Pass \"next\" to start a new unit. Leave empty to continue the current unit.")]
        string unit = "",
        [Description("Pass a number to add that many days to the specified unit number. Leave 0 for a single class.")]
        int days = 0)
        => Guarded(() =>
        {
            var plan = workspace.PlanAddNextClass(course, section, unit, days > 0 ? days : null);
            if (plan.ChangesNothing)
                return Answering("Nothing needed adding — that page already exists.",
                                 plan.Describe() + "\n\nNothing was created, because the page is already " +
                                 "there. A page with that name is never written over: it may be a lesson " +
                                 "written months ago.");

            var result = workspace.ApplyAddClasses(plan);
            if (!result.Succeeded) return Answering(result.Message);

            // The teacher asked for a page. Its name and its date are the
            // whole answer; how it was worked out is the model's half.
            var made = plan.Classes[0];
            return Answering($"Added {made.Title}, dated {made.Date:yyyy-MM-dd}.",
                             result.Message + "\n\n" + AssistWording.ACreatedPageCanBeTakenBack);
        });

    [McpServerTool(Name = "plan_remember_timetable", Title = "Plan remembering class dates",
                   ReadOnly = true, Destructive = false)]
    [Description("Work out what remembering a section's class dates would do, changing nothing. " +
                 "Dates are YYYY-MM-DD, separated by commas or spaces.")]
    public CallToolResult PlanRememberTimetable(
        [Description("The course code, for example ICS3U.")] string course,
        [Description("The section number, for example 1.")] int section,
        [Description("Every date this section meets, as YYYY-MM-DD, separated by commas.")] string dates,
        [Description("Where these came from, in the teacher's words — \"timetable.xlsx, block H\", \"typed in by hand\".")]
        string source = "the teacher")
        => Guarded(() =>
        {
            var found = workspace.Course(course);
            int number = workspace.Section(found, section);

            var parsed = new List<DateOnly>();
            var unreadable = new List<string>();
            foreach (string piece in dates.Split([',', ';', ' ', '\t', '\n', '\r'],
                                                 StringSplitOptions.RemoveEmptyEntries | StringSplitOptions.TrimEntries))
            {
                if (DateOnly.TryParse(piece, out var date)) parsed.Add(date);
                else unreadable.Add(piece);
            }

            if (unreadable.Count > 0)
                throw new AssistRefusal(
                    $"Nothing was recorded — {unreadable.Count} of those aren't dates I can read " +
                    $"({string.Join(", ", unreadable.Take(5))}). Give them as YYYY-MM-DD.");
            if (parsed.Count == 0)
                throw new AssistRefusal("Nothing was recorded — no dates were given.");

            parsed.Sort();
            return Proposing($"Would record {parsed.Count} class dates for {found.Code} Section {number}, " +
                             $"{parsed[0]:yyyy-MM-dd} to {parsed[^1]:yyyy-MM-dd}, from {source}.");
        });

    [McpServerTool(Name = "read_remembered_timetable", Title = "What dates this section meets",
                   ReadOnly = true, Destructive = false)]
    [Description("Read the class meeting dates Plantoir already knows for a section, changing nothing. " +
                 "CALL THIS FIRST whenever you need to know when a section's classes fall — before asking the " +
                 "teacher for a timetable, and before any tool that needs dates. It is remembered from the last " +
                 "time they gave one.")]
    public CallToolResult ReadRememberedTimetable(
        [Description("The course code, for example ICS3U.")] string course,
        [Description("The section number, for example 1.")] int section,
        [Description("Pass \"all\" to list every date on file.")] string scope = "",
        [Description("Pass \"yes\" to replace the recorded dates.")] string revise = "")
        => Guarded(() =>
        {
            var found = workspace.Course(course);
            int number = workspace.Section(found, section);
            string where = $"{found.Code} Section {number}";

            if (string.Equals(revise, "yes", StringComparison.OrdinalIgnoreCase))
            {
                return Answering($"Here you are — the dates for {where} are open for editing. {AssistWording.MayIAskForYourDates}");
            }

            var remembered = TimetableMemory.Read(workspace.FolderPath, found.Code, number);
            if (remembered is null || remembered.Dates.Count == 0)
                return Answering($"I don’t know when {where} meets yet. {AssistWording.MayIAskForYourDates}");

            if (string.Equals(scope, "all", StringComparison.OrdinalIgnoreCase))
            {
                var all = new StringBuilder($"Every date on file for {where}:");
                foreach (var date in remembered.Dates)
                    all.Append($"\n• {date:dddd}, {date:yyyy-MM-dd}");
                return Answering($"All {remembered.Dates.Count} dates for {where}.", all.ToString());
            }

            var classPages = workspace.ClassPages(found, number);
            var classByDate = new Dictionary<string, string>(StringComparer.OrdinalIgnoreCase);
            var existingClasses = new List<(string Title, DateOnly? Date)>();
            foreach (var cp in classPages)
            {
                string title = Path.GetFileNameWithoutExtension(cp);
                var dt = AssistWorkspace.DateOf(found, number, cp);
                existingClasses.Add((title, dt));
                if (dt is { } d)
                {
                    classByDate[d.ToString("yyyy-MM-dd")] = title;
                }
            }

            var today = DateOnly.FromDateTime(DateTime.Now);
            var firstDate = remembered.Dates[0];
            var lastDate = remembered.Dates[^1];
            var upcomingDates = new List<DateOnly>();
            var lines = new List<string>();

            if (today < firstDate)
            {
                for (int i = 0; i < remembered.Dates.Count && i < 3; i++)
                {
                    upcomingDates.Add(remembered.Dates[i]);
                }
                string countStr = upcomingDates.Count == 1 ? "first class is" : $"first {upcomingDates.Count} classes are";
                lines.Add($"The semester begins on {firstDate:dddd}, {firstDate:yyyy-MM-dd}. The {countStr}:");
            }
            else
            {
                foreach (var date in remembered.Dates)
                {
                    if (date >= today && upcomingDates.Count < 3)
                    {
                        upcomingDates.Add(date);
                    }
                }
                if (upcomingDates.Count == 0)
                {
                    lines.Add($"All {remembered.Dates.Count} scheduled classes for {where} have concluded (last class was on {lastDate:dddd}, {lastDate:yyyy-MM-dd}).");
                }
                else
                {
                    string countStr = upcomingDates.Count == 1 ? "upcoming class" : $"{upcomingDates.Count} upcoming classes";
                    lines.Add($"Your next {countStr} for {where}:");
                }
            }

            for (int i = 0; i < upcomingDates.Count; i++)
            {
                var date = upcomingDates[i];
                string dateStr = date.ToString("yyyy-MM-dd");
                string classTitle;
                if (classByDate.TryGetValue(dateStr, out var t))
                {
                    classTitle = t;
                }
                else
                {
                    int dateIdx = -1;
                    for (int d = 0; d < remembered.Dates.Count; d++)
                    {
                        if (remembered.Dates[d] == date)
                        {
                            dateIdx = d;
                            break;
                        }
                    }
                    if (dateIdx >= 0 && dateIdx < existingClasses.Count)
                    {
                        classTitle = existingClasses[dateIdx].Title;
                    }
                    else
                    {
                        classTitle = "(page not yet created)";
                    }
                }
                lines.Add($"• {date:dddd}, {date:yyyy-MM-dd} — {classTitle}");
            }

            lines.Add("");
            int spare = Math.Max(0, remembered.Dates.Count - existingClasses.Count);
            lines.Add($"{where} has {existingClasses.Count} class {(existingClasses.Count == 1 ? "page" : "pages")} across {remembered.Dates.Count} recorded dates ({spare} spare).");
            if (spare == 0)
            {
                lines.Add("Every recorded date is spoken for, so another class cannot be dated until more dates are recorded.");
            }
            else if (existingClasses.Count < remembered.Dates.Count)
            {
                var next = remembered.Dates[existingClasses.Count];
                lines.Add($"The next class would fall on {next:yyyy-MM-dd} ({next:dddd}).");
            }

            string origin = $"Where they came from: {remembered.Source}.";
            if (remembered.Recorded is { } when)
            {
                origin += $" Recorded {when:yyyy-MM-dd}.";
            }
            lines.Add("");
            lines.Add(origin);

            if (remembered.Dates.Count > upcomingDates.Count)
            {
                int rest = remembered.Dates.Count - upcomingDates.Count;
                lines.Add("");
                lines.Add($"There {(rest == 1 ? "is" : "are")} {rest} more. Say “show me all the dates” to see the full schedule.");
            }

            string fullAnswer = string.Join("\n", lines);
            return Answering(fullAnswer, fullAnswer);
        });

    [McpServerTool(Name = "remember_timetable", Title = "Remember when a section meets",
                   Destructive = false, Idempotent = true)]
    [Description("Write down the dates a section's classes fall on, so nobody has to ask again. Call this as soon " +
                 "as a teacher tells you when their class meets, however they say it. Replaces anything recorded " +
                 "before, so send the WHOLE list every time, not just new dates. Dates are YYYY-MM-DD, separated " +
                 "by commas or spaces.")]
    public string RememberTimetable(
        [Description("The course code, for example ICS3U.")] string course,
        [Description("The section number, for example 1.")] int section,
        [Description("Every date this section meets, as YYYY-MM-DD, separated by commas.")] string dates,
        [Description("Where these came from, in the teacher's words — \"timetable.xlsx, block H\", \"typed in by hand\".")]
        string source = "the teacher")
        => Guarded(() =>
        {
            var found = workspace.Course(course);
            int number = workspace.Section(found, section);

            var parsed = new List<DateOnly>();
            var unreadable = new List<string>();
            foreach (string piece in dates.Split([',', ';', ' ', '\t', '\n', '\r'],
                                                 StringSplitOptions.RemoveEmptyEntries | StringSplitOptions.TrimEntries))
            {
                if (DateOnly.TryParse(piece, out var date)) parsed.Add(date);
                else unreadable.Add(piece);
            }

            // Half a timetable is worse than none: it would be remembered, and
            // then quietly used to date the wrong classes.
            if (unreadable.Count > 0)
                throw new AssistRefusal(
                    $"Nothing was recorded — {unreadable.Count} of those aren't dates I can read " +
                    $"({string.Join(", ", unreadable.Take(5))}). Give them as YYYY-MM-DD and I'll keep the lot.");
            if (parsed.Count == 0)
                throw new AssistRefusal("Nothing was recorded — no dates were given.");

            if (!TimetableMemory.Write(workspace.FolderPath, found.Code, number, parsed, source,
                                       DateOnly.FromDateTime(DateTime.Now)))
                throw new AssistRefusal(
                    "Those dates couldn't be saved, so they aren't remembered. Tell the teacher they may be " +
                    "asked again — don't claim otherwise.");

            var stored = TimetableMemory.Read(workspace.FolderPath, found.Code, number)!;
            return $"Recorded {stored.Dates.Count} class dates for {found.Code} Section {number}, " +
                   $"{stored.Dates[0]:yyyy-MM-dd} to {stored.Dates[^1]:yyyy-MM-dd}. " +
                   "I won't need to ask for this again.";
        });

    [McpServerTool(Name = "read_timetable", Title = "Read a timetable", ReadOnly = true, Destructive = false)]
    [Description("Read one block's class meetings out of a school timetable, changing nothing. Returns each meeting's " +
                 "number and date, plus the days that are NOT teaching days (mod breaks, intersessions, exams, " +
                 "closing). Call this before planning a re-date so you can see the shape of the year and decide " +
                 "which lesson belongs on which day — that choice depends on what is in each lesson, and the tools " +
                 "cannot see that.")]
    public async Task<string> ReadTimetable(
        [Description(TimetableHelp)] string timetable,
        [Description(BlockHelp)] string block,
        CancellationToken cancellation,
        [Description("The first day of class, as YYYY-MM-DD. Meetings before it are ignored — a block runs all year, a section does not. Leave empty to use the whole block.")]
        string firstDay = "",
        [Description("The calendar year the school year starts in. Leave empty to work it out from today's date.")]
        int startYear = 0)
    {
        try
        {
            var parsed = await Load(timetable, block, startYear, cancellation, firstDay);
            var text = new StringBuilder();
            text.AppendLine($"Block {parsed.Block}: {parsed.Meetings.Count} class meetings, " +
                            $"{parsed.Meetings[0].Date:yyyy-MM-dd} to {parsed.Meetings[^1].Date:yyyy-MM-dd}.");
            text.AppendLine();
            foreach (var meeting in parsed.Meetings)
                text.AppendLine($"  {meeting.Number,3}  {meeting.Date:yyyy-MM-dd}  {meeting.Date:ddd}");

            if (parsed.NonTeachingDays.Count > 0)
            {
                text.AppendLine();
                text.AppendLine("Not teaching days — no unit content belongs on these:");
                foreach (var day in parsed.NonTeachingDays)
                    text.AppendLine($"       {day.Date:yyyy-MM-dd}  {day.Label}");
            }
            return text.ToString().TrimEnd();
        }
        catch (AssistRefusal refusal) { return refusal.Message; }
    }

    [McpServerTool(Name = "plan_re_date_classes", Title = "Plan re-dating classes",
                   ReadOnly = true, Destructive = false)]
    [Description("Work out what moving a section's classes onto a timetable would do, WITHOUT changing anything. " +
                 "Always call this first and show the teacher the result. " +
                 "Give `pages` and `meetings` as matching lists to say which lesson lands on which meeting — that " +
                 "choice is yours to make from the lesson content, because a naive spread can leave a class holding " +
                 "nothing but a warm-up, or split a lesson that has to stay whole. Leave both empty for an even " +
                 "spread across the block, which is a starting point rather than an answer. " +
                 "The plan also reports date problems the change would leave behind.")]
    public Task<CallToolResult> PlanReDateClasses(
        [Description("The course code, for example ICS3U.")] string course,
        [Description("The section number, for example 1.")] int section,
        [Description(TimetableHelp)] string timetable = "",
        [Description(BlockHelp)] string block = "",
        CancellationToken cancellation = default,
        [Description("Class page titles, in the order they are taught. Leave empty for an even spread.")]
        string[]? pages = null,
        [Description("Meeting numbers, one for each entry in `pages`, in the same order.")]
        int[]? meetings = null,
        [Description("The first day of class, as YYYY-MM-DD. Meetings before it are ignored — a block runs all year, a section does not. Leave empty to use the whole block.")]
        string firstDay = "",
        [Description("The calendar year the school year starts in. Leave empty to work it out from today's date.")]
        int startYear = 0)
        => ReDate(course, section, timetable, block, pages, meetings, startYear, apply: false, firstDay, cancellation);

    [McpServerTool(Name = "roll_over_section", Title = "Roll a section over to a new year",
                   Destructive = false, Idempotent = false)]
    [Description("Start a section again for a new year, after the teacher has copied the course from a prior one. " +
                 "Re-dates every class onto the new timetable, moves each lesson's materials with it, and moves the " +
                 "year-round pages — what Key Links points at, and the curriculum — to the first day of class. " +
                 "Also cuts the section loose from last year's website so the next publish makes a new one rather " +
                 "than overwriting it. The course is backed up first, automatically. " +
                 "\n\nAsk the teacher two things before calling this: what the first day of class is, and where their " +
                 "timetable spreadsheet is. Call plan_re_date_classes first and show them the dates. " +
                 "\n\nThis deliberately does NOT hide anything: the teacher should preview the site and check the " +
                 "dates and structure before deciding what students see. Afterwards the section has to be published " +
                 "once from Plantoir, where the teacher chooses what the new site is called.")]
    public async Task<string> RollOverSection(
        [Description("The course code, for example ICS3U.")] string course,
        [Description("The section number, for example 1.")] int section,
        [Description(TimetableHelp)] string timetable,
        [Description(BlockHelp)] string block,
        CancellationToken cancellation,
        [Description("Class page titles, in the order they are taught. Leave empty for an even spread.")]
        string[]? pages = null,
        [Description("Meeting numbers, one for each entry in `pages`, in the same order.")]
        int[]? meetings = null,
        [Description("The first day of class, as YYYY-MM-DD. Meetings before it are ignored — a block runs all year, a section does not. Leave empty to use the whole block.")]
        string firstDay = "",
        [Description("The calendar year the school year starts in. Leave empty to work it out from today's date.")]
        int startYear = 0)
    {
        try
        {
            var parsed = await Load(timetable, block, startYear, cancellation, firstDay);
            var plan = workspace.PlanReDate(course, section, parsed,
                pages ?? Array.Empty<string>(), meetings ?? Array.Empty<int>());
            var result = workspace.ApplyReDate(plan);

            var found = workspace.Course(course);
            string? released = workspace.ReleaseSite(found, section);

            var text = new StringBuilder(result.Message);
            text.Append(released is null
                ? "\nThis section had no website yet, so there was nothing to cut it loose from."
                : $"\nCut loose from last year's website — the old details are kept at {released}. " +
                  "Publishing this section from Plantoir will ask what to call the new site.");
            text.Append("\n\nNothing was hidden. Preview the section and check the dates and structure look right, " +
                        "then decide what students should see.");
            if (plan.Problems.Count > 0)
            {
                text.AppendLine().AppendLine();
                text.AppendLine("Worth looking at:");
                foreach (string problem in plan.Problems) text.AppendLine("  • " + problem);
            }
            return text.ToString();
        }
        catch (AssistRefusal refusal) { return refusal.Message; }
    }

    [McpServerTool(Name = "re_date_classes", Title = "Re-date classes", Destructive = false, Idempotent = true)]
    [Description("TEACHERS SAY: \"re-date my classes\", \"roll this section over to a new year\", " +
                 "\"put my classes on this year's dates\". Re-date every class in a section onto the " +
                 "class dates on file, by POSITION — the first class takes the first date — and move " +
                 "the pages each class uses onto that class's day with it. Pages this section's Key " +
                 "Links points at move to the first day of class. Curriculum pages are left alone, " +
                 "because Plantoir dates those itself on every build.")]
    public Task<CallToolResult> ReDateClasses(
        [Description("The course code, for example ICS3U.")] string course,
        [Description("The section number, for example 1.")] int section,
        [Description(TimetableHelp)] string timetable = "",
        [Description(BlockHelp)] string block = "",
        CancellationToken cancellation = default,
        [Description("Class page titles, in the order they are taught. Leave empty for an even spread.")]
        string[]? pages = null,
        [Description("Meeting numbers, one for each entry in `pages`, in the same order.")]
        int[]? meetings = null,
        [Description("The first day of class, as YYYY-MM-DD. Meetings before it are ignored — a block runs all year, a section does not. Leave empty to use the whole block.")]
        string firstDay = "",
        [Description("The calendar year the school year starts in. Leave empty to work it out from today's date.")]
        int startYear = 0)
        => ReDate(course, section, timetable, block, pages, meetings, startYear, apply: true, firstDay, cancellation);

    private async Task<CallToolResult> ReDate(string course, int section, string timetable, string block,
                                              string[]? pages, int[]? meetings, int startYear, bool apply,
                                              string firstDay, CancellationToken cancellation)
    {
        try
        {
            var found = workspace.Course(course);
            int number = workspace.Section(found, section);

            Timetable parsed;
            if (string.IsNullOrWhiteSpace(timetable))
            {
                var remembered = TimetableMemory.Read(workspace.FolderPath, found.Code, number);
                if (remembered is null || remembered.Dates.Count == 0)
                {
                    return Answering($"I don’t know when {found.Code} Section {number} meets, so I can’t re-date it. {AssistWording.MayIAskForYourDates}");
                }
                parsed = Timetable.FromDates(remembered.Dates, remembered.Source);
            }
            else
            {
                parsed = await Load(timetable, block, startYear, cancellation, firstDay);
            }

            var plan = workspace.PlanReDate(course, section, parsed,
                pages ?? Array.Empty<string>(), meetings ?? Array.Empty<int>());

            if (!apply)
            {
                if (plan.ChangesNothing)
                {
                    string already = $"Every page in {found.Code} Section {number} is already on the day it should be.";
                    return Answering(already);
                }
                return Proposing(plan.Describe());
            }

            if (plan.ChangesNothing)
            {
                string already = $"Every page in {found.Code} Section {number} is already on the day it should be.";
                return Answering(already);
            }

            var result = workspace.ApplyReDate(plan);
            int moved = plan.Moves.Count > 0 ? plan.Moves.Count : plan.Changing.Count();
            int classCount = plan.ClassCount > 0 ? plan.ClassCount : plan.Dates.Count;
            int materials = moved - classCount;
            string summary = $"Re-dated {classCount} {(classCount == 1 ? "class" : "classes")}" +
                             $" and {materials} {(materials == 1 ? "page" : "pages")} they use.";
            string detail = summary +
                            $"\n\n{AssistWorkspace.BackedUpNote}" +
                            "\n\nNothing was published or hidden, so students see no change until you deploy.";

            return Answering(summary, detail);
        }
        catch (AssistRefusal refusal) { return Answering(refusal.Message); }
        catch (Plantoir.Core.Models.OutsideWorkspaceException refusal) { return Answering(refusal.Message); }
    }

    private static async Task<Timetable> Load(string timetable, string block, int startYear,
                                              CancellationToken cancellation, string firstDay = "")
    {
        string csv = await TimetableSource.Read(timetable, cancellation);
        int year = startYear > 0
            ? startYear
            : Timetable.AcademicYearStarting(DateOnly.FromDateTime(DateTime.Now));
        var parsed = Timetable.Parse(csv, block, year);
        // The teacher's first day of class, when they gave one: a block runs
        // all year but a section does not span semesters.
        return ParseDate(firstDay, "firstDay") is { } from ? parsed.From(from) : parsed;
    }

    [McpServerTool(Name = "plan_sync_page_dates", Title = "Plan bringing materials into date",
                   ReadOnly = true, Destructive = false)]
    [Description("Work out what bringing a lesson's materials into date with the lesson would do, WITHOUT changing " +
                 "anything. This is the fix for the date problems the other tools report — when a class is dated in " +
                 "June but the concept page it links to is dated in November, this brings the concept to the class. " +
                 "Name classes to fix just those; name none to bring every page into line with the earliest class " +
                 "that links to it. Always show the teacher the result before using sync_page_dates.")]
    public string PlanSyncPageDates(
        [Description("The course code, for example ICS3U.")] string course,
        [Description("The section number, for example 1.")] int section,
        [Description("Class page titles whose linked pages should be brought into date. Leave empty for all.")]
        string[]? classes = null)
        => Guarded(() => workspace.PlanSyncDates(course, section, classes ?? Array.Empty<string>()).Describe() +
                         "\n\nNothing has been changed. Show this to the teacher and ask before going ahead.");

    [McpServerTool(Name = "sync_page_dates", Title = "Bring materials into date",
                   Destructive = false, Idempotent = true)]
    [Description("Set the date of the pages a class links to, to match that class. The course is backed up first, " +
                 "automatically. Only call this after plan_sync_page_dates and after the teacher has agreed. " +
                 "This changes dates only — nothing is published, and no page's visibility changes.")]
    public string SyncPageDates(
        [Description("The course code, for example ICS3U.")] string course,
        [Description("The section number, for example 1.")] int section,
        [Description("Class page titles whose linked pages should be brought into date. Leave empty for all.")]
        string[]? classes = null)
        => Guarded(() =>
        {
            var plan = workspace.PlanSyncDates(course, section, classes ?? Array.Empty<string>());
            var result = workspace.ApplySyncDates(plan);
            return result.Message;
        });

    // ---- Planning (changes nothing) --------------------------------------

    /// <summary>
    /// Dates arrive as plain strings and are parsed here, once, so a bad date
    /// is a sentence rather than a schema error — and so the comparison itself
    /// is never something the assistant does.
    /// </summary>
    private const string DateHelp =
        "A date as YYYY-MM-DD, for example 2026-09-15. Leave empty for no limit.";

    [McpServerTool(Name = "plan_publish_pages", Title = "Plan publishing pages", ReadOnly = true, Destructive = false)]
    [Description("Work out exactly what publishing pages would do, WITHOUT changing anything. " +
                 "Always call this before publish_pages and show the teacher the result. " +
                 "Choose pages by name, or by date with onOrAfter/before — \"every class from September 15th\" is one " +
                 "call, and the dates are compared for you. Accepts any page, not just class pages, and can follow " +
                 "their links, so you never need to work out which pages are linked.")]
    public CallToolResult PlanPublishPages(
        [Description("The course code, for example ICS3U.")] string course,
        [Description("The section number, for example 1.")] int section,
        [Description("True to also publish every page these pages link to. Choose deliberately; there is no default.")]
        bool includeLinked = false,
        [Description("The page titles, for example [\"Unit 2, Day 3\"]. May be empty if you give dates instead.")]
        string[]? pages = null,
        [Description("Only classes on or after this date. " + DateHelp)] string onOrAfter = "",
        [Description("Only classes strictly before this date. " + DateHelp)] string before = "")
        => Plan(course, section, pages, includeLinked, draft: false, onOrAfter, before);

    [McpServerTool(Name = "plan_unpublish_pages", Title = "Plan unpublishing pages", ReadOnly = true, Destructive = false)]
    [Description("TEACHERS SAY: \"what happens if I take that down?\", \"check before you hide Unit 3, Day 2\". " +
                 "Work out exactly what unpublishing pages from students would do, WITHOUT changing anything. " +
                 "Always call this before unpublish_pages and show the teacher the result. " +
                 "Choose pages by name, or by date with onOrAfter/before — \"hide everything from next Monday on\" is " +
                 "one call. Note that a page linked from a class you are unpublishing may also be linked from one that must " +
                 "stay up; the plan lists every page, so check it before agreeing.")]
    public CallToolResult PlanUnpublishPages(
        [Description("The course code, for example ICS3U.")] string course,
        [Description("The section number, for example 1.")] int section,
        [Description("True to also unpublish every page these pages link to. Choose deliberately; there is no default.")]
        bool includeLinked = false,
        [Description("The page titles, for example [\"Unit 2, Day 3\"]. May be empty if you give dates instead.")]
        string[]? pages = null,
        [Description("Only classes on or after this date. " + DateHelp)] string onOrAfter = "",
        [Description("Only classes strictly before this date. " + DateHelp)] string before = "")
        => Plan(course, section, pages, includeLinked, draft: true, onOrAfter, before);

    private CallToolResult Plan(string course, int section, string[]? pages, bool includeLinked,
                                bool draft, string onOrAfter, string before)
    {
        if (WholeUnitPlan(course, section, pages, publishing: !draft) is { } whole)
            return whole;

        return Guarded(() => Proposing(workspace.PlanPublish(
            course, section, pages ?? Array.Empty<string>(), includeLinked, draft,
            publishes: !draft, onOrAfter: ParseDate(onOrAfter, "onOrAfter"), before: ParseDate(before, "before"))));
    }

    private CallToolResult? WholeUnitPlan(string course, int section, string[]? pages, bool publishing)
    {
        if (pages == null || pages.Length != 1) return null;
        int? unit = PublishPlan.UnitNamed(pages[0]);
        if (unit == null) return null;

        var result = workspace.PlanWholeUnit(course, section, unit.Value, publishing);
        if (result.ErrorMessage != null)
            return Answering(result.ErrorMessage);
        if (result.AlreadyDoneSentence != null)
            return Answering(result.AlreadyDoneSentence);
        if (result.PlanText != null)
            return Proposing(result.PlanText);
        return null;
    }


    private static DateOnly? ParseDate(string raw, string which)
    {
        string value = raw.Trim();
        if (value.Length == 0) return null;
        if (DateOnly.TryParse(value, System.Globalization.CultureInfo.InvariantCulture,
                System.Globalization.DateTimeStyles.None, out var date))
            return date;
        throw new AssistRefusal($"“{raw}” isn’t a date {which} can use. Give it as YYYY-MM-DD, for example 2026-09-15.");
    }

    // ---- Taking it back --------------------------------------------------

    [McpServerTool(Name = "list_recent_changes", Title = "What this conversation changed",
                   ReadOnly = true, Destructive = false)]
    [Description("List what this conversation has changed, newest first, so the teacher can see what could be " +
                 "taken back. This history is only kept while this conversation is open. Anything older lives in " +
                 "Plantoir's Backups list, which is made before every change.")]
    public string ListRecentChanges()
    {
        var entries = workspace.History?.Entries;
        if (entries is null || entries.Count == 0)
            return "This conversation hasn’t changed anything yet.";

        var text = new StringBuilder();
        for (int i = entries.Count - 1; i >= 0; i--)
        {
            var entry = entries[i];
            text.AppendLine($"{(i == entries.Count - 1 ? "most recent: " : "             ")}" +
                            $"{entry.When:HH:mm} — {entry.Description} " +
                            $"({entry.Files.Count} file{(entry.Files.Count == 1 ? "" : "s")})");
        }
        // Never a tool's name: this sentence is read by a teacher, and
        // "undo_last_change" is a thing in the code, not a thing they can say.
        text.Append("\nThe most recent one can be taken back — say “undo that”.");
        return text.ToString();
    }

    [McpServerTool(Name = "undo_last_change", Title = "Undo the last change",
                   Destructive = false, Idempotent = false)]
    [Description("TEACHERS SAY: \"undo that\", \"put it back\", \"that was wrong, revert it\", \"never mind, undo\". " +
                 "Take back the most recent change this conversation made — the fix for publishing the wrong " +
                 "class in a hurry. Puts exactly those pages back the way they were, without disturbing anything " +
                 "else. Can be called more than once to step further back. " +
                 "\n\nOnly changes made in THIS conversation can be undone this way; the history is not kept " +
                 "afterwards. For anything older, Plantoir's Backups list has a full copy of the course taken " +
                 "before each change. " +
                 "\n\nIf the teacher had already published the section themselves, undoing the pages does not " +
                 "un-publish the live site — they need to publish again in Plantoir to bring it back in step.")]
    public CallToolResult UndoLastChange()
    {
        if (workspace.History is not { } history)
            return Answering(AssistWording.NothingToUndo);

        var result = history.Undo();
        if (!result.Succeeded && result.Restored.Count == 0 && result.Skipped.Count == 0)
            return Answering(AssistWording.NothingToUndo);

        // Nothing went back, because every file has been edited since. This
        // must not read like a success, and a count of files put back reads
        // exactly like one when the count is zero.
        if (result.Restored.Count == 0)
        {
            string refusal = AssistWording.CouldNotUndo(result.Description, result.Skipped.Count) +
                             "\n\n" + Listing(result.Skipped) +
                             "\n\n" + AssistWording.UndoIsStillAvailable;
            return Answering(refusal);
        }

        // The wordings are the contract's, not this file's. What a teacher is
        // told about an undo is one of the sentences both apps must say
        // identically — see contracts/assist-wording.json.
        string summary = result.Skipped.Count == 0
            ? AssistWording.Undid(result.Description)
            : AssistWording.UndidPartly(result.Description, result.Skipped.Count);

        var detail = new StringBuilder(summary);
        if (result.Skipped.Count > 0)
        {
            detail.Append("\n\nThe ones I left alone:\n").Append(Listing(result.Skipped));
            detail.Append("\n\n").Append(AssistWording.UndoIsStillAvailable);
        }
        detail.Append("\n\n").Append(AssistWording.UndoDoesNotReachTheLiveSite);
        return Answering(summary, detail.ToString());
    }

    /// <summary>The files an undo could not put back, named so they can be dealt with.</summary>
    private string Listing(IReadOnlyList<string> paths)
    {
        var lines = new List<string>();
        foreach (string path in paths.Take(MostListed)) lines.Add("  " + workspace.Relative(path));
        if (paths.Count > MostListed) lines.Add($"  …and {paths.Count - MostListed} more.");
        return string.Join("\n", lines);
    }

    // ---- The commonest request of all ------------------------------------

    private const string ClassDateHelp =
        "The day the class is taught, as YYYY-MM-DD. For \"tomorrow\" or \"today\", work out the date first — " +
        "the tool matches it exactly against each class's own date.";

    [McpServerTool(Name = "plan_publish_class_on", Title = "Plan publishing a day's class",
                   ReadOnly = true, Destructive = false)]
    [Description("TEACHERS SAY: \"what would publishing tomorrow's class do?\", \"show me before you put Monday up\". " +
                 "Work out what publishing the class taught on a given day would do, WITHOUT changing anything. " +
                 "This is the tool for \"publish tomorrow's class\" or \"publish today's class\": it finds the class " +
                 "by date, follows its links, gives pages no other class uses that class's date, and points the " +
                 "section's front page at it. Always show the teacher the result before using publish_class_on.")]
    public CallToolResult PlanPublishClassOn(
        [Description("The course code, for example ICS3U.")] string course,
        [Description("The section number, for example 1.")] int section,
        [Description(ClassDateHelp)] string date)
        => Guarded(() => Proposing(PlanForDay(course, section, date, publishes: true)));

    [McpServerTool(Name = "publish_class_on", Title = "Publish a day's class",
                   Destructive = false, Idempotent = true)]
    [Description("TEACHERS SAY: \"publish tomorrow's class\", \"put up Monday's lesson\", \"put Unit 2, Day 3 up\", " +
                 "\"make Friday's class visible\", \"post next class\", \"put the class live for students\". " +
                 "Publish the class taught on a given day, along with the pages it links to, then rebuild the " +
                 "section's preview. Pages that no other class links to take the class's date, and the section's " +
                 "front page is pointed at the most recent published class. The course is backed up first, " +
                 "automatically. Only call this after plan_publish_class_on and after the teacher has agreed. " +
                 "\n\nThis changes the teacher's files and rebuilds their PREVIEW. It does not put anything in " +
                 "front of students: only the teacher can do that, from Plantoir. Tell them to look the preview " +
                 "over and publish it there when they are happy. " +
                 "This takes a few minutes.")]
    public async Task<CallToolResult> PublishClassOn(
        [Description("The course code, for example ICS3U.")] string course,
        [Description("The section number, for example 1.")] int section,
        [Description(ClassDateHelp)] string date,
        IProgress<ProgressNotificationValue> progress,
        CancellationToken cancellation,
        [Description("False to change the pages without rebuilding the preview.")] bool preview = true)
    {
        try
        {
            var plan = PlanForDay(course, section, date, preview);
            if (plan.NothingToDoSentence is { } already) return Answering(already);

            var result = await workspace.Apply(plan, Relay(progress), cancellation);

            var text = new StringBuilder(result.Message);
            if (plan.Index is { WillChange: true } index)
                text.Append($"\nThe section's front page now shows “{index.ToClass}”.");

            // The teacher named a DAY, so the day is what they are told about.
            // Which pages that turned out to mean, and what happened to the
            // section's front page, are the model's business.
            return result.Succeeded
                ? Answering($"Published the class on {date}.", text.ToString())
                : Answering(text.ToString());
        }
        catch (AssistRefusal refusal) { return Answering(refusal.Message); }
        catch (OperationCanceledException) { return Answering("The publish was stopped before it finished."); }
    }

    private PublishPlan PlanForDay(string course, int section, string date, bool publishes)
    {
        var found = workspace.Course(course);
        int number = workspace.Section(found, section);
        var when = ParseDate(date, "date")
            ?? throw new AssistRefusal("No date was given for the class to publish.");
        string page = workspace.ClassOn(found, number, when);

        return workspace.PlanPublish(course, number,
            new[] { Path.GetFileNameWithoutExtension(page) },
            includeLinked: true, draft: false, publishes: publishes);
    }

    // ---- Acting ----------------------------------------------------------

    [McpServerTool(Name = "publish_pages", Title = "Publish pages", Destructive = false, Idempotent = true)]
    [Description("Make pages visible to students, optionally along with every page they link to, then rebuild the section preview. " +
                 "section's website. The course is backed up first, automatically. " +
                 "Only call this after plan_publish_pages and after the teacher has agreed to what it said. " +
                 "Pass every page you intend to change in ONE call: each call with preview=true rebuilds the preview again. " +
                 "This takes several minutes.")]
    public Task<CallToolResult> PublishPages(
        [Description("The course code, for example ICS3U.")] string course,
        [Description("The section number, for example 1.")] int section,
        [Description("True to also publish every page these pages link to.")] bool includeLinked = false,
        IProgress<ProgressNotificationValue> progress = null!,
        CancellationToken cancellation = default,
        [Description("The page titles to publish. May be empty if you give dates instead.")]
        string[]? pages = null,
        [Description("Only classes on or after this date. " + DateHelp)] string onOrAfter = "",
        [Description("Only classes strictly before this date. " + DateHelp)] string before = "",
        [Description("False to change the pages without rebuilding the preview.")] bool preview = true)
        => Act(course, section, pages, includeLinked, draft: false, preview, onOrAfter, before,
               progress, cancellation);

    [McpServerTool(Name = "unpublish_pages", Title = "Unpublish pages", Destructive = false, Idempotent = true)]
    [Description("TEACHERS SAY: \"take Unit 4, Day 5 back down\", \"students shouldn't see it yet\", \"hide that page\", " +
                 "\"I posted it by mistake\", \"make it a draft again\", \"pull that lesson\", \"un-publish it\". " +
                 "Unpublish pages, so students no longer see them, optionally along with every page they link to, then rebuild the section preview. " +
                 "section's website so they disappear from the live site. The course is backed up first, automatically. " +
                 "Only call this after plan_unpublish_pages and after the teacher has agreed to what it said. " +
                 "Pass every page you intend to change in ONE call: each call with preview=true rebuilds the preview again. " +
                 "This takes several minutes.")]
    public Task<CallToolResult> UnpublishPages(
        [Description("The course code, for example ICS3U.")] string course,
        [Description("The section number, for example 1.")] int section,
        [Description("True to also unpublish every page these pages link to.")] bool includeLinked = false,
        IProgress<ProgressNotificationValue> progress = null!,
        CancellationToken cancellation = default,
        [Description("The page titles to unpublish. May be empty if you give dates instead.")]
        string[]? pages = null,
        [Description("Only classes on or after this date. " + DateHelp)] string onOrAfter = "",
        [Description("Only classes strictly before this date. " + DateHelp)] string before = "",
        [Description("False to change the pages without rebuilding the preview.")] bool preview = true)
        => Act(course, section, pages, includeLinked, draft: true, preview, onOrAfter, before,
               progress, cancellation);

    // The cues cover STARTING a preview as well as refreshing one. The first
    // live request to the local assistant was "Preview the site", and with
    // every cue here assuming a preview already existed, the model matched
    // nothing — and wrote a paragraph describing a rebuild it never did.
    [McpServerTool(Name = "rebuild_preview", Title = "Rebuild the preview", Destructive = false, Idempotent = true)]
    [Description("TEACHERS SAY: \"preview the site\", \"show me the preview\", \"start the preview\", " +
                 "\"open the preview\", \"rebuild the preview\", \"refresh what I'm looking at\", " +
                 "\"update the preview\", \"build it again\". " +
                 "Build a section's preview and put it on screen, without changing any page. " +
                 "Use this after a batch of publish_pages or unpublish_pages calls made with preview=false. " +
                 "This takes several minutes.")]
    public async Task<string> RebuildPreview(
        [Description("The course code, for example ICS3U.")] string course,
        [Description("The section number, for example 1.")] int section,
        IProgress<ProgressNotificationValue> progress,
        CancellationToken cancellation)
    {
        try
        {
            var result = await workspace.RebuildPreview(course, section, Relay(progress), cancellation);
            return result.Message;
        }
        catch (AssistRefusal refusal) { return refusal.Message; }
        catch (OperationCanceledException) { return "The publish was stopped before it finished."; }
    }

    [McpServerTool(Name = "back_up_course", Title = "Back up a course", Destructive = false, Idempotent = false)]
    [Description("Make a full backup of one course, which the teacher can restore from inside Plantoir. " +
                 "Do this before any bulk editing of a course's files — including edits you make directly rather than " +
                 "through these tools. Course folders are not in version control, so a backup is the only undo.")]
    public string BackUpCourse(
        [Description("The course code, for example ICS3U.")] string course)
        => Guarded(() => $"Backed up to {workspace.BackUp(course)}");

    // ---- Shared ----------------------------------------------------------

    private async Task<CallToolResult> Act(string course, int section, string[]? pages, bool includeLinked,
                                           bool draft, bool preview, string onOrAfter, string before,
                                           IProgress<ProgressNotificationValue> progress,
                                           CancellationToken cancellation)
    {
        try
        {
            if (await WholeUnitRequested(course, section, pages, publishing: !draft, preview, progress, cancellation) is { } whole)
                return whole;

            var plan = workspace.PlanPublish(
                course, section, pages ?? Array.Empty<string>(), includeLinked, draft, publishes: !draft,
                ParseDate(onOrAfter, "onOrAfter"), ParseDate(before, "before"));

            // Four words, when four words are the whole answer.
            if (plan.NothingToDoSentence is { } already) return Answering(already);
            if (plan.ChangesNothing && !preview) return Answering(plan.Describe());

            // The count comes from the PLAN, not from what the writes
            // reported: it is the number the teacher just agreed to, and the
            // two disagreeing by one is how a reply stops being believed.
            int changing = plan.Changing.Count();
            string verb = plan.Hiding ? "Unpublished" : "Published";
            string word = changing == 1 ? "page" : "pages";

            var result = await workspace.Apply(plan, Relay(progress), cancellation);
            return result.Succeeded
                ? Answering($"{verb} {changing} {word}.", result.Message)
                : Answering(result.Message);
        }
        catch (AssistRefusal refusal) { return Answering(refusal.Message); }
        catch (OperationCanceledException) { return Answering("The publish was stopped before it finished."); }
    }

    private async Task<CallToolResult?> WholeUnitRequested(
        string course, int section, string[]? pages, bool publishing, bool preview,
        IProgress<ProgressNotificationValue> progress, CancellationToken cancellation)
    {
        if (pages == null || pages.Length != 1) return null;
        int? unit = PublishPlan.UnitNamed(pages[0]);
        if (unit == null) return null;

        var result = await workspace.ApplyWholeUnit(course, section, unit.Value, publishing, preview,
                                                    Relay(progress), cancellation);
        return result.Succeeded
            ? Answering(result.Message, result.Message)
            : Answering(result.Message);
    }

    /// <summary>
    /// Forwards the launchers' own milestone lines as MCP progress. The
    /// toolchain already narrates in plain words, so the assistant reports the
    /// toolchain's wording rather than a paraphrase of it.
    /// </summary>
    private static IProgress<string> Relay(IProgress<ProgressNotificationValue> progress)
    {
        int step = 0;
        return new Progress<string>(message =>
            progress.Report(new ProgressNotificationValue
            {
                Progress = Math.Min(++step, 99),
                Total = 100,
                Message = message,
            }));
    }

    /// <summary>
    /// A refusal is an answer, not a crash: it comes back as ordinary text so
    /// the assistant reads the reason to the teacher and can correct itself.
    /// </summary>
    private static string Guarded(Func<string> work)
    {
        try { return work(); }
        catch (AssistRefusal refusal) { return refusal.Message; }
        catch (Plantoir.Core.Models.OutsideWorkspaceException refusal) { return refusal.Message; }
        catch (IOException error) { return $"That couldn’t be read: {error.Message}"; }
        catch (UnauthorizedAccessException) { return "Plantoir doesn’t have permission to read that."; }
    }

    // ---- Two audiences ---------------------------------------------------

    /// <summary>
    /// An answer whose two audiences want different lengths.
    ///
    /// <paramref name="summary"/> is the ONE LINE the teacher reads in the
    /// chat; <paramref name="detail"/> is what the model is handed, at
    /// whatever length the question needs. The text content of the result is
    /// the detail and only the detail, so Claude Code — which reads it and
    /// writes its own summary — sees exactly what it saw before any of this
    /// existed. The teacher's line rides in <c>_meta</c>, which every other
    /// client ignores.
    ///
    /// This is <c>AssistToolOutcome</c> from the mac, ported. Its absence is
    /// why "read Unit 2, Day 3" used to put a whole page of Markdown in a
    /// teacher's chat window: one string cannot be short for a person and
    /// complete for a model at the same time.
    /// </summary>
    private static CallToolResult Answering(string summary, string detail) => new()
    {
        Content = [new TextContentBlock { Text = detail }],
        Meta = new JsonObject { [AssistToolAnswer.TeacherSummaryKey] = summary },
    };

    /// <summary>
    /// An answer that is the same words to both — every refusal, and every
    /// tool whose whole reply is already one sentence. No <c>_meta</c> is
    /// sent, and the client reads that absence as "show what you were given".
    /// </summary>
    private static CallToolResult Answering(string both) => new()
    {
        Content = [new TextContentBlock { Text = both }],
    };

    /// <summary><see cref="Guarded(Func{string})"/>, for a tool that answers in two halves.</summary>
    private static CallToolResult Guarded(Func<CallToolResult> work)
    {
        try { return work(); }
        catch (AssistRefusal refusal) { return Answering(refusal.Message); }
        catch (Plantoir.Core.Models.OutsideWorkspaceException refusal) { return Answering(refusal.Message); }
        catch (IOException error) { return Answering($"That couldn’t be read: {error.Message}"); }
        catch (UnauthorizedAccessException) { return Answering("Plantoir doesn’t have permission to read that."); }
    }

    /// <summary>
    /// The plan itself lists every page it would touch, with the key and the
    /// transition; this only adds the standing instruction. Rendering the list
    /// here as well is how two counts drifted apart in the first place — one
    /// description of the plan, in one place.
    ///
    /// The instruction is addressed to whatever is reading a plan on a surface
    /// with NO Go and Cancel of its own — which means Claude Code, and never
    /// the teacher. Plantoir's own window puts the two buttons under the plan,
    /// so a teacher who read "Show this to the teacher and ask before going
    /// ahead" was being addressed as though they were the model, about
    /// machinery, directly above the asking it described.
    /// </summary>
    private static CallToolResult Proposing(PublishPlan plan) =>
        plan.NothingToDoSentence is { } already
            ? Answering(already)
            : (plan.ChangesNothing && plan.UnknownNames.Count > 0)
                ? Answering(plan.Describe())
                : Proposing(plan.Describe());


    /// <summary>
    /// A PLAN: what WOULD happen, and nothing done yet.
    ///
    /// The plan itself is written for the teacher, because the teacher is who
    /// decides — so it is the summary as well as the body of the detail. Only
    /// the instruction to ask is added on the way out, and the answer is
    /// MARKED as a plan so the window knows to put Go and Cancel under it.
    ///
    /// A <c>plan_</c> tool that REFUSED does not come through here, and that
    /// is exactly what the mark is for: a refusal is an answer, not a
    /// proposal, and "Shall I go ahead?" under an explanation of why nothing
    /// can be done invites a teacher to approve a dead end. The mac transcript
    /// that produced this rule shows them declining one four times in a row.
    /// </summary>
    private static CallToolResult Proposing(string plan) => new()
    {
        Content = [new TextContentBlock { Text = plan + "\n\n" + AskBeforeGoingAhead }],
        Meta = new JsonObject
        {
            [AssistToolAnswer.TeacherSummaryKey] = plan,
            [AssistToolAnswer.IsPlanKey] = true,
        },
    };

    /// <summary>Said to a caller that has no Go and Cancel of its own. Never to a teacher.</summary>
    private const string AskBeforeGoingAhead =
        "Nothing has been changed. Show this to the teacher and ask before going ahead.";
}
