using System;
using System.Collections.Generic;

namespace Plantoir.Core.Models;

/// <summary>
/// Which folder problems are waiting to be shown, which have already been
/// shown, and what the teacher reads at the top of the dialog.
///
/// <para>Separate from the view because this is where the judgement is, and a
/// WinUI view cannot be tested here. The view owns one of these and does
/// nothing but present what it hands over.</para>
/// </summary>
public sealed class FolderProblemQueue
{
    private readonly List<SiteHealthFinding> _pending = new();
    private readonly HashSet<string> _pendingIdentities = new(StringComparer.Ordinal);
    private readonly HashSet<string> _shown = new(StringComparer.Ordinal);
    private bool _pendingCameFromPublishing;

    /// <summary>What is waiting, if anything.</summary>
    public int PendingCount => _pending.Count;

    /// <summary>
    /// Take note of what a run reported.
    ///
    /// <para>Returns whether any of it was NEW. A build announces its findings
    /// one at a time, so the same run reports the first finding again alongside
    /// the second — and a healthy course reports nothing at all, which must
    /// stay nothing rather than becoming an empty dialog.</para>
    /// </summary>
    public bool Note(IReadOnlyList<SiteHealthFinding> findings, bool cameFromPublishing)
    {
        bool anythingNew = false;
        foreach (var finding in findings)
        {
            if (_shown.Contains(finding.Identity)) continue;
            if (!_pendingIdentities.Add(finding.Identity)) continue;
            _pending.Add(finding);
            anythingNew = true;
        }
        // SET rather than replaced when batches mix, which they can if a deploy
        // reports while a preview's findings are still waiting: the publish
        // sentence is the one naming who has not seen the change yet
        // (students), and leaving that out of a batch that really did follow a
        // publish is the more costly of the two mistakes.
        //
        // Guarded on the batch being NON-EMPTY, and NOT on it being new — a
        // distinction worth the sentence, because the obvious guard is the
        // wrong one. The bug is the EMPTY batch: a deploy reports its findings
        // unconditionally, so a healthy course, or one whose deploy skipped
        // the build, hands over nothing at all, and setting the flag there
        // labelled the next unrelated build's findings as a publish. Guarding
        // on "new" would fix that and break the rule above, because a publish
        // that repeats a finding still waiting to be shown really did happen.
        if (cameFromPublishing && findings.Count > 0) _pendingCameFromPublishing = true;
        return anythingNew;
    }

    /// <summary>
    /// Forget what has been shown, because a new run is starting.
    ///
    /// <para>"Show it once" means once per BUILD, not once per section view.
    /// A teacher who dismissed a warning, went to Obsidian, and previewed
    /// again has asked a fresh question and deserves a fresh answer — and the
    /// case that matters most is the one after that: preview reports a missing
    /// Media folder, the teacher publishes anyway, and the publish's identical
    /// finding is the one carrying the sentence about what students can see.
    /// Suppressing it as "already shown" loses precisely the sentence the
    /// occasion exists for.</para>
    ///
    /// <para>What it does NOT forget is anything still waiting: a dialog that
    /// has not been read yet is not stale.</para>
    /// </summary>
    public void ForgetShown() => _shown.Clear();

    /// <summary>
    /// Hand a batch back, because it could not be shown after all.
    ///
    /// <para><see cref="TakeNext"/> marks a batch shown as it hands it over,
    /// which is right while a dialog is going up — but a dialog that never
    /// appeared has told nobody anything, and leaving it marked would drop the
    /// findings for good with only a log line behind them.</para>
    /// </summary>
    public void PutBack(IReadOnlyList<SiteHealthFinding> findings, bool cameFromPublishing)
    {
        foreach (var finding in findings) _shown.Remove(finding.Identity);
        Note(findings, cameFromPublishing);
    }

    /// <summary>
    /// Everything waiting, marked as shown, or null when nothing is.
    ///
    /// <para>Marked at the moment it is handed over rather than when the dialog
    /// closes: findings that arrive while it is on screen must be held for
    /// afterwards, not merged into what the teacher is already reading — the
    /// title and message would change under their cursor.</para>
    /// </summary>
    public (IReadOnlyList<SiteHealthFinding> Findings, bool CameFromPublishing)? TakeNext()
    {
        if (_pending.Count == 0) return null;
        var findings = _pending.ToArray();
        bool cameFromPublishing = _pendingCameFromPublishing;
        _pending.Clear();
        _pendingIdentities.Clear();
        _pendingCameFromPublishing = false;
        foreach (var finding in findings) _shown.Add(finding.Identity);
        return (findings, cameFromPublishing);
    }

    /// <summary>
    /// The title of the folder-problem dialog.
    ///
    /// <para>Plain, and never the machinery: a teacher is told what is wrong
    /// with THEIR course, not that a check failed. One problem names itself;
    /// several are counted, because a title listing three sentences is not a
    /// title.</para>
    /// </summary>
    public static string Title(IReadOnlyList<SiteHealthFinding> findings)
    {
        if (findings.Count == 1) return findings[0].Sentence;
        if (findings.Count == 0) return "";
        return $"{findings.Count} things need your attention";
    }
}
