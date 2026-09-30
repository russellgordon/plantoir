namespace Plantoir.Core.Scripting;

/// <summary>
/// The parsing contract with the launchers: everything the interface learns,
/// it learns from lines the scripts really print.
/// </summary>
public static class OutputParsers
{
    /// <summary>
    /// The announced preview address — "Preview will be available at: http://localhost:8091/".
    /// localhost is normalized to 127.0.0.1 (browsers try IPv6 ::1 first and
    /// the container publishes IPv4 only). The LAST announcement wins. The
    /// host port is a probed per-folder block, so it is never assumed.
    /// </summary>
    /// <summary>The launcher's announcement marker — app-rules.json → previewPorts.announcedAddress.marker.</summary>
    public const string PreviewAnnouncementMarker = "Preview will be available at: ";

    public static Uri? PreviewAddress(string text)
    {
        const string marker = PreviewAnnouncementMarker;
        Uri? found = null;
        foreach (string line in text.Split('\n'))
        {
            int index = line.IndexOf(marker, StringComparison.Ordinal);
            if (index < 0) continue;
            string address = line[(index + marker.Length)..].Trim().Replace("localhost", "127.0.0.1");
            if (Uri.TryCreate(address, UriKind.Absolute, out Uri? uri) && !uri.IsDefaultPort)
                found = uri;
            else if (Uri.TryCreate(address, UriKind.Absolute, out Uri? anyPort) && anyPort.Port > 0)
                found = anyPort;
        }
        return found;
    }

    /// <summary>
    /// The live-site address after a publish. Found by the LABEL the publisher
    /// prints (Site URL: / Live URL: / Site:) — never by guessing at the
    /// scheme or hostname; Admin: lines (Netlify's dashboard) are skipped, and
    /// a plain-http .netlify.app address is promoted to https since Netlify
    /// redirects there anyway.
    /// </summary>
    public static Uri? PublishedSiteUrl(string text)
    {
        string? announced = null;
        string? anyNetlifyAddress = null;
        foreach (string rawLine in text.Split('\n'))
        {
            string line = rawLine.Trim();
            if (line.StartsWith("Admin:", StringComparison.Ordinal)) continue;
            bool namesTheSite = line.StartsWith("Site URL:", StringComparison.Ordinal)
                             || line.StartsWith("Live URL:", StringComparison.Ordinal)
                             || line.StartsWith("Site:", StringComparison.Ordinal);
            foreach (string rawToken in line.Split(' ', StringSplitOptions.RemoveEmptyEntries))
            {
                string token = TidiedAddress(rawToken);
                if (!token.StartsWith("https://", StringComparison.Ordinal) &&
                    !token.StartsWith("http://", StringComparison.Ordinal)) continue;
                if (token.Contains("app.netlify.com") || token.Contains("docs.netlify.com")) continue;
                if (namesTheSite) announced = token;
                else if (token.Contains(".netlify.app")) anyNetlifyAddress = token;
            }
        }
        string? chosen = announced ?? anyNetlifyAddress;
        if (chosen is null) return null;
        if (chosen.StartsWith("http://", StringComparison.Ordinal) && chosen.Contains(".netlify.app"))
            chosen = "https://" + chosen["http://".Length..];
        return Uri.TryCreate(chosen, UriKind.Absolute, out Uri? uri) ? uri : null;
    }

    private static string TidiedAddress(string token)
    {
        // A pseudo console can render a following status line onto the tail of
        // the URL line with no separating space, gluing an emoji onto the
        // address — the "✅" from "Deploy complete." landing on the site link
        // and breaking it. These URLs are always ASCII, so cut at the first
        // non-ASCII character, then strip trailing sentence punctuation.
        int end = 0;
        while (end < token.Length && token[end] <= '\x7e') end++;
        token = token[..end];
        while (token.Length > 0 && (token[^1] == '.' || token[^1] == ',' || token[^1] == ')'))
            token = token[..^1];
        return token;
    }

    /// <summary>
    /// The folder a folder-mode publish landed in — deploy.ps1 prints
    /// "PUBLISHED_FOLDER=&lt;path&gt;" so the app can offer it in Explorer.
    /// The LAST marker wins; null when none appears (a Netlify publish).
    /// </summary>
    public static string? PublishedFolder(string text)
    {
        const string marker = "PUBLISHED_FOLDER=";
        string? found = null;
        foreach (string rawLine in text.Split('\n'))
        {
            string line = rawLine.Trim();
            int index = line.IndexOf(marker, StringComparison.Ordinal);
            if (index < 0) continue;
            string path = line[(index + marker.Length)..].Trim();
            if (path.Length > 0) found = path;
        }
        return found;
    }

    /// <summary>Custom-domain swap: host replaced, https forced, path kept.</summary>
    public static Uri ApplyingCustomDomain(string? domain, Uri url)
    {
        if (string.IsNullOrEmpty(domain)) return url;
        try
        {
            var builder = new UriBuilder(url) { Host = domain, Scheme = "https", Port = -1 };
            return builder.Uri;
        }
        catch { return url; }
    }

    /// <summary>"uploaded 125/234 required files" — the LAST match in the chunk wins.</summary>
    public static (int Done, int Total)? UploadProgress(string text)
    {
        (int, int)? found = null;
        foreach (string line in text.Split('\n'))
        {
            int index = line.IndexOf("uploaded ", StringComparison.Ordinal);
            if (index < 0) continue;
            string first = line[(index + "uploaded ".Length)..].Split(' ', StringSplitOptions.RemoveEmptyEntries).FirstOrDefault() ?? "";
            var parts = first.Split('/');
            if (parts.Length == 2 && int.TryParse(parts[0], out int done) && int.TryParse(parts[1], out int total))
                found = (done, total);
        }
        return found;
    }

    /// <summary>"Netlify requires 234 file(s) for this deploy." — total known before the first batch.</summary>
    public static int? UploadTotal(string text)
    {
        int? found = null;
        foreach (string line in text.Split('\n'))
        {
            int index = line.IndexOf("requires ", StringComparison.Ordinal);
            if (index < 0) continue;
            string first = line[(index + "requires ".Length)..].Split(' ', StringSplitOptions.RemoveEmptyEntries).FirstOrDefault() ?? "";
            if (int.TryParse(first, out int total)) found = total;
        }
        return found;
    }

    /// <summary>BuildKit "#12 [ 7/15] RUN …" — movement during the minutes-long first image build.</summary>
    public static (int Done, int Total)? BuildStepProgress(string text)
    {
        (int, int)? found = null;
        foreach (string line in text.Split('\n'))
        {
            if (!line.StartsWith("#", StringComparison.Ordinal)) continue;
            int open = line.IndexOf('[');
            int close = line.IndexOf(']');
            if (open < 0 || close < 0 || close <= open) continue;
            string inside = line[(open + 1)..close].Replace(" ", "");
            var parts = inside.Split('/');
            if (parts.Length == 2 && int.TryParse(parts[0], out int done) && int.TryParse(parts[1], out int total))
                found = (done, total);
        }
        return found;
    }

    /// <summary>
    /// "EXAMPLE_COURSE_CODE=EXC2O" — the installed example's real code (an
    /// alternate is assigned when EXC2O is taken). Last non-empty wins.
    /// </summary>
    public static string? ExampleCourseCode(string text)
    {
        const string marker = "EXAMPLE_COURSE_CODE=";
        string? found = null;
        foreach (string rawLine in text.Split('\n'))
        {
            string line = rawLine.Trim();
            int index = line.IndexOf(marker, StringComparison.Ordinal);
            if (index < 0) continue;
            string code = line[(index + marker.Length)..].Trim();
            if (code.Length > 0) found = code;
        }
        return found;
    }
}
