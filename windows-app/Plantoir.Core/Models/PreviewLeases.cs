namespace Plantoir.Core.Models;

/// <summary>
/// Hands out preview ports across every window. The four ports are the
/// CONTAINER-side ports; the launcher maps them into a probed host block,
/// so the app never assumes the host port — it parses the announced address.
/// </summary>
public static class PreviewLeases
{
    public static readonly IReadOnlyList<int> AvailablePorts = new[] { 8081, 8082, 8083, 8084 };

    public sealed record Lease(int Port, string FolderPath, string CourseCode, int SectionNumber);

    public sealed class LeaseRefusedException(string message) : Exception(message);

    private static readonly List<Lease> _active = new();
    private static readonly object _gate = new();

    public static IReadOnlyList<Lease> Active { get { lock (_gate) return _active.ToList(); } }

    public static Lease Take(string folderPath, string courseCode, int sectionNumber)
    {
        lock (_gate)
        {
            // Two builds of one section would race over the same output
            // folder — but the same section in a DIFFERENT folder is the
            // compare-two-years case, and is allowed.
            if (_active.Any(l => l.FolderPath == folderPath &&
                                 l.CourseCode == courseCode &&
                                 l.SectionNumber == sectionNumber))
                throw new LeaseRefusedException(
                    $"Section {sectionNumber} of {courseCode} is already being previewed in another window. Stop that preview first, or work with it there.");

            // Ports are per-container, one container per folder — only
            // same-folder previews contend.
            var taken = _active.Where(l => l.FolderPath == folderPath).Select(l => l.Port).ToHashSet();
            foreach (int port in AvailablePorts)
            {
                if (taken.Contains(port)) continue;
                var lease = new Lease(port, folderPath, courseCode, sectionNumber);
                _active.Add(lease);
                return lease;
            }
            throw new LeaseRefusedException(
                "Four previews of this folder are already running, which is the most that can run at once. Stop one, then try again.");
        }
    }

    public static void Release(Lease lease)
    {
        lock (_gate) _active.Remove(lease);
    }

    public static void Release(string folderPath, string courseCode, int sectionNumber)
    {
        lock (_gate)
        {
            _active.RemoveAll(l => l.FolderPath == folderPath &&
                                  string.Equals(l.CourseCode, courseCode, StringComparison.OrdinalIgnoreCase) &&
                                  l.SectionNumber == sectionNumber);
        }
    }

    public static void Reset()
    {
        lock (_gate) _active.Clear();
    }
}
