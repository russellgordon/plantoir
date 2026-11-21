using System.Text;
using System.Text.RegularExpressions;
using Plantoir.Core.Undo;

namespace Plantoir.Tests;

/// <summary>
/// #899 W4, the writer scan (the mac's <c>UndoWriterScanTests</c>;
/// <c>undo.rule.clearing</c>: "The writer scan lists every file that writes,
/// with which of these it is"). Every write of a teacher's work goes through
/// ONE door, <see cref="UndoDoor"/>, before the switch goes on. This reads ALL
/// the product source (<c>Plantoir</c>, <c>Plantoir.Core</c>,
/// <c>Plantoir.Mcp</c>, <c>PtyDriver</c>) and fails on any file holding a
/// writing call that is not on the list below with exactly that many calls: a
/// new writer, or a new call beside an allowed one, is red until somebody
/// decides whether it is a step. An entry nothing matches any more is red as
/// stale.
///
/// <para>Three kinds of reason, as on the mac: <c>door</c> (the list itself,
/// <c>Plantoir.Core/Undo</c>); <c>notAStep</c> (a write that is not a
/// teacher's change: the trail, leases, the toolchain mirror, models,
/// problem reports, the app's own state, a deploy, which rulings 17 and 18
/// keep off the list); <c>waitsFor</c> (a teacher's change not yet through
/// the door, and the Windows piece that wires it: W7 mirrors U3, the daily
/// page actions; W8 mirrors U4, settings, renames, New Course and reference
/// courses; W9 mirrors U5, backups, archives and the Recycle Bin; W11a
/// mirrors U7, today's undo itself). <b>The switch cannot go on while any
/// <c>waitsFor</c> remains</b>: <see cref="TheSwitchStaysOffWhileWritersWait"/>.</para>
///
/// <para>What counts as a writing call: <c>File.</c>'s writes, appends,
/// moves, copies, deletes, replaces, creates and attribute or time changes;
/// <c>Directory.</c>'s create, delete and move; a <c>FileInfo</c> or
/// <c>DirectoryInfo</c> <c>.Delete()</c> or <c>.MoveTo(</c>; an ACL set;
/// a <c>StreamWriter</c> made on a path; a zip extracted or made; the Win32
/// calls that write (<c>MoveFileEx</c>, <c>CreateHardLink</c>,
/// <c>SetFileInformationByHandle</c> and the like; never their
/// <c>extern</c> declaration); the Recycle Bin; a zip made or updated
/// (<c>ZipFile.Open</c> or <c>new ZipArchive</c> with
/// <c>ZipArchiveMode.Create</c> or <c>Update</c>); a launcher named in quotes
/// (<c>setup.ps1</c>, <c>preview.ps1</c>, <c>deploy.ps1</c>) or run by its
/// constant (<c>Workspace.MarkerLauncher</c>, <c>DeployCommand.ScriptName</c>
/// handed to a call whose name holds <c>Run</c> or <c>Start</c>), since a
/// launcher writes course files itself; a tool that writes named in quotes,
/// alone or at the start of a command line (<c>powershell</c>, <c>cmd</c>,
/// <c>robocopy</c>, <c>schtasks</c> and the others; W4's review, LOW 3); and, at most once a line, a stream opened to write
/// (<c>FileMode.Create</c>, <c>CreateNew</c>, <c>Append</c>,
/// <c>OpenOrCreate</c>, <c>Truncate</c>, <c>FileAccess.Write</c> or
/// <c>ReadWrite</c>, a handle with write or delete access). Comments are not
/// code and are not read; strings are, since a launcher's or a tool's name is
/// one. The count is per FILE, as the mac's is: the list says WHO writes, and
/// a new writer is what it catches. A file that writes only by calling
/// another file's writer (<c>AgentGuidance.WriteAtomically</c>) is not
/// itself listed; its writer is.</para>
/// </summary>
public sealed class UndoWriterScanTests
{
    private static readonly Regex WritingCall = new(
        @"\bFile\.(?:WriteAll\w*|AppendAll\w*|Move|Copy|Delete|Replace|Create\w*|AppendText|OpenWrite|Set\w+|Encrypt|Decrypt)\s*\("
        + @"|\bDirectory\.(?:CreateDirectory|Delete|Move|CreateSymbolicLink|CreateTempSubdirectory|Set\w+)\s*\("
        + @"|\bnew\s+StreamWriter\s*\("
        + @"|\bZipFile\.(?:ExtractToDirectory|CreateFromDirectory)\w*\s*\("
        + @"|\.ExtractToFile\s*\("
        + @"|\.MoveTo\s*\("
        + @"|\.Delete\s*\(\s*(?:true|false|recursive:\s*\w+)?\s*\)"
        + @"|\.SetAccessControl\s*\("
        + @"|(?<![\w.])(?:MoveFileExW?|MoveFileW?|CreateHardLinkW?|DeleteFileW?|SetFileInformationByHandle|SetFileAttributesW?|RemoveDirectoryW?|CreateDirectoryW?|ReplaceFileW?|CopyFileW?|CopyFile2|SetEndOfFile|SHFileOperationW?|CreateSymbolicLinkW?)\s*\("
        + @"|\bFileSystem\.(?:DeleteFile|DeleteDirectory|MoveFile|MoveDirectory|CopyFile|CopyDirectory)\s*\("
        + @"|\bZipFile\.Open\s*\([^;]*ZipArchiveMode\.(?:Create|Update)\b"
        + @"|\bnew\s+ZipArchive\s*\([^;]*ZipArchiveMode\.(?:Create|Update)\b"
        + @"|""(?:setup|preview|deploy)\.ps1"""
        + @"|\b\w*(?:Run|Start)\w*\s*\([^;]*\b(?:Workspace\.MarkerLauncher|DeployCommand\.ScriptName)\b"
        + @"|""(?:powershell|pwsh|cmd|robocopy|xcopy|tar|attrib|icacls|schtasks)(?:\.exe(?:""|\s)|""|\s+[-/])",
        RegexOptions.Compiled | RegexOptions.CultureInvariant);

    private static readonly Regex OpenedToWrite = new(
        @"\bFileMode\.(?:Create|CreateNew|Append|OpenOrCreate|Truncate)\b|\bFileAccess\.(?:Write|ReadWrite)\b|\bGeneric(?:Write|All)\b|\bCreateFileW?\s*\([^;]*\bDelete\b",
        RegexOptions.Compiled | RegexOptions.CultureInvariant);

    private static readonly Regex Extern = new(@"\bextern\b", RegexOptions.Compiled);

    private const string W7 = "waitsFor: W7";
    private const string W8 = "waitsFor: W8";
    private const string W9 = "waitsFor: W9";

    /// <summary>Every file allowed to write, under <c>windows-app/</c>, with how many writing calls it holds and why.</summary>
    internal static readonly Dictionary<string, (int Calls, string Reason)> Allowed = new(StringComparer.Ordinal)
    {
        ["Plantoir.Core/Assist/AppUpdater.cs"] = (1, "notAStep: the downloaded installer, removed after an update"),
        ["Plantoir.Core/Assist/AppUpdates.cs"] = (5, "notAStep: the installer's log and its markers in the app's state folder"),
        ["Plantoir.Core/Assist/AssistModelStore.cs"] = (1, "notAStep: the assistant's model removed (class D, plan 7)"),
        ["Plantoir.Core/Assist/AssistWorkspace.HowITeach.cs"] = (1, W7 + " (the How I Teach page, the mac's HowITeachPage)"),
        ["Plantoir.Core/Assist/AssistWorkspace.StartOfYear.cs"] = (1, W7 + " (the start of the year's pages put back when it stops part way, the mac's StartOfYearPlanner)"),
        ["Plantoir.Core/Assist/AssistWorkspace.cs"] = (4, W7 + " (the page writes still made file by file: Make Room's renames and its class folder, a page saved by Save for Re-date and its front page, Make Room and Duplicate Class, W7b2; and the rollover's site marker kept aside, undone with it, W7c. Publish, hide, Add Classes, curriculum mentions and Bring Pages into Date go through the door: W7a, W7b1)"),
        ["Plantoir.Core/Assist/ClaudeCodeLauncher.cs"] = (2, "notAStep: an outside assistant's launch files, outside every course"),
        ["Plantoir.Core/Assist/LaterClassesKept.cs"] = (3, W7 + " (the record of classes dated later that were kept, the mac's ClassesDatedLater)"),
        ["Plantoir.Core/Assist/LinksChecklist.cs"] = (9, W7 + " and W8 (the checklist's answered record, the mac's LinksChecklistOffer, U3; the published-pages record set aside by a rollover onto a new website and put back, U4's releaseSite)"),
        ["Plantoir.Core/Assist/LocalModel.cs"] = (7, "notAStep: the assistant's model download (class D, plan 7)"),
        ["Plantoir.Core/Assist/MachineWork.cs"] = (1, "notAStep: stale assistant-server records in the app's state folder"),
        ["Plantoir.Core/Assist/OutsideDoor.cs"] = (1, "notAStep: names cmd.exe to open an outside assistant's terminal; that assistant's changes are plantoir-mcp.exe's, counted there"),
        ["Plantoir.Core/Assist/ScheduledDeployCompletion.cs"] = (1, "notAStep: a deploy set for later's finished record, a world record (rulings 17 and 18)"),
        ["Plantoir.Core/Assist/ScheduledHealthFindings.cs"] = (1, "notAStep: a deploy set for later's health record, a world record"),
        ["Plantoir.Core/Assist/ScheduledPublishOutcome.cs"] = (16, "notAStep: a scheduled run's outcome record, a world record (the mac's ScheduledPublishOutcome)"),
        ["Plantoir.Core/Assist/ScheduledPublishWatcher.cs"] = (1, "notAStep: a scheduled run's outcome record's folder, a world record"),
        ["Plantoir.Core/Assist/ScheduledRun.cs"] = (2, "notAStep: a deploy set for later, run by Task Scheduler with no window: the deploy is not counted (rulings 17 and 18), and the run never opens the list"),
        ["Plantoir.Core/Assist/TaskScheduling.cs"] = (16, W8 + " (ruling 23: SETTING or CANCELLING a deploy for later is a step, undone by cancelling it and redone by setting it again; its Task Scheduler task, job and wrapper script are outside every course. No laterPieces entry names its piece yet, so it waits with U4's steps outside a working folder. The mac's ScheduledDeploy entry still reads held, M10)"),
                ["Plantoir.Core/Assist/TodaysClassOnTheFrontPage.cs"] = (3, W7 + " (the mac's TodaysClassOnTheFrontPage)"),
        ["Plantoir.Core/Assist/UndoHistory.cs"] = (3, "waitsFor: W11a (today's undo itself, retired when the switch goes on; the mac's AssistChangeHistory; W7a's review 1, MEDIUM 3: a page's earlier bytes written back as they were)"),
        ["Plantoir.Core/Assist/WorkLease.cs"] = (3, "notAStep: work leases"),
        ["Plantoir.Core/Models/AgentGuidance.cs"] = (4, W8 + " (the mac's AgentGuidance)"),
        ["Plantoir.Core/Models/AppDataRoot.cs"] = (1, "notAStep: the app's own state folder for --state-dir"),
        ["Plantoir.Core/Models/AppSettings.cs"] = (2, "notAStep: the app's own settings, outside every course (a preference is U4's only where it changes a course)"),
        ["Plantoir.Core/Models/BackupDeleter.cs"] = (3, W9 + " (Delete Backup, to the Recycle Bin by ruling 12, the mac's U5)"),
        ["Plantoir.Core/Models/BuildOutputLocation.cs"] = (3, "notAStep: the built websites' folder and its marker"),
        ["Plantoir.Core/Models/CourseArchiver.cs"] = (4, W9 + " (the archive zip it makes, seen since W4's review, LOW 3)"),
        ["Plantoir.Core/Models/CourseConfiguration.cs"] = (6, W8 + " (a course's course_config.json, as editJSON)"),
        ["Plantoir.Core/Models/CoursePageCopy.cs"] = (6, W8 + " (Copy a Page, the mac's CoursePageCopier)"),
        ["Plantoir.Core/Models/CourseRenamer.cs"] = (1, W8),
        ["Plantoir.Core/Models/CourseRestorer.cs"] = (24, W9 + " (restore, remove, archive and delete, the mac's CourseRestorer)"),
        ["Plantoir.Core/Models/DeployCommand.cs"] = (1, "notAStep: names deploy.ps1; the deploy is not counted (rulings 17 and 18)"),
        ["Plantoir.Core/Models/FolderContainers.cs"] = (1, "notAStep: names powershell.exe to stop a folder's previews; writes no course file"),
        ["Plantoir.Core/Models/FolderScaffold.cs"] = (1, W8 + " (a new working folder's scaffold, made with New Course)"),
        ["Plantoir.Core/Models/HowITeachSettingsRow.cs"] = (1, W7 + " (the How I Teach page made from Course Settings, the mac's HowITeachPage)"),
        ["Plantoir.Core/Models/LastViewedPages.cs"] = (1, "notAStep: the app's own record of the pages last viewed, in its state folder"),
        ["Plantoir.Core/Models/ObsidianFigureAddOns.cs"] = (13, W8 + " (the mac's ObsidianFigureAddOns)"),
        ["Plantoir.Core/Models/OutsideTerminal.cs"] = (1, "notAStep: names powershell.exe to open a terminal for the teacher; what is typed there is not the app's"),
        ["Plantoir.Core/Models/PlanningAssets.cs"] = (5, "notAStep: the Planning tab's assets mirror (#801), made the same as the app's own copy at every look, as the toolchain mirror is"),
        ["Plantoir.Core/Models/ProblemsAcknowledgements.cs"] = (3, "notAStep: folder-problem acknowledgements (plan 7: not steps)"),
        ["Plantoir.Core/Models/ReferenceCopier.cs"] = (6, W8),
        ["Plantoir.Core/Models/ReferenceImport.cs"] = (1, W8 + " (the mac's ReferenceImporter)"),
        ["Plantoir.Core/Models/ReferenceLock.cs"] = (3, W8 + " (a reference course's locks, lifted and put back inside the step that changes it, plan 2.6)"),
        ["Plantoir.Core/Models/ReferenceStaging.cs"] = (7, W8),
        ["Plantoir.Core/Models/ReferenceTreeCopier.cs"] = (3, W8),
        ["Plantoir.Core/Models/SectionAdder.cs"] = (11, W8 + " (Add Section, the mac's SectionAdder)"),
        ["Plantoir.Core/Models/SectionPublishState.cs"] = (3, "notAStep: the site markers, written by a deploy (rulings 17 and 18) and read by undo.rule.deployed"),
        ["Plantoir.Core/Models/SiteHealthRepair.cs"] = (3, W8),
        ["Plantoir.Core/Models/SpecialFolderRenamer.cs"] = (6, W8),
        ["Plantoir.Core/Models/ToolchainMirror.cs"] = (19, "notAStep: the toolchain mirror, its index and the launchers it copies into a working folder"),
        ["Plantoir.Core/Models/ToolchainReadiness.cs"] = (6, "notAStep: the toolchain mirror's copy markers"),
        ["Plantoir.Core/Models/UnitWordRenamer.cs"] = (6, W8),
        ["Plantoir.Core/Models/Workspace.cs"] = (1, "notAStep: names preview.ps1 as the marker of a working folder; runs nothing"),
        ["Plantoir.Core/Scripting/ActivityTrail.cs"] = (2, "notAStep: the activity trail"),
        ["Plantoir.Core/Scripting/MultiDestinationDeployRunner.cs"] = (2, W8 + " (the build before a deploy is preview.ps1, whose preflight rewrites course_config.json; the deploy it runs by DeployCommand.ScriptName is not counted, rulings 17 and 18)"),
        ["Plantoir.Core/Scripting/NewCourseCreator.cs"] = (4, W8 + " (New Course: the course folder and setup.ps1)"),
        ["Plantoir.Core/Scripting/PreviewCommand.cs"] = (1, W8 + " (starts preview.ps1, whose preflight rewrites a course's course_config.json outside the door; the mac's AssistSiteWork)"),
        ["Plantoir.Core/Scripting/ProblemReportBuilder.cs"] = (5, "notAStep: a problem report and its zip, built outside every course"),
        ["Plantoir.Core/Scripting/ScriptRunner.cs"] = (1, W8 + " (runs every launcher for the window through powershell.exe, seen since W4's review, LOW 3: preview.ps1's preflight rewrites course_config.json and setup.ps1 makes a course; a deploy it runs is not counted, rulings 17 and 18)"),
        ["Plantoir.Core/Scripting/ProblemReportStore.cs"] = (3, "notAStep: problem reports' records, outside every course"),
        ["Plantoir.Core/Undo/FolderIdentityFile.cs"] = (6, "door: a working folder's courses/.internal/folder-id, made the first time a step is recorded there"),
        ["Plantoir.Core/Undo/UndoJournal.cs"] = (3, "door: the list itself, outside every working folder"),
        ["Plantoir.Core/Undo/UndoJournalWriter.cs"] = (6, "door: the list's segments and content"),
        ["Plantoir.Core/Undo/UndoLock.cs"] = (2, "door: the list's own lock file"),
        ["Plantoir.Core/Undo/UndoOpKinds.cs"] = (11, "door: a folder a tree op makes beside its place or removes once taken out, and the app's own settings file an external op sets, by a temporary file and one rename (W6 and its fix round)"),
        ["Plantoir.Core/Undo/UndoSwap.cs"] = (24, "door: the staged swaps of a step, an undo, a redo and recovery, a tree's folders and a move included; the Hidden attribute set on a kept original and cleared before its put-back (W7a review 1, MEDIUM 1), and set on a kept original left and named as the hidden file (HideAKeptFileLeft, W7a part two review 1, LOW 2)"),
        ["Plantoir.Mcp/LauncherRunner.cs"] = (3, W8 + " (the server starts preview.ps1 through powershell.exe, whose preflight rewrites course_config.json; a deploy it runs is not counted, rulings 17 and 18)"),
        ["Plantoir/App.xaml.cs"] = (2, "notAStep: the startup log in the app's state folder"),
        ["Plantoir/Services/DialogGate.cs"] = (2, "notAStep: the UI tests' record of accelerators, in the app's state folder"),
        ["Plantoir/Services/ExternalLinks.cs"] = (1, "notAStep: the UI tests' record of links opened, in the app's state folder"),
        ["Plantoir/Services/MarketingShotCapturer.cs"] = (3, "notAStep: the plantoir.app captures' log and staged folder, a developer's command"),
        ["Plantoir/Services/PreviewStopper.cs"] = (2, "notAStep: stops a preview through preview.ps1, which writes no course file when it stops"),
        ["Plantoir/Views/FolderActions.cs"] = (6, "notAStep: Obsidian's own settings: its vault registry outside every course, and a vault's .obsidian defaults and saved layout when it is opened in Obsidian; no course page"),
        ["Plantoir/Views/SectionDetailView.xaml.cs"] = (2, W8 + " (starts preview.ps1, as PreviewCommand)"),
        ["Plantoir/Views/SidebarPane.Reference.cs"] = (2, "notAStep: the app's own record of reference notes shown, in its state folder"),
        ["PtyDriver/Program.cs"] = (3, "notAStep: the console host's own logs, outside every course"),
    };

    private static string WindowsApp
    {
        get
        {
            var dir = new DirectoryInfo(AppContext.BaseDirectory);
            for (int i = 0; i < 10 && dir is not null; i++, dir = dir.Parent)
            {
                string candidate = Path.Combine(dir.FullName, "windows-app", "Plantoir.Core");
                if (Directory.Exists(candidate)) return Path.Combine(dir.FullName, "windows-app");
            }
            throw new DirectoryNotFoundException("Could not find windows-app/ above the test assembly.");
        }
    }

    private static readonly string[] ProductProjects = ["Plantoir", "Plantoir.Core", "Plantoir.Mcp", "PtyDriver"];

    /// <summary>Every product <c>.cs</c> file with how many writing calls it holds, by its path under <c>windows-app/</c> with forward slashes.</summary>
    internal static Dictionary<string, int> WritersInTheProduct(out int scanned)
    {
        var found = new Dictionary<string, int>(StringComparer.Ordinal);
        scanned = 0;
        string root = WindowsApp;
        char separator = Path.DirectorySeparatorChar;
        foreach (string project in ProductProjects)
        {
            foreach (string file in Directory.EnumerateFiles(Path.Combine(root, project), "*.cs", SearchOption.AllDirectories))
            {
                if (file.Contains($"{separator}bin{separator}") || file.Contains($"{separator}obj{separator}")) continue;
                scanned++;
                int calls = WritingCalls(File.ReadAllText(file), file);
                if (calls > 0) found[Path.GetRelativePath(root, file).Replace('\\', '/')] = calls;
            }
        }
        return found;
    }

    /// <summary>How many writing calls a file's source holds, its comments taken out.</summary>
    internal static int WritingCalls(string source, string file)
    {
        int calls = 0;
        foreach (string line in WithoutComments(source, file).Split('\n'))
        {
            if (Extern.IsMatch(line)) continue;
            calls += WritingCall.Matches(line).Count;
            if (OpenedToWrite.IsMatch(line)) calls++;
        }
        return calls;
    }

    /// <summary>
    /// A file's source with its comments taken out and its strings KEPT (a
    /// launcher's or a tool's name is a string), each comment's line breaks
    /// kept so a line stays a line. One left-to-right pass, as the trail's
    /// wiring scan reads: a <c>//</c> or a quote inside a string or a comment
    /// is not mistaken for anything else.
    /// </summary>
    internal static string WithoutComments(string source, string file)
    {
        var code = new StringBuilder(source.Length);
        int i = 0;
        int n = source.Length;
        while (i < n)
        {
            char c = source[i];
            char next = i + 1 < n ? source[i + 1] : '\0';
            if (c == '/' && next == '/')
            {
                while (i < n && source[i] != '\n') i++;
                continue;
            }
            if (c == '/' && next == '*')
            {
                int close = source.IndexOf("*/", i + 2, StringComparison.Ordinal);
                if (close < 0) throw new Xunit.Sdk.XunitException($"{file}: a /* at offset {i} never closes, so the writer scan cannot read what follows it.");
                foreach (char inside in source.AsSpan(i, close + 2 - i))
                {
                    if (inside == '\n') code.Append('\n');
                }
                i = close + 2;
                continue;
            }
            int start = i;
            bool verbatim = false;
            while (i < n && (source[i] == '$' || source[i] == '@'))
            {
                if (source[i] == '@') verbatim = true;
                i++;
            }
            if (i < n && source[i] == '"')
            {
                int quotes = 0;
                while (i + quotes < n && source[i + quotes] == '"') quotes++;
                if (quotes >= 3)
                {
                    int close = source.IndexOf(new string('"', quotes), i + quotes, StringComparison.Ordinal);
                    int end = close < 0 ? n : close + quotes;
                    code.Append(source, start, end - start);
                    i = end;
                    continue;
                }
                i++;
                while (i < n)
                {
                    if (verbatim)
                    {
                        if (source[i] == '"' && i + 1 < n && source[i + 1] == '"') { i += 2; continue; }
                        if (source[i] == '"') break;
                    }
                    else
                    {
                        if (source[i] == '\\') { i += 2; continue; }
                        if (source[i] == '"' || source[i] == '\n') break;
                    }
                    i++;
                }
                i = Math.Min(i + 1, n);
                code.Append(source, start, i - start);
                continue;
            }
            if (i > start)
            {
                code.Append(source, start, i - start);
                continue;
            }
            if (c == '\'')
            {
                Match literal = Regex.Match(source.Substring(i, Math.Min(8, n - i)), @"^'(?:\\.[^']*|[^'\\\n])'");
                if (literal.Success)
                {
                    code.Append(literal.Value);
                    i += literal.Length;
                    continue;
                }
            }
            code.Append(c);
            i++;
        }
        return code.ToString();
    }

    [Fact]
    public void EveryWriterIsTheDoorOrNamedWithAReason()
    {
        Dictionary<string, int> found = WritersInTheProduct(out int scanned);
        Assert.True(scanned > 300, $"The scan read {scanned} product files, so it checked almost nothing.");
        var wrong = new List<string>();
        foreach ((string path, int calls) in found)
        {
            if (!Allowed.TryGetValue(path, out var entry)) wrong.Add($"{path} writes files ({calls} calls) and is not on the list");
            else if (entry.Calls != calls) wrong.Add($"{path} has {calls} writing calls; the list allows {entry.Calls}");
        }
        foreach (string path in Allowed.Keys)
        {
            if (!found.ContainsKey(path)) wrong.Add($"{path} is on the list and writes nothing any more: remove the stale entry");
        }
        wrong.Sort(StringComparer.Ordinal);
        Assert.True(wrong.Count == 0,
            "A write of a teacher's work must go through UndoDoor once Undo is on. Route it through the door, or add the file here with its count and the reason it is not a step (or the piece of #899 that will wire it):\n" + string.Join("\n", wrong));
    }

    /// <summary>The shapes a writing call takes, each counted once, and the shapes that are not one.</summary>
    [Fact]
    public void TheScanCountsEveryShapeOfWriteOnceAndNothingElse()
    {
        (string Source, int Calls)[] samples =
        [
            ("File.WriteAllText(path, text);", 1),
            ("await File.WriteAllBytesAsync(path, bytes);", 1),
            ("File.Move(temporary, path, overwrite: true);", 1),
            ("File.SetLastWriteTimeUtc(path, when);", 1),
            ("Directory.Delete(folder, recursive: true);", 1),
            ("info.Delete();", 1),
            ("folder.Delete(true);", 1),
            ("new DirectoryInfo(p).MoveTo(q);", 1),
            ("using var w = new StreamWriter(path, append: false);", 1),
            ("using var s = new FileStream(path, FileMode.CreateNew, FileAccess.Write, FileShare.None);", 1),
            ("ZipFile.ExtractToDirectory(zip, staging);", 1),
            ("entry.ExtractToFile(target);", 1),
            ("return MoveFileExW(from, onto, flags);", 1),
            ("bool linked = CreateHardLinkW(kept, page, IntPtr.Zero);", 1),
            ("security.SetAccessControl(acl);", 1),
            ("FileSystem.DeleteFile(path, UIOption.OnlyErrorDialogs, RecycleOption.SendToRecycleBin);", 1),
            ("runner.Run(\"preview.ps1\", args, folder);", 1),
            ("FileName = \"powershell.exe\",", 1),
            // W4's review, LOW 3: a tool named at the start of a command line,
            // a launcher run by its constant, and a zip made or changed.
            ("string command = \"powershell.exe -NoLogo -NoProfile -File \" + script;", 1),
            ("await runner.Run(DeployCommand.ScriptName, arguments, folder);", 1),
            ("runner.Run(Workspace.MarkerLauncher, args, folder, null, token);", 1),
            ("using var zip = ZipFile.Open(path, ZipArchiveMode.Create);", 1),
            ("using var zip = ZipFile.Open(path, ZipArchiveMode.Update);", 1),
            ("using var archive = new ZipArchive(stream, ZipArchiveMode.Create);", 1),
            ("Directory.CreateDirectory(d); File.Copy(a, b);", 2),
            ("SafeFileHandle h = CreateFileW(path, GenericRead | GenericWrite, Share, IntPtr.Zero, OpenAlways, 0, IntPtr.Zero);", 1),
            // Not writes.
            ("private static extern bool MoveFileExW(string a, string b, uint flags);", 0),
            ("// File.Delete(path);", 0),
            ("/* File.Delete(path); */ int a = 1;", 0),
            ("var outcome = BackupDeleter.Delete(chosen, held);", 0),
            ("stream.CopyTo(memory);", 0),
            ("string text = File.ReadAllText(path);", 0),
            ("using var s = new FileStream(path, FileMode.Open, FileAccess.Read, FileShare.ReadWrite);", 0),
            ("string name = path.Replace('/', '\\\\');", 0),
            ("Process.Start(new ProcessStartInfo(\"explorer.exe\", folder));", 0),
            ("using var zip = ZipFile.Open(path, ZipArchiveMode.Read);", 0),
            ("if (File.Exists(Path.Combine(folder, Workspace.MarkerLauncher))) return true;", 0),
            ("string label = \"cmdlet\";", 0),
            ("return (1, \"schtasks could not be started.\");", 0),
            ("string run = \"cmd /c start \" + target;", 1),
        ];
        var wrong = new List<string>();
        foreach ((string source, int calls) in samples)
        {
            int counted = WritingCalls(source, "sample.cs");
            if (counted != calls) wrong.Add($"{source}: counted {counted}, expected {calls}");
        }
        Assert.True(wrong.Count == 0, string.Join("\n", wrong));
    }

    /// <summary>A call split across lines after a comment, and a string holding <c>//</c>, read as the code they are.</summary>
    [Fact]
    public void CommentsAreTakenOutAndStringsKept()
    {
        string source = "string url = \"https://example.com\"; File.Delete(path);\n// File.Move(a, b);\n/* two\nlines */ Directory.CreateDirectory(d);\n";
        string code = WithoutComments(source, "sample.cs");
        Assert.Contains("\"https://example.com\"", code);
        Assert.DoesNotContain("File.Move", code);
        Assert.Equal(source.Split('\n').Length, code.Split('\n').Length);
        Assert.Equal(2, WritingCalls(source, "sample.cs"));
    }

    [Fact]
    public void EveryReasonIsOneOfTheThreeKinds()
    {
        foreach ((string path, (int _, string reason)) in Allowed)
        {
            string kind = reason.Split(':')[0];
            Assert.True(kind is "door" or "notAStep" or "waitsFor", $"{path}: {reason}");
            if (kind == "door") Assert.StartsWith("Plantoir.Core/Undo/", path);
            if (path.StartsWith("Plantoir.Core/Undo/", StringComparison.Ordinal)) Assert.Equal("door", kind);
            if (kind == "waitsFor") Assert.Matches(@"^waitsFor: W(7|8|9|11a)\b", reason);
        }
    }

    /// <summary>W11a flips the switch only once no writer waits for a piece (the mac's testTheSwitchStaysOffWhileWritersWait).</summary>
    [Fact]
    public void TheSwitchStaysOffWhileWritersWait()
    {
        int waiting = Allowed.Values.Count(entry => entry.Reason.StartsWith("waitsFor", StringComparison.Ordinal));
        if (waiting > 0)
            Assert.False(UndoSwitch.UndoJournalIsLive, $"{waiting} writers are not through the door yet; Undo cannot be switched on.");
    }
}
