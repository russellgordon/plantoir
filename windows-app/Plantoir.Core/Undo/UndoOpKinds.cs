using System.Runtime.InteropServices;
using System.Security.Cryptography;
using System.Text;
using System.Text.Json;

namespace Plantoir.Core.Undo;

// The op kinds U2 defines, on Windows (#899 W6; the mac's UndoOpKinds.swift):
// what each one's content is, how it is checked against what is there now,
// and how it is moved one way or the other. The rule is
// contracts/file-formats.json → undoJournal.opKinds; the cases are
// shared-rules.json → undo.checkCases and listingCases, and undo-json-cases.json → editJSONCases.
// Content, never times (ruling 4).

// ---- replaceText ------------------------------------------------------------------

/// <summary>
/// A hunk of a page: the text it replaced and the text either side of it
/// (<c>opKinds.replaceText</c>). The BEFORE WINDOW is contextBefore + before +
/// contextAfter, the AFTER WINDOW contextBefore + after + contextAfter, both
/// compared as UTF-8 bytes (carriage returns and a byte-order mark kept). A
/// window is FOUND when it occurs exactly once in the file (overlapping
/// occurrences counted) and every occurrence of the other window lies inside
/// it. Never a guess: two places the hunk could go are a change since.
/// </summary>
internal static class UndoHunk
{
    private static byte[]? Window(UndoOp op, bool after)
    {
        if (op.ContextBefore is null || op.ContextAfter is null) return null;
        string? middle = after ? op.After : op.Before;
        if (middle is null) return null;
        return Encoding.UTF8.GetBytes(op.ContextBefore + middle + op.ContextAfter);
    }

    /// <summary>Every index the needle starts at, overlapping ones included.</summary>
    internal static List<int> Occurrences(byte[] needle, byte[] haystack)
    {
        var found = new List<int>();
        if (needle.Length == 0 || needle.Length > haystack.Length) return found;
        for (int start = 0; start + needle.Length <= haystack.Length; start++)
        {
            if (haystack.AsSpan(start, needle.Length).SequenceEqual(needle)) found.Add(start);
        }
        return found;
    }

    /// <summary>Where the window is found (see the type's rule), or null.</summary>
    internal static int? PlaceOf(byte[] window, byte[] other, byte[] bytes)
    {
        List<int> mine = Occurrences(window, bytes);
        if (mine.Count != 1) return null;
        int start = mine[0];
        int end = start + window.Length;
        foreach (int otherStart in Occurrences(other, bytes))
        {
            if (otherStart < start || otherStart + other.Length > end) return null;
        }
        return start;
    }

    internal static UndoOpState StateOf(UndoOp op, UndoCurrent current)
    {
        if (current is not UndoCurrent.Bytes bytes || UndoCheck.DecodeStrictly(bytes.Content) is null) return UndoOpState.Neither;
        if (Window(op, after: false) is not { } beforeWindow || Window(op, after: true) is not { } afterWindow) return UndoOpState.Neither;
        if (PlaceOf(beforeWindow, afterWindow, bytes.Content) is not null) return UndoOpState.Before;
        if (PlaceOf(afterWindow, beforeWindow, bytes.Content) is not null) return UndoOpState.After;
        return UndoOpState.Neither;
    }

    /// <summary>The file with the hunk moved one way (an undo towards before), or null when it cannot be found.</summary>
    internal static byte[]? Moved(UndoOp op, byte[] bytes, bool backward)
    {
        if (Window(op, after: false) is not { } beforeWindow || Window(op, after: true) is not { } afterWindow) return null;
        byte[] source = backward ? afterWindow : beforeWindow;
        byte[] target = backward ? beforeWindow : afterWindow;
        if (PlaceOf(source, target, bytes) is not { } start) return null;
        var result = new byte[bytes.Length - source.Length + target.Length];
        bytes.AsSpan(0, start).CopyTo(result);
        target.CopyTo(result.AsSpan(start));
        bytes.AsSpan(start + source.Length).CopyTo(result.AsSpan(start + target.Length));
        return result;
    }
}

// ---- editJSON ---------------------------------------------------------------------

/// <summary>
/// One member of a JSON file whose top level is an object, found by walking
/// <c>keyPath</c> (<c>opKinds.editJSON</c>). A member that is not there is
/// "absent", which is what an op with no <c>before</c> (or no <c>after</c>)
/// means. Moving it changes ONLY that member's bytes
/// (<see cref="UndoJsonBytes"/>); a result that does not read back as exactly
/// the file with that one member changed is refused (changed since).
/// </summary>
internal static class UndoJsonMember
{
    /// <summary>What the key path holds: nothing, a value, or something that cannot be read as the rule needs.</summary>
    internal readonly record struct Reading(bool Absent, UndoJson? Value, bool CannotTell)
    {
        internal static Reading Missing => new(true, null, false);
        internal static Reading Unknown => new(false, null, true);
        internal static Reading Holding(UndoJson value) => new(false, value, false);
    }

    private static readonly JsonDocumentOptions Strict = new()
    {
        AllowTrailingCommas = false,
        CommentHandling = JsonCommentHandling.Disallow,
        MaxDepth = 256,
    };

    /// <summary>
    /// The file's top-level object as a value, read as the mac's reader reads
    /// it, or null when the file is not UTF-8 or not one JSON object. A UTF-8
    /// byte-order mark at the very start is passed over, as Foundation's reader
    /// does (measured on the mac, 2026-11-20: a file starting with one is read,
    /// its member judged; one with a space before the mark is not JSON), so the
    /// verdict before a write is the mac's. The byte mover still refuses such a
    /// file (<see cref="UndoJsonBytes.Locate"/> starts at the first byte, as
    /// the mac's does), so a member is never moved in it: changed since, on
    /// both platforms. Its numbers are the doubles the mac reads
    /// (<see cref="UndoJson.ReadAsTheMacReads"/>).
    /// </summary>
    internal static UndoJson.Members? TopLevel(byte[] bytes)
    {
        if (UndoCheck.DecodeStrictly(bytes) is null) return null;
        ReadOnlyMemory<byte> json = bytes;
        if (bytes.Length >= 3 && bytes[0] == 0xEF && bytes[1] == 0xBB && bytes[2] == 0xBF) json = bytes.AsMemory(3);
        try
        {
            using JsonDocument document = JsonDocument.Parse(json, Strict);
            if (document.RootElement.ValueKind != JsonValueKind.Object) return null;
            return UndoJson.From(document.RootElement, asTheMacReadsAFile: true) as UndoJson.Members;
        }
        // Text holding half of a surrogate pair (\ud800) cannot be read as a
        // string here; the mac cannot read such a file either (measured
        // 2026-11-20): not JSON there, changed since, on both.
        catch (Exception error) when (error is JsonException or InvalidOperationException) { return null; }
    }

    /// <summary>
    /// Whether the key path, and every object it passes through, is one this
    /// app is measured to walk as the mac walks it (#899 W6 review 2): each
    /// part, and every key of each object on the way (the top level included),
    /// printable ASCII (<see cref="UndoJson.IsMeasuredKey"/>); and the file
    /// holding only numbers read as measured. The mac takes canonically
    /// equivalent keys for one, so a file's Kelvin sign is its <c>K</c>, and
    /// a key starting with a byte-order mark is that key without it: a member
    /// this app would call missing and add beside the one the mac finds.
    /// </summary>
    internal static bool PathIsMeasured(IReadOnlyList<string> keyPath, UndoJson tree)
    {
        if (!tree.HoldsOnlyMeasuredNumbers) return false;
        UndoJson current = tree;
        foreach (string part in keyPath)
        {
            if (!UndoJson.IsMeasuredKey(part)) return false;
            if (current is not UndoJson.Members members) return true;
            foreach (string key in members.Items.Keys)
            {
                if (!UndoJson.IsMeasuredKey(key)) return false;
            }
            if (!members.Items.TryGetValue(part, out UndoJson? next)) return true;
            current = next;
        }
        return true;
    }

    internal static Reading ReadingOf(IReadOnlyList<string> keyPath, byte[] bytes) =>
        TopLevel(bytes) is { } tree ? ReadingOf(keyPath, tree) : Reading.Unknown;

    internal static Reading ReadingOf(IReadOnlyList<string> keyPath, UndoJson tree)
    {
        UndoJson current = tree;
        foreach (string part in keyPath)
        {
            if (current is not UndoJson.Members members) return Reading.Unknown;
            if (!members.Items.TryGetValue(part, out UndoJson? next)) return Reading.Missing;
            current = next;
        }
        return Reading.Holding(current);
    }

    internal static UndoOpState StateOf(UndoOp op, UndoCurrent current)
    {
        if (current is not UndoCurrent.Bytes bytes || op.KeyPath is not { } keyPath) return UndoOpState.Neither;
        if (TopLevel(bytes.Content) is not { } tree) return UndoOpState.Neither;
        Reading found = ReadingOf(keyPath, tree);
        if (found.CannotTell) return UndoOpState.Neither;
        // What this app is not measured to read as the mac reads it (a key
        // beyond printable ASCII on the path or in a value, text starting with
        // a byte-order mark, a number spelled beyond the measured digits):
        // cannot tell, never a guess (#899 W6 review 2).
        if (!PathIsMeasured(keyPath, tree)) return UndoOpState.CannotTell;
        if (found.Value is { IsMeasured: false }) return UndoOpState.CannotTell;
        if (op.ValueBefore is { IsMeasured: false } || op.ValueAfter is { IsMeasured: false }) return UndoOpState.CannotTell;
        // A whole number beyond 2^53, in the file or in the record, cannot be
        // compared exactly through a double: cannot tell, never a guess.
        if (found.Value is { IsExact: false }) return UndoOpState.CannotTell;
        if (op.ValueBefore is { IsExact: false } || op.ValueAfter is { IsExact: false }) return UndoOpState.CannotTell;
        if (Matches(found, op.ValueBefore)) return UndoOpState.Before;
        if (Matches(found, op.ValueAfter)) return UndoOpState.After;
        return UndoOpState.Neither;
    }

    internal static bool Matches(Reading found, UndoJson? expected)
    {
        if (found.CannotTell) return false;
        if (found.Absent) return expected is null;
        return expected is not null && UndoJson.Same(found.Value, expected);
    }

    /// <summary>The tree with the member set (null value: taken out), or null when a part on the way is missing or not an object.</summary>
    internal static UndoJson? Setting(IReadOnlyList<string> keyPath, int depth, UndoJson? value, UndoJson tree)
    {
        if (tree is not UndoJson.Members members || depth >= keyPath.Count) return null;
        var copy = new Dictionary<string, UndoJson>(members.Items, StringComparer.Ordinal);
        string first = keyPath[depth];
        if (depth == keyPath.Count - 1)
        {
            if (value is null) copy.Remove(first);
            else copy[first] = value;
            return new UndoJson.Members(copy);
        }
        if (!copy.TryGetValue(first, out UndoJson? inner)) return null;
        if (Setting(keyPath, depth + 1, value, inner) is not { } changed) return null;
        copy[first] = changed;
        return new UndoJson.Members(copy);
    }

    /// <summary>
    /// The file with the member moved one way, changing ONLY its bytes; null
    /// (which the plan reads as changed since) when that cannot be done safely:
    /// the file not UTF-8 or not one JSON object, a key written twice on the
    /// path, a part on the way missing when a value must be set, a new value
    /// that is not exact, a key path, file or new value this app is not
    /// measured to treat as the mac does (<see cref="PathIsMeasured"/>,
    /// <see cref="UndoJson.IsMeasured"/>), or a result that does not read back
    /// as exactly the file with that one member changed.
    /// </summary>
    internal static byte[]? Moved(UndoOp op, byte[] bytes, bool backward)
    {
        if (op.KeyPath is not { Count: > 0 } keyPath || TopLevel(bytes) is not { } tree) return null;
        // Never a byte written where this app is not measured to find the
        // member as the mac finds it (#899 W6 review 2).
        if (!PathIsMeasured(keyPath, tree)) return null;
        UndoJson? wanted = backward ? op.ValueBefore : op.ValueAfter;
        if (Setting(keyPath, 0, wanted, tree) is not { } expected) return null;
        if (UndoJsonBytes.Locate(keyPath, bytes) is not { } place) return null;
        byte[] result;
        if (place.Member is { } member)
        {
            if (wanted is not null)
            {
                if (wanted.Spelled() is not { } spelled) return null;
                result = Join(bytes.AsSpan(0, member.ValueStart), Encoding.UTF8.GetBytes(spelled), bytes.AsSpan(member.ValueEnd));
            }
            else
            {
                result = Join(bytes.AsSpan(0, member.RemoveStart), [], bytes.AsSpan(member.RemoveEnd));
            }
        }
        else
        {
            UndoJsonBytes.Gap gap = place.Missing!.Value;
            if (wanted is null) return bytes;
            if (wanted.Spelled() is not { } spelled) return null;
            var name = new StringBuilder();
            UndoJson.SpellString(keyPath[^1], name);
            byte[] inserted = [.. gap.Lead, .. Encoding.UTF8.GetBytes(name.ToString()), .. gap.Colon, .. Encoding.UTF8.GetBytes(spelled)];
            result = Join(bytes.AsSpan(0, gap.At), inserted, bytes.AsSpan(gap.At));
        }
        if (TopLevel(result) is not { } readBack || !UndoJson.Same(readBack, expected)) return null;
        return result;
    }

    private static byte[] Join(ReadOnlySpan<byte> first, ReadOnlySpan<byte> middle, ReadOnlySpan<byte> last)
    {
        var result = new byte[first.Length + middle.Length + last.Length];
        first.CopyTo(result);
        middle.CopyTo(result.AsSpan(first.Length));
        last.CopyTo(result.AsSpan(first.Length + middle.Length));
        return result;
    }
}

/// <summary>
/// Where a member is in a JSON file's bytes, found with a scanner of its own,
/// so nothing else of the file is ever re-spelled (the mac's
/// <c>UndoJSONBytes</c>; its hard review of U2b, LOW a: a rewrite changed 0.1
/// to 0.10000000000000001, key order, spellings, and dropped a duplicate).
/// </summary>
internal static class UndoJsonBytes
{
    /// <summary>A member found: what goes when it is taken out (with the comma after it, or the one before), and its value's bytes.</summary>
    internal readonly record struct Member(int RemoveStart, int RemoveEnd, int ValueStart, int ValueEnd);

    /// <summary>Where a new member goes, what comes before its name (a comma and the space the last member had, or nothing in an empty object), and what goes between its name and value.</summary>
    internal readonly record struct Gap(int At, byte[] Lead, byte[] Colon);

    internal readonly record struct Place(Member? Member, Gap? Missing);

    private sealed record Scanned(string Name, int NameStart, byte[] ColonBytes, int ValueStart, int ValueEnd, byte[] LeadBytes);

    private static bool IsSpace(byte value) => value is 0x20 or 0x09 or 0x0A or 0x0D;

    private static int SkipSpace(byte[] bytes, int index)
    {
        while (index < bytes.Length && IsSpace(bytes[index])) index++;
        return index;
    }

    /// <summary>The end of the string starting at <paramref name="index"/> (its opening quote), and its text, or null.</summary>
    private static (int End, string Text)? ScanString(byte[] bytes, int index)
    {
        if (index >= bytes.Length || bytes[index] != 0x22) return null;
        int at = index + 1;
        while (at < bytes.Length)
        {
            if (bytes[at] == 0x5C) { at += 2; continue; }
            if (bytes[at] == 0x22)
            {
                try
                {
                    using JsonDocument document = JsonDocument.Parse(bytes.AsMemory(index, at + 1 - index));
                    if (document.RootElement.ValueKind != JsonValueKind.String) return null;
                    return (at + 1, document.RootElement.GetString()!);
                }
                catch (JsonException) { return null; }
            }
            at++;
        }
        return null;
    }

    /// <summary>The end of the value starting at <paramref name="index"/>, or null.</summary>
    private static int? ScanValue(byte[] bytes, int index)
    {
        if (index >= bytes.Length) return null;
        byte first = bytes[index];
        if (first == 0x22) return ScanString(bytes, index)?.End;
        if (first is 0x7B or 0x5B)
        {
            // An object or an array: to its matching close, strings skipped.
            int depth = 0;
            int at = index;
            while (at < bytes.Length)
            {
                byte value = bytes[at];
                if (value == 0x22)
                {
                    if (ScanString(bytes, at) is not { } text) return null;
                    at = text.End;
                    continue;
                }
                if (value is 0x7B or 0x5B) depth++;
                else if (value is 0x7D or 0x5D)
                {
                    depth--;
                    if (depth == 0) return at + 1;
                }
                at++;
            }
            return null;
        }
        // A number, true, false or null: to the next delimiter.
        int end = index;
        while (end < bytes.Length && !IsSpace(bytes[end]) && bytes[end] is not (0x2C or 0x7D or 0x5D)) end++;
        return end > index ? end : null;
    }

    /// <summary>Every member of the object starting at <paramref name="index"/> (its <c>{</c>), and where its <c>}</c> is, or null.</summary>
    private static (List<Scanned> Members, int Close)? ScanObject(byte[] bytes, int index)
    {
        if (index >= bytes.Length || bytes[index] != 0x7B) return null;
        var members = new List<Scanned>();
        int at = index + 1;
        int leadStart = at;
        while (true)
        {
            at = SkipSpace(bytes, at);
            if (at >= bytes.Length) return null;
            if (bytes[at] == 0x7D) return (members, at);
            byte[] lead = bytes[leadStart..at];
            if (ScanString(bytes, at) is not { } name) return null;
            int colon = SkipSpace(bytes, name.End);
            if (colon >= bytes.Length || bytes[colon] != 0x3A) return null;
            colon++;
            int valueStart = SkipSpace(bytes, colon);
            if (ScanValue(bytes, valueStart) is not { } valueEnd) return null;
            members.Add(new Scanned(name.Text, at, bytes[name.End..valueStart], valueStart, valueEnd, lead));
            at = SkipSpace(bytes, valueEnd);
            if (at >= bytes.Length) return null;
            if (bytes[at] == 0x2C)
            {
                at++;
                leadStart = at;
                continue;
            }
            if (bytes[at] == 0x7D) return (members, at);
            return null;
        }
    }

    /// <summary>
    /// Where the member at the key path is, or the gap where it would go, or
    /// null when it cannot be found safely (a key written twice on the path, a
    /// part on the way missing or not an object, bytes that do not scan).
    /// </summary>
    internal static Place? Locate(IReadOnlyList<string> keyPath, byte[] bytes)
    {
        int objectStart = SkipSpace(bytes, 0);
        for (int depth = 0; depth < keyPath.Count; depth++)
        {
            if (ScanObject(bytes, objectStart) is not { } scanned) return null;
            var found = new List<Scanned>();
            foreach (Scanned candidate in scanned.Members)
            {
                if (string.Equals(candidate.Name, keyPath[depth], StringComparison.Ordinal)) found.Add(candidate);
            }
            if (found.Count > 1) return null;   // the key written twice on the path: never a guess at which
            bool isLast = depth == keyPath.Count - 1;
            if (found.Count == 0)
            {
                if (!isLast) return null;
                if (scanned.Members.Count > 0)
                {
                    Scanned last = scanned.Members[^1];
                    return new Place(null, new Gap(last.ValueEnd, [0x2C, .. last.LeadBytes], last.ColonBytes));
                }
                return new Place(null, new Gap(scanned.Close, [], ": "u8.ToArray()));
            }
            Scanned member = found[0];
            if (isLast)
            {
                // Taken out with the comma after it, or else the one before.
                int position = scanned.Members.IndexOf(member);
                if (position + 1 < scanned.Members.Count)
                    return new Place(new Member(member.NameStart, scanned.Members[position + 1].NameStart, member.ValueStart, member.ValueEnd), null);
                if (position > 0)
                    return new Place(new Member(scanned.Members[position - 1].ValueEnd, member.ValueEnd, member.ValueStart, member.ValueEnd), null);
                int inside = SkipSpace(bytes, objectStart + 1);
                return new Place(new Member(inside, member.ValueEnd, member.ValueStart, member.ValueEnd), null);
            }
            objectStart = member.ValueStart;
        }
        return null;
    }
}

// ---- Folders: createTree, removeTree, and a folder's move --------------------------

/// <summary>
/// A folder's listing (<c>opKinds.createTree</c>, <c>undo.listingCases</c>):
/// UTF-8 text, one line per item inside the folder (the folder itself is not
/// listed), each ending in a line feed, in the order of the paths' UTF-8
/// bytes: <c>folder &lt;path&gt;</c> or <c>file &lt;sha256&gt; &lt;path&gt;</c>, path
/// relative to the folder with forward slashes, spelled as the file system
/// gives it. A file named <c>.DS_Store</c> is never listed, at any depth.
/// </summary>
internal sealed class UndoTreeListing(IReadOnlyList<string> folders, IReadOnlyList<(string Path, string Sha)> files)
{
    internal IReadOnlyList<string> Folders { get; } = folders;
    internal IReadOnlyList<(string Path, string Sha)> Files { get; } = files;

    /// <summary>The one name a listing passes over, wherever it is: the Finder's record of a window.</summary>
    internal const string IgnoredName = ".DS_Store";

    internal string Text
    {
        get
        {
            var entries = new List<(byte[] Key, string Line)>();
            foreach (string folder in Folders) entries.Add((Encoding.UTF8.GetBytes(folder), "folder " + folder + "\n"));
            foreach ((string path, string sha) in Files) entries.Add((Encoding.UTF8.GetBytes(path), "file " + sha + " " + path + "\n"));
            entries.Sort((first, second) => first.Key.AsSpan().SequenceCompareTo(second.Key));
            var text = new StringBuilder();
            foreach ((_, string line) in entries) text.Append(line);
            return text.ToString();
        }
    }

    internal byte[] Bytes => Encoding.UTF8.GetBytes(Text);

    internal string Sha => UndoCheck.Sha(Bytes);

    /// <summary>A listing read back from its blob, or null.</summary>
    internal static UndoTreeListing? Parse(byte[] bytes)
    {
        if (UndoCheck.DecodeStrictly(bytes) is not { } text) return null;
        var folders = new List<string>();
        var files = new List<(string, string)>();
        foreach (string line in text.Split('\n', StringSplitOptions.RemoveEmptyEntries))
        {
            if (line.StartsWith("folder ", StringComparison.Ordinal))
            {
                string path = line["folder ".Length..];
                if (!UndoPath.IsWithinTheRules(path)) return null;
                folders.Add(path);
            }
            else if (line.StartsWith("file ", StringComparison.Ordinal))
            {
                string rest = line["file ".Length..];
                int space = rest.IndexOf(' ', StringComparison.Ordinal);
                if (space < 0) return null;
                string sha = rest[..space];
                string path = rest[(space + 1)..];
                if (!UndoFormat.IsBlobName(sha) || !UndoPath.IsWithinTheRules(path)) return null;
                files.Add((path, sha));
            }
            else return null;
        }
        var listing = new UndoTreeListing(folders, files);
        return listing.Bytes.AsSpan().SequenceEqual(bytes) ? listing : null;
    }
}

/// <summary>What is at a folder's place now (the mac's <c>UndoTreeReading</c>).</summary>
internal abstract record UndoTreeReading
{
    private UndoTreeReading() { }

    internal sealed record Absent : UndoTreeReading;

    /// <summary>A file, a link, or a folder holding a link.</summary>
    internal sealed record NotATree : UndoTreeReading;

    /// <summary>Something there could not be read or listed just now: cannot tell.</summary>
    internal sealed record CannotRead : UndoTreeReading;

    internal sealed record Tree(UndoTreeListing Listing, IReadOnlyDictionary<string, byte[]> Contents) : UndoTreeReading;

    /// <summary>The listing's hash, when there is a folder that can be listed.</summary>
    internal string? ListingSha => this is Tree tree ? tree.Listing.Sha : null;

    /// <summary>
    /// Reads the folder at <paramref name="fullPath"/>, never following a link
    /// (<see cref="UndoLinks"/>: a junction, a symbolic link, any name
    /// surrogate; a OneDrive placeholder is a file, not a link). Each file is
    /// hashed as it is read, a megabyte at a time, and nothing is held, unless
    /// <paramref name="keepingContents"/> (a caller that stores them).
    /// <paramref name="cannotRead"/> is a test's seam: a full path it names
    /// cannot be read or listed just now.
    /// </summary>
    internal static UndoTreeReading Read(string fullPath, bool keepingContents = false, Func<string, bool>? cannotRead = null)
    {
        switch (UndoLinks.Look(fullPath))
        {
            case UndoLinks.What.Nothing: return new Absent();
            case UndoLinks.What.CannotLook: return new CannotRead();
            case UndoLinks.What.Folder: break;
            default: return new NotATree();
        }
        if (cannotRead?.Invoke(fullPath) == true) return new CannotRead();
        var folders = new List<string>();
        var files = new List<(string, string)>();
        var contents = new Dictionary<string, byte[]>(StringComparer.Ordinal);
        bool couldNotRead = false;
        if (!Walk(fullPath, "", keepingContents, cannotRead, folders, files, contents, ref couldNotRead))
            return couldNotRead ? new CannotRead() : new NotATree();
        return new Tree(new UndoTreeListing(folders, files), contents);
    }

    private static bool Walk(string folder, string prefix, bool keepingContents, Func<string, bool>? cannotRead,
                             List<string> folders, List<(string, string)> files, Dictionary<string, byte[]> contents, ref bool couldNotRead)
    {
        List<string> entries;
        try { entries = Directory.EnumerateFileSystemEntries(folder).ToList(); }
        catch (Exception error) when (error is IOException or UnauthorizedAccessException)
        {
            couldNotRead = true;
            return false;
        }
        foreach (string entry in entries)
        {
            string name = System.IO.Path.GetFileName(entry);
            // The Finder's own record of a window is not the teacher's work.
            if (name == UndoTreeListing.IgnoredName) continue;
            string path = prefix.Length == 0 ? name : prefix + "/" + name;
            switch (UndoLinks.Look(entry))
            {
                case UndoLinks.What.Folder:
                    if (cannotRead?.Invoke(entry) == true) { couldNotRead = true; return false; }
                    folders.Add(path);
                    if (!Walk(entry, path, keepingContents, cannotRead, folders, files, contents, ref couldNotRead)) return false;
                    break;
                case UndoLinks.What.File:
                {
                    if (cannotRead?.Invoke(entry) == true) { couldNotRead = true; return false; }
                    if (keepingContents)
                    {
                        if (UndoLinks.ReadAll(entry) is not { } bytes) { couldNotRead = true; return false; }
                        files.Add((path, UndoCheck.Sha(bytes)));
                        contents[path] = bytes;
                    }
                    else
                    {
                        if (UndoLinks.HashOf(entry) is not { } sha) { couldNotRead = true; return false; }
                        files.Add((path, sha));
                    }
                    break;
                }
                case UndoLinks.What.CannotLook:
                    couldNotRead = true;
                    return false;
                default:
                    // A link (or something gone in the instant): never followed.
                    return false;
            }
        }
        return true;
    }

    /// <summary>
    /// Makes the folder a listing describes at a NEW place, with every file's
    /// content as given and flushed to the disk. False, with whatever it made
    /// removed, when a file's content is missing or a write fails, or when
    /// anything is at the place already.
    /// </summary>
    internal static bool Make(UndoTreeListing listing, IReadOnlyDictionary<string, byte[]> contents, string fullPath, bool failTheWrite = false)
    {
        if (UndoLinks.Look(fullPath) != UndoLinks.What.Nothing) return false;
        try { Directory.CreateDirectory(fullPath); }
        catch (Exception error) when (error is IOException or UnauthorizedAccessException) { return false; }
        bool made = !failTheWrite;
        try
        {
            var sorted = new List<string>(listing.Folders);
            sorted.Sort((first, second) => Encoding.UTF8.GetBytes(first).AsSpan().SequenceCompareTo(Encoding.UTF8.GetBytes(second)));
            foreach (string folder in sorted)
            {
                if (!made) break;
                Directory.CreateDirectory(Under(fullPath, folder));
            }
            foreach ((string path, string sha) in listing.Files)
            {
                if (!made) break;
                if (!contents.TryGetValue(path, out byte[]? bytes) || UndoCheck.Sha(bytes) != sha) { made = false; break; }
                string file = Under(fullPath, path);
                Directory.CreateDirectory(System.IO.Path.GetDirectoryName(file)!);
                using var stream = new FileStream(file, FileMode.CreateNew, FileAccess.Write, FileShare.None, bufferSize: 0);
                stream.Write(bytes, 0, bytes.Length);
                stream.Flush(flushToDisk: true);
            }
        }
        catch (Exception error) when (error is IOException or UnauthorizedAccessException) { made = false; }
        if (!made)
        {
            UndoLinks.RemoveFolder(fullPath);
            return false;
        }
        return true;
    }

    internal static string Under(string folder, string relative) => System.IO.Path.Combine(folder, relative.Replace('/', System.IO.Path.DirectorySeparatorChar));
}

/// <summary>
/// What is at a place, read WITHOUT following a link (#899 W6). Windows has
/// three things the mac's <c>lstat</c> tells apart in one call: a junction or
/// symbolic link (a reparse point whose tag is a name surrogate), which is
/// never followed and is "something else"; a cloud file or folder (OneDrive's
/// Files On Demand: a reparse point whose tag is NOT a name surrogate), which
/// is the teacher's own file and is read like any other (a placeholder whose
/// content is not on the disk then fails its READ, which is cannot tell, never
/// changed since); and a plain file or folder.
/// </summary>
internal static class UndoLinks
{
    internal enum What { Nothing, File, Folder, Link, CannotLook }

    private const uint NameSurrogate = 0x20000000;

    internal static What Look(string fullPath) => Look(fullPath, out _);

    /// <summary>
    /// <see cref="Look(string)"/>, keeping what the system said when it is
    /// <see cref="What.CannotLook"/> (null otherwise): a part-way rename
    /// names a place it could not look at with its reason (#899 W8b-18b).
    /// </summary>
    internal static What Look(string fullPath, out string? said)
    {
        said = null;
        FileAttributes attributes;
        try { attributes = File.GetAttributes(fullPath); }
        catch (FileNotFoundException) { return What.Nothing; }
        catch (DirectoryNotFoundException) { return What.Nothing; }
        catch (Exception error) when (error is IOException or UnauthorizedAccessException) { said = ShortReason(error, fullPath); return What.CannotLook; }
        if (attributes.HasFlag(FileAttributes.ReparsePoint))
        {
            if (ReparseTag(fullPath) is not { } tag)
            {
                said = new System.ComponentModel.Win32Exception(Marshal.GetLastPInvokeError()).Message;
                return What.CannotLook;
            }
            if ((tag & NameSurrogate) != 0) return What.Link;
        }
        return attributes.HasFlag(FileAttributes.Directory) ? What.Folder : What.File;
    }

    /// <summary>
    /// What the system said, short and with no path (the mac's
    /// <c>strerror</c>, #899 W8b window B, LOW 2): .NET's own message names
    /// the full path, the teacher's account folder included, and the
    /// sentence it goes into already names the place as the course does. An
    /// error of the system's carries its code, said as the system says it
    /// ("Access is denied."); any other keeps .NET's message with
    /// <paramref name="fullPath"/> said as its last name.
    /// </summary>
    internal static string ShortReason(Exception error, string fullPath)
    {
        const int FacilityWin32 = unchecked((int)0x80070000);
        if ((error.HResult & unchecked((int)0xFFFF0000)) == FacilityWin32)
            return new System.ComponentModel.Win32Exception(error.HResult & 0xFFFF).Message;
        string full = Path.TrimEndingDirectorySeparator(fullPath);
        return error.Message.Replace(full, Path.GetFileName(full), StringComparison.OrdinalIgnoreCase);
    }

    /// <summary>
    /// A link's <c>linkSha</c> (<c>opKinds.move</c>, U4b2-14; #899 W8-6): the
    /// SHA-256 of the target it holds, as stored (<see cref="FileSystemInfo.LinkTarget"/>,
    /// never <c>ResolveLinkTarget</c>, so what it leads to is never opened),
    /// as UTF-8, unchanged: separators are NOT normalised, so a link made on
    /// the mac (<c>../library</c>) and one Windows stores with backslashes
    /// differ, which is changed since, and safe. Null when the target cannot
    /// be read: a reparse point .NET does not read as a link (WSL's own), or
    /// an error.
    /// </summary>
    internal static string? LinkSha(string fullPath)
    {
        string? target;
        try
        {
            FileSystemInfo link = File.GetAttributes(fullPath).HasFlag(FileAttributes.Directory) ? new DirectoryInfo(fullPath) : new FileInfo(fullPath);
            target = link.LinkTarget;
        }
        catch (Exception error) when (error is IOException or UnauthorizedAccessException) { return null; }
        return target is null ? null : Convert.ToHexStringLower(SHA256.HashData(Encoding.UTF8.GetBytes(target)));
    }

    /// <summary>
    /// Whether the link at <paramref name="fullPath"/> is a link to a FOLDER
    /// (a junction, or a symbolic link made as a folder's), told by the
    /// link's OWN attributes, never by following it: so a link to a folder
    /// that leads nowhere is still one (#899 W8b-21). Ask it only of a place
    /// <see cref="Look"/> calls a link.
    /// </summary>
    internal static bool IsALinkToAFolder(string fullPath)
    {
        try { return File.GetAttributes(fullPath).HasFlag(FileAttributes.Directory); }
        catch (Exception error) when (error is IOException or UnauthorizedAccessException) { return false; }
    }

    /// <summary>A file's bytes, read sharing everything, or null when it cannot be read now.</summary>
    internal static byte[]? ReadAll(string fullPath)
    {
        try
        {
            using var stream = new FileStream(fullPath, FileMode.Open, FileAccess.Read, FileShare.ReadWrite | FileShare.Delete);
            using var memory = new MemoryStream();
            stream.CopyTo(memory);
            return memory.ToArray();
        }
        catch (Exception error) when (error is IOException or UnauthorizedAccessException) { return null; }
    }

    /// <summary>A file's SHA-256, read a megabyte at a time, or null when it cannot be read now.</summary>
    internal static string? HashOf(string fullPath)
    {
        try
        {
            using var stream = new FileStream(fullPath, FileMode.Open, FileAccess.Read, FileShare.ReadWrite | FileShare.Delete, bufferSize: 1 << 20);
            return Convert.ToHexStringLower(SHA256.HashData(stream));
        }
        catch (Exception error) when (error is IOException or UnauthorizedAccessException) { return null; }
    }

    /// <summary>
    /// Removes a folder a swap made or took out, and everything in it: each
    /// file by its handle with the read-only attribute IGNORED (a file in it may
    /// be a hard link to a page elsewhere, whose attribute must not change),
    /// a link inside as a link (never followed). True when it is gone.
    /// </summary>
    internal static bool RemoveFolder(string fullPath)
    {
        switch (Look(fullPath))
        {
            case What.Nothing: return true;
            case What.Link:
                try
                {
                    if (File.GetAttributes(fullPath).HasFlag(FileAttributes.Directory)) Directory.Delete(fullPath, recursive: false);
                    else File.Delete(fullPath);
                    return true;
                }
                catch (Exception error) when (error is IOException or UnauthorizedAccessException) { return false; }
            case What.File:
                return UndoStagedFile.RemoveByName(fullPath);
            case What.Folder:
            {
                bool allGone = true;
                List<string> entries;
                try { entries = Directory.EnumerateFileSystemEntries(fullPath).ToList(); }
                catch (Exception error) when (error is IOException or UnauthorizedAccessException) { return false; }
                foreach (string entry in entries)
                {
                    if (!RemoveFolder(entry)) allGone = false;
                }
                if (!allGone) return false;
                try { Directory.Delete(fullPath, recursive: false); return true; }
                catch (Exception error) when (error is IOException or UnauthorizedAccessException) { return false; }
            }
            default:
                return false;
        }
    }

    /// <summary>The reparse tag of a reparse point, from its directory entry; null when it cannot be read.</summary>
    private static uint? ReparseTag(string fullPath)
    {
        IntPtr found = FindFirstFileExW(UndoLock.LongPath(fullPath), 1 /* FindExInfoBasic */, out Win32FindData data, 0, IntPtr.Zero, 0);
        if (found == new IntPtr(-1)) return null;
        FindClose(found);
        return data.Reserved0;
    }

    [StructLayout(LayoutKind.Sequential, CharSet = CharSet.Unicode)]
    private struct Win32FindData
    {
        internal uint Attributes;
        internal System.Runtime.InteropServices.ComTypes.FILETIME Created;
        internal System.Runtime.InteropServices.ComTypes.FILETIME Accessed;
        internal System.Runtime.InteropServices.ComTypes.FILETIME Written;
        internal uint SizeHigh;
        internal uint SizeLow;
        internal uint Reserved0;
        internal uint Reserved1;
        [MarshalAs(UnmanagedType.ByValTStr, SizeConst = 260)] internal string FileName;
        [MarshalAs(UnmanagedType.ByValTStr, SizeConst = 14)] internal string AlternateName;
    }

    [DllImport("kernel32.dll", CharSet = CharSet.Unicode, SetLastError = true)]
    private static extern IntPtr FindFirstFileExW(string name, int infoLevel, out Win32FindData data, int searchOp, IntPtr filter, int flags);

    [DllImport("kernel32.dll", SetLastError = true)]
    private static extern bool FindClose(IntPtr handle);
}

/// <summary>One side of a move, judged by content (the mac's <c>UndoMoveSide</c>).</summary>
internal enum UndoMoveSide
{
    /// <summary>Nothing there.</summary>
    Free,
    /// <summary>The very file (by its SHA-256) or folder (by its listing) moved.</summary>
    HoldsTheContent,
    /// <summary>Something else (a link included, never followed).</summary>
    HoldsSomethingElse,
    /// <summary>Something there that could not be read just now.</summary>
    CannotRead,
}

/// <summary>Which spelling of a capitalisation-only move's one item its folder lists (#899 W8-5).</summary>
internal enum UndoCaseOnlySpelling
{
    /// <summary>The folder lists it as the move's <c>from</c>.</summary>
    From,
    /// <summary>The folder lists it as the move's <c>to</c>.</summary>
    To,
    /// <summary>A third spelling, neither side's, or no entry at all.</summary>
    Another,
    /// <summary>The folder could not be listed just now.</summary>
    CannotRead,
}

internal static class UndoMoveSides
{
    /// <summary>
    /// For a capitalisation-only move (<see cref="UndoOp.IsCaseOnlyMove"/>):
    /// which spelling the folder holding its item lists, where the two
    /// spellings are ONE item (the same identity at both, a link never
    /// followed; the mac's <c>UndoMoveSide.spellingListed</c>, which compares
    /// device and inode); null where they are not one item (nothing there,
    /// or two items, as on a case-sensitive folder), which is then judged as
    /// any move. The entry is matched by the moved item's own part without
    /// regard to case, then told apart from each side AS SPELLED (U4b2-9).
    /// </summary>
    internal static UndoCaseOnlySpelling? SpellingListed(string fromFull, string toFull, Func<string, bool>? cannotRead = null)
    {
        if (UndoFileIdentity.OfPlace(fromFull) is not { } atFrom || UndoFileIdentity.OfPlace(toFull) is not { } atTo || atFrom != atTo) return null;
        string folder = Path.GetDirectoryName(fromFull)!;
        string fromName = Path.GetFileName(fromFull);
        string toName = Path.GetFileName(toFull);
        if (cannotRead?.Invoke(folder) == true) return UndoCaseOnlySpelling.CannotRead;
        List<string> names;
        try
        {
            names = [];
            foreach (string entry in Directory.EnumerateFileSystemEntries(folder)) names.Add(Path.GetFileName(entry));
        }
        catch (Exception error) when (error is IOException or UnauthorizedAccessException)
        {
            return UndoCaseOnlySpelling.CannotRead;
        }
        foreach (string name in names)
        {
            if (UndoOp.PartInside(fromName, name) is not "") continue;
            if (string.Equals(name, toName, StringComparison.Ordinal)) return UndoCaseOnlySpelling.To;
            if (string.Equals(name, fromName, StringComparison.Ordinal)) return UndoCaseOnlySpelling.From;
            return UndoCaseOnlySpelling.Another;
        }
        return UndoCaseOnlySpelling.Another;
    }

    /// <summary>
    /// One side of a move as it holds now. <paramref name="overriding"/> gives,
    /// for paths inside the place (relative to it, "" the place itself), what
    /// to take instead of what is there (the mac's <c>UndoMoveSide.read(_:at:overriding:)</c>,
    /// U4b; #899 W8-2): a carried page as the step's own edit would leave it
    /// once taken back, and <see cref="UndoCurrent.Absent"/> for a file left
    /// out of the judgement (the swap's own staged and kept files). A path is
    /// matched to the listing by <see cref="UndoOp.PartInside"/>, the one
    /// comparison, and keeps the disk's spelling.
    /// </summary>
    internal static UndoMoveSide Read(UndoOp op, string fullPath, Func<string, bool>? cannotRead = null,
                                      IReadOnlyDictionary<string, UndoCurrent>? overriding = null) =>
        ReadNamingFoldersLeftOut(op, fullPath, cannotRead, overriding).Side;

    /// <summary>
    /// <see cref="Read"/>, naming too the folders inside the place that were
    /// left out of the judgement with the files left out (the mac's
    /// <c>UndoMoveSide.readNamingFoldersLeftOut</c>, U4b2-10; #899 W8-4): each
    /// relative to the place, deepest first, as the disk spells it. Only a
    /// side that holds the content names any.
    /// </summary>
    internal static (UndoMoveSide Side, IReadOnlyList<string> FoldersLeftOut) ReadNamingFoldersLeftOut(
        UndoOp op, string fullPath, Func<string, bool>? cannotRead = null, IReadOnlyDictionary<string, UndoCurrent>? overriding = null)
    {
        if (op.Sha is not null) return (ReadAFile(op, fullPath, cannotRead, overriding), []);
        if (op.LinkSha is { } linkSha) return (ReadALink(linkSha, fullPath, cannotRead), []);
        switch (UndoTreeReading.Read(fullPath, cannotRead: cannotRead))
        {
            case UndoTreeReading.Absent: return (UndoMoveSide.Free, []);
            case UndoTreeReading.CannotRead: return (UndoMoveSide.CannotRead, []);
            case UndoTreeReading.Tree tree:
            {
                if (overriding is not { Count: > 0 })
                    return (string.Equals(tree.Listing.Sha, op.ListingSha, StringComparison.Ordinal) ? UndoMoveSide.HoldsTheContent : UndoMoveSide.HoldsSomethingElse, []);
                var files = new List<(string Path, string Sha)>();
                var matched = new HashSet<string>(StringComparer.Ordinal);
                var filesLeftOut = new List<string>();
                foreach ((string path, string fileSha) in tree.Listing.Files)
                {
                    UndoCurrent? given = null;
                    foreach ((string inside, UndoCurrent item) in overriding)
                    {
                        if (UndoOp.PartInside(inside, path) is not "") continue;
                        given = item;
                        matched.Add(inside);
                    }
                    switch (given)
                    {
                        case null: files.Add((path, fileSha)); break;
                        case UndoCurrent.Absent: filesLeftOut.Add(path); break;
                        case UndoCurrent.Bytes bytes: files.Add((path, UndoCheck.Sha(bytes.Content))); break;
                        default: return (UndoMoveSide.HoldsSomethingElse, []);
                    }
                }
                foreach ((string inside, UndoCurrent item) in overriding)
                {
                    if (matched.Contains(inside) || inside.Length == 0) continue;
                    switch (item)
                    {
                        case UndoCurrent.Absent: break;
                        case UndoCurrent.Bytes bytes: files.Add((inside, UndoCheck.Sha(bytes.Content))); break;
                        default: return (UndoMoveSide.HoldsSomethingElse, []);
                    }
                }
                // U4b2-10: a folder holding nothing but files left out (and
                // folders so left out) may be one the step's edits made for
                // them, or an empty one of the content's own; each is decided
                // on its own (FoldersTheContentLacks).
                List<string> candidates = FoldersHoldingOnly(filesLeftOut, tree.Listing, files);
                return FoldersTheContentLacks(candidates, tree.Listing, files, op.ListingSha) is { } foldersLeftOut
                    ? (UndoMoveSide.HoldsTheContent, foldersLeftOut)
                    : (UndoMoveSide.HoldsSomethingElse, []);
            }
            default: return (UndoMoveSide.HoldsSomethingElse, []);
        }
    }

    /// <summary>Review 1 of U4b2-10: the most candidate folders decided one by one (the mac's <c>mostFoldersDecidedOneByOne</c>).</summary>
    internal const int MostFoldersDecidedOneByOne = 8;

    /// <summary>
    /// Which of <paramref name="candidates"/> (deepest first) the moved
    /// content did not hold: the set that, left out of the listing with the
    /// files left out, makes it match <paramref name="listingSha"/>, or null
    /// when none does (the mac's <c>foldersTheContentLacks</c>). The list keeps
    /// only the listing's hash, so the sets are tried, never read: each set
    /// that leaves a folder out only with every candidate below it, from all
    /// of them down to none. Two sets give two listings, so at most one
    /// matches. Up to <see cref="MostFoldersDecidedOneByOne"/> candidates every
    /// such set is tried (at most 256 hashes); beyond that only all or none,
    /// so a step with more, some of them the content's own, is refused as
    /// changed since, which takes nothing back.
    /// </summary>
    internal static List<string>? FoldersTheContentLacks(List<string> candidates, UndoTreeListing listing,
                                                         IReadOnlyList<(string Path, string Sha)> files, string? listingSha)
    {
        var setsToTry = new List<List<string>>();
        if (candidates.Count <= MostFoldersDecidedOneByOne)
        {
            for (int mask = (1 << candidates.Count) - 1; mask >= 0; mask--)
            {
                var leftOut = new List<string>();
                for (int position = 0; position < candidates.Count; position++)
                {
                    if ((mask & (1 << position)) != 0) leftOut.Add(candidates[position]);
                }
                if (LeavesOutEveryCandidateBelow(leftOut, candidates)) setsToTry.Add(leftOut);
            }
        }
        else setsToTry = [candidates, []];
        foreach (List<string> leftOut in setsToTry)
        {
            var foldersKept = new List<string>();
            foreach (string folder in listing.Folders)
            {
                if (!leftOut.Contains(folder, StringComparer.Ordinal)) foldersKept.Add(folder);
            }
            if (string.Equals(new UndoTreeListing(foldersKept, files).Sha, listingSha, StringComparison.Ordinal)) return leftOut;
        }
        return null;
    }

    private static bool LeavesOutEveryCandidateBelow(List<string> leftOut, List<string> candidates)
    {
        foreach (string folder in leftOut)
        {
            foreach (string other in candidates)
            {
                if (IsBelow(other, folder) && !leftOut.Contains(other, StringComparer.Ordinal)) return false;
            }
        }
        return true;
    }

    /// <summary>
    /// U4b2-10: every folder of <paramref name="listing"/> that holds at least
    /// one of <paramref name="filesLeftOut"/> and nothing else but folders that
    /// are themselves left out: no file of <paramref name="files"/>, no other
    /// folder (a listing holds no link: a folder holding one is not a tree).
    /// Deepest first; inside by the one comparison, <see cref="UndoOp.PartInside"/>
    /// (the mac's <c>foldersHoldingOnly</c>).
    /// </summary>
    internal static List<string> FoldersHoldingOnly(List<string> filesLeftOut, UndoTreeListing listing, IReadOnlyList<(string Path, string Sha)> files)
    {
        var deepestFirst = new List<string>(listing.Folders);
        deepestFirst.Sort((first, second) =>
        {
            int firstDepth = first.Split('/').Length, secondDepth = second.Split('/').Length;
            return firstDepth != secondDepth ? secondDepth.CompareTo(firstDepth) : string.CompareOrdinal(first, second);
        });
        var leftOut = new List<string>();
        foreach (string folder in deepestFirst)
        {
            if (!filesLeftOut.Any(path => IsBelow(path, folder))) continue;
            bool holdsSomethingKept = files.Any(file => IsBelow(file.Path, folder))
                || listing.Folders.Any(other => IsBelow(other, folder) && !leftOut.Contains(other, StringComparer.Ordinal));
            if (!holdsSomethingKept) leftOut.Add(folder);
        }
        return leftOut;
    }

    /// <summary>Whether <paramref name="path"/> is below <paramref name="folder"/> (never the folder itself), by the one comparison.</summary>
    private static bool IsBelow(string path, string folder) => UndoOp.PartInside(folder, path) is { Length: > 0 };

    /// <summary>
    /// One side of a link's move (U4b2-14; #899 W8-6; the mac's
    /// <c>UndoMoveSide.readLink</c>), read on the link itself and never
    /// followed, so what it leads to (outside the working folder, or nowhere)
    /// is never read: the content is a link (<see cref="UndoLinks.Look"/>, a
    /// name surrogate, never a OneDrive placeholder) whose target hashes to
    /// <paramref name="linkSha"/>; a folder, a file or a link with another
    /// target is something else; a link whose target cannot be read is
    /// cannot tell now.
    /// </summary>
    private static UndoMoveSide ReadALink(string linkSha, string fullPath, Func<string, bool>? cannotRead)
    {
        switch (UndoLinks.Look(fullPath))
        {
            case UndoLinks.What.Nothing: return UndoMoveSide.Free;
            case UndoLinks.What.Link:
                if (cannotRead?.Invoke(fullPath) == true) return UndoMoveSide.CannotRead;
                return UndoLinks.LinkSha(fullPath) is { } found
                    ? string.Equals(found, linkSha, StringComparison.Ordinal) ? UndoMoveSide.HoldsTheContent : UndoMoveSide.HoldsSomethingElse
                    : UndoMoveSide.CannotRead;
            case UndoLinks.What.CannotLook: return UndoMoveSide.CannotRead;
            default: return UndoMoveSide.HoldsSomethingElse;
        }
    }

    private static UndoMoveSide ReadAFile(UndoOp op, string fullPath, Func<string, bool>? cannotRead, IReadOnlyDictionary<string, UndoCurrent>? overriding)
    {
        if (op.Sha is { } sha)
        {
            switch (UndoLinks.Look(fullPath))
            {
                case UndoLinks.What.Nothing: return UndoMoveSide.Free;
                case UndoLinks.What.CannotLook: return UndoMoveSide.CannotRead;
                case UndoLinks.What.File:
                    if (overriding is not null && overriding.TryGetValue("", out UndoCurrent? given))
                    {
                        return given switch
                        {
                            UndoCurrent.Bytes bytes => string.Equals(UndoCheck.Sha(bytes.Content), sha, StringComparison.Ordinal) ? UndoMoveSide.HoldsTheContent : UndoMoveSide.HoldsSomethingElse,
                            UndoCurrent.Absent => UndoMoveSide.Free,
                            _ => UndoMoveSide.HoldsSomethingElse,
                        };
                    }
                    if (cannotRead?.Invoke(fullPath) == true) return UndoMoveSide.CannotRead;
                    return UndoLinks.HashOf(fullPath) is { } found
                        ? string.Equals(found, sha, StringComparison.Ordinal) ? UndoMoveSide.HoldsTheContent : UndoMoveSide.HoldsSomethingElse
                        : UndoMoveSide.CannotRead;
                default: return UndoMoveSide.HoldsSomethingElse;
            }
        }
        return UndoMoveSide.HoldsSomethingElse;
    }
}

// ---- external -----------------------------------------------------------------------

/// <summary>What an <c>external</c> target holds now.</summary>
internal readonly record struct UndoExternalReading(bool NotSet, UndoJson? Value, bool CannotTell)
{
    internal static UndoExternalReading Unset => new(true, null, false);
    internal static UndoExternalReading Unknown => new(false, null, true);
    internal static UndoExternalReading Holding(UndoJson value) => new(false, value, false);

    internal bool Matches(UndoJson? expected)
    {
        if (CannotTell) return false;
        if (NotSet) return expected is null;
        return expected is not null && UndoJson.Same(Value, expected);
    }
}

/// <summary>
/// The places outside every working folder an <c>external</c> op can change
/// (<c>preference:&lt;name&gt;</c>, one of the app's own settings). A test
/// passes a place of its own; the app passes <see cref="UndoAppSettingsPlaces"/>.
/// </summary>
internal interface IUndoExternalPlaces
{
    UndoExternalReading Read(string target);

    /// <summary>Sets the target (null: removes it). False when it could not.</summary>
    bool Write(string target, UndoJson? value);
}

/// <summary>
/// The app's own settings store (<c>%LOCALAPPDATA%\Plantoir\settings.json</c>,
/// following <c>--state-dir</c>), named <c>preference:&lt;name&gt;</c> by the
/// member's name as <see cref="Models.AppSettings"/> spells it. Read from the
/// FILE as it is on the disk now, as the app's typed settings read it (a member
/// the file does not hold is its default), never from a process's copy, which
/// may be older (<c>plantoir-mcp.exe</c> holds its own). A set replaces exactly
/// that member with exactly the value (a list or a dictionary replaced whole,
/// never merged into), into the file as it is on the disk now: the file is
/// read, that one member changed, the result checked to read back as the value,
/// and only then written whole, by a temporary file and one rename that
/// replaces, so a set either happened or did not. A result that does not read
/// back as the value (a number given for a text setting) writes nothing and is
/// refused (couldNotWrite), the file byte for byte as it was. Once written, the
/// copy this process runs on (<see cref="Models.AppSettings.Current"/>) is given
/// the same member, so its next save keeps it. A name the store does not have
/// is cannot tell (never "not set"), and a typed setting cannot be removed, so
/// setting one to "not set" is refused (couldNotWrite). Rejected (the first
/// review of W6, MEDIUM): <c>JsonConvert.PopulateObject</c> on the running copy
/// and its <c>Save()</c>, which appended to a list and merged a dictionary,
/// saved before checking, and wrote that process's older copy of every other
/// setting over the file. Which of the app's settings a step records, and
/// under what names, is W8's (the mac's U4 wires its preferences); nothing
/// writes an external op on Windows before then.
/// </summary>
internal sealed class UndoAppSettingsPlaces : IUndoExternalPlaces
{
    private const string Family = "preference:";

    private static readonly Newtonsoft.Json.Linq.JsonLoadSettings AsWritten = new()
    {
        CommentHandling = Newtonsoft.Json.Linq.CommentHandling.Ignore,
        DuplicatePropertyNameHandling = Newtonsoft.Json.Linq.DuplicatePropertyNameHandling.Replace,
    };

    private readonly string? _file;
    private readonly Func<Models.AppSettings?> _running;

    /// <summary>The app's own store: <see cref="Models.AppSettings.DefaultPath"/>, and the copy this process runs on.</summary>
    internal UndoAppSettingsPlaces() : this(null, () => Models.AppSettings.Current) { }

    /// <summary>A store in a file of the caller's (a test's, the harness's), and the copy that process runs on, if any.</summary>
    internal UndoAppSettingsPlaces(string? file, Func<Models.AppSettings?> running)
    {
        _file = file;
        _running = running;
    }

    private string SettingsFile => _file ?? Models.AppSettings.DefaultPath;

    private static string? NameOf(string target) =>
        target.StartsWith(Family, StringComparison.Ordinal) && target.Length > Family.Length ? target[Family.Length..] : null;

    public UndoExternalReading Read(string target)
    {
        if (NameOf(target) is not { } name) return UndoExternalReading.Unknown;
        try
        {
            string? text = System.IO.File.Exists(SettingsFile) ? System.IO.File.ReadAllText(SettingsFile) : null;
            return MemberOf(text ?? "{}", name);
        }
        catch (Exception error) when (error is IOException or UnauthorizedAccessException)
        {
            return UndoExternalReading.Unknown;
        }
    }

    public bool Write(string target, UndoJson? value)
    {
        if (NameOf(target) is not { } name || value is null || value.Spelled(onlyAsTheMacIsMeasuredToWrite: false) is not { } spelled) return false;
        string temporary = SettingsFile + ".undo-writing";
        try
        {
            if (!TheStoreHas(name)) return false;
            string now = System.IO.File.Exists(SettingsFile) ? System.IO.File.ReadAllText(SettingsFile) : "{}";
            // A file the app's own reader cannot read is never written over: cannot tell what it holds.
            if (MemberOf(now, name).CannotTell) return false;
            Newtonsoft.Json.Linq.JObject all = Newtonsoft.Json.Linq.JObject.Load(Reader(now), AsWritten);
            // The app's reader matches a name ignoring case: every spelling of it goes, the one name comes in.
            foreach (Newtonsoft.Json.Linq.JProperty spelling in all.Properties().ToList())
            {
                if (string.Equals(spelling.Name, name, StringComparison.OrdinalIgnoreCase)) spelling.Remove();
            }
            Newtonsoft.Json.Linq.JToken member = Newtonsoft.Json.Linq.JToken.Load(Reader(spelled));
            all[name] = member;
            string written = all.ToString(Newtonsoft.Json.Formatting.Indented);
            if (!MemberOf(written, name).Matches(value)) return false;
            Directory.CreateDirectory(Path.GetDirectoryName(Path.GetFullPath(SettingsFile))!);
            System.IO.File.WriteAllText(temporary, written);
            System.IO.File.Move(temporary, SettingsFile, overwrite: true);
            if (_running() is { } running)
            {
                var replacing = new Newtonsoft.Json.JsonSerializerSettings { ObjectCreationHandling = Newtonsoft.Json.ObjectCreationHandling.Replace };
                var one = new Newtonsoft.Json.Linq.JObject { [name] = member.DeepClone() };
                Newtonsoft.Json.JsonConvert.PopulateObject(one.ToString(Newtonsoft.Json.Formatting.None), running, replacing);
            }
            return true;
        }
        catch (Exception error) when (error is Newtonsoft.Json.JsonException or InvalidOperationException or ArgumentException
                                          or IOException or UnauthorizedAccessException)
        {
            try { System.IO.File.Delete(temporary); } catch (Exception cleanup) when (cleanup is IOException or UnauthorizedAccessException) { }
            return false;
        }
    }

    /// <summary>A reader that keeps a date-like string as text, so a member that is not set is never re-spelled.</summary>
    private static Newtonsoft.Json.JsonTextReader Reader(string text) =>
        new(new StringReader(text)) { DateParseHandling = Newtonsoft.Json.DateParseHandling.None };

    private static bool TheStoreHas(string name) =>
        Newtonsoft.Json.Linq.JObject.FromObject(new Models.AppSettings()).Property(name, StringComparison.Ordinal) is not null;

    /// <summary>The named member as the app's typed settings read it from this text, or cannot tell.</summary>
    private static UndoExternalReading MemberOf(string text, string name)
    {
        try
        {
            if (Newtonsoft.Json.JsonConvert.DeserializeObject<Models.AppSettings>(text) is not { } settings) return UndoExternalReading.Unknown;
            Newtonsoft.Json.Linq.JObject all = Newtonsoft.Json.Linq.JObject.FromObject(settings);
            if (all.Property(name, StringComparison.Ordinal) is not { } property) return UndoExternalReading.Unknown;
            if (HoldsADate(property.Value)) return UndoExternalReading.Unknown;
            using JsonDocument document = JsonDocument.Parse(property.Value.ToString(Newtonsoft.Json.Formatting.None));
            return UndoJson.From(document.RootElement) is { } value ? UndoExternalReading.Holding(value) : UndoExternalReading.Unknown;
        }
        catch (Exception error) when (error is JsonException or Newtonsoft.Json.JsonException or InvalidOperationException or ArgumentException)
        {
            return UndoExternalReading.Unknown;
        }
    }

    private static bool HoldsADate(Newtonsoft.Json.Linq.JToken token)
    {
        if (token.Type == Newtonsoft.Json.Linq.JTokenType.Date) return true;
        foreach (Newtonsoft.Json.Linq.JToken inner in token.Children())
        {
            if (HoldsADate(inner)) return true;
        }
        return false;
    }
}
