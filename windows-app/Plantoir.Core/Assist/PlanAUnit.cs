using Plantoir.Core.Models;

namespace Plantoir.Core.Assist;

/// <summary>
/// Plan a Unit with Claude… and Plan a Unit with Codex… on an empty Planning
/// tab (#801 item 5, the mac's #708): the two doors Revise With ▸ opens, with
/// an opening message of their own (<c>contracts/app-rules.json</c> →
/// <c>outsideAgents.planAUnit</c>), as Fix with… does for problems. The message
/// REPLACES the greeting, so no unit-planning reminder and no reference-courses
/// sentence ride along (<c>planAUnit.atTheClick</c>); it goes to the door as
/// its <c>openingMessage</c> (<see cref="ClaudeCodeLauncher.Prepare"/>).
/// Pinned by <c>PlanAUnitTests</c>; the buttons themselves are 790b.
/// </summary>
public static class PlanAUnit
{
    /// <summary><c>planAUnit.message</c>, with <c>{course}</c> and <c>{howITeach}</c> to fill: one line, no semicolon.</summary>
    public const string Message =
        "I'm a teacher working on {course} in Plantoir, and I'd like to plan a unit with you. "
        + "Follow the plantoir-unit-planning guide, and use the plantoir tools for anything to do with this course. "
        + "Start by listing its sections so we both know what's there. "
        + "{howITeach} "
        + "After that, ask me which unit I want to plan, which sections it covers "
        + "and whether a colleague teaches it on other dates. "
        + "Do not build anything until I say go.";

    /// <summary><c>planAUnit.buttons</c>.</summary>
    public const string ClaudeButtonTitle = "Plan a Unit with Claude…";
    public const string CodexButtonTitle = "Plan a Unit with Codex…";

    /// <summary><c>planAUnit.trailLine</c>, after the course and the separator.</summary>
    public const string TrailLine = "asked {assistant} to plan a unit from the Planning tab";

    /// <summary>
    /// The opening message for a course (<c>planAUnit.courseIsNamedAs</c>): its
    /// code, and its name in brackets when that is not empty and differs, the
    /// name on one line and cut at <see cref="FixWithAssistant.CourseNameMaxCharacters"/>;
    /// then <see cref="FixWithAssistant.Replaced"/> over the whole message.
    /// </summary>
    public static string OpeningMessage(string courseCode, string courseName)
    {
        string named = courseCode;
        string name = FixWithAssistant.CutToCharacters(UnitPlans.OneLine(courseName), FixWithAssistant.CourseNameMaxCharacters);
        if (name.Length > 0 && name != courseCode) named += $" ({name})";
        return FixWithAssistant.Replaced(FixWithAssistant.Fill(Message, new()
        {
            ["{course}"] = named,
            ["{howITeach}"] = ClaudeCodeLauncher.HowITeachSentence,
        }));
    }

    /// <summary>A button's title for a door.</summary>
    public static string ButtonTitle(FixWithAssistant.Assistant assistant) =>
        assistant == FixWithAssistant.Assistant.Claude ? ClaudeButtonTitle : CodexButtonTitle;

    /// <summary>The trail's line for a door that opened: the course, then which assistant was asked; nothing from a plan.</summary>
    public static string TrailText(string courseCode, FixWithAssistant.Assistant assistant) =>
        courseCode + UnitPlans.TrailSeparator
        + FixWithAssistant.Fill(TrailLine, new() { ["{assistant}"] = FixWithAssistant.NameOf(assistant) });
}
