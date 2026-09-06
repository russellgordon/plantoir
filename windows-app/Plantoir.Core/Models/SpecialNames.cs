using System;

namespace Plantoir.Core.Models;

/// <summary>
/// What a teacher is told when a folder or file a feature depends on cannot
/// simply be removed.
///
/// <para><b>Every sentence here is pinned to
/// <c>contracts/shared-rules.json</c> -> <c>specialNames</c> by
/// <c>SpecialNamesContractTests</c>.</b> They are written out in C# rather
/// than read from the contract at runtime for the same reason
/// <c>AssistWording</c> is: the contract is generated FROM the macOS app, so a
/// changed sentence must fail a Windows build rather than change a teacher's
/// screen on a machine the tests never ran on.</para>
///
/// <para><b>Each blocked sentence NAMES the switch to turn off first.</b> That
/// is the whole design: removal is never silently greyed out, and clicking
/// minus never auto-flips a related switch behind a dialog. The teacher is
/// told in plain words what depends on the folder and which control to change,
/// and then they decide. It also means these sentences and the app's actual
/// switch labels have to agree — see the note on
/// <see cref="CurriculumFolderBlockedByCoverageSetting"/>.</para>
/// </summary>
public static class SpecialNames
{
    // ---- Blocked: the curriculum folder ---------------------------------

    /// <summary>
    /// Course Settings, while the coverage map is on.
    ///
    /// <para><b>This sentence renamed a Windows switch.</b> It names "Publish
    /// the curriculum coverage map"; the Course Settings toggle here was
    /// called "Include Curriculum Coverage map", so the ⓘ would have sent a
    /// teacher looking for a control that did not exist under that name. The
    /// LABEL was changed to match the contract rather than the sentence
    /// changed to match the label: the contract is generated from the macOS
    /// app, so the mac's wording is the product's wording, and a Windows-only
    /// paraphrase is drift rather than a decision.</para>
    /// </summary>
    public const string CurriculumFolderBlockedByCoverageSetting =
        "The curriculum coverage map needs this folder to show your expectations. To remove it, turn off “Publish the curriculum coverage map” in Settings first.";

    /// <summary>
    /// New Course wizard, while curriculum PAGES are on. The jurisdiction is
    /// the province the course's code belongs to, so the sentence names the
    /// switch a BC teacher can actually see.
    /// </summary>
    public static string CurriculumFolderBlockedByCurriculumPages(string jurisdiction) =>
        $"This folder holds your curriculum expectations. To remove it, turn off “Include {jurisdiction} curriculum pages” first.";

    /// <summary>New Course wizard, while the coverage MAP is on.</summary>
    public const string CurriculumFolderBlockedByCoverageMap =
        "This folder holds your curriculum expectations for the coverage map. To remove it, turn off “Include the curriculum coverage map” first.";

    // ---- Blocked: the marks floor ---------------------------------------

    /// <summary>
    /// Course Settings: the last folder that counts for marks, while the
    /// coverage map is on. The LONGEST sentence in this file, and the one to
    /// size a flyout against.
    /// </summary>
    public const string LastGradedFolderBlocked =
        "At least one folder must count for marks while the curriculum coverage map is enabled. To remove or uncheck this folder, choose another graded folder under Marks first, or turn off “Publish the curriculum coverage map”.";

    /// <summary>The same floor in the wizard, naming the wizard's own switch.</summary>
    public const string LastGradedFolderBlockedWizard =
        "At least one folder must count for marks while the curriculum coverage map is enabled. To remove or uncheck this folder, choose another graded folder under Marks first, or turn off “Include the curriculum coverage map”.";

    // ---- Blocked: the per-section floor ---------------------------------

    /// <summary>
    /// The folder named "All Classes" is never removable — Russell's decision
    /// on 2026-08-24, replacing a rule that made class folders merely
    /// consequential when alternatives existed. The next-class button and the
    /// schedule write pages into that folder, so a confirmation would be
    /// asking the teacher to break both. EXACTLY that name, compared
    /// case-insensitively: every other per-section folder, including other
    /// names that mention classes, is as removable as before.
    /// </summary>
    public const string ClassFolderBlocked =
        "“All Classes” holds your class pages and lessons — the pages the next-class button and the schedule write to. It cannot be removed; other per-section folders can.";

    public const string LastPerSectionFolderBlocked =
        "Each section needs at least one folder for its class pages and lessons. Add another per-section folder first before removing this one.";

    public const string SectionIndexFileBlocked =
        "Every section needs an index.md page for its home page. Without it, the section cannot be published.";

    // ---- Consequential: ask first, then do it ---------------------------

    public static string RemoveGradedFolderTitle(string name) => $"Remove “{name}”?";

    public const string RemoveGradedFolderMessage =
        "This folder holds work that counts for marks. Removing it will take it out of your course’s marks pool.";

    public static string RemoveCurriculumFolderTitle(string name) => $"Remove “{name}”?";

    public const string RemoveCurriculumFolderMessage =
        "This folder holds your curriculum expectations. Removing it means expectations will not be available if you later enable curriculum coverage.";

    // ---- The switch labels these sentences name -------------------------

    /// <summary>
    /// The Course Settings coverage switch's label, kept here BESIDE the
    /// sentence that names it so the two cannot drift apart unnoticed. A test
    /// asserts the sentence contains this string.
    /// </summary>
    public const string CoverageSwitchLabelInSettings = "Publish the curriculum coverage map";

    /// <summary>The wizard's coverage switch label, same reasoning.</summary>
    public const string CoverageSwitchLabelInWizard = "Include the curriculum coverage map";

    /// <summary>The wizard's curriculum-pages switch label, for one jurisdiction.</summary>
    public static string CurriculumPagesSwitchLabel(string jurisdiction) =>
        $"Include {jurisdiction} curriculum pages";

    /// <summary>
    /// The jurisdiction named in the wizard's curriculum switch, when nothing
    /// better is known. Ontario is the default because that is the catalog
    /// every unrecognised code falls back to.
    /// </summary>
    public const string DefaultJurisdiction = "Ontario";
}
