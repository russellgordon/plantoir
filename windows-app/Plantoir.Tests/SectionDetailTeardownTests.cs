using System;
using System.IO;
using System.Linq;
using System.Text.RegularExpressions;
using Plantoir.Core.Models;

namespace Plantoir.Tests;

/// <summary>
/// The teardown half of issue #162: stopping a preview and giving its lease
/// back must name the folder the work STARTED in, never the folder the window
/// happens to be showing by the time the teardown runs.
///
/// <para>Read as SOURCE rather than driven, and deliberately so. No
/// <c>SectionDetailView</c> mounts in a unit test — it is WinUI, and
/// <c>Plantoir.Tests</c> is plain <c>net9.0</c> — and CLAUDE.md forbids a
/// <c>[UiFact]</c> that drives Preview, because <c>--state-dir</c> does not
/// redirect what the launcher itself resolves. The mac's own guard for this
/// rule is a source read too.</para>
///
/// <para>It asserts ZERO reads of the window's live folder inside the marked
/// region, not a list of named methods: <c>ReleaseLease</c> alone has six
/// callers, and a test that named the five sites known on the day it was
/// written would stay green the moment somebody added a sixth — which is the
/// whole failure this is here to prevent.</para>
/// </summary>
public class SectionDetailTeardownSourceTests
{
    private const string Begin = "==== BEGIN TEARDOWN REGION";
    private const string End = "==== END TEARDOWN REGION";

    private static string Source => File.ReadAllText(Path.Combine(
        RepoRoot, "windows-app", "Plantoir", "Views", "SectionDetailView.xaml.cs"));

    /// <summary>Comments say what the rule IS; only code can break it.</summary>
    private static string WithoutComments(string text) => Regex.Replace(text, @"//[^\n]*", "");

    private static string TeardownRegion(string source)
    {
        int begin = source.IndexOf(Begin, StringComparison.Ordinal);
        int end = source.IndexOf(End, StringComparison.Ordinal);
        Assert.True(begin >= 0, $"SectionDetailView.xaml.cs no longer carries a '{Begin}' marker.");
        Assert.True(end > begin, $"SectionDetailView.xaml.cs no longer carries a '{End}' marker after the start.");
        Assert.Equal(begin, source.LastIndexOf(Begin, StringComparison.Ordinal));
        Assert.Equal(end, source.LastIndexOf(End, StringComparison.Ordinal));
        return source[begin..end];
    }

    [Fact]
    public void TheTeardownNeverReadsTheWindowsLiveWorkingFolder()
    {
        string region = WithoutComments(TeardownRegion(Source));

        // The region has to still CONTAIN the teardown, or the markers could
        // be pulled together around nothing and the scan would pass on an
        // empty string.
        foreach (string method in new[]
                 {
                     "private void AbandonWait()",
                     "private void CancelPreview()",
                     "private void CancelDeploy()",
                     "private void StopPreview()",
                     "public async Task StopPreviewAsync()",
                     "private void ReleaseLease()",
                 })
        {
            Assert.True(region.Contains(method, StringComparison.Ordinal),
                $"'{method}' is no longer inside the marked teardown region — either it moved out " +
                "(and is now unguarded) or the markers were narrowed around it.");
        }

        var reads = Regex.Matches(region, @"_window\s*\.\s*Workspace");
        Assert.True(reads.Count == 0,
            $"The teardown region reads the window's live working folder {reads.Count} time(s). " +
            "A stop or a lease release that asks the window where it is pointing NOW runs against " +
            "the folder the teacher has just switched TO — stopping another window's preview there " +
            "and deleting its lease row, while the folder being left carries on serving. Name " +
            "_folderThisSectionWorksIn or _folderThisSectionRegisteredIn instead.");
    }

    /// <summary>
    /// The scan above is LEXICAL, and a method called FROM the region can read
    /// the live folder just as easily. One does: every teardown path ends in
    /// <c>RefreshChrome()</c>, which asks the live folder whether the course is
    /// being built elsewhere and sets the Deploy button's state from it.
    ///
    /// <para>That one is correct — what a teacher may click next is a question
    /// about the folder now on screen, and it stops and releases nothing — so
    /// it is named here rather than tidied away. What must not happen is a
    /// SECOND one arriving unnoticed and taking the first's cover.</para>
    /// </summary>
    [Fact]
    public void RefreshChromeIsTheOnlyCalleeThatReadsTheLiveFolder()
    {
        string source = Source;
        string region = WithoutComments(TeardownRegion(source));
        var bodies = MethodBodies(WithoutComments(source));

        var reading = new SortedSet<string>(StringComparer.Ordinal);
        foreach (Match call in Regex.Matches(region, @"(?<![.\w])([A-Za-z_]\w*)\s*\("))
        {
            string name = call.Groups[1].Value;
            if (bodies.TryGetValue(name, out string? body) && Regex.IsMatch(body, @"_window\s*\.\s*Workspace"))
                reading.Add(name);
        }

        Assert.True(reading.SetEquals(new[] { "RefreshChrome" }),
            "Methods called from the teardown region whose own bodies read the window's live " +
            $"working folder: [{string.Join(", ", reading)}]. Exactly one is allowed — RefreshChrome, " +
            "which only decides what the teacher may click next. Anything else is the wrong-folder " +
            "stop arriving by another door; give it the capture instead.");

        // It cannot see past this file: a callee in another class that reads
        // the folder through some other route is invisible here. The region's
        // own comment says which properties are the honest ones to name.
        Assert.True(bodies.ContainsKey("RefreshChrome"),
            "RefreshChrome is no longer a method of this file, so this scan is no longer reading what it thinks.");
    }

    /// <summary>
    /// Every method in the file by name, mapped to its body — brace counting
    /// over comment-stripped source. Overloads collapse onto one entry, which
    /// is fine for a "does ANY of these read the folder" question.
    /// </summary>
    private static Dictionary<string, string> MethodBodies(string code)
    {
        var bodies = new Dictionary<string, string>(StringComparer.Ordinal);
        foreach (Match header in Regex.Matches(code, @"\b([A-Za-z_]\w*)\s*\([^()]*\)\s*\r?\n\s*\{"))
        {
            int open = code.IndexOf('{', header.Index + header.Length - 1);
            if (open < 0) continue;
            int depth = 0;
            for (int i = open; i < code.Length; i++)
            {
                if (code[i] == '{') depth++;
                else if (code[i] == '}' && --depth == 0)
                {
                    string body = code[(open + 1)..i];
                    string name = header.Groups[1].Value;
                    bodies[name] = bodies.TryGetValue(name, out string? already) ? already + "\n" + body : body;
                    break;
                }
            }
        }
        return bodies;
    }

    [Fact]
    public void EveryStartNotesTheFolderItDecidedOn()
    {
        string code = WithoutComments(Source);

        // Three starts decide a folder: the Preview button, the assistant's
        // automated preview (which "Preview Again" after a repair also goes
        // through), and the deploy — the last AFTER its own preview stop, so
        // that stop still names the preview's folder. The fourth is
        // StagePreviewForCapture, which is the marketing-shot harness: it sets
        // _previewUrl, so `hadPreview` is true and a later stop would sweep,
        // and a staged view must not answer the teardown's question any
        // differently from a real one.
        var written = Regex.Matches(code, @"_folderThisSectionWorksIn\s*=\s*[^=]");
        Assert.True(written.Count == 4,
            $"_folderThisSectionWorksIn is written {written.Count} time(s), expected 4 (the two " +
            "preview starts, the deploy, and the shot harness). Delete one and every stop it fed " +
            "becomes a silent no-op wearing the shape of this fix working.");

        // The registration key is written exactly once, and readonly makes
        // the compiler say so: a deploy starting in the one render pass
        // between a folder change and the teardown moves the WORK folder, and
        // if the registration rode along the old folder's lease row would be
        // stranded.
        Assert.Contains("private readonly string? _folderThisSectionRegisteredIn;", code, StringComparison.Ordinal);
        var registered = Regex.Matches(code, @"_folderThisSectionRegisteredIn\s*=\s*[^=]");
        Assert.True(registered.Count == 1,
            $"_folderThisSectionRegisteredIn is written {registered.Count} time(s), expected 1.");
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

/// <summary>
/// The behaviour the captures buy, in the one place a unit test can reach it:
/// a lease is keyed by the folder it was taken in, so releasing the folder a
/// window has just switched TO leaves the folder it left still holding a row —
/// and takes away a row that belonged to somebody else.
/// </summary>
[Collection(SharedActivityState.Name)]
public class PreviewLeaseFolderKeyTests : IDisposable
{
    public PreviewLeaseFolderKeyTests() => PreviewLeases.Reset();
    public void Dispose() => PreviewLeases.Reset();

    [Fact]
    public void ReleasingTheFolderAWindowSwitchedToLeavesTheOldFolderHeld()
    {
        // One window previewing ICS3U section 1 in folder A; another window
        // previewing the same section in folder B, which PreviewLeases allows
        // on purpose (the compare-two-years case).
        var inA = PreviewLeases.Take(@"C:\folderA", "ICS3U", 1);
        PreviewLeases.Take(@"C:\folderB", "ICS3U", 1);

        // The window on A is pointed at B. A teardown that asked the window
        // where it is NOW would release this:
        PreviewLeases.Release(@"C:\folderB", "ICS3U", 1);

        // …and it is the wrong row twice over — B's window loses the lease it
        // is still previewing with, and A's survives with nothing left to
        // stop it.
        Assert.Contains(PreviewLeases.Active, lease => lease.FolderPath == @"C:\folderA");
        Assert.DoesNotContain(PreviewLeases.Active, lease => lease.FolderPath == @"C:\folderB");

        // Keyed by the folder the work STARTED in, the right row goes and
        // B's is untouched — which is what the captures make possible.
        PreviewLeases.Reset();
        PreviewLeases.Take(@"C:\folderA", "ICS3U", 1);
        var stillB = PreviewLeases.Take(@"C:\folderB", "ICS3U", 1);
        PreviewLeases.Release(@"C:\folderA", "ICS3U", 1);
        Assert.Equal(new[] { stillB }, PreviewLeases.Active.ToArray());

        // And the exact release carries its own folder, so it needs no
        // capture at all — which is why only the folder-keyed sweep beside it
        // had to change.
        Assert.Equal(@"C:\folderA", inA.FolderPath);
    }
}
