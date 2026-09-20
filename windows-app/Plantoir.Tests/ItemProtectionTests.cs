using Plantoir.Core.Models;

namespace Plantoir.Tests;

/// <summary>
/// What happens when a teacher presses minus, per list and per course state.
///
/// The SENTENCES are pinned against the contract in
/// <see cref="SpecialNamesContractTests"/>; these are the RULES — which case
/// applies when. Written as behaviour a teacher would recognise, because the
/// failure this guards against is a folder that silently stops publishing.
/// </summary>
public class ItemProtectionTests
{
    private static ProtectionContext Settings(
        bool coverage = true,
        string? curriculumFolder = "Ontario Curriculum",
        string[]? graded = null,
        string[]? perSection = null) =>
        new(InWizard: false,
            CurriculumCoverageEnabled: coverage,
            CurriculumPagesEnabled: false,
            Jurisdiction: SpecialNames.DefaultJurisdiction,
            ResolvedCurriculumFolder: curriculumFolder,
            GradedFolders: graded ?? new[] { "Tasks" },
            PerSectionFolders: perSection ?? new[] { "All Classes" });

    private static ProtectionContext Wizard(
        bool coverage = true,
        bool pages = false,
        string jurisdiction = "Ontario",
        string? curriculumFolder = "Ontario Curriculum",
        string[]? graded = null,
        string[]? perSection = null) =>
        new(InWizard: true,
            CurriculumCoverageEnabled: coverage,
            CurriculumPagesEnabled: pages,
            Jurisdiction: jurisdiction,
            ResolvedCurriculumFolder: curriculumFolder,
            GradedFolders: graded ?? new[] { "Tasks" },
            PerSectionFolders: perSection ?? new[] { "All Classes" });

    // ---- All Classes -----------------------------------------------------

    /// <summary>
    /// Russell's decision, 2026-08-24: EXACTLY that folder, never removable,
    /// however many per-section folders there are. The next-class button and
    /// the schedule write pages into it, so a confirmation would be asking the
    /// teacher to break both.
    /// </summary>
    [Fact]
    public void AllClassesIsNeverRemovable()
    {
        var many = Settings(perSection: new[] { "All Classes", "Handouts", "Labs" });
        var protection = ItemProtectionRule.For("All Classes", ItemList.PerSectionFolders, many);

        Assert.True(protection.IsBlocked);
        Assert.Equal(SpecialNames.ClassFolderBlocked, protection.Reason);
    }

    [Fact]
    public void AllClassesIsMatchedWithoutRegardToCase()
    {
        var many = Settings(perSection: new[] { "all classes", "Handouts" });
        Assert.True(ItemProtectionRule.For("all classes", ItemList.PerSectionFolders, many).IsBlocked);
    }

    /// <summary>
    /// The rule is that ONE name, not "anything mentioning classes". A folder
    /// called "Class Resources" is as removable as it ever was — the rule this
    /// replaced was wider, and narrowing it back is the decision.
    /// </summary>
    [Fact]
    public void AnotherFolderThatMentionsClassesIsStillRemovable()
    {
        var many = Settings(perSection: new[] { "All Classes", "Class Resources" });
        var protection = ItemProtectionRule.For("Class Resources", ItemList.PerSectionFolders, many);

        Assert.Equal(ProtectionKind.Ordinary, protection.Kind);
    }

    // ---- The per-section floor ------------------------------------------

    [Fact]
    public void TheLastPerSectionFolderCannotGo()
    {
        var only = Settings(perSection: new[] { "Handouts" });
        var protection = ItemProtectionRule.For("Handouts", ItemList.PerSectionFolders, only);

        Assert.True(protection.IsBlocked);
        Assert.Equal(SpecialNames.LastPerSectionFolderBlocked, protection.Reason);
    }

    [Fact]
    public void SectionIndexCannotGo()
    {
        var protection = ItemProtectionRule.For("index.md", ItemList.PerSectionFiles, Settings());
        Assert.True(protection.IsBlocked);
        Assert.Equal(SpecialNames.SectionIndexFileBlocked, protection.Reason);

        Assert.True(ItemProtectionRule.For("INDEX.MD", ItemList.PerSectionFiles, Settings()).IsBlocked);
        Assert.Equal(ProtectionKind.Ordinary,
            ItemProtectionRule.For("Key Links.md", ItemList.PerSectionFiles, Settings()).Kind);
    }

    // ---- The curriculum folder ------------------------------------------

    [Fact]
    public void InSettingsTheCurriculumFolderIsBlockedWhileTheMapIsOn()
    {
        var protection = ItemProtectionRule.For(
            "Ontario Curriculum", ItemList.SharedFolders, Settings(coverage: true));

        Assert.True(protection.IsBlocked);
        Assert.Equal(SpecialNames.CurriculumFolderBlockedByCoverageSetting, protection.Reason);
        // The whole design: name the switch, so the teacher knows what to do.
        Assert.Contains(SpecialNames.CoverageSwitchLabelInSettings, protection.Reason);
    }

    [Fact]
    public void WithTheMapOffTheCurriculumFolderMerelyAsksFirst()
    {
        var protection = ItemProtectionRule.For(
            "Ontario Curriculum", ItemList.SharedFolders, Settings(coverage: false));

        Assert.True(protection.AsksFirst);
        Assert.Equal(SpecialNames.RemoveCurriculumFolderTitle("Ontario Curriculum"), protection.Title);
        Assert.Equal(SpecialNames.RemoveCurriculumFolderMessage, protection.Message);
    }

    [Fact]
    public void InTheWizardTheCoverageMapBlocksBeforeCurriculumPagesDo()
    {
        var protection = ItemProtectionRule.For("Ontario Curriculum", ItemList.SharedFolders,
            Wizard(coverage: true, pages: true));

        Assert.Equal(SpecialNames.CurriculumFolderBlockedByCoverageMap, protection.Reason);
    }

    [Fact]
    public void InTheWizardCurriculumPagesBlockWhenTheMapIsOff()
    {
        var protection = ItemProtectionRule.For("Ontario Curriculum", ItemList.SharedFolders,
            Wizard(coverage: false, pages: true));

        Assert.Equal(SpecialNames.CurriculumFolderBlockedByCurriculumPages("Ontario"), protection.Reason);
    }

    /// <summary>
    /// A BC teacher is told to turn off the switch a BC teacher can see. The
    /// wizard's own label is built from the same jurisdiction, so the two
    /// cannot disagree.
    /// </summary>
    [Fact]
    public void TheWizardSentenceNamesTheProvinceOnTheSwitch()
    {
        var protection = ItemProtectionRule.For("BC Curriculum", ItemList.SharedFolders,
            Wizard(coverage: false, pages: true, jurisdiction: "British Columbia",
                   curriculumFolder: "BC Curriculum"));

        Assert.Contains(SpecialNames.CurriculumPagesSwitchLabel("British Columbia"), protection.Reason);
        Assert.DoesNotContain("Ontario", protection.Reason);
    }

    [Fact]
    public void InTheWizardWithBothOffTheCurriculumFolderMerelyAsksFirst()
    {
        var protection = ItemProtectionRule.For("Ontario Curriculum", ItemList.SharedFolders,
            Wizard(coverage: false, pages: false));

        Assert.True(protection.AsksFirst);
    }

    /// <summary>
    /// Only the RESOLVED folder is protected — a second folder that happens to
    /// mention curriculum is not the one the build would use.
    /// </summary>
    [Fact]
    public void OnlyTheResolvedCurriculumFolderIsProtected()
    {
        var context = Settings(curriculumFolder: "AP Curriculum");
        Assert.True(ItemProtectionRule.For("AP Curriculum", ItemList.SharedFolders, context).IsBlocked);
        Assert.Equal(ProtectionKind.Ordinary,
            ItemProtectionRule.For("Ontario Curriculum", ItemList.SharedFolders, context).Kind);
    }

    // ---- The marks floor -------------------------------------------------

    [Fact]
    public void TheLastGradedFolderCannotGoWhileTheMapIsOn()
    {
        var context = Settings(coverage: true, graded: new[] { "Tasks" });
        var protection = ItemProtectionRule.For("Tasks", ItemList.SharedFolders, context);

        Assert.True(protection.IsBlocked);
        Assert.Equal(SpecialNames.LastGradedFolderBlocked, protection.Reason);
    }

    [Fact]
    public void TheSameFloorAppliesToUntickingInTheMarksList()
    {
        var context = Settings(coverage: true, graded: new[] { "Tasks" });
        Assert.True(ItemProtectionRule.For("Tasks", ItemList.GradedFolders, context).IsBlocked);
    }

    /// <summary>
    /// Ticking a SECOND folder is what unblocks the first — which is why the
    /// context is re-read on every interaction rather than captured once.
    /// </summary>
    [Fact]
    public void ASecondGradedFolderUnblocksTheFirst()
    {
        var context = Settings(coverage: true, graded: new[] { "Tasks", "Tests" });
        var protection = ItemProtectionRule.For("Tasks", ItemList.SharedFolders, context);

        Assert.True(protection.AsksFirst);
        Assert.Equal(SpecialNames.RemoveGradedFolderMessage, protection.Message);
    }

    /// <summary>Turning the map off is the other way out, and the sentence says so.</summary>
    [Fact]
    public void TurningTheMapOffUnblocksTheLastGradedFolder()
    {
        var context = Settings(coverage: false, graded: new[] { "Tasks" });
        var protection = ItemProtectionRule.For("Tasks", ItemList.SharedFolders, context);

        Assert.True(protection.AsksFirst);
        Assert.Equal(ProtectionKind.Consequential, protection.Kind);
    }

    [Fact]
    public void TheWizardsMarksFloorNamesTheWizardsOwnSwitch()
    {
        var context = Wizard(coverage: true, graded: new[] { "Tasks" });
        var protection = ItemProtectionRule.For("Tasks", ItemList.GradedFolders, context);

        Assert.Equal(SpecialNames.LastGradedFolderBlockedWizard, protection.Reason);
        Assert.Contains(SpecialNames.CoverageSwitchLabelInWizard, protection.Reason);
    }

    [Fact]
    public void AGradedFolderIsMatchedWithoutRegardToCase()
    {
        var context = Settings(coverage: false, graded: new[] { "Tasks" });
        Assert.True(ItemProtectionRule.For("tasks", ItemList.SharedFolders, context).AsksFirst);
    }

    // ---- Everything else -------------------------------------------------

    [Fact]
    public void AnOrdinaryFolderIsJustRemoved()
    {
        Assert.Equal(ProtectionKind.Ordinary,
            ItemProtectionRule.For("Concepts", ItemList.SharedFolders, Settings()).Kind);
        Assert.Equal(ProtectionKind.Ordinary,
            ItemProtectionRule.For("Learning Goals.md", ItemList.SharedFiles, Settings()).Kind);
    }

    [Fact]
    public void AnEmptyNameIsOrdinaryRatherThanThrowing()
    {
        Assert.Equal(ProtectionKind.Ordinary,
            ItemProtectionRule.For("", ItemList.SharedFolders, Settings()).Kind);
    }

    /// <summary>
    /// A course with no curriculum folder at all protects nothing as one —
    /// the resolver returns null and every shared folder is ordinary.
    /// </summary>
    [Fact]
    public void ACourseWithNoCurriculumFolderProtectsNothingAsOne()
    {
        var context = Settings(curriculumFolder: null, graded: new[] { "Tasks", "Tests" });
        Assert.Equal(ProtectionKind.Ordinary,
            ItemProtectionRule.For("Concepts", ItemList.SharedFolders, context).Kind);
    }

    // ---- The wizard's EFFECTIVE switch values ---------------------------

    /// <summary>
    /// The coverage switch counts as ON only when the teacher can REACH it.
    ///
    /// <para>The wizard only creates that switch for a code with example
    /// content that includes curriculum, and only enables it while
    /// pre-populate and curriculum pages are both on. A rule that reads the
    /// raw switch instead blocks a removal and names a control that is not on
    /// the screen — which is the deadlock this was written to prevent, and
    /// which the first cut of the port shipped.</para>
    /// </summary>
    [Theory]
    // hasContent, prepopulating, contentHasCurriculum, pagesOn, coverageOn, expected
    [InlineData(true,  true,  true,  true,  true,  true)]
    [InlineData(false, true,  true,  true,  true,  false)]   // no example content: switch never created
    [InlineData(true,  false, true,  true,  true,  false)]   // pre-populate off: switch disabled
    [InlineData(true,  true,  false, true,  true,  false)]   // payload has no curriculum
    [InlineData(true,  true,  true,  false, true,  false)]   // curriculum pages off: switch disabled
    [InlineData(true,  true,  true,  true,  false, false)]   // reachable, and switched off
    public void TheCoverageSwitchCountsAsOnOnlyWhenItCanBeReached(
        bool hasContent, bool prepopulating, bool contentHasCurriculum,
        bool pagesOn, bool coverageOn, bool expected)
    {
        Assert.Equal(expected, CourseConfiguration.CurriculumCoverageEnabled(
            hasContent, prepopulating, contentHasCurriculum, pagesOn, coverageOn));
    }

    /// <summary>
    /// The commonest from-scratch path, end to end: a code with no example
    /// content leaves nothing blocked on a switch the teacher cannot see.
    /// Both folders ask first instead, which is a way forward.
    /// </summary>
    [Fact]
    public void AFromScratchCourseIsNeverBlockedOnAnUnreachableSwitch()
    {
        bool coverage = CourseConfiguration.CurriculumCoverageEnabled(
            hasExampleContent: false, prepopulating: false,
            contentIncludesCurriculum: false, curriculumPagesSwitchIsOn: true,
            coverageSwitchIsOn: true);
        Assert.False(coverage);

        var context = Wizard(coverage: coverage, pages: CourseConfiguration.CurriculumPagesEnabled(
            hasExampleContent: false, prepopulating: false,
            contentIncludesCurriculum: false, curriculumSwitchIsOn: true));

        // The wizard's factory defaults: "Ontario Curriculum" and one graded
        // folder, "Tasks" — the two rows that deadlocked.
        Assert.True(ItemProtectionRule.For("Ontario Curriculum", ItemList.SharedFolders, context).AsksFirst);
        Assert.True(ItemProtectionRule.For("Tasks", ItemList.SharedFolders, context).AsksFirst);
        Assert.False(ItemProtectionRule.For("Ontario Curriculum", ItemList.SharedFolders, context).IsBlocked);
        Assert.False(ItemProtectionRule.For("Tasks", ItemList.SharedFolders, context).IsBlocked);

        // "All Classes" is blocked by a rule that names no switch at all, so
        // it stays blocked — and that is correct.
        Assert.True(ItemProtectionRule.For("All Classes", ItemList.PerSectionFolders, context).IsBlocked);
    }

    /// <summary>
    /// Blocked outranks consequential. A folder that is BOTH the curriculum
    /// folder and the last graded one must show the curriculum reason rather
    /// than quietly asking, because the ⓘ has to explain the rule that would
    /// actually refuse.
    /// </summary>
    [Fact]
    public void AFolderThatIsBothTheCurriculumFolderAndGradedIsBlocked()
    {
        var context = Settings(coverage: true, curriculumFolder: "Tasks", graded: new[] { "Tasks" });
        Assert.True(ItemProtectionRule.For("Tasks", ItemList.SharedFolders, context).IsBlocked);
    }
}
