using System;
using System.Collections.Generic;
using System.Linq;
using Plantoir.Core.Assist;
using Xunit;

namespace Plantoir.Tests;

/// <summary>
/// The shelf of things a teacher can ask for: what it offers, and that its
/// shape is remembered.
/// </summary>
public class AssistPromptShelfTests
{
    private static readonly string[] GroupTitles =
    [
        "Making pages visible",
        "Taking it back",
        "Checking",
        "Planning classes",
        "Putting the site online",
    ];

    [Fact]
    public void OpenGroupsSerializationAndParsing()
    {
        string serialized = AssistPromptShelf.SerializeOpenGroups(new[] { "Checking", "Taking it back" });
        var parsed = AssistPromptShelf.ParseOpenGroups(serialized);

        Assert.Contains("Checking", parsed);
        Assert.Contains("Taking it back", parsed);
        Assert.Equal(2, parsed.Count);
    }

    [Fact]
    public void NothingStoredMeansEverythingIsShut()
    {
        Assert.Empty(AssistPromptShelf.ParseOpenGroups(null));
        Assert.Empty(AssistPromptShelf.ParseOpenGroups(""));
        Assert.Empty(AssistPromptShelf.ParseOpenGroups("   "));
    }

    [Fact]
    public void TheShelfsShortcutPhrasingsStillFire()
    {
        Assert.Equal("deploy_section", AssistCardCommand.Matching("Deploy now")?.ToolName);
        Assert.Equal("check_section",
            AssistCardCommand.Matching("What would students see in this section right now?")?.ToolName);
        Assert.Equal("rebuild_preview", AssistCardCommand.Matching("Rebuild the preview")?.ToolName);
        Assert.Equal("undo_last_change", AssistCardCommand.Matching("Undo that")?.ToolName);
        Assert.Equal("publish_class_on", AssistCardCommand.Matching("Publish tomorrow's class")?.ToolName);
    }

    [Fact]
    public void NoGroupTitleContainsTheSeparator()
    {
        foreach (string title in GroupTitles)
        {
            Assert.DoesNotContain("|", title);
            Assert.False(string.IsNullOrWhiteSpace(title));
        }
    }

    [Fact]
    public void NoGroupTitleClaimsPublishingReachesStudents()
    {
        foreach (string title in GroupTitles)
        {
            if (title == "Putting the site online") continue;
            Assert.DoesNotContain("student", title, StringComparison.OrdinalIgnoreCase);
        }
    }

    [Fact]
    public void EveryCardIsEitherMatchedInCodeOrKnownToGoToTheModel()
    {
        var goesToTheModel = new HashSet<string>(StringComparer.Ordinal)
        {
            // "Publish Unit 2, Day 3" left this set with #432: the exact form
            // "publish unit <n>, day <m>" is answered in code, as it is on the mac.
            // "Unpublish Unit 2, Day 3" left this set with #217: the hide and
            // unpublish frame answers it in code, as it does on the mac.
            // "Deploy at 6:30 AM" left this set with #193: the deploy-at-a-time
            // family answers it in code, as it does on the mac.
            // "Cancel scheduled deploy" left it with #466 (the mac's #449,
            // 2026-10-07): the cancel frame accepts the shelf's own sentence,
            // with no determiner, so the card is answered in code and the set
            // is empty. It stays, empty, so a new card that should go to the
            // model is still a decision somebody writes down here.
        };

        var seen = new HashSet<string>(StringComparer.Ordinal);
        foreach (var (_, phrasings) in AssistPromptShelf.Groups)
        {
            foreach (string phrasing in phrasings)
            {
                Assert.DoesNotContain(phrasing, seen);
                seen.Add(phrasing);

                if (goesToTheModel.Contains(phrasing))
                {
                    Assert.Null(AssistCardCommand.Matching(phrasing));
                }
                else
                {
                    Assert.NotNull(AssistCardCommand.Matching(phrasing));
                }
            }
        }
        Assert.NotEmpty(seen);
    }

    [Fact]
    public void TheShelfOffersTheCapabilitiesATeacherWouldLookFor()
    {
        var everything = new List<string>();
        foreach (var (_, phrasings) in AssistPromptShelf.Groups)
        {
            everything.AddRange(phrasings);
        }
        string all = string.Join("\n", everything).ToLowerInvariant();

        foreach (string expected in new[] { "publish", "unpublish", "undo", "preview", "deploy",
                                            "class page", "new unit", "dates" })
        {
            Assert.Contains(expected, all);
        }
    }
}
