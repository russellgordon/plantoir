using System.Text.Json.Nodes;
using Plantoir.Core.Assist;

namespace Plantoir.Tests;

public class AssistPromptHistoryTests
{
    [Fact]
    public void PromptHistory_AllContractCases_Pass()
    {
        var doc = ContractLoader.LoadJson("assist-cases.json");
        var cases = doc["promptHistory"]!["cases"]!.AsArray();

        foreach (var testCase in cases)
        {
            if (testCase is null) continue;
            string name = testCase["name"]!.ToString();
            var remember = testCase["remember"]?.AsArray();

            var history = new AssistPromptHistory();
            if (remember != null)
            {
                foreach (var r in remember)
                {
                    history.Remember(r!.ToString());
                }
            }

            if (testCase["expectEntries"] is JsonArray expectedEntries)
            {
                var actual = history.Entries;
                Assert.Equal(expectedEntries.Count, actual.Count);
                for (int i = 0; i < expectedEntries.Count; i++)
                {
                    Assert.Equal(expectedEntries[i]!.ToString(), actual[i]);
                }
            }

            if (testCase["steps"] is JsonArray steps)
            {
                foreach (var step in steps)
                {
                    string action = step!["do"]!.ToString();
                    string? typed = step["typed"]?.ToString();
                    string? expected = step["expect"]?.ToString();

                    if (action == "up")
                    {
                        string? actual = history.Earlier(typed ?? "");
                        Assert.Equal(expected, actual);
                    }
                    else if (action == "down")
                    {
                        string? actual = history.Later();
                        Assert.Equal(expected, actual);
                    }
                    else if (action == "type")
                    {
                        history.StopBrowsing();
                    }
                }
            }
        }
    }

    [Fact]
    public void PromptHistory_SurvivesBeingStoredAndReadBack()
    {
        var history = new AssistPromptHistory();
        history.Remember("Publish “Unit 2, Day 3”; and the rest");
        history.Remember("What would students see in this section right now?");

        var readBack = AssistPromptHistory.Read(history.Stored);

        Assert.Equal(history.Entries, readBack.Entries);
    }

    [Fact]
    public void PromptHistory_UnreadableStorageBecomesAnEmptyHistory()
    {
        var history = AssistPromptHistory.Read("{ not json");
        Assert.Empty(history.Entries);
    }

    [Fact]
    public void PromptHistory_NullOrWhitespaceStorageBecomesAnEmptyHistory()
    {
        var history1 = AssistPromptHistory.Read(null);
        Assert.Empty(history1.Entries);

        var history2 = AssistPromptHistory.Read("   ");
        Assert.Empty(history2.Entries);
    }

    [Fact]
    public void PromptHistory_OldestFallOffOnceItIsFull()
    {
        var history = new AssistPromptHistory();
        for (int i = 1; i <= AssistPromptHistory.MostRemembered + 5; i++)
        {
            history.Remember($"Publish Unit 1, Day {i}");
        }

        Assert.Equal(AssistPromptHistory.MostRemembered, history.Entries.Count);
        Assert.Equal("Publish Unit 1, Day 6", history.Entries[0]);
        Assert.Equal($"Publish Unit 1, Day {AssistPromptHistory.MostRemembered + 5}", history.Entries[^1]);
    }
}
