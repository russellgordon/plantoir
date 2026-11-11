using Plantoir.Core.Scripting;
using Xunit;

namespace Plantoir.Tests;

/// <summary>
/// #728's one asker per question, as behaviour rather than text: a deploy's
/// runner is shared by every view of its section, so exactly one view asks its
/// question; a view that leaves with the question up hands it on, and its own
/// dialog — closed as it leaves, or answered in the moment before — sends
/// nothing (the implementation review's finding: without that, the left view's
/// Primary and the new asker's both reached the one prompt). What these cannot
/// reach without a window — that <c>TaskProgressView</c> really hides its
/// dialog on Unloaded — is <c>SectionDeployRunSourceTests</c>' scan.
/// </summary>
[Collection(SharedActivityState.Name)]
public sealed class QuestionAskersTests : IDisposable
{
    public QuestionAskersTests() => QuestionAskers.Reset();
    public void Dispose() => QuestionAskers.Reset();

    [Fact]
    public void OneViewAsks_TheSecondIsTurnedAway_UntilTheFirstIsDone()
    {
        var runner = new ScriptRunner();
        object first = new(), second = new();
        Assert.True(QuestionAskers.TryClaim(runner, first));
        Assert.True(QuestionAskers.TryClaim(runner, first), "the asker's own claim is still its own");
        Assert.False(QuestionAskers.TryClaim(runner, second), "two views asked the one question");
        QuestionAskers.Release(runner, second);   // not its claim: nothing happens
        Assert.False(QuestionAskers.TryClaim(runner, second));
        QuestionAskers.Release(runner, first);
        Assert.True(QuestionAskers.TryClaim(runner, second));
        Assert.True(QuestionAskers.TryClaim(new ScriptRunner(), first), "another runner's question is another question");
    }

    [Fact]
    public void AViewLeavingHandsTheQuestionOn_AndOnlyItsOwn()
    {
        var runner = new ScriptRunner();
        object leaving = new(), staying = new();
        var handedOn = new List<ScriptRunner>();
        QuestionAskers.LeftUnanswered += handedOn.Add;
        Assert.True(QuestionAskers.TryClaim(runner, leaving));

        QuestionAskers.HandOn(runner, staying);   // not the asker: nothing to hand on
        Assert.Empty(handedOn);

        QuestionAskers.HandOn(runner, leaving);
        Assert.Equal(new[] { runner }, handedOn);
        Assert.True(QuestionAskers.TryClaim(runner, staying), "the next view could not take the question up");
        // The left view's dialog ends after this and releases — not the new asker's claim.
        QuestionAskers.Release(runner, leaving);
        Assert.False(QuestionAskers.TryClaim(runner, new object()), "the left view's release freed the new asker's claim");
    }

    /// <summary>
    /// A hand-on asked for while the leaving view's dialog is still OPEN waits
    /// until that dialog has closed (<see cref="QuestionAskers.Done"/>), and
    /// then exactly one view gets the question (#728's third review: handed
    /// on at once, the next view in the same window met WinUI's one-dialog
    /// rule, its ShowAsync threw, and nobody asked again).
    /// </summary>
    [Fact]
    public void AHandOnWhileTheDialogIsOpen_WaitsUntilItCloses_ThenOneViewGetsIt()
    {
        var runner = new ScriptRunner();
        object leaving = new(), next = new(), another = new();
        var handedOn = new List<ScriptRunner>();
        QuestionAskers.LeftUnanswered += handedOn.Add;
        Assert.True(QuestionAskers.TryClaim(runner, leaving));

        QuestionAskers.HandOnWhenDone(runner, leaving);   // the view leaves; its dialog is closing
        Assert.Empty(handedOn);
        Assert.False(QuestionAskers.TryClaim(runner, next), "the question was free while the old dialog was still up");

        QuestionAskers.Done(runner, leaving);              // its ShowAsync has returned
        Assert.Equal(new[] { runner }, handedOn);
        Assert.True(QuestionAskers.TryClaim(runner, next));
        Assert.False(QuestionAskers.TryClaim(runner, another), "two views got the handed-on question");

        QuestionAskers.Done(runner, leaving);              // twice: nothing more
        QuestionAskers.Done(runner, next);                 // the next view answers: an ordinary end
        Assert.Single(handedOn);

        // Not asked to hand on: Done only lets the claim go.
        Assert.True(QuestionAskers.TryClaim(runner, another));
        QuestionAskers.Done(runner, another);
        Assert.Single(handedOn);
        // A hand-on asked by a view that does not hold the claim is ignored.
        Assert.True(QuestionAskers.TryClaim(runner, next));
        QuestionAskers.HandOnWhenDone(runner, another);
        QuestionAskers.Done(runner, next);
        Assert.Single(handedOn);
    }

    /// <summary>A dialog closing after its view left sends nothing, whichever button it reports.</summary>
    [Theory]
    [InlineData(true, false, true, QuestionAskers.Answer.Send)]
    [InlineData(false, false, true, QuestionAskers.Answer.Cancel)]
    [InlineData(true, true, true, QuestionAskers.Answer.Nothing)]    // answered as its view left: handed on
    [InlineData(false, true, true, QuestionAskers.Answer.Nothing)]   // hidden as its view left: not a Cancel
    [InlineData(true, false, false, QuestionAskers.Answer.Nothing)]  // another view already answered
    [InlineData(false, false, false, QuestionAskers.Answer.Nothing)]
    public void WhatAClosingDialogDoes(bool mainButton, bool askerHasLeft, bool stillWaits, QuestionAskers.Answer expected) =>
        Assert.Equal(expected, QuestionAskers.WhatToDo(mainButton, askerHasLeft, stillWaits));
}
