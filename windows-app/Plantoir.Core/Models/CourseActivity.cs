namespace Plantoir.Core.Models;

/// <summary>
/// The cross-window answer to "is this course busy right now?" — previews
/// via PreviewLeases (held for the preview's whole life), publishes via the
/// begin/end records here. Adding a section re-runs the course setup, which
/// rewrites the course's folders and files while a preview or publish may be
/// mid-copy of those very files; the Add Section entry points decline while
/// their course is busy anywhere. Mirrors the mac app's CourseActivity
/// (row 104). The same code in a different working folder is a different
/// course, so every question carries the folder path.
/// </summary>
public static class CourseActivity
{
    private sealed record PublishRecord(string FolderPath, string CourseCode, int SectionNumber);

    private static readonly List<PublishRecord> _publishes = new();
    private static readonly object _gate = new();

    /// <summary>
    /// Record a publish for its whole life: dispose the token on EVERY exit
    /// path (success, failure, a build that never reached publishing).
    /// Disposing twice is harmless.
    /// </summary>
    public static IDisposable BeginPublish(string folderPath, string courseCode, int sectionNumber)
    {
        var record = new PublishRecord(folderPath, courseCode, sectionNumber);
        lock (_gate) _publishes.Add(record);
        return new PublishToken(record);
    }

    private sealed class PublishToken(PublishRecord record) : IDisposable
    {
        private PublishRecord? _record = record;
        public void Dispose()
        {
            if (_record is null) return;
            lock (_gate) _publishes.Remove(_record);
            _record = null;
        }
    }

    // ---- Preview BUILDS, for the quit question (#231, mac #232) ------------

    private static readonly List<PublishRecord> _previewBuilds = new();

    /// <summary>
    /// Record a preview being BUILT — from the press until its page first
    /// answers, or the run ends. Not the port lease: that is held for as long
    /// as the preview is OPEN, and an open preview is not work that can be lost.
    /// A publish's own build is not recorded here; the publish already is.
    /// </summary>
    public static IDisposable BeginPreviewBuild(string folderPath, string courseCode, int sectionNumber)
    {
        var record = new PublishRecord(folderPath, courseCode, sectionNumber);
        lock (_gate) _previewBuilds.Add(record);
        return new Token(() => { lock (_gate) _previewBuilds.Remove(record); });
    }

    private sealed class Token(Action end) : IDisposable
    {
        private Action? _end = end;
        public void Dispose() { _end?.Invoke(); _end = null; }
    }

    /// <summary>What this app has under way right now, for the quit question.</summary>
    public static QuitConfirmation.UnderWay UnderWay()
    {
        lock (_gate)
            return new QuitConfirmation.UnderWay(_publishes.Count, PreviewLeases.Active.Count(), _previewBuilds.Count, 0);
    }

    public static bool IsPreviewing(string folderPath, string courseCode) =>
        PreviewLeases.Active.Any(l => l.FolderPath == folderPath && l.CourseCode == courseCode);

    public static bool IsPublishing(string folderPath, string courseCode)
    {
        lock (_gate) return _publishes.Any(p => p.FolderPath == folderPath && p.CourseCode == courseCode);
    }

    /// <summary>
    /// Whether THIS copy of the app is deploying exactly this section — the
    /// window's own Deploy or another window's (#386 / mac #381,
    /// <c>shared-rules.json → previewWhileItsSectionDeploys</c>, layer
    /// <c>window</c>). The SECTION, not the course: section 1 may still be
    /// previewed while section 2 deploys from the same app. Another program's
    /// deploy is the work leases' to refuse, course-wide.
    /// </summary>
    public static bool IsPublishingSection(string folderPath, string courseCode, int sectionNumber)
    {
        lock (_gate)
            return _publishes.Any(p => p.FolderPath == folderPath && p.CourseCode == courseCode &&
                                       p.SectionNumber == sectionNumber);
    }

    /// <summary>
    /// True when an assistant is working on this course in another process.
    /// Unlike previews and publishes this is read from disk, because the MCP
    /// server has its own memory and neither side can see the other's.
    /// </summary>
    public static bool IsAssisting(string folderPath, string courseCode) =>
        Assist.WorkLease.IsHeld(folderPath, courseCode, Assist.WorkLease.Assisting);

    /// <summary>
    /// Another process is running a build of this course right now.
    ///
    /// The question Preview and Deploy ask before starting. Note what it does
    /// NOT ask: whether a conversation is open. A teacher previewing a section
    /// while asking the assistant to change it is the intended way to use both,
    /// and only the few seconds of an actual build are exclusive.
    /// </summary>
    public static bool IsBuildingElsewhere(string folderPath, string courseCode) =>
        Assist.WorkLease.IsHeld(folderPath, courseCode, Assist.WorkLease.Building);

    /// <summary>
    /// The short line naming what stands in the way of structural work on
    /// this course, or null when it is free.
    /// </summary>
    public static string? BusyReason(string folderPath, string courseCode)
    {
        bool previewing = IsPreviewing(folderPath, courseCode);
        bool publishing = IsPublishing(folderPath, courseCode);
        if (previewing && publishing) return "Available once preview and deploy complete";
        if (previewing) return "Available once preview completed";
        if (publishing) return "Available once deploy completed";
        // Said in the app's voice, naming the thing the teacher started rather
        // than the process that holds the lease — and since #468 naming WHICH
        // thing: an outside session, or this app's own assistant window.
        return ReviseHoldReason(folderPath, courseCode);
    }

    // ---- Who holds a course's assist lease (#468, mac #458) ---------------

    /// <summary>
    /// True when a Claude or Codex session — an outside <c>plantoir-mcp</c>,
    /// not one of this app's window servers (<see cref="Assist.WindowServers"/>)
    /// — holds a live assist lease on the course. The mac's
    /// <c>isRevisedElsewhere</c>.
    /// </summary>
    public static bool IsRevisedElsewhere(string folderPath, string courseCode) =>
        AssistLeases(folderPath, courseCode).Any(pid => Assist.WindowServers.Find(pid) is null);

    /// <summary>This app's assistant window holding the course through its own server, or null.</summary>
    public static Assist.WindowServers.Entry? WindowRevising(string folderPath, string courseCode) =>
        AssistLeases(folderPath, courseCode).Select(Assist.WindowServers.Find).FirstOrDefault(entry => entry is not null);

    private static IEnumerable<int> AssistLeases(string folderPath, string courseCode) =>
        Assist.WorkLease.LiveLeasesOfOthers(folderPath)
            .Where(lease => lease.Kind == Assist.WorkLease.Assisting
                            && string.Equals(lease.Course, courseCode, StringComparison.OrdinalIgnoreCase))
            .Select(lease => lease.Pid);

    /// <summary>
    /// The sentence under a greyed item while an assistant holds the course,
    /// or null: an outside session first (the teacher may not have it in
    /// front of them), else this app's own window — whose hold stays, only in
    /// its own words.
    /// </summary>
    public static string? ReviseHoldReason(string folderPath, string courseCode)
    {
        if (IsRevisedElsewhere(folderPath, courseCode)) return Assist.AssistWording.AvailableOnceYouFinishRevisingWithClaude;
        if (WindowRevising(folderPath, courseCode) is { } window)
            return Assist.WindowHoldWording.AvailableOnceTheAssistantCloses(window.CourseCode, window.SectionNumber);
        return null;
    }

    /// <summary>The three Revise items on a course (<c>doorCourseHold.reviseCases</c> → <c>item</c>).</summary>
    public enum ReviseItem { Claude, Codex, Local }

    /// <summary>
    /// The pure rule of <c>doorCourseHold.reviseCases</c> on Windows: an
    /// outside session greys ALL THREE items with
    /// <see cref="Assist.AssistWording.AvailableOnceYouFinishRevisingWithClaude"/>.
    /// The mac's <c>reviseUnavailableReason</c> minus its <c>active</c> half,
    /// which describes the mac's lease-less, one-at-a-time window; Windows'
    /// window holds a lease of its own and is answered by
    /// <see cref="ReviseHoldReason"/>.
    /// </summary>
    public static string? ReviseUnavailableReason(ReviseItem item, bool revisedElsewhere) =>
        revisedElsewhere ? Assist.AssistWording.AvailableOnceYouFinishRevisingWithClaude : null;

    /// <summary>The structural work an assist lease holds (<c>doorCourseHold.holds.structuralWork</c>).</summary>
    public enum StructuralWork { Rename, Restore, AddSection }

    /// <summary>
    /// The refusal for structural work held ONLY by an assistant (not by a
    /// preview or deploy, which keep their own sentences), or null: the
    /// contract's <c>claudeIsRevisingTheCourse*</c> for an outside session,
    /// the window's own words for this app's window. The mac's
    /// <c>structuralHoldReason</c>.
    /// </summary>
    public static string? AssistHoldRefusal(string folderPath, string courseCode, StructuralWork work)
    {
        if (IsRevisedElsewhere(folderPath, courseCode))
            return work switch
            {
                StructuralWork.Rename => Assist.AssistWording.ClaudeIsRevisingTheCourseRename(courseCode),
                StructuralWork.Restore => Assist.AssistWording.ClaudeIsRevisingTheCourseRestore(courseCode),
                _ => Assist.AssistWording.ClaudeIsRevisingTheCourseAddSection(courseCode),
            };
        if (WindowRevising(folderPath, courseCode) is { } window)
            return work switch
            {
                StructuralWork.Rename => Assist.WindowHoldWording.CloseTheAssistantThenRename(window.CourseCode, window.SectionNumber),
                StructuralWork.Restore => Assist.WindowHoldWording.CloseTheAssistantThenRestore(window.CourseCode, window.SectionNumber),
                _ => Assist.WindowHoldWording.CloseTheAssistantThenAddSection(window.CourseCode, window.SectionNumber),
            };
        return null;
    }

    /// <summary>A preview or a deploy of the course is running in this app — the half of <see cref="BusyReason"/> that is not an assistant.</summary>
    public static bool IsPreviewingOrPublishing(string folderPath, string courseCode) =>
        IsPreviewing(folderPath, courseCode) || IsPublishing(folderPath, courseCode);

    public static void Reset()
    {
        lock (_gate) { _publishes.Clear(); _previewBuilds.Clear(); }
        PreviewLeases.Reset();
    }
}
