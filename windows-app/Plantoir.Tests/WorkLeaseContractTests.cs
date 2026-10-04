using System.Text.Json.Nodes;
using Plantoir.Core.Assist;

namespace Plantoir.Tests;

/// <summary>
/// #289: the lease rules of mac #156, run from the contract rather than
/// retyped. Three case lists, each through the pure seam in
/// <see cref="WorkLease"/>: who stands in whose way
/// (<c>shared-rules.json</c> → <c>workLeases.declining.cases</c>), who counts as
/// alive (<c>workLeases.liveness.cases</c>), and what a lease's body says
/// (<c>file-formats.json</c> → <c>workLease.bodyCases</c>).
/// </summary>
public class WorkLeaseContractTests
{
    private static bool AppliesHere(JsonNode c) =>
        c["appliesOn"] is not JsonArray platforms || platforms.Any(p => p!.ToString() == "windows");

    [Fact]
    public void EveryDecliningCaseIsDecidedAsTheContractSays()
    {
        var cases = ContractLoader.LoadJson("shared-rules.json")["workLeases"]!["declining"]!["cases"]!.AsArray();
        // 32 since #413/#438: two copy cases are appliesOn ["windows"] (the mac
        // reads no copy lease and says so in onTheMac), and a third holds on
        // both. A case for another platform only is skipped by appliesOn, never
        // by name.
        Assert.True(cases.Count >= 32, $"only {cases.Count} declining cases were read");
        Assert.True(cases.Count(c => c!["appliesOn"] is JsonArray a && a.Any(p => p!.ToString() == "windows")) >= 2,
            "the windows-only copy cases are gone");

        var wrong = new List<string>();
        int ran = 0;
        foreach (var c in cases.Where(c => AppliesHere(c!)))
        {
            ran++;
            var asker = c!["asker"]!.ToString() switch
            {
                "aBuild" => WorkLease.Asker.ABuild,
                "aScheduledPublish" => WorkLease.Asker.AScheduledPublish,
                var other => throw new InvalidOperationException($"unknown asker {other}"),
            };
            int myPid = c["me"]!["pid"]!.GetValue<int>();
            var claim = c["me"]!["claim"] is JsonObject claimed
                ? new WorkLease.Claim(claimed["moment"]!.ToString(), claimed["pid"]!.GetValue<int>())
                : null;
            var others = c["others"]!.AsArray().Select(o => new WorkLease.Other(
                o!["course"]!.ToString(),
                o["kind"]!.ToString(),
                o["pid"]!.GetValue<int>(),
                o["moment"]?.ToString(),
                o["alive"]!.GetValue<bool>(),
                o["nameLine"]?.GetValue<bool>() ?? true)).ToList();

            string decided = WorkLease.FirstInTheWay(asker, "ICS3U", myPid, claim, others) is null ? "allowed" : "declined";
            if (decided != c["expect"]!.ToString())
                wrong.Add($"\"{c["name"]}\": expected {c["expect"]}, decided {decided}");
        }
        Assert.True(wrong.Count == 0, string.Join("\n", wrong));
        Assert.True(ran >= 32, $"only {ran} declining cases ran here");
    }

    [Fact]
    public void TheScheduledPublishWaitIsTheContractsOwn()
    {
        var wait = ContractLoader.LoadJson("shared-rules.json")["workLeases"]!["declining"]!["scheduledPublishWait"]!;
        Assert.Equal(wait["longestSeconds"]!.GetValue<int>(), (int)ScheduledRun.LongestWait.TotalSeconds);
        Assert.Equal(wait["lookAgainEverySeconds"]!.GetValue<int>(), (int)ScheduledRun.LookAgainEvery.TotalSeconds);
        Assert.Equal("wall", wait["clock"]!.ToString());
    }

    [Fact]
    public void EveryLivenessCaseIsDecidedAsTheContractSays()
    {
        var cases = ContractLoader.LoadJson("shared-rules.json")["workLeases"]!["liveness"]!["cases"]!.AsArray();
        var wrong = new List<string>();
        int ran = 0;
        foreach (var c in cases.Where(c => AppliesHere(c!)))
        {
            ran++;
            var signal = c!["signal"]!.ToString() switch
            {
                "exists" => WorkLease.Signal.Exists,
                "noSuchProcess" => WorkLease.Signal.NoSuchProcess,
                "notPermitted" => WorkLease.Signal.NotPermitted,
                _ => WorkLease.Signal.OtherError,
            };
            var (answer, entry) = c["table"] switch
            {
                null => (WorkLease.TableAnswer.NotAsked, (WorkLease.TableEntry?)null),
                JsonObject table => (WorkLease.TableAnswer.Entry, new WorkLease.TableEntry(
                    table["name"]?.ToString(), table["zombie"]?.GetValue<bool>() ?? false, table["start"]?.ToString())),
                var text when text.ToString() == "noSuchProcess" => (WorkLease.TableAnswer.NoSuchProcess, null),
                _ => (WorkLease.TableAnswer.CouldNotAsk, null),
            };
            bool alive = WorkLease.IsAlive(c["pid"]!.GetValue<int>(), signal, answer, entry,
                c["lease"]?["name"]?.ToString(), c["lease"]?["start"]?.ToString());
            string decided = alive ? "alive" : "gone";
            if (decided != c["expect"]!.ToString())
                wrong.Add($"\"{c["name"]}\": expected {c["expect"]}, decided {decided}");
        }
        Assert.True(ran >= 17, $"only {ran} liveness cases ran");
        Assert.True(wrong.Count == 0, string.Join("\n", wrong));
    }

    [Fact]
    public void EveryBodyCaseIsReadAsTheContractSays()
    {
        var cases = ContractLoader.LoadJson("file-formats.json")["workLease"]!["bodyCases"]!.AsArray();
        Assert.True(cases.Count >= 7, $"only {cases.Count} body cases were read");
        foreach (var c in cases)
        {
            var (name, start) = WorkLease.ReadBody(c!["body"]!.ToString());
            Assert.True(c["expect"]!["name"]?.ToString() == name, $"\"{c["name"]}\": name {name ?? "null"}");
            Assert.True(c["expect"]!["start"]?.ToString() == start, $"\"{c["name"]}\": start {start ?? "null"}");
        }
    }

    [Fact]
    public void ALeaseIsWrittenInTheSharedShape()
    {
        string folder = Path.Combine(Path.GetTempPath(), "plantoir-tests", "lease-shape-" + Guid.NewGuid().ToString("N"));
        Directory.CreateDirectory(Path.Combine(folder, "courses"));
        try
        {
            using var lease = WorkLease.Take(folder, "ics3u", WorkLease.Building);
            string file = Path.Combine(folder, "courses", ".internal", "activity",
                $"ICS3U.build.{Environment.ProcessId}.lease");
            string body = File.ReadAllText(file);
            Assert.EndsWith("\n", body);
            Assert.DoesNotContain("\r", body);
            string[] lines = body.TrimEnd('\n').Split('\n');
            Assert.Equal(Environment.ProcessId.ToString(), lines[0]);
            Assert.Equal(System.Diagnostics.Process.GetCurrentProcess().ProcessName, lines[1]);
            Assert.Matches(@"^\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}\.\d{7}Z$", lines[2]);
            Assert.Equal(lines[2], lease.Claim.Moment);
        }
        finally { try { Directory.Delete(folder, true); } catch { } }
    }
}
