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
    internal static (uint Volume, ulong Index)? Of(FileStream stream)
    {
        if (!OperatingSystem.IsWindows()) return null;
        if (!GetFileInformationByHandle(stream.SafeFileHandle, out ByHandleFileInformation information)) return null;
        return (information.VolumeSerialNumber, ((ulong)information.FileIndexHigh << 32) | information.FileIndexLow);
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

    [DllImport("kernel32.dll", SetLastError = true)]
    private static extern bool GetFileInformationByHandle(SafeFileHandle file, out ByHandleFileInformation information);
}
