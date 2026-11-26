namespace Plantoir.Core.Models;

/// <summary>
/// Hands out preview ports across every window. The four ports are the
/// CONTAINER-side ports; the launcher maps them into a probed host block,
/// so the app never assumes the host port — it parses the announced address.
/// </summary>
public static class PreviewLeases
{
    public static readonly IReadOnlyList<int> AvailablePorts = new[] { 8081, 8082, 8083, 8084 };

    /// <summary>
    /// One start's hold on a port. <paramref name="Owner"/> is the window that
    /// took it (#928 item 4): a sweep for rows left behind takes only its own
    /// window's, never another window's preview of the same section.
    /// </summary>
    public sealed record Lease(int Port, string FolderPath, string CourseCode, int SectionNumber, object? Owner = null);

    public sealed class LeaseRefusedException(string message) : Exception(message);

    private static readonly List<Lease> _active = new();
    private static readonly object _gate = new();

    public static IReadOnlyList<Lease> Active { get { lock (_gate) return _active.ToList(); } }

    public static Lease Take(string folderPath, string courseCode, int sectionNumber, object? owner = null)
    {
        lock (_gate)
        {
            // Two builds of one section would race over the same output
            // folder — but the same section in a DIFFERENT folder is the
            // compare-two-years case, and is allowed. One folder however it is
            // spelled is one folder (#769): the lease keeps the spelling it was
            // given, only the comparisons fold it.
            if (_active.Any(l => WorkingFolder.IsTheSame(l.FolderPath, folderPath) &&
                                 l.CourseCode == courseCode &&
                                 l.SectionNumber == sectionNumber))
                throw new LeaseRefusedException(
                    $"Section {sectionNumber} of {courseCode} is already being previewed in another window. Stop that preview first, or work with it there.");

            // Ports are per-container, one container per folder — only
            // same-folder previews contend.
            var taken = _active.Where(l => WorkingFolder.IsTheSame(l.FolderPath, folderPath)).Select(l => l.Port).ToHashSet();
            foreach (int port in AvailablePorts)
            {
                if (taken.Contains(port)) continue;
                var lease = new Lease(port, folderPath, courseCode, sectionNumber, owner);
                _active.Add(lease);
                return lease;
            }
            throw new LeaseRefusedException(
                "Four previews of this folder are already running, which is the most that can run at once. Stop one, then try again.");
        }
    }

    /// <summary>
    /// Give back exactly this lease, the one its start took (#928 item 4):
    /// compared by reference, so a start that has already let go never
    /// removes a later lease that happens to be equal in every field (the
    /// same window, section and port, taken again).
    /// </summary>
    public static void Release(Lease lease)
    {
        lock (_gate)
        {
            int at = _active.FindIndex(held => ReferenceEquals(held, lease));
            if (at >= 0) _active.RemoveAt(at);
        }
    }

    /// <summary>
    /// The rows for this section that <paramref name="owner"/>'s window left
    /// behind (a replaced view's), and only those: another window's lease of
    /// the same section is that window's preview, still running (#928 item 4).
    /// </summary>
    public static void ReleaseLeftBehind(object owner, string folderPath, string courseCode, int sectionNumber)
    {
        lock (_gate)
        {
            _active.RemoveAll(l => ReferenceEquals(l.Owner, owner) &&
                                  WorkingFolder.IsTheSame(l.FolderPath, folderPath) &&
                                  string.Equals(l.CourseCode, courseCode, StringComparison.OrdinalIgnoreCase) &&
                                  l.SectionNumber == sectionNumber);
        }
    }

    /// <summary>
    /// Every row <paramref name="owner"/>'s window still holds, of any section
    /// (#928 review 2, L10): read as that window closes, so a row a replaced
    /// view left behind goes with its window instead of being stranded until
    /// relaunch. Each is then released by reference (<see cref="Release(Lease)"/>).
    /// </summary>
    public static IReadOnlyList<Lease> HeldBy(object owner)
    {
        lock (_gate) return _active.Where(l => ReferenceEquals(l.Owner, owner)).ToList();
    }

    public static void Release(string folderPath, string courseCode, int sectionNumber)
    {
        lock (_gate)
        {
            _active.RemoveAll(l => WorkingFolder.IsTheSame(l.FolderPath, folderPath) &&
                                  string.Equals(l.CourseCode, courseCode, StringComparison.OrdinalIgnoreCase) &&
                                  l.SectionNumber == sectionNumber);
        }
    }

    public static void Reset()
    {
        lock (_gate) _active.Clear();
    }
}
