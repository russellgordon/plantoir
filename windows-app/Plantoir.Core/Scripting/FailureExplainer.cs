namespace Plantoir.Core.Scripting;

/// <summary>
/// Turns a failed task's raw output into one actionable sentence — or null
/// when nothing is recognized, because an honest fallback (showing the
/// output) beats a confident guess.
/// </summary>
public static class FailureExplainer
{
    public static string? Explanation(string output) =>
        RateLimitExplanation(output)
        ?? AccountExplanation(output)
        ?? ConnectionExplanation(output)
        ?? FolderAccessExplanation(output)
        ?? MissingBuildExplanation(output);

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
}
