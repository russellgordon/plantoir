namespace Plantoir.Core.Scripting;

/// <summary>
/// Turns a failed task's raw output into one actionable sentence — or null
/// when nothing is recognized, because an honest fallback (showing the
/// output) beats a confident guess.
/// </summary>
public static class FailureExplainer
{
    public static string? Explanation(string output) =>
        SetupExplanation(output)
        ?? VaultLinkExplanation(output)
        ?? RateLimitExplanation(output)
        ?? AccountExplanation(output)
        ?? ConnectionExplanation(output)
        ?? FolderAccessExplanation(output)
        ?? MissingFrontPageExplanation(output)
        ?? MissingBuildExplanation(output);

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
    private static string? MissingFrontPageExplanation(string output) =>
        output.Contains("no front page, so no website was produced")
            ? "This section has no front page, so there is no website to publish. Put the front page back, then publish again."
            : null;
}
