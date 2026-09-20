using Plantoir.Core.Models;

namespace Plantoir.Tests;

/// <summary>
/// How a folder problem reaches somebody talking to the ASSISTANT, which has
/// no dialog to raise and no window to raise it in.
///
/// <para>The teacher asked for something, so the answer to what they asked
/// comes first and the finding follows it. The sentence is the payload's own,
/// exactly as in the app's dialog — the whole point of the wording travelling
/// in the line is that the same problem cannot be worded three different
/// ways.</para>
/// </summary>
public class AssistFolderProblemTests
{
    private static SiteHealthFinding Finding(string name = "mediaFolderMissing") =>
        new(name, "The Media folder for ICS3U is not there.",
            "Images and files you have added to pages live in a folder called Media.",
            true, "ICS3U", 1);

    [Fact]
    public void AHealthyCourseAddsNothingToTheAnswer()
    {
        const string message = "Published ICS3U Section 1.";
        Assert.Equal(message, SiteHealthFinding.Appending(message, null));
        Assert.Equal(message, SiteHealthFinding.Appending(message, System.Array.Empty<SiteHealthFinding>()));
    }

    [Fact]
    public void TheAnswerComesFirstAndTheFindingFollowsIt()
    {
        string said = SiteHealthFinding.Appending("Published ICS3U Section 1.", new[] { Finding() });

        Assert.StartsWith("Published ICS3U Section 1.", said);
        Assert.Contains("The Media folder for ICS3U is not there.", said);
        Assert.Contains("Images and files you have added to pages live in a folder called Media.", said);
    }

    [Fact]
    public void NoMachineryReachesTheTeacher()
    {
        // The line the build printed is a JSON payload, and an assistant's
        // answer is read by a teacher (CLAUDE.md rule 1).
        string said = SiteHealthFinding.Appending("Published ICS3U Section 1.",
            new[] { Finding(), Finding("sectionIndexMissing") });

        Assert.DoesNotContain(SiteHealthFinding.Marker, said);
        Assert.DoesNotContain("mediaFolderMissing", said);
        Assert.DoesNotContain("fixable", said);
    }

    [Fact]
    public void EachFindingGetsItsOwnParagraph()
    {
        var second = Finding("sectionIndexMissing") with
        {
            Sentence = "ICS3U Section 1 has no front page.",
            Detail = "Every section has a page called index.md.",
        };
        string said = SiteHealthFinding.Appending("Published.", new[] { Finding(), second });

        Assert.Equal(3, said.Split("\n\n").Length);
    }
}
