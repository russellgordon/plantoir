using System;
using System.Collections.Generic;
using System.IO;

namespace Plantoir.Tests;

/// <summary>
/// No window code makes a <c>Progress&lt;T&gt;</c> INSIDE <c>Task.Run(...)</c>.
///
/// <para>A <c>Progress&lt;T&gt;</c> reports on the synchronisation context it
/// was CREATED on. Made inside the lambda handed to <c>Task.Run</c>, it is
/// created on a pool thread, so its handler runs there and touches WinUI
/// controls off the interface thread: <c>RPC_E_WRONG_THREAD</c> (0x8001010E),
/// unhandled, and the app closes. That is what Keep a Copy for Reference… did
/// on its first progress report, found by <c>ReferenceCourseUiTests</c> on the
/// first unlocked run of bundle 11; Import Courses for Reference… had the same
/// shape. No unit test can mount the window, so this reads the source, the way
/// <c>SectionDetailTeardownSourceTests</c> does.</para>
/// </summary>
public class ProgressMadeOnTheInterfaceThreadTests
{
    [Fact]
    public void NoProgressIsCreatedInsideATaskRun()
    {
        string views = Path.Combine(RepoRoot, "windows-app", "Plantoir");
        var offenders = new List<string>();
        foreach (string file in Directory.EnumerateFiles(views, "*.cs", SearchOption.AllDirectories))
        {
            if (file.Contains($"{Path.DirectorySeparatorChar}obj{Path.DirectorySeparatorChar}")
                || file.Contains($"{Path.DirectorySeparatorChar}bin{Path.DirectorySeparatorChar}")) continue;
            string text = File.ReadAllText(file);
            int at = 0;
            while ((at = text.IndexOf("Task.Run(", at, StringComparison.Ordinal)) >= 0)
            {
                int open = at + "Task.Run".Length, depth = 0, end = open;
                for (; end < text.Length; end++)
                {
                    if (text[end] == '(') depth++;
                    else if (text[end] == ')' && --depth == 0) break;
                }
                if (text[open..end].Contains("new Progress<", StringComparison.Ordinal))
                    offenders.Add($"{Path.GetFileName(file)} at offset {at}");
                at = end;
            }
        }
        Assert.True(offenders.Count == 0,
            "a Progress<T> is made inside Task.Run, so it reports on a pool thread: " + string.Join(", ", offenders));
    }

    private static string RepoRoot
    {
        get
        {
            var dir = new DirectoryInfo(AppContext.BaseDirectory);
            for (int i = 0; i < 8 && dir is not null; i++, dir = dir.Parent)
                if (File.Exists(Path.Combine(dir.FullName, "Dockerfile"))) return dir.FullName;
            throw new DirectoryNotFoundException("Could not find repository root containing Dockerfile.");
        }
    }
}
