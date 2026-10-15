using System;
using System.IO;
using System.Linq;
using System.Xml.Linq;
using Xunit;

namespace Plantoir.Tests;

/// <summary>
/// The ledger's own rule, made a test: every entry is owed by a milestone
/// LATER than the version being built (#481, 2026-10-15).
/// </summary>
/// <remarks>
/// <para>While Windows catches up to the mac's 1.7.1 in batches, the ledger
/// holds work later batches own, each entry on the milestone its feature
/// shipped in on the mac. Those must all be gone by the time the version they
/// name is cut — and "remember to empty the ledger" is the kind of rule that is
/// remembered until the day it matters. So this reads <c>&lt;Version&gt;</c>
/// from <c>Plantoir.csproj</c>: setting it to 1.7.1 turns every v1.5.0–v1.7.1
/// entry still in the ledger red, and the release cannot be cut green.</para>
///
/// <para>It is "later than this build", not "empty at the cut", on purpose: an
/// entry owed by a genuinely later release (a v2.0.0) rightly survives a 1.7.1
/// cut. A milestone that is not a version at all fails, because it cannot be
/// compared — which is what retired the old "Windows: parity with mac v1.4.0"
/// spelling.</para>
///
/// <para><c>RELEASING.md</c> runs the suite again AFTER the version is set,
/// because a run made before the bump compares against the previous version
/// and passes with entries left.</para>
/// </remarks>
public class NamedGapLedgerTests
{
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

    private static Version ThisBuild()
    {
        var project = XDocument.Load(Path.Combine(RepoRoot, "windows-app", "Plantoir", "Plantoir.csproj"));
        string text = project.Descendants("Version").Single().Value.Trim();
        return Version.Parse(text);
    }

    [Fact]
    public void EveryEntryIsOwedByAMilestoneLaterThanThisBuild()
    {
        var thisBuild = ThisBuild();
        var problems = NamedGapLedger.All
            .Select(entry =>
            {
                string milestone = entry.Milestone;
                string bare = milestone.StartsWith('v') ? milestone[1..] : milestone;
                if (!Version.TryParse(bare, out var owedBy))
                    return $"{entry.Area} → \"{entry.Key}\" (#{entry.Issue}) names the milestone " +
                           $"\"{milestone}\", which is not a version, so nothing can tell whether it is " +
                           "later than this build. Name the GitHub milestone the issue carries (\"v1.6.0\").";
                if (owedBy <= thisBuild)
                    return $"{entry.Area} → \"{entry.Key}\" is owed by #{entry.Issue} on {milestone}, and " +
                           $"this build is {thisBuild}. A ledger entry may only hold open work a LATER " +
                           "release owns: build it, or move the issue (and this entry) to a later milestone " +
                           "with Russell's say-so — never cut a release over it.";
                return null;
            })
            .Where(problem => problem is not null)
            .ToList();

        Assert.True(problems.Count == 0, string.Join("\n", problems));
    }
}
