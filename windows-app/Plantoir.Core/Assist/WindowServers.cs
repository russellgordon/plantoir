namespace Plantoir.Core.Assist;

/// <summary>
/// The <c>plantoir-mcp</c> processes THIS app started for its own assistant
/// windows, by process id, with the course and section each one serves (#468).
/// </summary>
/// <remarks>
/// <para><b>Why the app needs to know which servers are its own.</b> Windows'
/// assistant window runs its own <c>plantoir-mcp</c>, locked to its course,
/// and that server takes the same <c>assist</c> lease a Claude or Codex
/// session's server takes (<see cref="WorkLease.Assisting"/>). The lease is
/// what greys the doors, refuses a second window on the course and holds
/// Rename Course, Add Section and restore — and all of that STAYS for the
/// window (Windows has no one-window rule: two conversations on one course
/// would write the same pages). What changes with #468 is only the SENTENCE:
/// "a Claude or Codex session" said about the teacher's own assistant window
/// names the wrong cause. A lease whose process id is registered here is the
/// window's; any other live assist lease is an outside session's.</para>
///
/// <para><b>Rejected: <see cref="AssistActivity"/>.</b> It is claimed when the
/// window OPENS, before its server starts, and released when it closes, while
/// the server can outlive the window by up to three seconds (McpClient's
/// dispose waits for it) — both ends would read the window's lease as an
/// outside session's for a moment. It also cannot tell the window's lease
/// from an outside session's when both hold one course. The registry is keyed
/// on the very process that holds the lease, so neither gap exists (stack-2
/// plan review, H1).</para>
///
/// <para><b>Known limit.</b> In-process: a SECOND Plantoir's window is not in
/// this one's registry, so its lease reads here as a Claude or Codex session.
/// The hold is right either way; only the sentence names the wrong cause.</para>
/// </remarks>
public static class WindowServers
{
    /// <summary>One of this app's window servers: its process, and the course and section its window is on.</summary>
    public sealed record Entry(int Pid, string CourseCode, int SectionNumber);

    private static readonly object s_gate = new();
    private static readonly Dictionary<int, Entry> s_entries = new();

    /// <summary>
    /// Record a server this app started for a window. Disposing the result
    /// forgets it — the caller does so only once the server has EXITED, so its
    /// lease is never read as an outside session's while it is still alive.
    /// </summary>
    public static IDisposable Register(int pid, string courseCode, int sectionNumber)
    {
        var entry = new Entry(pid, courseCode, sectionNumber);
        lock (s_gate) s_entries[pid] = entry;
        return new Registration(entry);
    }

    /// <summary>The window server with this process id, or null when it is not one of this app's.</summary>
    public static Entry? Find(int pid)
    {
        lock (s_gate) return s_entries.TryGetValue(pid, out var entry) ? entry : null;
    }

    /// <summary>For tests: forget every registration.</summary>
    internal static void Reset()
    {
        lock (s_gate) s_entries.Clear();
    }

    private sealed class Registration : IDisposable
    {
        private Entry? _entry;
        public Registration(Entry entry) => _entry = entry;

        public void Dispose()
        {
            lock (s_gate)
            {
                if (_entry is null) return;
                // Only if it is still THIS registration: a recycled id may have
                // been registered again since.
                if (s_entries.TryGetValue(_entry.Pid, out var now) && ReferenceEquals(now, _entry))
                    s_entries.Remove(_entry.Pid);
                _entry = null;
            }
        }
    }
}

/// <summary>
/// The sentences for a hold whose cause is THIS app's own assistant window
/// (#468). Windows' own: the mac's window takes no lease, so the contract has
/// no keys for them (<c>shared-rules.json → doorCourseHold.reviseCases</c>,
/// the <c>onWindows</c> notes leave this to Windows). Shaped like the
/// sentence the app already says about an open window — "Close the assistant
/// for {course} Section {section} first" (AssistModelStore, the backup list).
/// Kept off <see cref="AssistWording"/> on purpose: every member there must
/// name a contract key.
/// </summary>
public static class WindowHoldWording
{
    /// <summary>Under a greyed menu item while the window is open on the course.</summary>
    public static string AvailableOnceTheAssistantCloses(string course, int section) =>
        $"Available once you close the assistant for {course} Section {section}";

    /// <summary>Rename Course, refused while the window is open on the course.</summary>
    public static string CloseTheAssistantThenRename(string course, int section) =>
        $"Close the assistant for {course} Section {section} first, then rename.";

    /// <summary>Restoring a backup, refused while the window is open on the course.</summary>
    public static string CloseTheAssistantThenRestore(string course, int section) =>
        $"Close the assistant for {course} Section {section} first, then restore.";

    /// <summary>Add Section, refused while the window is open on the course.</summary>
    public static string CloseTheAssistantThenAddSection(string course, int section) =>
        $"Close the assistant for {course} Section {section} first, then add the section.";

    /// <summary>A door or a second window, refused at the click while the window is open on the course.</summary>
    public const string FinishInThatWindowFirst =
        "There is an assistant working on this course already. Finish in that window, close it, then start again here.";
}
