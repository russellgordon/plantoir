using System.Text.Json.Nodes;

namespace Plantoir.Core.Assist;

/// <summary>
/// Who a tool call is answering — the three clients of one set of tools
/// (#489, the mac's <c>AssistToolRunner.Surface</c>, #457 batch B).
/// </summary>
/// <remarks>
/// <para><see cref="Outside"/> is an assistant working from another program
/// (Claude Code, Codex) through <c>plantoir-mcp</c>; <see cref="LocalWindow"/>
/// is Plantoir's own assistant window; <see cref="Menu"/> is the Section
/// menu's nine functions, whose calls are built in code and never reach a
/// model. <see cref="Menu"/> is <see cref="LocalWindow"/> everywhere except
/// three places — its VOICE (the <c>…FromTheMenu</c> twins in
/// <see cref="AssistWording"/>), its BACKUPS (a fresh copy before every change,
/// <see cref="Plantoir.Core.Models.BackupMaker.Menu"/>) and its CLAIM on a
/// section (<c>SectionMenuActivity</c>).</para>
/// </remarks>
public enum AssistSurface { Outside, LocalWindow, Menu }

/// <summary>
/// The ONE entry every client's tool call goes through on this side of the
/// server: the in-app assistant's model and fixed phrasings (through
/// <see cref="AssistAgent"/>), and the Section menu's code-built calls
/// (through <c>SectionVerbs</c>). The mac's
/// <c>AssistToolRunner.run(call:)</c>.
/// </summary>
/// <remarks>
/// <para><b>Why one entry.</b> Building and deploying are done by pressing
/// Plantoir's own buttons, and a page edit stops the preview, changes the
/// files and starts it again. If the menu reached the tools any other way it
/// would need its own copy of those rules, and a copy is what drifts. The
/// server-side gates (a course kept for reference, an outside change during a
/// build) live in <c>plantoir-mcp</c>'s request filter, which every client
/// meets the same way.</para>
///
/// <para><b>Not a pure move out of <see cref="AssistAgent"/></b> (the plan
/// review's H3). The seams stay on the agent, where the windows and the tests
/// set them, and are handed to a runner per call; the runner RETURNS whether
/// the work was handed to the app instead of setting the agent's flag, and the
/// agent appends exactly one <c>tool</c> message for whatever came back.</para>
/// </remarks>
public sealed class AssistToolRunner
{
    private readonly IToolServer _tools;
    private readonly string _courseCode;
    private readonly int _section;

    public AssistToolRunner(IToolServer tools, string courseCode, int section, AssistSurface surface)
    {
        _tools = tools;
        _courseCode = courseCode;
        _section = section;
        Surface = surface;
    }

    /// <summary>Who these calls answer.</summary>
    public AssistSurface Surface { get; }

    // ---- Seams: what the window does. Each is the agent's property of the same name.

    public Action<string>? OnToolProgress { get; init; }

    /// <summary>Put the section's preview on screen in the main window (starts one when none is serving).</summary>
    public Action? ShowPreviewInApp { get; init; }

    /// <summary>
    /// Really REBUILD the section's preview: stop a serving one and start it
    /// again, or start one. Before #489 <c>rebuild_preview</c> called
    /// <see cref="ShowPreviewInApp"/>, which does nothing while a preview is
    /// serving, and still answered "rebuilding" (the plan's finding 0.7). Null
    /// falls back to <see cref="ShowPreviewInApp"/>.
    /// </summary>
    public Action? RebuildPreviewInApp { get; init; }

    public Action? StartDeployInApp { get; init; }
    public Func<Task<string?>>? StartDeployInAppAsync { get; init; }
    public Func<bool>? SectionIsBusy { get; init; }
    public Func<bool>? SectionIsBeingDeployed { get; init; }
    public Func<bool>? PreviewIsShowing { get; init; }
    public Action? StopPreviewInApp { get; init; }
    public Func<Task>? StopPreviewInAppAsync { get; init; }
    public Func<bool> CourseIsKeptForReference { get; init; } = () => false;

    /// <summary>
    /// The in-app assistant's deploy puts the question about classes dated
    /// after the next class (#475) to the section's window — after the
    /// deploy's own refusals and BEFORE the preview is stopped, so a Cancel
    /// leaves the preview the teacher was reading. Null: nobody is asked here
    /// (the server's deploy holds back what it cannot ask about).
    /// </summary>
    public Func<Task<LaterClassesAtADeploy>>? AskAboutClassesDatedLaterInApp { get; init; }

    /// <summary>
    /// Whether a page change stops a showing preview first and starts it again
    /// after (the default). False for the hide the question at Deploy makes
    /// (#475): no preview either side — the deploy builds the site straight
    /// after, and a hide that failed must not leave the teacher with no
    /// preview for a deploy that never happened (the plan review's M1; the
    /// mac's <c>previewFollowsAChange</c>).
    /// </summary>
    public bool PreviewFollowsAChange { get; set; } = true;

    /// <summary>
    /// Whether the Section menu is changing this section right now
    /// (<c>SectionMenuActivity</c>). Asked on <see cref="AssistSurface.LocalWindow"/>
    /// before any write, so the assistant's change and the menu's never
    /// interleave two undo lists on one section.
    /// </summary>
    public Func<bool>? SectionIsChangingFromTheMenu { get; init; }

    /// <summary>
    /// Whether a copy of the course is being saved right now (the work lease's
    /// <c>copying</c>). Asked by the menu's Rebuild Preview only, whose
    /// refusal is <c>AssistWording.CourseIsBeingCopiedFromTheMenu</c>.
    /// </summary>
    public Func<bool>? CourseIsBeingCopied { get; init; }

    // ---- Which tools do what to the preview

    /// <summary>
    /// Tools that change pages. They run on the server as pure file edits —
    /// <c>preview: false</c>, so the server builds nothing — and then the
    /// app's own preview is put on screen to show what changed.
    /// </summary>
    internal static readonly HashSet<string> EditsPages = new(StringComparer.OrdinalIgnoreCase)
    {
        "publish_pages", "unpublish_pages", "publish_class_on", "undo_last_change",
        "re_date_classes", "roll_over_section", "sync_page_dates",
        "add_next_class", "add_classes", "make_room_for_classes", "add_curriculum_mentions",
    };

    /// <summary>
    /// Tools that must always start a preview in Plantoir after finishing their work,
    /// even if a preview was not previously active.
    /// </summary>
    internal static readonly HashSet<string> AlwaysStartsPreview = new(StringComparer.OrdinalIgnoreCase)
    {
        "re_date_classes", "roll_over_section",
    };

    /// <summary>The page-editing tools that accept a preview flag to decline the server's build.</summary>
    internal static readonly HashSet<string> TakesPreviewFlag = new(StringComparer.OrdinalIgnoreCase)
    {
        "publish_pages", "unpublish_pages", "publish_class_on",
    };

    internal static readonly HashSet<string> WriteTools = new(StringComparer.OrdinalIgnoreCase)
    {
        "publish_pages", "unpublish_pages", "publish_class_on", "undo_last_change",
        "add_next_class", "add_classes", "make_room_for_classes",
        "schedule_deploy", "cancel_scheduled_deploy",
        "rebuild_preview", "deploy_section", "re_date_classes", "roll_over_section",
        "remember_timetable", "sync_page_dates", "add_curriculum_mentions",
        "back_up_course",
    };

    internal static bool IsWriteTool(string name) => WriteTools.Contains(name);

    private bool ThisSectionIsBeingDeployed() => SectionIsBeingDeployed?.Invoke() == true;

    /// <summary>
    /// Run one call. Returns what it produced and whether the work was handed
    /// to the app — which ends the assistant's turn (a small model asked "what
    /// next?" after one of these restates it, and the teacher reads the same
    /// sentence twice).
    /// </summary>
    public async Task<(AssistToolAnswer Answer, bool HandedToApp)> Run(JsonObject call, CancellationToken cancellation)
    {
        string name = call["function"]?["name"]?.GetValue<string>() ?? "";
        var arguments = new JsonObject();
        if (call["function"]?["arguments"]?.GetValue<string>() is { } raw)
        {
            try { arguments = JsonNode.Parse(raw) as JsonObject ?? new JsonObject(); }
            catch { /* a malformed call is answered, not crashed on */ }
        }

        // Building and deploying are done by pressing Plantoir's own buttons,
        // once, where the teacher can watch — never by the server in a hidden
        // container run whose transcript lands in this chat.
        // These answers appear in the transcript word for word, so they are
        // written for the teacher — and they END the turn. Asked "what next?"
        // after reading one of these, a small model restates it, and the
        // teacher saw the same sentence twice. There is nothing next: the
        // main window has the work.
        // The Section menu's claim (#489): the in-app assistant's change to a
        // section the menu is changing right now is refused before anything
        // is backed up or written, so two undo lists never interleave on one
        // section. The menu itself, and every read, go ahead.
        if (Surface == AssistSurface.LocalWindow && IsWriteTool(name) && SectionIsChangingFromTheMenu?.Invoke() == true)
            return Handed(AssistWording.SectionIsChangingFromTheMenu(_courseCode, _section.ToString()));

        if (name.Equals("rebuild_preview", StringComparison.OrdinalIgnoreCase) && ThisSectionIsBeingDeployed())
        {
            // Before a window is opened, a preview stopped or a no-window
            // rebuild run (#386): the same publish record the window asks.
            return Handed(AssistWording.SectionIsBeingDeployed(_courseCode, _section.ToString()));
        }
        // Rebuild Preview from the menu while a copy is being saved: the one
        // sentence on this path that asks to be asked again (#457, #489).
        if (name.Equals("rebuild_preview", StringComparison.OrdinalIgnoreCase) && Surface == AssistSurface.Menu
            && CourseIsBeingCopied?.Invoke() == true)
            return Handed(AssistWording.CourseIsBeingCopiedFromTheMenu(_courseCode));
        if (name.Equals("rebuild_preview", StringComparison.OrdinalIgnoreCase)
            && (RebuildPreviewInApp is not null || ShowPreviewInApp is not null))
        {
            // REBUILD, not show (#489, Q1): a serving preview is stopped and
            // started again, so "rebuilding" is true.
            if (RebuildPreviewInApp is not null) RebuildPreviewInApp.Invoke();
            else ShowPreviewInApp!.Invoke();
            return Handed(AssistWording.PreviewIsRebuilding(_courseCode, _section.ToString()));
        }
        if ((name.Equals("deploy_section", StringComparison.OrdinalIgnoreCase)
             || name.Equals("schedule_deploy", StringComparison.OrdinalIgnoreCase))
            && CourseIsKeptForReference())
        {
            return Handed(AssistWording.DeployRefusedForAReferenceCourse(_courseCode));
        }
        if (name.Equals("deploy_section", StringComparison.OrdinalIgnoreCase) &&
            (StartDeployInApp is not null || StartDeployInAppAsync is not null))
        {
            if (SectionIsBusy?.Invoke() == true)
            {
                if (StartDeployInApp is not null) StartDeployInApp.Invoke();
                else if (StartDeployInAppAsync is not null) _ = StartDeployInAppAsync.Invoke();
                return Handed(AssistWording.SectionIsBusy(_courseCode, _section.ToString()));
            }

            // #475: the question, in the section's window, before anything is
            // stopped. The window runs the deploy's own refusals first and
            // asks nothing when one of them will refuse.
            bool deployWillBeRefused = false;
            if (AskAboutClassesDatedLaterInApp is not null)
            {
                var asked = await AskAboutClassesDatedLaterInApp.Invoke();
                deployWillBeRefused = asked.WillBeRefused;
                switch (asked.Answer)
                {
                    case LaterClassesAnswer.Cancelled:
                        return Handed(AssistWording.DeployWasCancelled);
                    case LaterClassesAnswer.CannotAsk:
                        return Handed(AssistWording.DeployWaitsForAnOpenQuestion(_courseCode, _section.ToString()));
                    case LaterClassesAnswer.NoWindow:
                        return Handed(AssistWording.DeployHasClassesDatedLaterAndNoWindow(
                            _courseCode, _section.ToString(), asked.Unasked ?? Array.Empty<string>()));
                }
            }

            // A deploy the window will refuse keeps the preview: the window's
            // own refusal speaks (its dialog, and the sentence relayed), and
            // the page the teacher was reading is not lost for a deploy that
            // never starts (2C's implementation review, L-1).
            if (!deployWillBeRefused && PreviewIsShowing?.Invoke() == true)
            {
                if (StopPreviewInAppAsync is not null)
                {
                    await StopPreviewInAppAsync.Invoke();
                }
                else
                {
                    StopPreviewInApp?.Invoke();
                }
            }

            if (StartDeployInAppAsync is not null)
            {
                string? outcome = await StartDeployInAppAsync.Invoke();
                return Handed(outcome ?? AssistWording.DeployDidNotFinish(_courseCode, _section.ToString()));
            }
            StartDeployInApp?.Invoke();
            // No async wiring available means no way to await the real
            // outcome — the caller pressed the button and this is all
            // that can honestly be said about it.
            return Handed(AssistWording.Deployed(_courseCode, _section.ToString()));
        }

        // A page edit does what a person would do: stop the preview, change
        // the files, start the preview again. The server never builds
        // (preview declined), so the work happens once, in the main window.
        bool edits = EditsPages.Contains(name);
        if (TakesPreviewFlag.Contains(name)) arguments["preview"] = false;
        bool hadPreview = PreviewFollowsAChange && PreviewIsShowing?.Invoke() == true;
        if (edits && hadPreview)
        {
            if (StopPreviewInAppAsync is not null)
            {
                await StopPreviewInAppAsync.Invoke();
            }
            else
            {
                StopPreviewInApp?.Invoke();
            }
        }

        var answer = await _tools.CallTool(name, arguments, OnToolProgress, cancellation);
        bool handed = IsWriteTool(name)
                      || name.Equals("check_section", StringComparison.OrdinalIgnoreCase)
                      || name.Equals("read_remembered_timetable", StringComparison.OrdinalIgnoreCase);
        if (edits && PreviewFollowsAChange && (hadPreview || AlwaysStartsPreview.Contains(name)) && ShowPreviewInApp is not null &&
            !ThisSectionIsBeingDeployed())
        {
            ShowPreviewInApp.Invoke();
        }
        return (answer, handed);
    }

    /// <summary>An answer made here, without the server: the same words to the teacher and the model.</summary>
    private static (AssistToolAnswer, bool) Handed(string text) => (AssistToolAnswer.Same(text), true);
}
