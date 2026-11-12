namespace Plantoir.Core.Models;

/// <summary>
/// One section of one course in one working folder — the key a section's
/// app-lifetime state is filed under (#728, the mac's <c>SectionRuns</c> key:
/// canonical folder, lowercased course, section).
/// </summary>
/// <remarks>
/// <para><b>Made canonical when it is BUILT</b>, so two spellings of one folder
/// are one key: the folder through <see cref="WorkingFolder.Resolved"/> and
/// compared case-insensitively — the app's single notion of "the same working
/// folder" (#162) — and the course code case-insensitively. A key built from
/// <c>C:\Work\</c> and one from <c>c:\work</c> find the same entry, which is
/// what lets a second window on the same folder see the same deploy.</para>
///
/// <para>Deliberately separate from the deploy it is used for first: a
/// section's Problems store (#734) is keyed the same way.</para>
/// </remarks>
public readonly struct SectionKey : IEquatable<SectionKey>
{
    private SectionKey(string folder, string course, int section)
    {
        Folder = folder;
        Course = course;
        Section = section;
    }

    /// <summary>The folder as <see cref="WorkingFolder.Resolved"/> spells it.</summary>
    public string Folder { get; }
    public string Course { get; }
    public int Section { get; }

    public static SectionKey For(string? folder, string course, int section) =>
        new(WorkingFolder.Resolved(folder ?? ""), course ?? "", section);

    public bool Equals(SectionKey other) =>
        Section == other.Section
        && string.Equals(Folder, other.Folder, StringComparison.OrdinalIgnoreCase)
        && string.Equals(Course, other.Course, StringComparison.OrdinalIgnoreCase);

    public override bool Equals(object? obj) => obj is SectionKey other && Equals(other);

    public override int GetHashCode() => HashCode.Combine(
        StringComparer.OrdinalIgnoreCase.GetHashCode(Folder ?? ""),
        StringComparer.OrdinalIgnoreCase.GetHashCode(Course ?? ""),
        Section);

    public static bool operator ==(SectionKey left, SectionKey right) => left.Equals(right);
    public static bool operator !=(SectionKey left, SectionKey right) => !left.Equals(right);

    public override string ToString() => $"{Course}/{Section} in {Folder}";
}

/// <summary>
/// App-lifetime state, one entry per <see cref="SectionKey"/>, created on
/// first ask and NEVER replaced or removed: work that is running holds its
/// entry, and a reader that found a new object would watch something nothing
/// writes (the mac's reason, #706). Thread-safe; what an entry does with
/// threads is the entry's business.
/// </summary>
public sealed class PerSectionStore<T> where T : class
{
    private readonly Dictionary<SectionKey, T> _entries = new();
    private readonly object _gate = new();

    /// <summary>The entry for <paramref name="key"/>, made by <paramref name="make"/> the first time.</summary>
    public T GetOrCreate(SectionKey key, Func<SectionKey, T> make)
    {
        lock (_gate)
        {
            if (_entries.TryGetValue(key, out var found)) return found;
            var made = make(key);
            _entries[key] = made;
            return made;
        }
    }

    /// <summary>The entry, or null — never creates one.</summary>
    public T? Find(SectionKey key)
    {
        lock (_gate) return _entries.TryGetValue(key, out var found) ? found : null;
    }

    /// <summary>For tests only: forget every entry.</summary>
    internal void Reset()
    {
        lock (_gate) _entries.Clear();
    }
}
