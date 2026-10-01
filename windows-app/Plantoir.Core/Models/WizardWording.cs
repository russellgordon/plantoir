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
    /// "Start from a computer studies skeleton": the template with the
    /// family's label filled in. The general family reads
    /// <see cref="SkeletonToggleLabelForAGeneralSkeleton"/> outright.
    /// </summary>
    public static string SkeletonToggleLabel(string familyName, string label)
    {
        if (familyName == Catalogs.SkeletonCatalog.GeneralFamilyName) return SkeletonToggleLabelForAGeneralSkeleton;
        string subject = label.ToLowerInvariant();
        return SkeletonToggleLabelTemplate.Replace("{article}", "a").Replace("{subject}", subject);
    }
}
