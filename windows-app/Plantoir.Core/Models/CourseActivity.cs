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
        // than the process that holds the lease.
        if (IsAssisting(folderPath, courseCode)) return "Available once you finish revising with Claude";
        return null;
    }

    public static void Reset()
    {
        lock (_gate) { _publishes.Clear(); _previewBuilds.Clear(); }
        PreviewLeases.Reset();
    }
}
