using System.Runtime.InteropServices;
using System.Text;
using Microsoft.Win32.SafeHandles;

namespace Plantoir.Core.Undo;

/// <summary>
/// The two identifier files (<c>undoJournal.identifierFiles</c>, #899 piece
/// W1): <c>undo\computer-id</c>, and every working folder's
/// <c>courses\.internal\folder-id</c>, the one file of the journal's format
/// both apps share on a synced folder.
///
/// <para><b>Written</b> as a lower-case UUID, one line feed, UTF-8 with no
/// byte-order mark, made EXCLUSIVELY so two processes making it at once end
/// with one: written whole under a temporary name and hard-linked onto the
/// name (a link onto a name that exists is refused, 183), or, where the volume
/// has no hard links (FAT, exFAT, many SMB shares), created with
/// <see cref="FileMode.CreateNew"/> and written in one write. Never replaced
/// while it holds an identifier.</para>
///
/// <para><b>Read</b> leniently: a byte-order mark, white space, carriage
/// returns and line feeds ignored, either case accepted, compared in lower
/// case.</para>
///
/// <para><b>Unreadable</b> never blocks the folder for good. Empty and written
/// less than ten seconds ago: a creator is at work, not yet (ten, not two,
/// because FAT keeps a modification time to two seconds). Otherwise it is set
/// aside as <c>folder-id.unreadable-&lt;uuid&gt;</c>, only while it is still
/// the file inspected (the same file on its volume, by the identity the read
/// took from its own handle: the W1 review's H1), and it is renamed aside
/// through the very handle that was compared and read again, so the file
/// moved is always the one inspected and a good file another process made
/// at the name is never moved (the review's second round; see
/// <see cref="SetAside"/>).</para>
///
/// <para>Nothing in the app calls this yet: the first step recorded in a folder
/// makes its <c>folder-id</c> (W2's door, W4's start-up for
/// <c>computer-id</c>). Its clock is passed in, so "less than ten seconds"
/// never waits on a real clock in a test.</para>
/// </summary>
internal sealed class FolderIdentityFile
{
    /// <summary>A creator is at work while the empty file is younger than this.</summary>
    internal static readonly TimeSpan CreatorAtWork = TimeSpan.FromSeconds(10);

    private static readonly UTF8Encoding Utf8NoBom = new(encoderShouldEmitUTF8Identifier: false);

    private readonly TimeProvider _clock;
    private readonly Func<string, string, bool>? _hardLink;
    private readonly Action? _betweenCheckAndRename;

    /// <param name="path">The identifier file's full path.</param>
    /// <param name="clock">The clock "less than ten seconds ago" is judged by.</param>
    /// <param name="hardLink">A seam: link the first path's file onto the second name; false when the volume has no hard links. The real call by default.</param>
    /// <param name="betweenCheckAndRename">A seam for tests: runs after the file is found to be the one inspected and before it is renamed aside, where another process could set it aside and make a new one.</param>
    internal FolderIdentityFile(string path, TimeProvider clock, Func<string, string, bool>? hardLink = null, Action? betweenCheckAndRename = null)
    {
        FilePath = path;
        _clock = clock;
        _hardLink = hardLink;
        _betweenCheckAndRename = betweenCheckAndRename;
    }

    internal string FilePath { get; }

    /// <summary>What a read of the file comes to.</summary>
    internal enum Outcome { Identifier, Absent, NotYet, Unreadable }

    /// <param name="Inspected">The volume serial and file index of the file this read looked at, taken
    /// from the same handle the bytes were read through; null when nothing was opened.</param>
    internal readonly record struct Answer(Outcome Outcome, string? Identifier = null, (ulong Volume, ulong Index)? Inspected = null);

    /// <summary>The identifier a text holds, in lower case, or null when it holds none.</summary>
    internal static string? IdentifierIn(string text)
    {
        var kept = new StringBuilder();
        foreach (char character in text)
        {
            if (character is '\uFEFF' or ' ' or '\t' or '\r' or '\n') continue;
            kept.Append(character);
        }
        string bare = kept.ToString();
        if (bare.Length != 36 || bare[8] != '-' || bare[13] != '-' || bare[18] != '-' || bare[23] != '-') return null;
        return Guid.TryParseExact(bare, "D", out Guid id) ? id.ToString("D") : null;
    }

    /// <summary>Reads it, without changing anything.</summary>
    internal Answer Read()
    {
        byte[] bytes;
        DateTime written;
        (ulong Volume, ulong Index)? inspected;
        try
        {
            using var stream = new FileStream(FilePath, FileMode.Open, FileAccess.Read, FileShare.ReadWrite | FileShare.Delete);
            // The identity of THIS file, from the handle its bytes are read
            // through: what SetAside later compares with (the W1 review's H1).
            inspected = IdentityOf(stream.SafeFileHandle);
            using var memory = new MemoryStream();
            stream.CopyTo(memory);
            bytes = memory.ToArray();
            written = File.GetLastWriteTimeUtc(FilePath);
        }
        catch (FileNotFoundException) { return new Answer(Outcome.Absent); }
        catch (DirectoryNotFoundException) { return new Answer(Outcome.Absent); }
        catch (IOException) { return new Answer(Outcome.NotYet); }               // held at the moment: never a reason to set it aside
        catch (UnauthorizedAccessException) { return new Answer(Outcome.NotYet); }

        string text;
        try { text = new UTF8Encoding(false, true).GetString(bytes); }
        catch (DecoderFallbackException) { return new Answer(Outcome.Unreadable, null, inspected); }
        if (IdentifierIn(text) is { } id) return new Answer(Outcome.Identifier, id, inspected);
        if (bytes.Length == 0 && _clock.GetUtcNow().UtcDateTime - written < CreatorAtWork) return new Answer(Outcome.NotYet, null, inspected);
        return new Answer(Outcome.Unreadable, null, inspected);
    }

    /// <summary>
    /// The identifier, made if there is none. Null means "not yet": a creator
    /// is at work, or the file could not be read at the moment; the caller
    /// records nothing this time (a live step is refused before anything
    /// changes).
    /// </summary>
    internal string? ReadOrMake()
    {
        for (int attempt = 0; attempt < 4; attempt++)
        {
            Answer answer = Read();
            switch (answer.Outcome)
            {
                case Outcome.Identifier:
                    return answer.Identifier;
                case Outcome.NotYet:
                    return null;
                case Outcome.Unreadable:
                    if (SetAside(answer.Inspected) is { } putBack) return putBack;
                    break;
            }
            if (MakeExclusively() is { } made) return made;
            // Somebody else made it between our look and our make: read theirs.
        }
        return null;
    }

    /// <summary>Makes the file if no file has the name; null when one appeared first.</summary>
    internal string? MakeExclusively()
    {
        string? folder = Path.GetDirectoryName(FilePath);
        if (folder is not null) Directory.CreateDirectory(folder);
        string id = Guid.NewGuid().ToString("D");
        byte[] bytes = Utf8NoBom.GetBytes(id + "\n");

        string temporary = FilePath + ".tmp-" + Guid.NewGuid().ToString("N");
        try
        {
            using (var stream = new FileStream(temporary, FileMode.CreateNew, FileAccess.Write, FileShare.None))
            {
                stream.Write(bytes);
                stream.Flush(flushToDisk: true);
            }
            switch (Link(temporary, FilePath))
            {
                case LinkResult.Linked: return id;
                case LinkResult.NameTaken: return null;
            }
        }
        catch (IOException) { /* fall through to the exclusive create */ }
        catch (UnauthorizedAccessException) { }
        finally
        {
            try { File.Delete(temporary); } catch { }
        }

        // No hard links on this volume: the exclusive create of the name itself,
        // written in one write.
        try
        {
            using var stream = new FileStream(FilePath, FileMode.CreateNew, FileAccess.Write, FileShare.None);
            stream.Write(bytes);
            stream.Flush(flushToDisk: true);
            return id;
        }
        catch (IOException) { return null; }   // it exists now: somebody else made it
    }

    private enum LinkResult { Linked, NameTaken, NoLinks }

    private LinkResult Link(string existing, string name)
    {
        if (_hardLink is not null) return _hardLink(existing, name) ? LinkResult.Linked : File.Exists(name) ? LinkResult.NameTaken : LinkResult.NoLinks;
        if (CreateHardLinkW(LongPath(name), LongPath(existing), IntPtr.Zero)) return LinkResult.Linked;
        int error = Marshal.GetLastWin32Error();
        return error is 183 or 80 ? LinkResult.NameTaken : LinkResult.NoLinks;   // ERROR_ALREADY_EXISTS, ERROR_FILE_EXISTS
    }

    /// <summary>
    /// Sets an unreadable file aside, only while it is still the file
    /// <paramref name="inspectedByTheRead"/> names: the identity
    /// <see cref="Read"/> took from the handle it found the file unreadable
    /// through. Returns an identifier when the file at the name turns out to
    /// hold one by now; otherwise null, and the caller looks again.
    ///
    /// <para>The name is opened ONCE, asking for delete access and sharing
    /// everything, and that one handle is compared with the identity
    /// inspected, read again (still no identifier in it), and renamed aside
    /// through (<c>SetFileInformationByHandle</c>, <c>FileRenameInfo</c>, never
    /// replacing a name). So what is moved is provably the file inspected,
    /// wherever another process has moved it meanwhile, and a good file
    /// another process made at the name is never touched. A creator still
    /// writing its file holds it with no sharing, so the open fails and
    /// nothing moves; nothing writes into a finished identifier file.</para>
    ///
    /// <para>Rejected, by the W1 review's two rounds: taking the identity at
    /// the moment of the call (it compared the file with itself, and a good
    /// identifier was set aside 3,000 times of 3,000 under a concurrent
    /// maker); comparing by path and then moving by path (another process
    /// could set the damaged file aside and make a good one between the two,
    /// and the good one was moved; a move back fails once a third has made its
    /// own, stranding every step under the good identifier).</para>
    /// </summary>
    internal string? SetAside((ulong Volume, ulong Index)? inspectedByTheRead)
    {
        if (inspectedByTheRead is not { } inspected) return null;   // the read opened nothing: nothing to set aside
        string aside = FilePath + ".unreadable-" + Guid.NewGuid().ToString("D");
        using SafeFileHandle handle = CreateFileW(LongPath(FilePath), GenericRead | DeleteAccess,
            FileShareRead | FileShareWrite | FileShareDelete, IntPtr.Zero, OpenExisting, 0, IntPtr.Zero);
        if (handle.IsInvalid) return null;   // gone, held with no sharing (a creator at work), or denied: look again
        if (IdentityOf(handle) != inspected) return null;   // another process replaced it: look again

        byte[] bytes;
        try
        {
            long length = RandomAccess.GetLength(handle);
            if (length > 4096) length = 4096;   // an identifier file is 37 bytes; more is damaged whatever it holds
            bytes = new byte[length];
            int read = 0;
            while (read < bytes.Length)
            {
                int got = RandomAccess.Read(handle, bytes.AsSpan(read), read);
                if (got == 0) break;
                read += got;
            }
        }
        catch (IOException) { return null; }
        catch (UnauthorizedAccessException) { return null; }
        if (IdentifierIn(new UTF8Encoding(false, false).GetString(bytes)) is { } held) return held;   // it holds one by now

        _betweenCheckAndRename?.Invoke();
        RenameThrough(handle, Path.GetFullPath(aside));
        return null;
    }

    // ---- Windows -------------------------------------------------------------

    /// <summary>The file's volume serial and 64-bit index: the same file on its volume, whatever its name.</summary>
    internal static (ulong Volume, ulong Index)? FileIdentity(string path)
    {
        try
        {
            using SafeFileHandle handle = File.OpenHandle(path, FileMode.Open, FileAccess.Read, FileShare.ReadWrite | FileShare.Delete);
            return IdentityOf(handle);
        }
        catch { return null; }
    }

    /// <summary>The volume serial and 64-bit index of the file an open handle is on.</summary>
    private static (ulong Volume, ulong Index)? IdentityOf(SafeFileHandle handle)
    {
        if (!GetFileInformationByHandle(handle, out ByHandleFileInformation info)) return null;
        return (info.VolumeSerialNumber, ((ulong)info.FileIndexHigh << 32) | info.FileIndexLow);
    }

    /// <summary>A raw P/Invoke path is not given <c>\\?\</c> by .NET: past 259 characters it must be.</summary>
    private static string LongPath(string path) =>
        path.Length < 260 || path.StartsWith(@"\\?\", StringComparison.Ordinal) ? path
        : path.StartsWith(@"\\", StringComparison.Ordinal) ? @"\\?\UNC\" + path[2..] : @"\\?\" + path;

    [StructLayout(LayoutKind.Sequential)]
    private struct ByHandleFileInformation
    {
        public uint FileAttributes;
        public System.Runtime.InteropServices.ComTypes.FILETIME CreationTime;
        public System.Runtime.InteropServices.ComTypes.FILETIME LastAccessTime;
        public System.Runtime.InteropServices.ComTypes.FILETIME LastWriteTime;
        public uint VolumeSerialNumber;
        public uint FileSizeHigh;
        public uint FileSizeLow;
        public uint NumberOfLinks;
        public uint FileIndexHigh;
        public uint FileIndexLow;
    }

    [DllImport("kernel32.dll", SetLastError = true)]
    private static extern bool GetFileInformationByHandle(SafeFileHandle file, out ByHandleFileInformation information);

    [DllImport("kernel32.dll", SetLastError = true, CharSet = CharSet.Unicode)]
    private static extern bool CreateHardLinkW(string fileName, string existingFileName, IntPtr securityAttributes);

    private const uint GenericRead = 0x80000000;
    private const uint DeleteAccess = 0x00010000;
    private const uint FileShareRead = 1, FileShareWrite = 2, FileShareDelete = 4;
    private const uint OpenExisting = 3;
    private const int FileRenameInfoClass = 3;

    [DllImport("kernel32.dll", SetLastError = true, CharSet = CharSet.Unicode)]
    private static extern SafeFileHandle CreateFileW(string fileName, uint desiredAccess, uint shareMode, IntPtr securityAttributes,
                                                     uint creationDisposition, uint flagsAndAttributes, IntPtr templateFile);

    [DllImport("kernel32.dll", SetLastError = true)]
    private static extern bool SetFileInformationByHandle(SafeFileHandle file, int informationClass, IntPtr information, uint size);

    /// <summary>
    /// Renames the file an open handle is on to <paramref name="newPath"/> (a
    /// full path), never replacing a file there: <c>FILE_RENAME_INFO</c> is a
    /// replace flag (padded to a pointer), the root directory (none), the
    /// name's length in bytes, then the name. False when it is refused.
    /// </summary>
    private static bool RenameThrough(SafeFileHandle handle, string newPath)
    {
        string name = LongPath(newPath);
        int rootOffset = IntPtr.Size;                 // after the 4-byte flag, aligned to a pointer
        int lengthOffset = rootOffset + IntPtr.Size;
        int nameOffset = lengthOffset + sizeof(uint);
        int nameBytes = name.Length * sizeof(char);
        int size = nameOffset + nameBytes + sizeof(char);
        IntPtr buffer = Marshal.AllocHGlobal(size);
        try
        {
            for (int offset = 0; offset < size; offset++) Marshal.WriteByte(buffer, offset, 0);   // no replace, no root
            Marshal.WriteInt32(buffer, lengthOffset, nameBytes);
            Marshal.Copy(name.ToCharArray(), 0, buffer + nameOffset, name.Length);
            return SetFileInformationByHandle(handle, FileRenameInfoClass, buffer, (uint)size);
        }
        finally
        {
            Marshal.FreeHGlobal(buffer);
        }
    }
}
