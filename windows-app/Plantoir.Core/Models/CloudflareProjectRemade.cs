using System;
using System.Collections.Generic;
using System.Linq;
using System.Text.RegularExpressions;

namespace Plantoir.Core.Models;

/// <summary>
/// deploy.py made a section's Cloudflare Pages project again because the saved
/// one was gone from the account (#395, the mac's
/// <c>CloudflareProjectRemadeReport</c>). The shared Python prints
/// <c>PLANTOIR_CLOUDFLARE_REMADE: &lt;course&gt;/&lt;section&gt; &lt;project&gt; &lt;address&gt;</c>
/// with the course's one permitted space written <c>+</c>; this reads it back
/// so the trail can say the address may have changed.
///
/// <para>Contract: <c>shared-rules.json → activityTrail.mustRecord →
/// "cloudflare project made again"</c> (<c>marker</c>, <c>line</c>). Anything
/// not of the marker's exact shape records NOTHING — a path, a missing field,
/// extra words, <c>setup</c> in place of a section, a dotted project name —
/// because a line on the trail that is wrong is worse than none.</para>
/// </summary>
public sealed record CloudflareProjectRemade(string Course, int Section, string Project, string Address)
{
    public const string Marker = "PLANTOIR_CLOUDFLARE_REMADE:";

    // Course: letters/digits with at most one '+' (the space); section: a
    // number; project: Cloudflare's own shape (lower-case letters, digits,
    // hyphens — no dot, no slash); address: a host name, no path.
    private static readonly Regex Shape = new(
        @"PLANTOIR_CLOUDFLARE_REMADE: (?<course>[A-Za-z0-9]+(?:\+[A-Za-z0-9]+)?)/(?<section>[1-9][0-9]*) " +
        @"(?<project>[a-z0-9](?:[a-z0-9-]*[a-z0-9])?) (?<address>[A-Za-z0-9-]+(?:\.[A-Za-z0-9-]+)+)\s*$",
        RegexOptions.CultureInvariant);

    /// <summary>The report a line carries, or null for anything not of the marker's shape.</summary>
    public static CloudflareProjectRemade? Parse(string? line)
    {
        if (string.IsNullOrEmpty(line)) return null;
        int at = line.IndexOf(Marker, StringComparison.Ordinal);
        if (at < 0) return null;
        var match = Shape.Match(line[at..].TrimEnd('\r', '\n'));
        if (!match.Success || match.Index != 0) return null;
        return new CloudflareProjectRemade(
            match.Groups["course"].Value.Replace('+', ' '),
            int.Parse(match.Groups["section"].Value),
            match.Groups["project"].Value,
            match.Groups["address"].Value);
    }

    /// <summary>The entry's <c>line</c> after the place (the Note writes <c>{course}/{section}</c>).</summary>
    public string TrailSentence =>
        $"the Cloudflare project {Project} was not in this Cloudflare account, so it was made again; " +
        $"the website is now at {Address}";

    /// <summary>Every report in a scheduled publish's record.</summary>
    public static IReadOnlyList<CloudflareProjectRemade> ReportsIn(IEnumerable<string> lines) =>
        lines.Select(Parse).Where(report => report is not null).Select(report => report!).ToList();
}
