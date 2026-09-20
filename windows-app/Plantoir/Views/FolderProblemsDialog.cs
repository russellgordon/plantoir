using System.Collections.Generic;
using Microsoft.UI.Text;
using Microsoft.UI.Xaml;
using Microsoft.UI.Xaml.Controls;
using Plantoir.Core.Models;

namespace Plantoir.Views;

/// <summary>
/// What a teacher reads when a build found something wrong with their course's
/// folders, and what they read after pressing the button that puts it right.
///
/// <para><b>The sentences are not this file's to write.</b> Each finding
/// carries its own <c>Sentence</c> and <c>Detail</c> in the
/// <c>PLANTOIR_HEALTH:</c> line the build printed — that is the whole reason
/// the wording travels in the payload, so that the same problem cannot be
/// worded differently on the two platforms. Nothing here composes a sentence
/// from a check's <c>Name</c>. What this file DOES choose is the chrome: the
/// title when there is more than one problem, and the button labels, which come
/// from <see cref="SiteHealthRepair"/>.</para>
///
/// <para>The pair of dialogs, and the order they appear in, are pinned by
/// <c>contracts/shared-rules.json</c> -&gt; <c>siteHealth.repair</c>.</para>
/// </summary>
public static class FolderProblemsDialog
{
    /// <summary>
    /// The findings themselves.
    ///
    /// <para>One problem names itself in the title; several are counted,
    /// because a title listing three sentences is not a title. The repair
    /// button appears only when this app can really put something right —
    /// <see cref="SiteHealthRepair.ButtonTitle"/> decides, from the check's
    /// NAME, and returns null for the four that are never offered.</para>
    /// </summary>
    public static ContentDialog Findings(IReadOnlyList<SiteHealthFinding> findings)
    {
        var dialog = new ContentDialog
        {
            Title = Title(findings),
            Content = Body(findings),
            CloseButtonText = "OK",
        };
        if (SiteHealthRepair.ButtonTitle(findings) is { } repairLabel)
        {
            dialog.PrimaryButtonText = repairLabel;
            dialog.DefaultButton = ContentDialogButton.Primary;
        }
        return dialog;
    }

    /// <summary>
    /// What the repair did — including when it failed, which is the case that
    /// made this dialog necessary rather than optional.
    ///
    /// <para>"Preview Again" appears only when
    /// <see cref="SiteHealthRepair.Outcome.CanRebuild"/> says so: not when
    /// nothing needed repairing, not when a repair failed, and not when a
    /// publish is running just now. Naming a button that is not on screen would
    /// be worse than saying nothing, so the sentences for those cases never
    /// mention one.</para>
    /// </summary>
    public static ContentDialog RepairOutcome(SiteHealthRepair.Outcome outcome)
    {
        var dialog = new ContentDialog
        {
            Title = outcome.Headline,
            Content = Paragraph(outcome.Detail),
            CloseButtonText = "OK",
        };
        if (outcome.CanRebuild)
        {
            dialog.PrimaryButtonText = "Preview Again";
            dialog.DefaultButton = ContentDialogButton.Primary;
        }
        return dialog;
    }

    // ---- The words around the findings -----------------------------------

    /// <summary>
    /// The title lives in <see cref="FolderProblemQueue"/>, with the rest of
    /// this feature's judgement, because the test project cannot reach a WinUI
    /// project and a sentence a teacher reads deserves a test.
    /// </summary>
    private static string Title(IReadOnlyList<SiteHealthFinding> findings) =>
        FolderProblemQueue.Title(findings);

    private static UIElement Body(IReadOnlyList<SiteHealthFinding> findings)
    {
        var stack = new StackPanel { Spacing = 12 };
        foreach (var finding in findings)
        {
            // With one finding the sentence is already the title, so repeating
            // it here would have the teacher read it twice.
            if (findings.Count > 1)
                stack.Children.Add(Paragraph(finding.Sentence, bold: true));
            stack.Children.Add(Paragraph(finding.Detail));
        }
        return stack;
    }

    private static TextBlock Paragraph(string text, bool bold = false) => new()
    {
        Text = text,
        TextWrapping = TextWrapping.Wrap,
        FontWeight = bold ? FontWeights.SemiBold : FontWeights.Normal,
        // A ContentDialog sizes to its content, and an unbounded paragraph
        // makes one as wide as the window. Matches the width NewCourseDialog
        // settles on for the same reason.
        MaxWidth = 460,
    };
}
