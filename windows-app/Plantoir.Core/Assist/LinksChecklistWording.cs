namespace Plantoir.Core.Assist;

/// <summary>
/// The links checklist's sentences (<c>shared-rules.json</c> →
/// <c>linksChecklist.wording</c>; #392 / mac #379), one member per key,
/// pinned key by key by <c>LinksChecklistWordingContractTests</c>.
/// Templates: <see cref="Fill"/> fills {course}, {section}, {name},
/// {page}, {folder}, {count} and {pages} in ONE pass.
/// </summary>
public static class LinksChecklistWording
{
    public const string MenuItem = @"Publish Pages That Links Lead To…";
    public const string SheetTitle = @"Links to Hidden Pages in {course} Section {section}";
    public const string Intro = @"Pages students can see link to these pages, which are still hidden. The ticked pages will be published.";
    public const string FromAClassHeading = @"Used by a class students can see";
    public const string NotReachedHeading = @"Linked from other pages students can see";
    public const string ClassesHeading = @"Classes not yet published";
    public const string DatedLike = @"will have the same date as {name}";
    public const string AlreadyDatedLike = @"has the same date as {name}";
    public const string KeepsItsDate = @"was published before, so it keeps its date";
    public const string KeepsTheDateItHas = @"keeps the date it has";
    public const string DatedAsTheFirstClass = @"will have the date of {name}, the first class of the year";
    public const string FirstUsedIn = @"first used in {name} — it will come with that class";
    public const string ClassRow = @"a class of its own — tick it to publish it now";
    public const string ComesWith = @"brings {count} more {pages} with it";
    public const string LinkedFrom = @"linked from {name}";
    public const string LinkedFromSeveral = @"linked from {name} and {count} more";
    public const string LinkedFromRow = @"linked from {name} — it goes when that page goes";
    public const string LinkedFromSeveralRows = @"linked from {name} and {count} more hidden {pages} — it goes when one of them goes";
    public const string ComesWithAClass = @"comes with {name} — it goes when that class goes";
    public const string RowInFolder = @"{page} (in {folder})";
    public const string FrontPageStaysPut = @"Publishing a class here does not change which class the front page shows.";
    public const string NothingChangesUntilYouDeploy = @"Nothing changes for students until you deploy.";
    public const string PublishButton = @"Publish {count} {pages}";
    public const string PublishNothingTicked = @"Publish";
    public const string NotNow = @"Not Now";
    public const string DeployUnderWay = @"{course} is being deployed just now. Try again when that has finished.";
    public const string NeedsAPreviewFirst = @"Pages in {course} have changed since Section {section} was last previewed or deployed. Preview it again, and this list will be up to date.";
    public const string NothingLeftToPublish = @"Those pages have all been published or removed since the website was made.";
    public const string PageChangedSince = @"{name} changed since it was checked, so it was left as it is.";
    public const string Published = @"{count} {pages} will be on the website the next time you deploy.";

    /// <summary>"page" or "pages", to agree with <paramref name="count"/>.</summary>
    public static string Pages(int count) => count == 1 ? "page" : "pages";

    /// <summary>Every placeholder filled in one pass, so a value can never be filled twice.</summary>
    public static string Fill(string template, IReadOnlyDictionary<string, string> values) =>
        System.Text.RegularExpressions.Regex.Replace(template, @"\{(\w+)\}",
            m => values.TryGetValue(m.Groups[1].Value, out var value) ? value : m.Value);
}
