using Plantoir.Core.Models;

namespace Plantoir.Tests;

/// <summary>
/// Which folder problems reach the teacher, once each, and what the dialog is
/// titled.
///
/// <para>The failure mode for this whole feature is NAGGING: a healthy course
/// must see nothing at all, and a warning dismissed by habit is one that gets
/// dismissed when it matters. Most of what is pinned here is about not showing
/// something.</para>
/// </summary>
public class FolderProblemQueueTests
{
    private static SiteHealthFinding Finding(string name, int section = 1, string course = "ICS3U") =>
        new(name, $"{name} happened.", "Some detail.", true, course, section);

    [Fact]
    public void AHealthyCourseHasNothingToShow()
    {
        var queue = new FolderProblemQueue();
        Assert.False(queue.Note(System.Array.Empty<SiteHealthFinding>(), false));
        Assert.Null(queue.TakeNext());
    }

    [Fact]
    public void ARunAnnouncingItsFindingsOneAtATimeProducesOneBatch()
    {
        // The runner raises a notification per finding, and each one carries
        // the whole list so far. Without de-duplication the second announcement
        // would offer the first finding again.
        var queue = new FolderProblemQueue();
        var first = Finding("mediaFolderMissing");
        var second = Finding("sectionIndexMissing");

        Assert.True(queue.Note(new[] { first }, false));
        Assert.True(queue.Note(new[] { first, second }, false));

        var batch = queue.TakeNext();
        Assert.Equal(new[] { "mediaFolderMissing", "sectionIndexMissing" },
                     batch!.Value.Findings.Select(f => f.Name).ToArray());
        Assert.Null(queue.TakeNext());
    }

    [Fact]
    public void SomethingAlreadyShownIsNeverShownAgain()
    {
        // A teacher who dismissed the dialog and carried on editing must not
        // meet it again on the next redraw, or on the next announcement from
        // the same run.
        var queue = new FolderProblemQueue();
        var finding = Finding("mediaFolderMissing");
        queue.Note(new[] { finding }, false);
        queue.TakeNext();

        Assert.False(queue.Note(new[] { finding }, false));
        Assert.Null(queue.TakeNext());
    }

    [Fact]
    public void TheSameCheckInAnotherSectionIsAnotherProblem()
    {
        var queue = new FolderProblemQueue();
        queue.Note(new[] { Finding("sectionIndexMissing", section: 1) }, false);
        queue.TakeNext();

        Assert.True(queue.Note(new[] { Finding("sectionIndexMissing", section: 2) }, false));
        Assert.Single(queue.TakeNext()!.Value.Findings);
    }

    [Fact]
    public void WhatArrivesWhileADialogIsUpIsHeldRatherThanMergedOrDropped()
    {
        // Taken = on screen. Merging into what the teacher is reading would
        // change the title and message under their cursor; dropping would lose
        // a failed deploy's findings, which is reachable — they can arrive
        // while an earlier batch is still up.
        var queue = new FolderProblemQueue();
        queue.Note(new[] { Finding("mediaFolderMissing") }, false);
        queue.TakeNext();

        Assert.True(queue.Note(new[] { Finding("noGradedFolders") }, false));

        var afterwards = queue.TakeNext();
        Assert.Single(afterwards!.Value.Findings);
        Assert.Equal("noGradedFolders", afterwards.Value.Findings[0].Name);
    }

    [Fact]
    public void TheNextBuildSaysItAgainIfItIsStillWrong()
    {
        // "Show it once" means once per BUILD, not once for the life of the
        // view. A teacher who dismissed the warning, went to Obsidian and
        // previewed again has asked a fresh question.
        var queue = new FolderProblemQueue();
        var finding = Finding("mediaFolderMissing");
        queue.Note(new[] { finding }, false);
        queue.TakeNext();

        queue.ForgetShown();

        Assert.True(queue.Note(new[] { finding }, false));
        Assert.Single(queue.TakeNext()!.Value.Findings);
    }

    [Fact]
    public void APublishRepeatsWhatAPreviewSaidBecauseTheSentenceIsDifferent()
    {
        // The case that matters most: the publish's copy of the same finding
        // is the one carrying what students can see. Suppressing it as
        // "already shown" loses precisely the sentence the occasion exists for.
        var queue = new FolderProblemQueue();
        var finding = Finding("mediaFolderMissing");
        queue.Note(new[] { finding }, cameFromPublishing: false);
        Assert.False(queue.TakeNext()!.Value.CameFromPublishing);

        queue.ForgetShown();
        queue.Note(new[] { finding }, cameFromPublishing: true);

        Assert.True(queue.TakeNext()!.Value.CameFromPublishing);
    }

    [Fact]
    public void ForgettingWhatWasShownDoesNotDiscardWhatIsStillWaiting()
    {
        // A dialog that has not been read yet is not stale.
        var queue = new FolderProblemQueue();
        queue.Note(new[] { Finding("mediaFolderMissing") }, false);

        queue.ForgetShown();

        Assert.Equal(1, queue.PendingCount);
    }

    [Fact]
    public void AHealthyPublishDoesNotRelabelTheNextBuildsFindings()
    {
        // A deploy reports its findings unconditionally, so a healthy course —
        // or a deploy that skipped the build — hands over an EMPTY batch. That
        // must not leave the flag set for the next build's findings.
        var queue = new FolderProblemQueue();
        queue.Note(System.Array.Empty<SiteHealthFinding>(), cameFromPublishing: true);

        queue.Note(new[] { Finding("noGradedFolders") }, cameFromPublishing: false);
        Assert.False(queue.TakeNext()!.Value.CameFromPublishing);
    }

    [Fact]
    public void APublishRepeatingSomethingStillWaitingStillCountsAsAPublish()
    {
        // The mixing rule, and the direction that matters. A preview's finding
        // can still be waiting — another dialog held the one slot WinUI allows
        // — when the teacher publishes. The publish really did happen, so the
        // batch must carry the sentence that names students.
        var queue = new FolderProblemQueue();
        var finding = Finding("mediaFolderMissing");
        queue.Note(new[] { finding }, cameFromPublishing: false);
        queue.Note(new[] { finding }, cameFromPublishing: true);   // nothing NEW, but a publish

        Assert.True(queue.TakeNext()!.Value.CameFromPublishing);
    }

    [Fact]
    public void ABatchHandedBackIsShownAfterAll()
    {
        // TakeNext marks a batch shown as it hands it over, which is right
        // while a dialog is going up — but one that never appeared has told
        // nobody anything.
        var queue = new FolderProblemQueue();
        queue.Note(new[] { Finding("mediaFolderMissing") }, cameFromPublishing: true);
        var taken = queue.TakeNext();

        queue.PutBack(taken!.Value.Findings, taken.Value.CameFromPublishing);

        var again = queue.TakeNext();
        Assert.Single(again!.Value.Findings);
        Assert.True(again.Value.CameFromPublishing);
    }

    [Fact]
    public void APublishingBatchStaysAPublishingBatchWhenABuildJoinsIt()
    {
        // The publish sentence is the one naming who has not seen the change
        // yet (students). Leaving it out of a batch that really did follow a
        // publish is the more costly of the two mistakes.
        var queue = new FolderProblemQueue();
        queue.Note(new[] { Finding("mediaFolderMissing") }, cameFromPublishing: true);
        queue.Note(new[] { Finding("noGradedFolders") }, cameFromPublishing: false);

        Assert.True(queue.TakeNext()!.Value.CameFromPublishing);
    }

    [Fact]
    public void AnOrdinaryBuildsBatchIsNotClaimedToHaveFollowedAPublish()
    {
        var queue = new FolderProblemQueue();
        queue.Note(new[] { Finding("mediaFolderMissing") }, cameFromPublishing: false);
        Assert.False(queue.TakeNext()!.Value.CameFromPublishing);
    }

    [Fact]
    public void TheOccasionResetsWithTheBatchItBelongedTo()
    {
        var queue = new FolderProblemQueue();
        queue.Note(new[] { Finding("mediaFolderMissing") }, cameFromPublishing: true);
        queue.TakeNext();

        queue.Note(new[] { Finding("noGradedFolders") }, cameFromPublishing: false);
        Assert.False(queue.TakeNext()!.Value.CameFromPublishing);
    }

    // ---- The title -------------------------------------------------------

    [Fact]
    public void OneProblemNamesItself()
    {
        var finding = Finding("mediaFolderMissing") with
        {
            Sentence = "The Media folder for ICS3U is not there.",
        };
        Assert.Equal("The Media folder for ICS3U is not there.",
                     FolderProblemQueue.Title(new[] { finding }));
    }

    [Fact]
    public void SeveralAreCountedRatherThanListed()
    {
        // A title carrying three sentences is not a title.
        Assert.Equal("3 things need your attention", FolderProblemQueue.Title(new[]
        {
            Finding("mediaFolderMissing"),
            Finding("sectionIndexMissing"),
            Finding("noGradedFolders"),
        }));
    }

    [Fact]
    public void NoProblemsHaveNoTitleRatherThanZeroThings()
    {
        // Reachable only while a dialog is being torn down. "0 things need your
        // attention" is the unreachable-by-design string made reachable, which
        // the mac's own view met twice.
        Assert.Equal("", FolderProblemQueue.Title(System.Array.Empty<SiteHealthFinding>()));
    }
}
