namespace Plantoir.Core.Models;

/// <summary>
/// What the New Course wizard says.
///
/// <para>Pinned against <c>contracts/shared-rules.json</c> → <c>wizard</c> by
/// <c>WizardWordingTests</c>, so the two apps say the same thing. The mac reads
/// the same key from its own <c>WizardWording</c>.</para>
/// </summary>
/// <remarks>
/// <para><b>Why this class exists at all, for one string.</b> The label lived
/// as a literal in <c>NewCourseDialog</c>, and the only thing pinning it on
/// this side was <c>NewCourseWizardUiTests</c> — which carries <c>[UiFact]</c>
/// and skips unless <c>PLANTOIR_UI_TESTS=1</c>, so a plain <c>dotnet test</c>
/// built it and ran nothing. The first thing a teacher presses had no gate
/// behind it.</para>
///
/// <para>It could not simply be asserted where it was: <c>Plantoir.Tests</c>
/// targets <c>net9.0</c> and references <c>Plantoir.Core</c> and
/// <c>Plantoir.Mcp</c> only, so it cannot see the WinUI app at all — and a
/// <c>ContentDialog</c> cannot be constructed off a XAML thread even if it
/// could. Anything that must FAIL in an ordinary run has to live in Core.
/// That is the general shape, not a fact about this string.</para>
///
/// <para><b>What this does and does not prove.</b> It pins the CONSTANT, not
/// the rendered button — a view that went back to a literal would leave this
/// unused and green. Only the UI suite sees the button itself, and it is
/// opt-in. The mac has exactly the same arrangement, which
/// <c>shared-rules.json</c> → <c>wizard.gatedTests</c> says in as many words.
/// So the UI test keeps its assertion, reading the contract rather than a
/// literal: the two check different things.</para>
///
/// <para>AUTHORED rather than generated, and that is the point of the contract
/// entry. A readout emitted by <c>--write-contracts</c> would simply be
/// rewritten to match whatever the button now says, and the pin would be
/// worthless. GitHub issue #119.</para>
/// </remarks>
public static class WizardWording
{
    /// <summary>
    /// The button that creates the course — the first thing a teacher presses
    /// in this app.
    /// </summary>
    public const string CreateCourseButton = "Create Course";

    // ---- "This is a club" (#274, mac #267; shared-rules.json → wizard.clubToggle).
    // Pinned by ClubWizardTests against the contract, never retyped there.

    public const string ClubToggleLabel = "This is a club";

    public const string ClubToggleCaption =
        "A club meets rather than holds classes: its pages are numbered one after another, it has no curriculum, and it starts with a page for its first meeting. The words below can be changed now, but not once the club is made.";

    /// <summary>The Starting Content note while the club box is ticked.</summary>
    public const string ClubStartingContentNote =
        "A club starts with empty folders and one page for its first meeting — no ready-made pages, no subject skeleton and no curriculum coverage page. The coverage page can be turned on later in Course Settings.";

    public const string ClubClassFolderRow = "Folder for meeting pages";
    public const string ClubFrontPageHeadingRow = "Front page heading";
    public const string ClubPageWordRow = "Pages are named";
    public const string ClubNounRow = "The assistant calls a page a";

    /// <summary><c>rows.pageWordCaption</c> with the word filled in.</summary>
    public static string ClubPageWordCaption(string word) => $"Pages will be named “{word} 1”, “{word} 2” and so on.";

    /// <summary>
    /// The panel's words, which FOLLOW THE TICK BOX (#390, mac #368) — never
    /// ClubCodeRule: a teacher can untick it for a club-shaped code, and the
    /// words must describe what will actually be made.
    /// </summary>
    public sealed record PanelWords(
        string CreateButton, string NamingHeading, string NamingCaption, string CreatingTitle,
        string CodeLabel, string NameLabel, string SectionMarkerCaption, string GradeCaption,
        string StructureCaption, string GradedFolderCaption, string DefaultSiteName);

    public static PanelWords ForACourse { get; } = new(
        CreateCourseButton, "Units",
        "Chosen once, when the course is made — the pages are named this way as they are written",
        "Creating your course", "Course code", "Course name",
        "e.g. “S1” appears beside the course code", "e.g. “Grade 12” before the course name",
        "Defaults are fine for most courses", GradedFolderRule.Caption, "Course Website");

    public static PanelWords ForAClub { get; } = new(
        "Create Club", "Meetings",
        "Chosen once, when the club is made — the pages are named this way as they are written",
        "Creating your club", "Club code", "Club name",
        "e.g. “S1” appears beside the club code", "e.g. “Grade 12” before the club name",
        "Defaults are fine for most clubs",
        "Tick the folders holding work that counts for marks. A club starts without a curriculum coverage map, so these matter only if the coverage page is turned on later in Course Settings.",
        "Club Website");

    /// <summary>The words for what the box says will be made.</summary>
    public static PanelWords Panel(bool isClub) => isClub ? ForAClub : ForACourse;

    // ---- Starting Content (GitHub issue #250; wizard.whenTheNoteIsShown and
    // wizard.whereTheStartingContentSentencesAreRendered say which is shown
    // where). Pinned by WizardWordingTests and, rendered, by the [UiFact]s in
    // NewCourseWizardUiTests.

    /// <summary>A course starting empty for a code with no ready-made pages, or whose skeleton was turned down.</summary>
    public const string NoExampleContentNote =
        "Example content isn’t available for this course code yet, so the course will start with empty folders ready for your own pages.";

    /// <summary>
    /// The same sentence without its first clause, for a code whose ready-made
    /// pages AND skeleton were both declined: "isn't available" is false to
    /// somebody who was offered it one question ago.
    /// </summary>
    public const string NoStartingContentNote =
        "This course will start with empty folders ready for your own pages.";

    /// <summary>The skeleton toggle's label; {article} and {subject} are filled by <see cref="SkeletonToggleLabel"/>.</summary>
    public const string SkeletonToggleLabelTemplate = "Start from {article} {subject} skeleton";

    /// <summary>The GENERAL family's label, outright: its own label "This Course" was written for the skeleton's pages.</summary>
    public const string SkeletonToggleLabelForAGeneralSkeleton = "Start from a general course skeleton";

    /// <summary>Under the skeleton toggle, for a code with no ready-made pages.</summary>
    public const string SkeletonToggleCaption =
        "There is no ready-made course for this code, but there is a starting point shaped for the subject: folders that suit it, four units of class pages to rename, a page explaining what the site can do, and placeholders saying what belongs where.";

    /// <summary>Under the skeleton toggle, for a code whose ready-made pages were declined.</summary>
    public const string SkeletonToggleCaptionWhenExampleContentIsDeclined =
        "There is also a starting point shaped for the subject: folders that suit it, four units of class pages to rename, a page explaining what the site can do, and placeholders saying what belongs where.";

    /// <summary>Stands in for the structure editor while the example content chooses the folders.</summary>
    public const string StructureFromExampleNote =
        "The example content chooses the folders and files for this course, so every page lands where its links expect it. Turn off pre-populating to start from the subject’s own structure instead, and change it however you like.";

    /// <summary>
    /// Names that keep their capitals inside the lowercased subject, as whole
    /// words (<c>wizard.skeletonToggleLabelSubject.properNouns</c>).
    /// </summary>
    public static readonly IReadOnlyList<string> ProperNouns = new[]
    {
        "English", "French", "First Nations", "Métis", "Inuit", "Indigenous",
    };

    /// <summary>Starts that are written with a vowel and SOUND like a consonant: "a unit", "a one-".</summary>
    public static readonly IReadOnlyList<string> ConsonantSoundVowelStarts = new[]
    {
        "uni", "use", "usu", "uti", "ubi", "ura", "eu", "one", "once", "ewe",
    };

    /// <summary>Starts that are written with a consonant and SOUND like a vowel: "an hour".</summary>
    public static readonly IReadOnlyList<string> VowelSoundConsonantStarts = new[]
    {
        "hour", "honest", "honour", "honor", "heir",
    };

    /// <summary>
    /// "Start from an English skeleton": the template with the family's label
    /// filled in (GitHub issue #349, the mac's #336). The subject is the label
    /// LOWERCASED except for <see cref="ProperNouns"/>, which keep their
    /// capitals wherever they appear as whole words; the article is chosen by
    /// the first word's SOUND. The general family reads
    /// <see cref="SkeletonToggleLabelForAGeneralSkeleton"/> outright.
    /// </summary>
    /// <remarks>
    /// Until #349 the article was always "a", which rendered twelve of the
    /// fifty families wrongly ("a english skeleton", "a economics skeleton").
    /// Every comparison is ORDINAL on the lowercased word — a culture-aware
    /// comparison would let the machine's language decide an English article.
    /// </remarks>
    public static string SkeletonToggleLabel(string familyName, string label)
    {
        if (familyName == Catalogs.SkeletonCatalog.GeneralFamilyName) return SkeletonToggleLabelForAGeneralSkeleton;
        string subject = SkeletonSubject(label);
        return SkeletonToggleLabelTemplate
            .Replace("{article}", Article(subject), StringComparison.Ordinal)
            .Replace("{subject}", subject, StringComparison.Ordinal);
    }

    /// <summary>The label lowercased, with each proper noun put back where it stands as whole words.</summary>
    public static string SkeletonSubject(string label)
    {
        string subject = label.ToLowerInvariant();
        foreach (string noun in ProperNouns)
        {
            string lowered = noun.ToLowerInvariant();
            int at = 0;
            while ((at = subject.IndexOf(lowered, at, StringComparison.Ordinal)) >= 0)
            {
                int end = at + lowered.Length;
                bool startsAWord = at == 0 || !char.IsLetter(subject[at - 1]);
                bool endsAWord = end == subject.Length || !char.IsLetter(subject[end]);
                if (startsAWord && endsAWord)
                    subject = subject.Substring(0, at) + noun + subject.Substring(end);
                at = end;
            }
        }
        return subject;
    }

    /// <summary>"an" or "a" for the first word of a subject, by its first sound.</summary>
    public static string Article(string subject)
    {
        string word = subject.Split(' ', StringSplitOptions.RemoveEmptyEntries).FirstOrDefault()?.ToLowerInvariant() ?? "";
        if (ConsonantSoundVowelStarts.Any(start => word.StartsWith(start, StringComparison.Ordinal))) return "a";
        if (VowelSoundConsonantStarts.Any(start => word.StartsWith(start, StringComparison.Ordinal))) return "an";
        return word.Length > 0 && "aeiou".Contains(word[0]) ? "an" : "a";
    }
}
