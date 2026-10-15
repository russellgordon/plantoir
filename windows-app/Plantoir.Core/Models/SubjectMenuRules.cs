namespace Plantoir.Core.Models;

/// <summary>
/// Which items in the menu bar's File, Course, Section and View menus can be
/// used right now — decided in ONE pure place, from facts the window gathers
/// (#488, the mac's #457; <c>contracts/shared-rules.json</c> →
/// <c>subjectMenus</c>, run by <c>SubjectMenusContractTests</c>).
/// </summary>
/// <remarks>
/// <para><b>Presence follows the computer, enablement follows the selection.</b>
/// Whether "Revise With ▸ Claude…" is DRAWN depends on whether Claude is
/// installed — decided when the menu bar is built, never here. Whether it can
/// be USED depends on what is selected, and that is this type's whole job. The
/// menu bar GREYS what does not apply rather than hiding it, because a menu
/// whose items come and go with the selection cannot be learned; the sidebar's
/// context menus keep HIDING, because they are about one row.</para>
///
/// <para><b>A dialog greys everything</b> (<see cref="Situation.SheetIsUp"/>).
/// Measured on this PC for #488 (documentation/12-windows-app.md → "Menus, the
/// Section menu's functions and #475 on Windows"): WinUI did NOT deliver a menu
/// item's key with a ContentDialog up, unlike the mac, where a menu key fired
/// behind a sheet — but the rule is the contract's, and <c>MenuRoute.Run</c>
/// asks the window again at the click whatever this said, which is the guard
/// that counts.</para>
///
/// <para>The item and situation names are the contract's own, PascalCased:
/// <see cref="ContractName(Item)"/> and <see cref="ItemNamed"/> map them both
/// ways. "Finder" and "Terminal" in two names are the mac's neutral words for
/// what Windows calls Show in File Explorer and Open in Terminal; renaming them
/// here would break the mapping and buy nothing a teacher sees.</para>
/// </remarks>
public static class SubjectMenuRules
{
    /// <summary>What kind of sidebar row is selected.</summary>
    public enum Row { None, Course, Section, Backup, Archived, AllBackups }

    /// <summary>The outside assistants and the local one, for the Revise With items.</summary>
    public enum ReviseTarget { Claude, Codex, LocalAssistant }

    /// <summary>Every item whose enablement is decided here, in the contract's order.</summary>
    public enum Item
    {
        // File
        OpenWorkingFolder,
        OpenRecent,
        NewCourse,
        ImportCoursesForReference,
        RestoreFromArchive,
        ReloadCourses,
        // Course
        AddSection,
        CopyAPage,
        SaveCourseSettings,
        RevertCourseSettings,
        Rename,
        SetSchoolYear,
        KeepACopyForReference,
        BackUpNow,
        RestoreFromBackup,
        CourseReviseWithClaude,
        CourseReviseWithCodex,
        CourseReviseWithLocalAssistant,
        CourseOpenInObsidian,
        CourseShowInFinder,
        CourseNewTerminalAtFolder,
        DeleteBackup,
        DeleteArchive,
        RemoveCourse,
        // Section
        Preview,
        Deploy,
        OpenInBrowser,
        ScheduleDeploy,
        CancelScheduledDeploy,
        GetReadyForTheStartOfTheYear,
        UndoGettingReady,
        PublishPagesLinksLeadTo,
        SectionReviseWithClaude,
        SectionReviseWithCodex,
        SectionReviseWithLocalAssistant,
        SectionOpenInObsidian,
        SectionShowInFinder,
        SectionNewTerminalAtFolder,
        RemoveSection,
        // Section: the assistant's own functions (mac #457 batch B; #489 here).
        PublishPages,
        HidePages,
        PublishClassForADate,
        RebuildPreview,
        UndoLastChange,
        AddNextClass,
        ReDateClasses,
        MakeRoomForClasses,
        ClassDates,
        // View
        Back,
        Forward,
        ReloadPage,
    }

    /// <summary>
    /// Everything the rule needs to know, gathered by the window when the menu
    /// is refreshed and again at the click. Each property is a
    /// <c>situationKeys</c> entry of the contract, with its default.
    /// </summary>
    public sealed record Situation
    {
        /// <summary>A Plantoir window is in front with a working folder open.</summary>
        public bool HasFolder { get; init; }
        /// <summary>The folder's tools are still being copied, or the copy failed (#473 here, #476 on the mac).</summary>
        public bool FolderGettingReady { get; init; }
        /// <summary>A ContentDialog is up on the window.</summary>
        public bool SheetIsUp { get; init; }
        public Row Row { get; init; } = Row.None;
        /// <summary>The selected course, or the selected section's course, is kept for reference.</summary>
        public bool KeptForReference { get; init; }
        /// <summary>Rename and Add Section must wait: previewing, deploying, or an assistant holds the course (#458/#468).</summary>
        public bool StructuralHold { get; init; }
        /// <summary>The course is previewing or deploying.</summary>
        public bool Busy { get; init; }
        /// <summary>A copy of the course is being zipped (#351).</summary>
        public bool Copying { get; init; }
        /// <summary>A deploy of the course is running.</summary>
        public bool Deploying { get; init; }
        /// <summary>The selected section has a deploy scheduled.</summary>
        public bool HasSchedule { get; init; }
        /// <summary>The selected section holds a start-of-the-year undo (#96).</summary>
        public bool HasStartOfYearUndo { get; init; }
        /// <summary>The selected section's last build left a links checklist (#379).</summary>
        public bool HasLinksOffer { get; init; }
        /// <summary>Which Revise targets are greyed for a reason (#458).</summary>
        public IReadOnlySet<ReviseTarget> ReviseBlocked { get; init; } = new HashSet<ReviseTarget>();
        public bool ObsidianInstalled { get; init; }
        /// <summary>Course Settings is showing with an unsaved change Save would write.</summary>
        public bool SettingsMaySave { get; init; }
        /// <summary>Course Settings is showing with an unsaved change Revert would discard.</summary>
        public bool SettingsMayRevert { get; init; }
        /// <summary>The section window's Preview (or Stop Preview) button is enabled.</summary>
        public bool PreviewButtonEnabled { get; init; }
        /// <summary>The section window's Deploy button would be enabled.</summary>
        public bool DeployButtonEnabled { get; init; }
        /// <summary>The section window is showing a preview.</summary>
        public bool PreviewIsShowing { get; init; }
        /// <summary>A preview of the selected section is running, building or showing.</summary>
        public bool PreviewIsRunning { get; init; }
        /// <summary>The last change the Section menu made in this window was made in the selected section.</summary>
        public bool LastChangeIsHere { get; init; }
        /// <summary>One of the assistant's functions is running on the selected section.</summary>
        public bool VerbIsRunning { get; init; }
        public bool CanGoBack { get; init; }
        public bool CanGoForward { get; init; }
    }

    /// <summary>The items that can be used in <paramref name="situation"/>.</summary>
    public static IReadOnlySet<Item> Enabled(Situation situation)
    {
        var enabled = new HashSet<Item>();
        if (situation.SheetIsUp) return enabled;

        bool isLive = !situation.KeptForReference;
        bool isCourse = situation.Row == Row.Course;
        bool isSection = situation.Row == Row.Section;
        bool isCourseOrSection = isCourse || isSection;

        // File. Open Working Folder… and Open Recent are live in any window
        // without a dialog. (The mac's "no window" case does not exist here:
        // the menu bar lives inside a window, and closing the last one quits.)
        enabled.Add(Item.OpenWorkingFolder);
        enabled.Add(Item.OpenRecent);
        if (situation.HasFolder && !situation.FolderGettingReady) enabled.Add(Item.NewCourse);
        if (situation.HasFolder)
        {
            enabled.Add(Item.ImportCoursesForReference);
            enabled.Add(Item.ReloadCourses);
        }
        if (situation.Row == Row.Archived) enabled.Add(Item.RestoreFromArchive);

        // Course: with a section selected these act on its course.
        if (isCourseOrSection)
        {
            enabled.Add(Item.CopyAPage);
            if (isLive && !situation.StructuralHold)
            {
                enabled.Add(Item.AddSection);
                enabled.Add(Item.Rename);
            }
            if (!isLive) enabled.Add(Item.SetSchoolYear);
            if (isLive && !situation.Busy) enabled.Add(Item.KeepACopyForReference);
            if (!situation.Copying) enabled.Add(Item.BackUpNow);
        }
        if (situation.SettingsMaySave) enabled.Add(Item.SaveCourseSettings);
        if (situation.SettingsMayRevert) enabled.Add(Item.RevertCourseSettings);
        if (situation.Row == Row.Backup && !situation.Copying) enabled.Add(Item.RestoreFromBackup);
        // The Revise and folder group acts on the course ROW only: with a
        // section selected the Section menu's copy is the live one, so the two
        // Open in Obsidian items are never enabled at once.
        if (isCourse && isLive)
        {
            if (!situation.ReviseBlocked.Contains(ReviseTarget.Claude)) enabled.Add(Item.CourseReviseWithClaude);
            if (!situation.ReviseBlocked.Contains(ReviseTarget.Codex)) enabled.Add(Item.CourseReviseWithCodex);
            // The local assistant works per SECTION: never live on a course row.
        }
        if (isCourse && situation.ObsidianInstalled) enabled.Add(Item.CourseOpenInObsidian);
        if (isCourse || situation.Row == Row.Backup || situation.Row == Row.Archived) enabled.Add(Item.CourseShowInFinder);
        if (isCourse) enabled.Add(Item.CourseNewTerminalAtFolder);
        if (situation.Row == Row.Backup) enabled.Add(Item.DeleteBackup);
        if (situation.Row == Row.Archived) enabled.Add(Item.DeleteArchive);
        if (isCourse && !situation.Copying) enabled.Add(Item.RemoveCourse);

        // Section
        if (isSection)
        {
            if (situation.PreviewButtonEnabled) enabled.Add(Item.Preview);
            if (situation.DeployButtonEnabled && isLive) enabled.Add(Item.Deploy);
            if (situation.PreviewIsShowing) enabled.Add(Item.OpenInBrowser);
            // Neither on a course kept for reference: nothing deploys from one,
            // and the menu bar may not disagree with its row (the mac's ruling
            // on #457's implementation review).
            if (isLive && !situation.HasSchedule) enabled.Add(Item.ScheduleDeploy);
            if (isLive && situation.HasSchedule) enabled.Add(Item.CancelScheduledDeploy);
            if (isLive && !situation.Deploying)
            {
                enabled.Add(Item.GetReadyForTheStartOfTheYear);
                if (situation.HasStartOfYearUndo) enabled.Add(Item.UndoGettingReady);
                if (situation.HasLinksOffer) enabled.Add(Item.PublishPagesLinksLeadTo);
            }
            if (isLive)
            {
                if (!situation.ReviseBlocked.Contains(ReviseTarget.Claude)) enabled.Add(Item.SectionReviseWithClaude);
                if (!situation.ReviseBlocked.Contains(ReviseTarget.Codex)) enabled.Add(Item.SectionReviseWithCodex);
                if (!situation.ReviseBlocked.Contains(ReviseTarget.LocalAssistant)) enabled.Add(Item.SectionReviseWithLocalAssistant);
            }
            // The assistant's functions: each writes to the section, so none on
            // a course kept for reference, none while it deploys or a copy is
            // being zipped, and one at a time. Rebuild Preview writes only the
            // built site, so it is live on a reference course.
            bool verbsMayRun = isLive && !situation.Deploying && !situation.Copying && !situation.VerbIsRunning;
            if (verbsMayRun)
            {
                enabled.Add(Item.PublishPages);
                enabled.Add(Item.HidePages);
                enabled.Add(Item.PublishClassForADate);
                enabled.Add(Item.AddNextClass);
                enabled.Add(Item.ReDateClasses);
                enabled.Add(Item.MakeRoomForClasses);
                enabled.Add(Item.ClassDates);
                if (situation.LastChangeIsHere) enabled.Add(Item.UndoLastChange);
            }
            if (situation.PreviewIsRunning && situation.PreviewButtonEnabled && !situation.VerbIsRunning)
                enabled.Add(Item.RebuildPreview);
            if (situation.ObsidianInstalled) enabled.Add(Item.SectionOpenInObsidian);
            enabled.Add(Item.SectionShowInFinder);
            enabled.Add(Item.SectionNewTerminalAtFolder);
            // Not on a course kept for reference (interface.whatIsWithheld).
            if (isLive && !situation.Copying) enabled.Add(Item.RemoveSection);
        }

        // View: the embedded preview's own navigation.
        if (situation.PreviewIsShowing)
        {
            enabled.Add(Item.ReloadPage);
            if (situation.CanGoBack) enabled.Add(Item.Back);
            if (situation.CanGoForward) enabled.Add(Item.Forward);
        }
        return enabled;
    }

    /// <summary>The contract's name for an item: the enum name with its first letter lowered.</summary>
    public static string ContractName(Item item) => Camel(item.ToString());

    /// <summary>The item the contract calls <paramref name="name"/>, or null.</summary>
    public static Item? ItemNamed(string name) =>
        Enum.GetValues<Item>().Cast<Item?>().FirstOrDefault(item => ContractName(item!.Value) == name);

    /// <summary>The contract's name for a row (<c>none</c>, <c>allBackups</c>, …).</summary>
    public static string ContractName(Row row) => Camel(row.ToString());

    /// <summary>The contract's name for a Revise target (<c>claude</c>, <c>codex</c>, <c>localAssistant</c>).</summary>
    public static string ContractName(ReviseTarget target) => Camel(target.ToString());

    private static string Camel(string name) => char.ToLowerInvariant(name[0]) + name[1..];
}
