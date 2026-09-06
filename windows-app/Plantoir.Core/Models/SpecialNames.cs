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

    // ---- Renaming a folder ------------------------------------------
    // Every sentence below is the contract's own, taken from it rather than
    // retyped, and pinned by SpecialFolderRenamerTests. The refusals are all
    // checked before anything on disk is touched.

    public const string RenameProblemEmpty =
        "Type the folder’s new name.";

    public const string RenameProblemUnchanged =
        "That is already this folder’s name.";

    /// <summary>Windows adds the backslash to the two the contract names, because on this platform it is a separator too.</summary>
    public const string RenameProblemHasSeparator =
        "A folder’s name cannot contain “/” or “:”.";

    public const string RenameProblemIsHidden =
        "A name starting with a dot makes the folder hidden, and Plantoir would stop finding it.";

    public const string RenameProblemIsMedia =
        "Plantoir looks after the Media folder itself, so nothing else can be called Media.";

    /// <summary>Carries {name}.</summary>
    public const string RenameProblemAlreadyUsed =
        "This course already has a folder called “{name}”.";

    /// <summary>Carries {name}.</summary>
    public const string RenameProblemLooksLikeASection =
        "“{name}” is what Plantoir calls a section’s own folder, so it cannot be used here.";

    /// <summary>Carries {name}.</summary>
    public const string RenameProblemDestinationExists =
        "There is already something called “{name}” beside it. Move or rename that first.";

    /// <summary>
    /// A name Windows itself will not accept. Carries {name}.
    ///
    /// <para>NOT in the contract, and written here knowingly — the handoff's
    /// "Sentences the contract does not carry" list is where this kind
    /// belongs. The contract's `hasSeparator` names only "/" and ":", because
    /// those are the two that matter on the mac. Windows additionally refuses
    /// <c>&lt; &gt; " | ? *</c>, a trailing dot or space, and the device names
    /// (CON, PRN, NUL, AUX, COM1…) it has reserved since DOS.</para>
    ///
    /// <para>Without this, <c>CON</c> passes every check and fails at the move
    /// with whatever the operating system says; and <c>Tasks.</c> is worse
    /// still, because Windows strips the trailing dot, so
    /// <c>Directory.Exists</c> finds the ORIGINAL folder and the teacher is
    /// told "There is already something called Tasks. beside it" about the
    /// folder they are renaming.</para>
    /// </summary>
    public const string RenameProblemWindowsWontAllowIt =
        "Windows does not allow a folder to be called \u201c{name}\u201d. Try another name.";

    /// <summary>The sheet's title. Carries {name}.</summary>
    public const string RenameSheetTitle =
        "Rename “{name}”";

    /// <summary>
    /// What the sheet explains before the teacher commits.
    ///
    /// <para>The contract's sentence says "on your Mac", which is that
    /// platform's wording rather than a shared one — the same deliberate
    /// difference as "Setting up this Mac" against "Setting up this PC" in
    /// app-rules.json's markerOrigins. Said here as "on this PC". Flagged in
    /// MAC-HANDOFF so the contract can mark it platform-specific, rather than
    /// leaving the next reader to conclude that Windows drifted.</para>
    /// </summary>
    public const string RenameExplanation =
        "This renames the folder on this PC — in every section that has one — and points your pages’ links at the new name. It happens straight away, so Cancel in Settings will not undo it.";

    /// <summary>Carries {old} and {new}.</summary>
    public const string RenameDone =
        "“{old}” is now “{new}”.";

    public const string RenameRelinkedOne =
        "One page had links pointing into it, and they now point at the new name.";

    /// <summary>Carries {count}.</summary>
    public const string RenameRelinkedMany =
        "{count} pages had links pointing into it, and they now point at the new name.";

    public const string RenameRelinkedNone =
        "No page linked into it by name, so nothing else needed changing.";

    /// <summary>"your Mac" in the contract; "this PC" here, as above.</summary>
    public const string RenameNothingWasThere =
        "There was no folder by that name on this PC, so only this course’s settings changed. Make it in Obsidian when you need it.";
}
