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
        if (cameFromPublishing) _pendingCameFromPublishing = true;
        return anythingNew;
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
