using System;
using System.IO;
using System.Linq;
using System.Text.RegularExpressions;

namespace Plantoir.Tests;

/// <summary>
/// A confirmation belongs to the working folder it was asked in.
///
/// <para>This is the Windows delivery of the contract's
/// <c>workingFolderSelection.alsoCleared</c>
/// (<c>contracts/shared-rules.json</c>): "every confirmation waiting on an
/// answer about an archive, a backup or a rename" goes when the window changes
/// folder. The mac holds those as FIELDS and drops them; here each is a
/// continuation suspended on an <c>await dialog.ShowAsync()</c>, so there is
/// no field to clear and the check has to happen where the continuation
/// resumes.</para>
///
/// <para>What it prevents, read off the code rather than imagined: every one
/// of these confirmations names a course, an archive or a backup by a path
/// taken BEFORE the dialog, then finishes by asking the window where it is
/// NOW. Answering a backup restore after the folder has moved archives the NEW
/// folder's course of that code and overwrites it from the OLD folder's zip,
/// and reports success. The deletes remove the old folder's file while the
/// window shows the new one.</para>
///
/// <para><b>What this scan cannot see</b>, said plainly so nobody reads it as
/// covering more than it does. It reads ONE file. Dialogs elsewhere are not
/// examined — <c>CourseSettingsView</c>'s folder-rename sheet finishes inside a
/// <c>Closing</c> deferral against a course captured at construction, so it
/// acts on the right folder's files and is a milder case of the same thing;
/// <c>TaskProgressView</c>'s runner questions belong to a task rather than a
/// folder; <c>MainWindow</c>'s dialogs act on no course. Nor can it tell
/// whether a continuation TOUCHES the workspace: it requires the check after
/// every awaited dialog here, and an opt-out has to be written down as a
/// <c>folder-check: not needed</c> comment saying why. That is the point — a
/// new confirmation added without either fails, rather than being judged
/// correct by a test that cannot judge.</para>
///
/// <para>And it sees DIALOGS only. A confirmation can wait on something that
/// is not a dialog — the rename waits up to five seconds for Obsidian to quit,
/// with nothing on screen at all — and
/// <see cref="AWaitThatIsNotADialogIsCheckedToo"/> below is what covers those,
/// with its own narrower limit stated there. Outside this file the same shape
/// lives in <c>MainWindow.StopPreviewForAsync</c>, which now captures its
/// folder before awaiting the stop; nothing scans for that.</para>
/// </summary>
public class ConfirmationFolderGuardTests
{
    private const string Guard = "TheFolderMovedUnderThisConfirmation(";
    private const string OptOut = "folder-check: not needed";

    [Fact]
    public void EveryConfirmationInTheSidebarIsCheckedAgainstTheFolderItWasAskedIn()
    {
        string path = Path.Combine(RepoRoot, "windows-app", "Plantoir", "Views", "SidebarPane.xaml.cs");
        string[] lines = File.ReadAllLines(path);

        // An awaited dialog: the pane's own helper, or a dialog type's
        // ShowAsync directly (the wizard and the Add Section dialog).
        // ShowAsync takes an optional placement argument, so the parentheses
        // must not be required empty — `await dialog.ShowAsync(
        // ContentDialogPlacement.InPlace)` is the same site wearing a
        // different spelling, and a scan that missed it would pass a
        // confirmation nobody had guarded.
        var site = new Regex(@"await\s+(ShowDialogSafelyAsync\(|\w+\.ShowAsync\()");

        // Where the enclosing method ends, near enough: a line whose only
        // content is a closing brace at method indentation.
        var methodEnd = new Regex(@"^    \}\s*$");

        var unguarded = new System.Collections.Generic.List<string>();
        int found = 0;

        for (int i = 0; i < lines.Length; i++)
        {
            if (!site.IsMatch(lines[i])) continue;
            found++;

            // The check must fall between THIS await and the NEXT one (or the
            // end of the method). A fixed window of lines is what lets a new
            // confirmation added just below a guarded one borrow its
            // neighbour's check and pass having none of its own.
            bool answered = lines[i].Contains(OptOut, StringComparison.Ordinal)
                         || (i > 0 && lines[i - 1].Contains(OptOut, StringComparison.Ordinal))
                         || (i > 1 && lines[i - 2].Contains(OptOut, StringComparison.Ordinal));

            for (int j = i + 1; j < lines.Length && !answered; j++)
            {
                if (lines[j].Contains(Guard, StringComparison.Ordinal)
                    || lines[j].Contains(OptOut, StringComparison.Ordinal)) { answered = true; break; }
                if (site.IsMatch(lines[j]) || methodEnd.IsMatch(lines[j])) break;
            }

            if (!answered) unguarded.Add($"{path}:{i + 1}: {lines[i].Trim()}");
        }

        Assert.True(found >= 14,
            $"Only {found} awaited dialogs found in SidebarPane.xaml.cs — this scan has stopped " +
            "reading what it thinks it reads.");

        Assert.True(unguarded.Count == 0,
            "These confirmations resume without asking whether the window still shows the folder " +
            "they were asked about, so answering one after a folder change acts on a folder nobody " +
            $"is looking at:\n{string.Join("\n", unguarded)}\n" +
            $"Add `if ({Guard}askedIn)) return;` after the await, or say why not with a " +
            $"`// {OptOut} — …` comment.");
    }

    /// <summary>
    /// A dialog is not the only thing a confirmation waits on, and the scan
    /// above cannot see the others.
    ///
    /// <para>The rename path meets the widest window in the whole file:
    /// <c>await FolderActions.QuitObsidianAndWait()</c> polls for up to five
    /// seconds with NO dialog on screen at all, so the File menu and Ctrl+O
    /// are both fully live — and everything after it reads the LIVE workspace,
    /// down to setting the selection to the renamed code. A check before a
    /// wait says nothing about what is true after it.</para>
    ///
    /// <para>So: in any method that captured a folder, a <c>Workspace.Reload()</c>
    /// or a <c>Workspace.Selection =</c> that follows an <c>await</c> must have
    /// the check between them. <b>Its limit</b>, said rather than implied: it
    /// watches those two writes only, not every read of the workspace — a
    /// lexical scan cannot tell a read inside a local function (which runs
    /// BEFORE the await that appears above it) from one in the continuation,
    /// and a scan that cried wolf there would be turned off. The two writes it
    /// does watch are the ones that produced the reported defect.</para>
    /// </summary>
    [Fact]
    public void AWaitThatIsNotADialogIsCheckedToo()
    {
        string path = Path.Combine(RepoRoot, "windows-app", "Plantoir", "Views", "SidebarPane.xaml.cs");
        string[] lines = File.ReadAllLines(path);

        var capture = new Regex(@"string\?\s+askedIn\s*=");
        var anyAwait = new Regex(@"(^|[^\w.])await\s");
        var stateWrite = new Regex(@"Workspace\.Reload\(\)|Workspace\.Selection\s*=");
        var methodEnd = new Regex(@"^    \}\s*$");

        var unguarded = new System.Collections.Generic.List<string>();
        bool insideACapturingMethod = false;
        bool awaitedSinceTheLastCheck = false;
        int checks = 0;

        for (int i = 0; i < lines.Length; i++)
        {
            string line = lines[i];
            if (methodEnd.IsMatch(line)) { insideACapturingMethod = false; awaitedSinceTheLastCheck = false; continue; }
            if (capture.IsMatch(line)) { insideACapturingMethod = true; awaitedSinceTheLastCheck = false; continue; }
            if (!insideACapturingMethod) continue;

            if (line.Contains(Guard, StringComparison.Ordinal)) { awaitedSinceTheLastCheck = false; checks++; continue; }
            if (stateWrite.IsMatch(line) && awaitedSinceTheLastCheck)
                unguarded.Add($"{path}:{i + 1}: {line.Trim()}");
            if (anyAwait.IsMatch(line)) awaitedSinceTheLastCheck = true;
        }

        Assert.True(checks >= 11, $"Only {checks} folder checks found — this scan is no longer reading what it thinks.");

        Assert.True(unguarded.Count == 0,
            "These reload the courses or set the selection after waiting on something, without asking " +
            "whether the window still shows the folder they were working in — so they land the old " +
            $"folder's answer in the new folder's sidebar:\n{string.Join("\n", unguarded)}");
    }

    [Fact]
    public void TheCheckIsOneHelperRatherThanASpellingRepeatedAtEachSite()
    {
        string source = File.ReadAllText(Path.Combine(
            RepoRoot, "windows-app", "Plantoir", "Views", "SidebarPane.xaml.cs"));
        string code = Regex.Replace(source, @"//[^\n]*", "");

        // One definition, and it asks the ONE comparison — an ordinal `!=`
        // spelled at a site would answer "a different folder" for the same
        // folder typed with different casing and void an answer the teacher
        // meant (issue #162's other half).
        int definitions = Regex.Matches(code, @"private bool TheFolderMovedUnderThisConfirmation").Count;
        Assert.True(definitions == 1, $"The check is defined {definitions} times, expected once.");
        Assert.Contains("!WorkingFolder.IsTheSame(askedIn, Workspace.WorkspacePath)", code, StringComparison.Ordinal);

        // Every site captures BEFORE the dialog. A capture taken after the
        // await would compare the live folder with itself and never fire.
        int captures = Regex.Matches(code, @"string\?\s+askedIn\s*=").Count;
        int uses = Regex.Matches(code, @"TheFolderMovedUnderThisConfirmation\(askedIn\)").Count;
        Assert.True(captures >= 9, $"Only {captures} confirmations capture their folder.");
        Assert.True(uses >= captures,
            $"{captures} folders captured but only {uses} checked — a capture nobody reads is worse " +
            "than none, because it reads as a guarded site.");
    }

    private static string RepoRoot
    {
        get
        {
            var dir = new DirectoryInfo(AppContext.BaseDirectory);
            for (int i = 0; i < 8 && dir is not null; i++, dir = dir.Parent)
            {
                if (File.Exists(Path.Combine(dir.FullName, "Dockerfile")))
                    return dir.FullName;
            }
            throw new DirectoryNotFoundException("Could not find repository root containing Dockerfile.");
        }
    }
}
