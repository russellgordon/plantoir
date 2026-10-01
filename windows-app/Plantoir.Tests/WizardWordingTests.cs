using Plantoir.Core.Models;
using Xunit;

namespace Plantoir.Tests;

/// <summary>
/// What the New Course wizard says, against the contract.
///
/// <para>GitHub issue #119. Both apps have said "Create Course" since the
/// wizard existed and nothing pinned it anywhere that RUNS until 2026-09-08:
/// this side asserted it only in <c>NewCourseWizardUiTests</c>, which is
/// opt-in behind <c>PLANTOIR_UI_TESTS=1</c> and part of no gate, and the mac
/// asserted it nowhere. Two apps agreeing by habit is not two apps agreeing on
/// purpose — the first notice of a drift would have been a teacher reading a
/// different button from the one in the other platform's screenshots.</para>
/// </summary>
public class WizardWordingTests
{
    [Fact]
    public void TheCreateButtonIsTheOneInTheContract()
    {
        string expected = ContractLoader.LoadJson("shared-rules.json")
            ["wizard"]!["createCourseButton"]!.ToString();

        Assert.Equal(expected, WizardWording.CreateCourseButton);
    }

    /// <summary>
    /// And the dialog really uses the constant rather than a literal of its
    /// own.
    /// </summary>
    /// <remarks>
    /// <para>The honest limit of the test above: it pins the CONSTANT, so a
    /// view that went back to a literal would leave it unused and this suite
    /// green. <c>Plantoir.Tests</c> cannot reference the WinUI project — it
    /// targets <c>net9.0</c> where the app targets
    /// <c>net9.0-windows10.0.19041.0</c>, and a <c>ContentDialog</c> cannot be
    /// constructed off a XAML thread anyway — so the SOURCE is read
    /// instead.</para>
    ///
    /// <para>Cruder than a reference and it catches the one thing that
    /// matters: somebody typing the words back in. <c>NewCourseWizardUiTests</c>
    /// checks what is actually RENDERED, which nothing here can, and is opt-in
    /// for the same reason it always was.</para>
    /// </remarks>
    [Fact]
    public void TheWizardDialogUsesTheConstantRatherThanItsOwnCopy()
    {
        string source = File.ReadAllText(Path.Combine(
            ContractLoader.RepositoryRoot, "windows-app", "Plantoir", "Views", "NewCourseDialog.cs"));

        // Since #390 the button follows the club box: both words come from
        // WizardWording.Panel, and NEVER from the code (ClubCodeRule) — a
        // teacher can untick the box for a club-shaped code.
        Assert.Contains("PrimaryButtonText = WizardWording.Panel(isClub: false).CreateButton;", source);
        Assert.Contains("PrimaryButtonText = words.CreateButton;", source);
        Assert.Contains("var words = WizardWording.Panel(IsClub);", source);
        Assert.DoesNotContain("WizardWording.Panel(IsClubCode", source);
        Assert.DoesNotContain($"PrimaryButtonText = \"{WizardWording.CreateCourseButton}\"", source);
        Assert.DoesNotContain($"\"{WizardWording.ForAClub.CreateButton}\"", source);
    }

    /// <summary>
    /// The Starting Content sentences (#250), each against its own key.
    /// </summary>
    [Theory]
    [InlineData("noExampleContentNote", WizardWording.NoExampleContentNote)]
    [InlineData("noStartingContentNote", WizardWording.NoStartingContentNote)]
    [InlineData("skeletonToggleLabel", WizardWording.SkeletonToggleLabelTemplate)]
    [InlineData("skeletonToggleLabelForAGeneralSkeleton", WizardWording.SkeletonToggleLabelForAGeneralSkeleton)]
    [InlineData("skeletonToggleCaption", WizardWording.SkeletonToggleCaption)]
    [InlineData("skeletonToggleCaptionWhenExampleContentIsDeclined", WizardWording.SkeletonToggleCaptionWhenExampleContentIsDeclined)]
    [InlineData("structureFromExampleNote", WizardWording.StructureFromExampleNote)]
    public void EachStartingContentSentenceIsTheContracts(string key, string constant)
    {
        string expected = ContractLoader.LoadJson("shared-rules.json")["wizard"]![key]!.ToString();
        Assert.Equal(expected, constant);
    }

    [Fact]
    public void TheGeneralFamilyReadsItsOwnSentenceRatherThanThisCourse()
    {
        Assert.Equal(WizardWording.SkeletonToggleLabelForAGeneralSkeleton,
            WizardWording.SkeletonToggleLabel("general", "This Course"));
    }

    /// <summary>The dialog renders the constants rather than literals of its own (the honest limit above, again).</summary>
    [Fact]
    public void TheWizardDialogRendersTheStartingContentSentencesFromTheConstants()
    {
        string source = File.ReadAllText(Path.Combine(
            ContractLoader.RepositoryRoot, "windows-app", "Plantoir", "Views", "NewCourseDialog.cs"));
        foreach (string member in new[] { "NoExampleContentNote", "NoStartingContentNote", "SkeletonToggleCaption",
                     "SkeletonToggleCaptionWhenExampleContentIsDeclined", "StructureFromExampleNote", "SkeletonToggleLabel(" })
            Assert.Contains("WizardWording." + member, source);
        Assert.DoesNotContain("Example content isn’t available", source);
        Assert.DoesNotContain("$\"Start from a {", source);
        foreach (string id in new[] { "\"noStartingContentNote\"", "\"noExampleContentNote\"",
                     "\"skeletonToggleCaptionWhenExampleContentIsDeclined\"", "\"skeletonToggleLabel\"" })
            Assert.Contains(id, source);
    }
}
