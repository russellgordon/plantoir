using System;

namespace Plantoir.Core.Assist;

/// <summary>
/// Whether each outside door exists on this PC, asked when the app starts and
/// when its window comes to the front — never while a view draws (#736, the
/// mac's <c>OutsideAssistantPresence</c>). The doors' own tests search PATH
/// and the places the installers use, which is disk work a Problems tab
/// redrawing on every tick must not do.
/// </summary>
public static class OutsideAssistantPresence
{
    private static readonly object Gate = new();
    private static bool _claude, _codex, _asked;

    /// <summary>Asks both doors again (<see cref="ClaudeCodeLauncher.IsAvailable"/>, <see cref="CodexLauncher.IsAvailable"/>).</summary>
    public static void Refresh()
    {
        bool claude = ClaudeCodeLauncher.IsAvailable, codex = CodexLauncher.IsAvailable;
        bool changed;
        lock (Gate)
        {
            changed = !_asked || claude != _claude || codex != _codex;
            _claude = claude;
            _codex = codex;
            _asked = true;
        }
        if (changed) Changed?.Invoke();
    }

    /// <summary>
    /// Whether Claude's door was there when last asked. False until the first
    /// <see cref="Refresh"/> has finished — which never asks the disk itself,
    /// so a view that draws first shows no button and gets
    /// <see cref="Changed"/> a moment later.
    /// </summary>
    public static bool ClaudeIsInstalled { get { lock (Gate) return _claude; } }

    /// <summary>Whether Codex's door was there when last asked; false until the first <see cref="Refresh"/>.</summary>
    public static bool CodexIsInstalled { get { lock (Gate) return _codex; } }

    /// <summary>What a refresh found differs from what was known (raised on the refreshing thread).</summary>
    public static event Action? Changed;
}

/// <summary>
/// What a door that did not open says (<c>outsideAgents.agents[].didNotOpenTitle</c>
/// and <c>couldNotStart</c>), in one place, so Revise With ▸ and Fix with…
/// say the same thing. Pinned against the contract by <c>FixWithAssistantContractTests</c>.
/// </summary>
public static class OutsideDoorWording
{
    public const string ClaudeDidNotOpenTitle = "Claude didn’t open";
    public const string CodexDidNotOpenTitle = "Codex didn’t open";

    public static string ClaudeCouldNotStart(string course) =>
        $"Plantoir couldn’t start a Claude session for {course}. If Claude Code was updated or moved recently, restarting Plantoir may be enough.";

    public static string CodexCouldNotStart(string course) =>
        $"Plantoir couldn’t start a Codex session for {course}. If Codex was updated or moved recently, restarting Plantoir may be enough.";

    public static string DidNotOpenTitle(FixWithAssistant.Assistant assistant) =>
        assistant == FixWithAssistant.Assistant.Claude ? ClaudeDidNotOpenTitle : CodexDidNotOpenTitle;

    public static string CouldNotStart(FixWithAssistant.Assistant assistant, string course) =>
        assistant == FixWithAssistant.Assistant.Claude ? ClaudeCouldNotStart(course) : CodexCouldNotStart(course);

    /// <summary>
    /// The click-time refusal both Revise With ▸ and Fix with… make (#468;
    /// <c>fixWith.atTheClick</c>): while any assistant holds the course — a
    /// session can start between the menu or the tab drawing and the click —
    /// each cause in its own words: a Claude or Codex session
    /// (<c>finishTheClaudeSessionFirst</c>), or this app's own window. Null
    /// when nothing holds it.
    /// </summary>
    public static (string Title, string Message)? RefusedWhileRevised(string folder, string courseCode)
    {
        if (!Plantoir.Core.Models.CourseActivity.IsAssisting(folder, courseCode)) return null;
        return (AssistWording.CourseIsAlreadyBeingRevised(courseCode),
                Plantoir.Core.Models.CourseActivity.IsRevisedElsewhere(folder, courseCode)
                    ? AssistWording.FinishTheClaudeSessionFirst
                    : WindowHoldWording.FinishInThatWindowFirst);
    }
}
