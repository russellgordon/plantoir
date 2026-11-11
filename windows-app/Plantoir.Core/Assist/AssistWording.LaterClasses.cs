using Plantoir.Core.Models;

namespace Plantoir.Core.Assist;

/// <summary>
/// The question about classes dated after the next class (#475, the mac's
/// <c>AssistWording.laterClasses*</c>): what the section window asks at Deploy
/// (never at Section ▸ Publish Pages…, since #694 / #726), and what an
/// assistant is told when its deploy is held back for it. Every sentence is the contract's
/// (<c>contracts/assist-wording.json</c>) word for word, rendered by
/// <c>ContractTests.AssistWording_MatchesContract</c> with the generator's
/// own examples; where and in what order they are said is
/// <c>shared-rules.json</c> → <c>classesDatedLater</c>.
/// </summary>
public static partial class AssistWording
{
    /// <summary>The question's title.</summary>
    public const string LaterClassesTitle = "Deploy classes dated later?";

    /// <summary>The question's title, for a club's meetings.</summary>
    public const string LaterClassesTitleForAMeeting = "Deploy meetings dated later?";

    /// <summary>At Deploy: <paramref name="nextDay"/> is the next class day.</summary>
    public static string LaterClassesAtDeploy(DateOnly nextDay) =>
        $"These classes are published but dated after {MenuDay(nextDay)}, the next class. Ticked ones go to students when this section is deployed. Untick any class that should not go yet: it is hidden first, with any page only it links to, so the preview shows what students will see.";

    /// <summary>At Deploy, for a club's meetings.</summary>
    public static string LaterClassesAtDeployForAMeeting(DateOnly nextDay) =>
        $"These meetings are published but dated after {MenuDay(nextDay)}, the next meeting. Ticked ones go to students when this section is deployed. Untick any meeting that should not go yet: it is hidden first, with any page only it links to, so the preview shows what students will see.";

    /// <summary>Under the list.</summary>
    public const string LaterClassesKeptNote =
        "A class left ticked is not asked about again unless its date changes. Section ▸ Undo Last Change publishes again any you untick; the next deploy sends them out.";

    /// <summary>Under the list, for a club's meetings.</summary>
    public const string LaterClassesKeptNoteForAMeeting =
        "A meeting left ticked is not asked about again unless its date changes. Section ▸ Undo Last Change publishes again any you untick; the next deploy sends them out.";

    /// <summary>One row's day: "Wednesday, 2026-10-14" — invariant and Gregorian (#144).</summary>
    public static string LaterClassesDay(DateOnly day) => MenuDay(day);

    /// <summary>
    /// The one button beside Cancel at Deploy, the default (Return): the
    /// ticked classes go out and are kept at their dates, the unticked are
    /// hidden first (#694 / #726). Keep All is gone: it only repeated Return.
    /// </summary>
    public const string DeployTickedButton = "Deploy Ticked";

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
