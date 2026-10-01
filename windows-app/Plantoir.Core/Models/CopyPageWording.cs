namespace Plantoir.Core.Models;

/// <summary>
/// Every sentence Copy a Page says (#247, mac #207):
/// <c>contracts/shared-rules.json → copyingAPageBetweenCourses.wording</c>,
/// by key. <c>CopyAPageWordingTests</c> compares each with the contract, so a
/// sentence changed there fails here. The checklist's sentences are in the
/// FUTURE tense and the result screen's in the past — separate keys, because
/// the screen that lets a teacher change their mind must not say anything
/// has happened yet.
/// </summary>
public static class CopyPageWording
{
    /// <summary>The templates, by contract key; placeholders in braces.</summary>
    public static readonly IReadOnlyDictionary<string, string> Templates = new Dictionary<string, string>
    {
        ["menuItem"] = "Copy a Page from This Course\u2026",
        ["sheetTitle"] = "Copy a page from {course}",
        ["whichPage"] = "Page",
        ["whichCourse"] = "Copy into",
        ["whichFolder"] = "Folder",
        ["pagePickerPrompt"] = "Search",
        ["noPagesMatch"] = "No page of that name in this course.",
        ["copiesStartHidden"] = "Copies start hidden, so nothing changes on any website until you publish them.",
        ["datesAreKept"] = "The pages keep the dates they had.",
        ["nothingIsWrittenOver"] = "Nothing already in that course is changed or written over.",
        ["nothingWasCopied"] = "Nothing was copied.",
        ["copyAnother"] = "Copy another",
        ["thereIsNoCourseToCopyInto"] = "There is no other course to copy into yet",
        ["alsoCopyLinkedPages"] = "Also copy the pages this page links to",
        ["willCopy"] = "This will copy {pages} pages into {course}, in {folder}.",
        ["willBringPicturesAndFilesInAll"] = "It will bring {count} pictures and files, {size}.",
        ["picturesWillComeInUnderANewName"] = "{count} will have the same name as something different already here, so they will come in under new names.",
        ["thePageYouChose"] = "the page you chose",
        ["willBeLeftAsItIs"] = "\u201C{page}\u201D is already in this course, so it will be left as it is \u2014 links will lead to the one that is here.",
        ["aClassPageWillBeLeftAlone"] = "\u201C{page}\u201D is one of that course's classes, so it will be left where it is.",
        ["anIndexPageWillNotBeCopied"] = "\u201C{page}\u201D is the way in to a folder rather than a page, so it will not be copied.",
        ["aPageAtTheCourseRootWillNotBeCopied"] = "\u201C{page}\u201D sits outside the course's folders, so it will not be copied.",
        ["aPageInsideOneSectionsFolderWillNotBeCopied"] = "\u201C{page}\u201D belongs to one section's classes, so it will not be copied.",
        ["thePageCouldNotBeRead"] = "\u201C{page}\u201D could not be read, so it will not be copied.",
        ["embeddedPagesAlwaysComeAlong"] = "This page is shown inside another one, so it comes along.",
        ["aClassPageWasLeftAlone"] = "\u201C{page}\u201D is one of that course's classes, so it was left where it is.",
        ["anIndexPageIsNotCopied"] = "\u201C{page}\u201D is the way in to a folder rather than a page, so it was not copied.",
        ["aPageAtTheCourseRootIsNotCopied"] = "\u201C{page}\u201D sits outside the course's folders, so it was not copied.",
        ["aPageInsideOneSectionsFolderIsNotCopied"] = "\u201C{page}\u201D belongs to one section's classes, so it was not copied.",
        ["savingACopyFirst"] = "Saving a copy of {course} first\u2026",
        ["theBackupTaken"] = "A copy of {course} from before this is saved as {named}.",
        ["copiedInto"] = "Copied {pages} pages into {course}, in {folder}.",
        ["willBringPicturesAndFiles"] = "Brings {count} pictures and files, {size}.",
        ["picturesAlreadyThere"] = "{count} are already in this course and will be used as they are.",
        ["picturesBroughtInUnderANewName"] = "{count} have the same name as something different already here, so they come in under a new name.",
        ["aPageOfThatNameIsAlreadyHere"] = "\u201C{page}\u201D is already in this course, so it was left as it is \u2014 links will lead to the one that is here.",
        ["theseLinksWillNotLeadAnywhereYet"] = "These links will not lead anywhere yet: \u201C{name}\u201D, \u201C{name}\u201D.",
        ["thatCourseIsDeployingRightNow"] = "Available once {course}\u2019s deploy has finished",
        ["thisCourseHasNoPagesToCopy"] = "{course} has no pages in shared folders to copy",
        ["thatCourseHasNowhereToPutIt"] = "{course} has no folder for a page to go in yet",
        ["theCopyOfTheCourseCouldNotBeSaved"] = "A copy of {course} could not be saved, so nothing was copied. Check there is room on the disk and try again.",
        ["thePageIsWrittenInAWayPlantoirCannotBeSureOf"] = "\u201C{page}\u201D was not copied: its settings are written in a way Plantoir cannot be sure of, and a copy must never turn up where students can read it.",
        ["theCopyIsStillThereAndMustBeRemoved"] = "\u201C{page}\u201D could not be shown to be hidden from students and could not be removed again. It is at {path} \u2014 take it out before you deploy that course.",
        ["theCopyCouldNotBeMadeHidden"] = "\u201C{page}\u201D was not copied: Plantoir could not be certain it would arrive hidden from students, and a copy must never turn up where students can read it.",
        ["thePicturesCouldNotBePointedAtTheirNewNames"] = "\u201C{page}\u201D was not copied: one of its pictures had to come in under a new name and Plantoir could not be certain the page would find it.",
        ["thePageCouldNotBeWritten"] = "\u201C{page}\u201D could not be copied.",
        ["aPictureCouldNotBeCopied"] = "\u201C{name}\u201D could not be copied, so the page that shows it will not find it.",
    };

    /// <summary>The sentence for <paramref name="key"/>, with each placeholder filled in turn.</summary>
    /// <remarks>
    /// A placeholder named twice (<c>theseLinksWillNotLeadAnywhereYet</c>'s
    /// two <c>{name}</c>s) is filled by <see cref="Names"/>, never here.
    /// </remarks>
    public static string Say(string key, params (string Name, string Value)[] fills) =>
        fills.Aggregate(Templates[key], (text, fill) => text.Replace("{" + fill.Name + "}", fill.Value));

    /// <summary>
    /// <c>theseLinksWillNotLeadAnywhereYet</c> for any number of names: the
    /// contract writes two quoted names as the pattern; one or many are the
    /// same shape, comma-separated.
    /// </summary>
    public static string Names(IEnumerable<string> names)
    {
        string template = Templates["theseLinksWillNotLeadAnywhereYet"];
        int first = template.IndexOf("“{name}”", StringComparison.Ordinal);
        int last = template.LastIndexOf("“{name}”", StringComparison.Ordinal) + "“{name}”".Length;
        string listed = string.Join(", ", names.Select(name => $"“{name}”"));
        return template[..first] + listed + template[last..];
    }

    /// <summary>A count of pages, as "1 page" or "3 pages" — used where a sentence's {pages} stands.</summary>
    public static string Pages(int count) => count == 1 ? "1 page" : $"{count} pages";
}
