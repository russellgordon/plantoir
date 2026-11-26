using System.Runtime.InteropServices;
using Microsoft.Win32.SafeHandles;

namespace Plantoir.Core.Undo;

/// <summary>
/// Which file an OPEN handle is (#899 W2a, reading on): the volume's serial
/// number and the 64-bit file index, from <c>GetFileInformationByHandle</c> on
/// the handle itself, never looked up by path (the W1 review's low on
/// <c>FolderIdentityFile</c>: a path can name another file by the time it is
/// looked at again).
/// </summary>
internal static class UndoFileIdentity
{
    /// <summary>The file's identity, or null where the system cannot say (not Windows, or the call failed).</summary>
    internal static (uint Volume, ulong Index)? Of(FileStream stream) => Of(stream.SafeFileHandle);

    /// <summary>The same, for a handle opened by other means (the swap's kept original, #899 W3).</summary>
    internal static (uint Volume, ulong Index)? Of(SafeFileHandle handle)
    {
        if (!OperatingSystem.IsWindows() || handle.IsInvalid) return null;
        if (!GetFileInformationByHandle(handle, out ByHandleFileInformation information)) return null;
        return (information.VolumeSerialNumber, ((ulong)information.FileIndexHigh << 32) | information.FileIndexLow);
    }

    /// <summary>
    /// The identity of the item at <paramref name="fullPath"/> itself, a link
    /// never followed (opened with no access, for its attributes only, every
    /// sharing allowed), or null when nothing is there or it cannot be opened.
    /// Two spellings of one place on NTFS give the same identity (measured on
    /// the PC, #899 W8-5: <c>Media</c> and <c>media</c> both
    /// <c>8a81f26a:017f00000023b811</c>, before and after the rename).
    /// </summary>
    internal static (uint Volume, ulong Index)? OfPlace(string fullPath)
    {
        if (!OperatingSystem.IsWindows()) return null;
        using SafeFileHandle handle = CreateFileW(UndoLock.LongPath(fullPath), 0, ShareAll, IntPtr.Zero, OpenExisting,
                                                  BackupSemantics | OpenReparsePoint, IntPtr.Zero);
        return Of(handle);
    }

    /// <summary>How many names the file an open handle is has on its volume (hard links), or null where the system cannot say.</summary>
    internal static uint? LinksOf(SafeFileHandle handle)
    {
        if (!OperatingSystem.IsWindows() || handle.IsInvalid) return null;
        if (!GetFileInformationByHandle(handle, out ByHandleFileInformation information)) return null;
        return information.NumberOfLinks;
    }

    /// <summary>
    /// Whether a file index stays a file's for its life on the volume that
    /// holds <paramref name="folder"/>: NTFS and ReFS. FAT and exFAT number a
    /// file by where its entry sits, and a network share answers for a server
    /// we cannot see, so those are read whole (safe, only slower).
    /// </summary>
    internal static bool IsStableHere(string folder)
    {
        if (!OperatingSystem.IsWindows()) return false;
        try
        {
            string full = Path.GetFullPath(folder);
            if (full.StartsWith(@"\\", StringComparison.Ordinal)) return false;
            // The volume the folder itself is on, junctions and mount points
            // followed (W2a's review, LOW 6), not the drive letter's: a state
            // folder reached through a junction onto an exFAT stick or a share
            // must read whole.
            string? format = UndoPlaces.FileSystemOf(full);
            if (format is null) return false;
            return string.Equals(format, "NTFS", StringComparison.OrdinalIgnoreCase)
                || string.Equals(format, "ReFS", StringComparison.OrdinalIgnoreCase);
        }
        catch (Exception error) when (error is IOException or UnauthorizedAccessException or ArgumentException)
        {
            return false;
        }
    }

    [StructLayout(LayoutKind.Sequential)]
    private struct ByHandleFileInformation
    {
        public uint FileAttributes;
        public uint CreationTimeLow, CreationTimeHigh;
        public uint LastAccessTimeLow, LastAccessTimeHigh;
        public uint LastWriteTimeLow, LastWriteTimeHigh;
        public uint VolumeSerialNumber;
        public uint FileSizeHigh, FileSizeLow;
        public uint NumberOfLinks;
        public uint FileIndexHigh, FileIndexLow;
    }

    private const uint ShareAll = 0x7;
    private const uint OpenExisting = 3;
    private const uint BackupSemantics = 0x02000000;
    private const uint OpenReparsePoint = 0x00200000;

    [DllImport("kernel32.dll", CharSet = CharSet.Unicode, SetLastError = true)]
    private static extern SafeFileHandle CreateFileW(string name, uint access, uint share, IntPtr security, uint disposition, uint flags, IntPtr template);

    [DllImport("kernel32.dll", SetLastError = true)]
    private static extern bool GetFileInformationByHandle(SafeFileHandle file, out ByHandleFileInformation information);
}
