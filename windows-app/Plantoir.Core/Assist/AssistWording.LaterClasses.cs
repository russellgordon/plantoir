using Plantoir.Core.Models;

namespace Plantoir.Core.Assist;

/// <summary>
/// The question about classes dated after the next class (#475, the mac's
/// <c>AssistWording.laterClasses*</c>): what the section window asks at Deploy
/// and at Section ▸ Publish Pages…, and what an assistant is told when its
/// deploy is held back for it. Every sentence is the contract's
/// (<c>contracts/assist-wording.json</c>) word for word, rendered by
/// <c>ContractTests.AssistWording_MatchesContract</c> with the generator's
/// own examples; where and in what order they are said is
/// <c>shared-rules.json</c> → <c>classesDatedLater</c>.
/// </summary>
public static partial class AssistWording
{
    /// <summary>The question's title.</summary>
    public const string LaterClassesTitle = "Hide classes dated later?";

    /// <summary>The question's title, for a club's meetings.</summary>
    public const string LaterClassesTitleForAMeeting = "Hide meetings dated later?";

    /// <summary>At Deploy: <paramref name="nextDay"/> is the next class day.</summary>
    public static string LaterClassesAtDeploy(DateOnly nextDay) =>
        $"These classes are published but dated after {MenuDay(nextDay)}, the next class. Students will see them once this section is deployed. Ticked ones are hidden first, with any page only they link to.";

    /// <summary>At Deploy, for a club's meetings.</summary>
    public static string LaterClassesAtDeployForAMeeting(DateOnly nextDay) =>
        $"These meetings are published but dated after {MenuDay(nextDay)}, the next meeting. Students will see them once this section is deployed. Ticked ones are hidden first, with any page only they link to.";

    /// <summary>At Section ▸ Publish Pages…, before the plan.</summary>
    public static string LaterClassesAtPublish(DateOnly nextDay) =>
        $"These classes are dated after {MenuDay(nextDay)}, the next class. Ticked ones are left hidden; the rest are published with the other pages.";

    /// <summary>At Section ▸ Publish Pages…, for a club's meetings.</summary>
    public static string LaterClassesAtPublishForAMeeting(DateOnly nextDay) =>
        $"These meetings are dated after {MenuDay(nextDay)}, the next meeting. Ticked ones are left hidden; the rest are published with the other pages.";

    /// <summary>Under the list, both times.</summary>
    public const string LaterClassesKeptNote =
        "A class you untick stays published, and is not asked about again unless its date changes.";

    /// <summary>Under the list, for a club's meetings.</summary>
    public const string LaterClassesKeptNoteForAMeeting =
        "A meeting you untick stays published, and is not asked about again unless its date changes.";

    /// <summary>One row's day: "Wednesday, 2026-10-14" — invariant and Gregorian (#144).</summary>
    public static string LaterClassesDay(DateOnly day) => MenuDay(day);

    /// <summary>The default button at Deploy: hide the ticked, keep the rest, deploy.</summary>
    public const string HideTickedAndDeployButton = "Hide Ticked and Deploy";

    /// <summary>Beside it, always: every listed class is kept at its date, and the deploy goes.</summary>
    public const string KeepAllAndDeployButton = "Keep All and Deploy";

    /// <summary>At Publish Pages…, with <paramref name="count"/> classes ticked to stay hidden.</summary>
    public static string LeaveOutAndContinueButton(int count) => $"Leave {count} Hidden and Continue";

    /// <summary>At Publish Pages…, with none ticked.</summary>
    public const string PublishThemAllButton = "Publish Them All";

    /// <summary>
    /// An assistant working from another program asked to deploy with a class
    /// dated later and no answer on file: refused before anything runs,
    /// shaped like <see cref="DeployNeedsAnAnswer"/>. Several: the
    /// <c>NamingSeveral</c> twin.
    /// </summary>
    public static string DeployHasClassesDatedLater(string course, string section, IReadOnlyList<string> titles) =>
        titles.Count == 1
            ? $"{course} Section {section} was not deployed, so nothing was sent to students: “{titles[0]}” is published and dated after the next class, and the teacher is asked about that before the section goes out. Deploy it once from its window in Plantoir, where the question can be answered; after that it can be deployed from here."
            : DeployHasClassesDatedLaterNamingSeveral(course, section, titles);

    /// <summary>The same, naming several (three, then how many more).</summary>
    public static string DeployHasClassesDatedLaterNamingSeveral(string course, string section, IReadOnlyList<string> titles) =>
        $"{course} Section {section} was not deployed, so nothing was sent to students: {NamedFew(titles)} are published and dated after the next class, and the teacher is asked about that before the section goes out. Deploy it once from its window in Plantoir, where the question can be answered; after that it can be deployed from here.";

    /// <summary>The in-app assistant asked to deploy, and no window can show the section to ask in.</summary>
    public static string DeployHasClassesDatedLaterAndNoWindow(string course, string section, IReadOnlyList<string> titles) =>
        $"{course} Section {section} was not deployed: {(titles.Count == 1 ? $"“{titles[0]}” is" : NamedFew(titles) + " are")} published and dated after the next class. Deploy it from its window in Plantoir, where you are asked about that first.";

    /// <summary>The in-app assistant asked to deploy while the section's window already has a question up — never waited on.</summary>
    public static string DeployWaitsForAnOpenQuestion(string course, string section) =>
        $"{course} Section {section} was not deployed: its window is waiting on another question. Answer that first, then deploy.";
}
