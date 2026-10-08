namespace Plantoir.Core.Scripting;

/// <summary>
/// Turns a failed task's raw output into one actionable sentence — or null
/// when nothing is recognized, because an honest fallback (showing the
/// output) beats a confident guess.
/// </summary>
public static class FailureExplainer
{
    public static string? Explanation(string output) =>
        ReferenceCourseExplanation(output)
        ?? SectionIsBeingDeployedExplanation(output)
        ?? SectionDeployRefusalOf(output)?.Sentence
        ?? FolderCopyExplanation(output)
        ?? SetupExplanation(output)
        ?? VaultLinkExplanation(output)
        ?? RateLimitExplanation(output)
        ?? AccountExplanation(output)
        ?? ConnectionExplanation(output)
        ?? FolderAccessExplanation(output)
        ?? UnreadableFrontPageExplanation(output)
        ?? MissingFrontPageExplanation(output)
        ?? MissingBuildExplanation(output)
        ?? WorkspaceNotCreatedExplanation(output);

    /// <summary>
    /// The one-time Windows setup (the launchers' Install-WindowsSubsystem)
    /// has three ways to stop that are not faults: Windows wants a restart,
    /// the teacher declined the permission prompt, or the download failed.
    /// Checked FIRST because that setup's own log is echoed into the output
    /// and could contain lines the broader matchers below would misread.
    /// </summary>
    /// <summary>
    /// A Windows link (junction/symlink) inside the TEACHER's own course
    /// folder. The toolchain itself creates none on Windows any more, so
    /// this error can only come from their filesystem — commonly the
    /// Obsidian trick of linking one shared Media folder into several
    /// vaults, which current Windows refuses to traverse (WinError 448).
    /// </summary>
    private static string? VaultLinkExplanation(string output) =>
        output.Contains("untrusted mount point")
            ? "Part of this course folder is a link to another folder, and Windows won't let the website builder follow it. Replace the link with the real folder (the details above name which one), then try again."
            : null;

    /// <summary>
    /// A launcher refused a course kept for reference (#241,
    /// <c>app-rules.json → failureExplanations</c> cases 0–2): the refusal is
    /// LIFTED with its cross taken off, and the "cannot tell" refusal, which
    /// the launchers print over two lines, is joined into the teacher's one.
    /// deploy.sh ends its first line with an em dash; deploy.ps1 with a plain
    /// hyphen, because Windows PowerShell 5.1 reads a script without a
    /// byte-order mark in the machine's code page — both read the same here.
    /// Matters most for a deploy set to happen on its own, which runs with the
    /// app closed: without it the teacher meets "did not finish".
    /// </summary>
    private static string? ReferenceCourseExplanation(string output)
    {
        const string refusalTail = "is kept for reference, so it is never deployed. Deploy the course you are teaching instead.";
        string[] lines = output.Replace("\r", "").Split('\n');
        for (int index = 0; index < lines.Length; index++)
        {
            string line = lines[index].Trim().TrimStart('❌', ' ');
            if (line.EndsWith(refusalTail, StringComparison.Ordinal)) return line;
            if (line.StartsWith("Plantoir cannot tell whether ", StringComparison.Ordinal)
                && line.TrimEnd('-', '—', ' ').EndsWith("is kept for reference", StringComparison.Ordinal)
                && index + 1 < lines.Length)
            {
                return line.TrimEnd('-', '—', ' ') + " — " + lines[index + 1].Trim();
            }
        }
        return null;
    }

    /// <summary>
    /// preview.ps1 refused because this very section is being deployed (#386,
    /// shared-rules.json -> previewWhileItsSectionDeploys.failureExplanationCases):
    /// the launcher's first line, LIFTED with its cross taken off - never
    /// reworded, so one refusal is said one way.
    /// </summary>
    private static string? SectionIsBeingDeployedExplanation(string output)
    {
        const string sign = "is being deployed right now, so it cannot be previewed until that has finished.";
        foreach (string raw in output.Split('\n'))
        {
            string line = raw.Trim();
            if (!line.EndsWith(sign, StringComparison.Ordinal)) continue;
            return line.TrimStart('❌', ' ');
        }
        return null;
    }

    /// <summary>
    /// What deploy.ps1, or preview.ps1 --build-only, refused with while the
    /// same section was still being deployed (#467 / mac #439,
    /// shared-rules.json -> deployWhileItsSectionDeploys).
    /// <paramref name="ByALaterDeploy"/> is true when the deploy set for
    /// later was in the way, false when another deploy of the section was;
    /// <paramref name="Sentence"/> is the launcher's first line with the
    /// cross taken off - the sentence the window shows.
    /// </summary>
    public sealed record SectionDeployRefusal(bool ByALaterDeploy, string Sentence);

    /// <summary>The words the refusal always carries, one per leg (sentences.launcher; pinned by a test).</summary>
    public static readonly string[] SectionDeployRefusalMarkers =
    {
        "so it cannot be deployed again until that has finished.",
        "so it cannot be built until that has finished.",
    };

    /// <summary>The part of the first line that names the deploy set for later.</summary>
    public const string LaterDeployMarker = "is still being deployed by a deploy that was set for later";

    /// <summary>
    /// The refusal in a launcher's output, LIFTED as #386's is (the
    /// launcher's line already is the sentence a teacher can act on), or
    /// null. Detection reads only the ASCII markers, so a cross that reached
    /// plantoir-mcp as '?' or as mojibake (it reads the launcher without
    /// naming an encoding) cannot hide the refusal; there only
    /// <see cref="SectionDeployRefusal.ByALaterDeploy"/> is used, to choose
    /// the assistant's sentence. The window reads the console as UTF-8, so
    /// the lifted sentence it shows has a real cross to take off.
    /// </summary>
    public static SectionDeployRefusal? SectionDeployRefusalOf(string? output)
    {
        if (string.IsNullOrEmpty(output)) return null;
        foreach (string raw in output.Replace("\r", "").Split('\n'))
        {
            string line = raw.Trim();
            if (!SectionDeployRefusalMarkers.Any(marker => line.EndsWith(marker, StringComparison.Ordinal))) continue;
            string sentence = line.TrimStart('❌', '?', ' ');
            return new SectionDeployRefusal(sentence.Contains(LaterDeployMarker, StringComparison.Ordinal), sentence);
        }
        return null;
    }

    /// <summary>
    /// A folder publish whose copy did not finish (#304, mac #227): deploy.sh's
    /// cross line, and deploy.ps1's own robocopy-failure line, both mean the
    /// folder is not up to date. Matched on the launcher's words; the copy's
    /// error number means nothing to a teacher.
    /// </summary>
    private static string? FolderCopyExplanation(string output) =>
        output.Contains("Not every page could be copied into the publishing folder", StringComparison.Ordinal)
            ? "Plantoir could not copy every page into your publishing folder, so it is not up to date. Try " +
              "publishing again; if the same thing happens, one of your pages may not open or the folder may " +
              "not be taking new files."
            : null;

    private static string? SetupExplanation(string output)
    {
        if (output.Contains("needs to restart to finish getting ready"))
            return "This PC needs to restart to finish getting ready. Restart it, then try setting up again — it carries on by itself.";
        if (output.Contains("Windows permission was declined"))
            return "Plantoir needs your permission to get this PC ready. Try again, and choose Yes when Windows asks.";
        if (output.Contains("Windows could not add the feature this needs"))
            return "This PC couldn't get ready — check your internet connection, then try setting up again. It's safe to try as many times as you like.";
        return null;
    }

    private static readonly string[] FolderAccessSigns =
    {
        "FileReadError", "Get-FileHash", "Access is denied", "UnauthorizedAccess",
        "is denied", "being used by another process",
    };

    private static string? FolderAccessExplanation(string output) =>
        FolderAccessSigns.Any(output.Contains)
            ? "Plantoir couldn't read every file in this working folder. It may not have permission, or a file is open in another program. Try a folder you own — for example, one on your Desktop."
            : null;

    private static string? RateLimitExplanation(string output)
    {
        if (!output.Contains("429") && !output.Contains("rate limit", StringComparison.OrdinalIgnoreCase))
            return null;
        return $"Netlify is limiting how often websites can be deployed right now. Try deploying again {WaitDescription(output)}.";
    }

    internal static string WaitDescription(string output)
    {
        int? seconds = SecondsUntilReset(output);
        if (seconds is null) return "in a few minutes";
        if (seconds <= 90) return "in about a minute";
        int minutes = seconds.Value / 60 + (seconds.Value % 60 > 0 ? 1 : 0);
        return $"in about {minutes} minutes";
    }

    /// <summary>Digits immediately after the marker "(in ~" — from "Window resets at: … (in ~59s)."</summary>
    internal static int? SecondsUntilReset(string output)
    {
        const string marker = "(in ~";
        int index = output.IndexOf(marker, StringComparison.Ordinal);
        if (index < 0) return null;
        int start = index + marker.Length;
        int end = start;
        while (end < output.Length && char.IsAsciiDigit(output[end])) end++;
        return end > start && int.TryParse(output[start..end], out int seconds) ? seconds : null;
    }

    private static string? AccountExplanation(string output)
    {
        if (output.Contains("Netlify token missing"))
            return "Your Netlify account isn't connected yet. Add your Netlify access token, then deploy again.";
        if (output.Contains("Netlify API error 401") || output.Contains("Netlify API error 403"))
            return "Netlify didn't accept your access token — it may have expired or been removed. Create a new one on Netlify, then deploy again.";
        return null;
    }

    private static readonly string[] ConnectionSigns =
    {
        "Could not resolve host",
        "nodename nor servname",
        "Temporary failure in name resolution",
        "Network is unreachable",
        "The Internet connection appears to be offline",
    };

    private static string? ConnectionExplanation(string output) =>
        ConnectionSigns.Any(output.Contains)
            ? "Your computer couldn't reach the internet. Check your connection, then try again."
            : null;

    private static string? MissingBuildExplanation(string output) =>
        output.Contains("Built site not found")
            ? "This website hasn't been built yet. Preview it once, then deploy."
            : null;

    /// <summary>
    /// The build ran, succeeded at everything it could, and still produced no
    /// website, because the section has no front page (index.md).
    ///
    /// Asked BEFORE MissingBuildExplanation, and the order is the point: a
    /// publish runs the build and then the deploy on one transcript, so when a
    /// front page is missing the output carries both lines — and "hasn't been
    /// built yet" is the wrong thing to say to somebody who just watched it
    /// build. The build's own reason is the specific one, so it wins.
    /// </summary>
    /// <summary>
    /// The mac's builder could not be handed the working folder at all
    /// (#221, #230): the daemon refused the bind mount with
    /// "bind source path does not exist". This app builds natively and has no
    /// mount, so the output cannot appear here today; the case is implemented
    /// anyway so the two explainers stay ONE list of troubles, exactly as the
    /// mac implements the Windows-only "untrusted mount point" case.
    ///
    /// <para>Matched NARROWLY and asked LAST, both copied from the mac rather
    /// than re-derived: "Error response from daemon" was the tempting
    /// substring and would tell a teacher whose disk was full to check where
    /// their folder is kept, and a matcher placed earlier could shadow the
    /// specific troubles above it. The sentence is the contract's, and it
    /// reads mac-shaped (the home-folder advice is the mac VM's limit); said
    /// so on #230 rather than forked.</para>
    /// </summary>
    private static string? WorkspaceNotCreatedExplanation(string output) =>
        output.Contains("bind source path does not exist")
            ? "Plantoir could not get this folder ready for building. Check that it is inside your home folder — on your Desktop or in Documents, for example — and not on an external drive or in a shared location, then try again."
            : null;

    private static string? MissingFrontPageExplanation(string output) =>
        output.Contains("no front page, so no website was produced")
            ? "This section has no front page, so there is no website to publish. Put the front page back, then publish again."
            : null;

    /// <summary>
    /// A section whose FRONT PAGE's settings cannot be read (#300, the mac's
    /// #246): the build hides such a page, so there is no website to publish.
    /// Asked before the missing-front-page and missing-build cards — the
    /// build's line deliberately never says "no front page", and it is
    /// followed by "Built site not found" — and the line number is read only
    /// from the same line as the sign. The mac's
    /// <c>FailureExplainer.unreadableFrontPageExplanation</c>, word for word.
    /// </summary>
    private static string? UnreadableFrontPageExplanation(string output)
    {
        const string sign = "the settings at the top of its front page could not be read";
        int at = output.IndexOf(sign, StringComparison.Ordinal);
        if (at < 0) return null;
        const string headline = "The settings at the top of this section's front page could not be read, "
            + "so there is no website to publish. ";
        return LineNumberAfter("(near line ", output[(at + sign.Length)..]) is { } line
            ? headline + $"Open the front page in Obsidian, fix its settings near line {line}, then publish again."
            : headline + "Open the front page in Obsidian, fix its settings, then publish again.";
    }

    /// <summary>The number after <paramref name="marker"/>, only when the marker is on the same line.</summary>
    private static int? LineNumberAfter(string marker, string text)
    {
        int at = text.IndexOf(marker, StringComparison.Ordinal);
        if (at < 0 || text[..at].Contains('\n')) return null;
        string digits = new(text[(at + marker.Length)..].TakeWhile(char.IsAsciiDigit).ToArray());
        return int.TryParse(digits, System.Globalization.NumberStyles.None, System.Globalization.CultureInfo.InvariantCulture, out int line) ? line : null;
    }
}
