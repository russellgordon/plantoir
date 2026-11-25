using Plantoir.Core.Models;

namespace Plantoir.Core.Assist;

/// <summary>
/// Classes ▸ Roll Over to a New Year…'s sentences (#954, the mac's #897 piece
/// B): the dialog's title, intro and dates lines, the website question's two
/// answers and the lines said in place of it, the plan's lines and the
/// finished lines. The mac's <c>AssistWording.menuRollOver…</c> and
/// <c>rollover…FromTheMenu</c>, word for word; each key of
/// <c>contracts/assist-wording.json</c> has a member of its own name here
/// (<c>ContractTests.AssistWording_MatchesContract</c>).
/// </summary>
public static partial class AssistWording
{
    // ---- The dialog -------------------------------------------------------------

    public static string MenuRollOverTitle(string course, string section) =>
        $"Roll over {course} Section {section} to a new year";

    public const string MenuRollOverIntro =
        "Rolling over puts this section's classes onto the class dates on file, and sets aside last year's record of which pages students could reach.";

    public const string MenuRollOverIntroForAMeeting =
        "Rolling over puts this section's meetings onto the meeting dates on file, and sets aside last year's record of which pages students could reach.";

    /// <summary>The dates the rollover will use, first to last, each as "2026-09-08 (Tuesday)".</summary>
    public static string MenuRollOverDates(string first, string last) => RollOverWords.Dates(first, last, ClassNoun.Class);

    public static string MenuRollOverDatesForAMeeting(string first, string last) => RollOverWords.Dates(first, last, ClassNoun.Meeting);

    /// <summary>
    /// The last date on file is before today. It names Class Dates… where the
    /// menu bar has it, Meetings ▸ Meeting Dates… in a club (#1027), from the layout.
    /// </summary>
    public static string MenuRollOverDatesAreOld => RollOverWords.DatesAreOld(ClassNoun.Class);

    public static string MenuRollOverDatesAreOldForAMeeting => RollOverWords.DatesAreOld(ClassNoun.Meeting);

    /// <summary>The question's two answers, under <see cref="RolloverWebsiteQuestion"/>, in this order.</summary>
    public const string MenuRollOverNewWebsite = "Start a new website, and leave last year's as it is";

    public const string MenuRollOverKeepWebsite = "Keep last year's website, so links students saved keep working";

    /// <summary>No question: no record ties the section to a website at the moment.</summary>
    public const string MenuRollOverNotDeployedYet =
        "This section is not on a website at the moment, so there is no website to keep. A new website is made the next time it is deployed.";

    /// <summary>No question: a new website started now would get the address the section's website already has.</summary>
    public const string MenuRollOverANewWebsiteWouldReuseItsAddress =
        "This section's website was started this calendar year, and a new website started now would get the same address. " +
        "It keeps deploying to the same website, so links students saved keep working. " +
        "A new website can be started for this section once the calendar year changes.";

    /// <summary>No question: the section deploys only to a folder.</summary>
    public const string MenuRollOverDeploysToAFolder =
        "This section deploys to a folder, so there is no website address to keep or replace.";

    public const string MenuRollOverButton = "Roll Over";

    // ---- The plan ---------------------------------------------------------------

    /// <summary>The plan, for "same".</summary>
    public const string MenuRollOverPlanKeepsTheWebsite =
        "It would keep deploying this section to the same website as last year.";

    /// <summary>The plan, for either answer: what the rollover sets aside.</summary>
    public const string MenuRollOverPlanSetsTheRecordAside =
        "It would also set aside last year's record of which pages students could reach, and the answers given about them last year, so the new year starts afresh.";

    // ---- The finished lines -------------------------------------------------------

    /// <summary><see cref="RolloverCouldNotStartANewWebsite"/> without the first person.</summary>
    public static string RolloverCouldNotStartANewWebsiteFromTheMenu(string stillPinned) =>
        $"This section could not be moved off {stillPinned}, so deploying it will still replace last year's website there. " +
        "Try again, or check whether that file is locked or open somewhere else.";

    /// <summary>The finished line for a section that deploys only to a folder.</summary>
    public const string RolloverDeploysToAFolderFromTheMenu =
        "This section deploys to a folder, so where it deploys is unchanged. Nothing goes out until you deploy.";

    /// <summary>The last sentence of the menu's new-website line: true on Cloudflare too, which asks for no name.</summary>
    public const string RolloverANewWebsiteIsMadeAtTheNextDeploy =
        "A new website is made the next time this section is deployed.";

    /// <summary>
    /// The finished line for a new website from the menu, in place of
    /// <see cref="RolloverStartedANewWebsite"/>, whose last sentence says
    /// Plantoir will ask what to call it (untrue on Cloudflare).
    /// </summary>
    public static string RolloverStartedANewWebsiteFromTheMenu(string keptAs) =>
        RollOverWords.StartedANewWebsite(keptAs, deploysToAFolder: false);

    /// <summary>The same, for a course that now deploys only to a folder, whose marker an old web host left.</summary>
    public static string RolloverStartedANewWebsiteFromTheMenuDeployingToAFolder(string keptAs) =>
        RollOverWords.StartedANewWebsite(keptAs, deploysToAFolder: true);

}

/// <summary>
/// Roll Over to a New Year…'s sentences in a course's noun (#954): what the
/// dialog and the menu's runner call. The keyed forms on
/// <see cref="AssistWording"/> are these with the contract's examples.
/// </summary>
public static class RollOverWords
{
    /// <summary>The intro in the course's noun.</summary>
    public static string Intro(ClassNoun noun) =>
        noun == ClassNoun.Meeting ? AssistWording.MenuRollOverIntroForAMeeting : AssistWording.MenuRollOverIntro;

    /// <summary>The dates line in the course's noun.</summary>
    public static string Dates(string first, string last, ClassNoun noun) =>
        $"The dates on file for this section's {(noun == ClassNoun.Meeting ? "meetings" : "classes")}: {first} to {last}.";

    /// <summary>The dates-are-old line in the course's noun.</summary>
    public static string DatesAreOld(ClassNoun noun)
    {
        var item = SubjectMenuRules.Item.ClassDates;
        string path = SubjectMenuLayout.Path(item, SubjectMenuLayout.TitleSayingTheNoun(item, noun)!, noun);
        string singular = noun == ClassNoun.Meeting ? "meeting" : "class";
        return "The last of these dates has passed, so they may be last year's. To give this year's " +
               $"{singular} dates, cancel and choose {path} first.";
    }

    /// <summary>The menu's new-website line, ending as the course deploys.</summary>
    public static string StartedANewWebsite(string keptAs, bool deploysToAFolder) =>
        AssistWording.RolloverIsOnANewWebsite + $" Last year's details are kept at {keptAs}, so you can go back to it. " +
        (deploysToAFolder ? AssistWording.MenuRollOverDeploysToAFolder : AssistWording.RolloverANewWebsiteIsMadeAtTheNextDeploy);
}
