namespace Plantoir.Core.Models;

/// <summary>What the sidebar has selected.</summary>
///
/// <remarks>
/// Lives in Core rather than in the WinUI project so the rule below can be
/// TESTED: <c>Plantoir.Tests</c> is plain <c>net9.0</c> and cannot reference
/// <c>Plantoir.ViewModels</c>, which is why nothing gated this rule before
/// (issue #162). Nothing about the type changed on the way down — no XAML
/// names it, and <see cref="Serialized"/> and <see cref="Parse"/> already
/// delegated to <see cref="WindowMemoryCodec"/>, so the strings
/// <c>App.RememberOpenWindows</c> writes are identical. Precedent:
/// <c>FolderRemoval</c>, moved the same way for issue #142.
/// </remarks>
public abstract record SidebarSelection
{
    public sealed record CourseItem(string Code) : SidebarSelection;
    public sealed record SectionItem(string Code, int Number) : SidebarSelection;
    public sealed record ArchivedEntry(string Id) : SidebarSelection;
    public sealed record BackupEntry(string Id) : SidebarSelection;

    /// <summary>The stored string form for per-window restore (row 99).</summary>
    public string Serialized => this switch
    {
        CourseItem(var code) => WindowMemoryCodec.EncodeCourse(code),
        SectionItem(var code, var number) => WindowMemoryCodec.EncodeSection(code, number),
        ArchivedEntry(var id) => WindowMemoryCodec.EncodeArchived(id),
        BackupEntry(var id) => WindowMemoryCodec.EncodeBackup(id),
        _ => "",
    };

    /// <summary>Unrecognized or empty stored forms restore no selection.</summary>
    public static SidebarSelection? Parse(string? stored) =>
        WindowMemoryCodec.ParseSelection(stored) switch
        {
            { Kind: "course" } d => new CourseItem(d.Code),
            { Kind: "section" } d => new SectionItem(d.Code, d.Section),
            { Kind: "archived" } d => new ArchivedEntry(d.Id),
            { Kind: "backup" } d => new BackupEntry(d.Id),
            _ => null,
        };
}

/// <summary>
/// The part of a window's state that a change of working folder decides:
/// which folder it is pointed at, what the sidebar has selected, and the
/// sidebar memory that SURVIVES the change.
///
/// <para>The rule is
/// <c>contracts/shared-rules.json</c> → <c>workingFolderSelection</c>, and it
/// is here so that both ways a folder is adopted go through ONE funnel:
/// <see cref="PointAt"/>. Two clears, one per route, is how a route quietly
/// keeps the old folder's selection while the other lets go — which is the
/// shape of the mac's issue #93 and of this one.</para>
///
/// <para>What is deliberately NOT done here is as load-bearing as what is.
/// The selection is never checked against the courses that just loaded: that
/// would erase the legitimately RIGHT "Course Not Found" a teacher sees after
/// deleting a course in File Explorer with its window open, it would make what
/// they see depend on when some unrelated reload happened to run (courses are
/// reloaded after every rename, backup, restore and archive), and it would
/// still land on the wrong course when the new folder has one wearing the same
/// code. Both rejections are written out in the contract.</para>
/// </summary>
public sealed class WindowFolderState
{
    /// <summary>The working folder this window is pointed at, or null before it has one.</summary>
    public string? FolderPath { get; private set; }

    /// <summary>What the sidebar has selected — the thing a folder change lets go of.</summary>
    public SidebarSelection? Selection { get; set; }

    // ---- Kept across a folder change --------------------------------------
    //
    // The filter is a way of LOOKING rather than a thing named: a teacher who
    // typed "3U" to narrow one folder is usually after the same courses in the
    // next. Disclosure state is the sidebar's SHAPE — a code left open that
    // this folder does not have draws nothing at all, and no action hangs off
    // a disclosure triangle for it to aim at the wrong folder.

    public string FilterText { get; set; } = "";

    /// <summary>null means "every course open" — the Windows fallback.</summary>
    public HashSet<string>? ExpandedCourseCodes { get; set; }
    public bool IsShowingArchived { get; set; }
    public bool IsShowingBackups { get; set; }

    /// <summary>
    /// Point this window at a working folder — the ONE place a folder is
    /// adopted, whether the teacher chose it or the app restored it.
    ///
    /// <para>Returns the folder LEFT BEHIND, or null when none was: pointing a
    /// window at the folder it already shows is not a change of folder, so
    /// nothing is let go of and nothing is released. Sameness is
    /// <see cref="WorkingFolder.IsTheSame"/>, so re-choosing the open folder
    /// from the OS picker — which hands back the true on-disk casing, not the
    /// casing the path was stored with — counts as the same folder.</para>
    /// </summary>
    public string? PointAt(string path)
    {
        string? leftBehind = WorkingFolder.IsLeavingAFolderBehind(FolderPath, path) ? FolderPath : null;
        if (leftBehind is not null) LetGoOfTheFolderBeingLeft();
        FolderPath = path;
        return leftBehind;
    }

    /// <summary>
    /// Everything this window holds that NAMES a course, an archive or a
    /// backup in the folder being left. A sentence naming a course the window
    /// no longer shows is worse than no sentence, because it will be read as
    /// being about the folder now on screen.
    ///
    /// <para>On Windows that reduces to the selection, and the reduction is a
    /// finding rather than an omission. The mac also lets go of five pending
    /// confirmations and four alerts, which it holds as FIELDS; here every one
    /// of those is an awaited modal <c>ContentDialog</c> (SidebarPane's
    /// archive, restore, delete and rename confirmations), so the state is a
    /// continuation on the stack with nothing to clear — and the folder it
    /// acts on is read inside that continuation rather than pinned when the
    /// dialog went up. Inventing fields to clear would mean inventing the
    /// state to go with them.</para>
    ///
    /// <para><b>What the modality does and does not close.</b> The MENU route
    /// to the folder picker is genuinely shut while a dialog is up:
    /// <c>OpenWorkingFolder_Click</c> is a <c>MenuFlyoutItem</c>, and the
    /// dialog's overlay covers the menu bar. The <b>Ctrl+O accelerator is
    /// NOT</b> — it is declared on MainWindow's <c>Root</c> grid, WinUI
    /// searches for accelerators window-wide unless a <c>ScopeOwner</c> says
    /// otherwise, and none is set. So a teacher who presses Ctrl+O with a
    /// restore confirmation on screen can still change folder, and answering
    /// the dialog afterwards acts on the folder they have left. This is
    /// written down rather than fixed here, because the fix is a guard on
    /// every dialog-raising path rather than anything this rule can do — see
    /// documentation/12-windows-app.md, "What the modality does not close".</para>
    ///
    /// <para>Nothing is chosen in the new folder to take the selection's
    /// place: the empty state already says what to do, and picking for the
    /// teacher would be a guess. A course in the new folder wearing the SAME
    /// code is a different course and is not landed on either.</para>
    /// </summary>
    private void LetGoOfTheFolderBeingLeft()
    {
        Selection = null;
    }
}
