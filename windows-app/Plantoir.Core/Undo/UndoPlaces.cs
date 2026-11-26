using System.Runtime.InteropServices;
using System.Text;
using Microsoft.Win32.SafeHandles;

namespace Plantoir.Core.Undo;

/// <summary>
/// Where a place REALLY is, its links, junctions and mount points followed by
/// the system itself (#899 W2b): the final path of an open handle
/// (<c>GetFinalPathNameByHandleW</c>) and the file system of the volume the
/// handle is on (<c>GetVolumeInformationByHandleW</c>). Asked of a handle, never
/// worked out from the spelling of a path, because a folder on the path may be
/// a junction to somewhere else (<c>rule.stagedThenSwapped</c>: "every place a
/// step names is checked to be inside its working folder, links resolved").
/// </summary>
internal static class UndoPlaces
{
    /// <summary>
    /// The final path of <paramref name="path"/>, or of its deepest folder that
    /// is there when it is not, in the system's own <c>\\?\</c> form
    /// (<c>\\?\C:\…</c>, or <c>\\?\UNC\server\share\…</c> for a network place),
    /// with the rest of the path appended as spelled. Null when nothing on the
    /// path can be opened.
    /// </summary>
    internal static string? FinalPath(string path)
    {
        if (!OperatingSystem.IsWindows()) return null;
        string full = Path.GetFullPath(path);
        string rest = "";
        string? probe = full;
        while (probe is not null)
        {
            if (FinalPathOfExisting(probe) is { } final)
                return rest.Length == 0 ? final : final.TrimEnd('\\') + rest;
            string? parent = Path.GetDirectoryName(probe);
            if (parent is null) return null;
            rest = probe[parent.TrimEnd('\\').Length..] + rest;
            probe = parent;
        }
        return null;
    }

    /// <summary>
    /// Whether <paramref name="relative"/> (forward slashes) under
    /// <paramref name="root"/> leads to a place inside the root once every link
    /// and junction on the way is followed: the final path of its deepest
    /// existing part starts with the root's own final path. A place that
    /// cannot be resolved at all is not inside.
    /// </summary>
    internal static bool StaysInside(string root, string relative)
    {
        string? rootFinal = FinalPath(root);
        string? placeFinal = FinalPath(Path.Combine(root, relative.Replace('/', Path.DirectorySeparatorChar)));
        if (rootFinal is null || placeFinal is null) return false;
        string prefix = rootFinal.TrimEnd('\\') + "\\";
        // NTFS names are compared without regard to case, as the volume does.
        return placeFinal.StartsWith(prefix, StringComparison.OrdinalIgnoreCase)
            || string.Equals(placeFinal.TrimEnd('\\'), rootFinal.TrimEnd('\\'), StringComparison.OrdinalIgnoreCase);
    }

    /// <summary>
    /// The first of <paramref name="op"/>'s places (<see cref="UndoOp.PathsNamed"/>:
    /// path, from, to) that no longer stays inside the working folder, links
    /// resolved (<see cref="StaysInside"/>), or null when every one does: the
    /// one place a leaves-the-folder refusal names, at the plan and again just
    /// before each change, never the other side of a move (the mac's
    /// <c>UndoCheck.placeLeavingTheFolder</c>, U4b2-2; #899 W8-1).
    /// </summary>
    internal static string? FirstPlaceLeadingOut(string root, UndoOp op)
    {
        foreach (string place in op.PathsNamed)
        {
            if (!StaysInside(root, place, op)) return place;
        }
        return null;
    }

    /// <summary>
    /// <see cref="StaysInside(string, string)"/> for a place <paramref name="op"/>
    /// names (the mac's <c>staysInside(_:_:namedBy:)</c>, U4b2-14; #899 W8-6).
    /// A link's move names the link itself at its <c>from</c> and <c>to</c>,
    /// so there the link is never followed: only the folder above it is
    /// resolved, and a link leading out of the working folder, or nowhere,
    /// is moved as a link like any other.
    /// </summary>
    internal static bool StaysInside(string root, string relative, UndoOp op)
    {
        if (op.LinkSha is null || (relative != op.From && relative != op.To)) return StaysInside(root, relative);
        if (!UndoPath.IsWithinTheRules(relative)) return false;
        int slash = relative.LastIndexOf('/');
        return slash < 0 || StaysInside(root, relative[..slash]);
    }

    /// <summary>
    /// The file system of the volume <paramref name="folder"/> (or its deepest
    /// existing parent) is REALLY on, after junctions and mount points (W2a's
    /// review, LOW 6: the drive letter's file system is not the folder's when a
    /// junction leads onto another volume); "network" for a place reached
    /// through a share. Null when it cannot be told.
    /// </summary>
    internal static string? FileSystemOf(string folder)
    {
        if (!OperatingSystem.IsWindows()) return null;
        string? probe = Path.GetFullPath(folder);
        while (probe is not null)
        {
            using SafeFileHandle handle = OpenToLookAt(probe);
            if (!handle.IsInvalid)
            {
                if (FinalPathOf(handle) is { } final && final.StartsWith(@"\\?\UNC\", StringComparison.OrdinalIgnoreCase)) return "network";
                var name = new StringBuilder(64);
                if (!GetVolumeInformationByHandleW(handle, null, 0, out _, out _, out _, name, name.Capacity)) return null;
                return name.ToString();
            }
            probe = Path.GetDirectoryName(probe);
        }
        return null;
    }

    private static string? FinalPathOfExisting(string path)
    {
        using SafeFileHandle handle = OpenToLookAt(path);
        return handle.IsInvalid ? null : FinalPathOf(handle);
    }

    private static string? FinalPathOf(SafeFileHandle handle)
    {
        var buffer = new StringBuilder(1024);
        uint length = GetFinalPathNameByHandleW(handle, buffer, (uint)buffer.Capacity, 0);
        if (length == 0) return null;
        if (length >= buffer.Capacity)
        {
            buffer = new StringBuilder((int)length + 1);
            length = GetFinalPathNameByHandleW(handle, buffer, (uint)buffer.Capacity, 0);
            if (length == 0 || length >= buffer.Capacity) return null;
        }
        return buffer.ToString();
    }

    /// <summary>A handle that only reads attributes, sharing everything, folders included (backup semantics): it stands in nobody's way.</summary>
    private static SafeFileHandle OpenToLookAt(string path) =>
        CreateFileW(UndoLock.LongPath(path), FileReadAttributes, FileShareAll, IntPtr.Zero, OpenExisting, FileFlagBackupSemantics, IntPtr.Zero);

    private const uint FileReadAttributes = 0x80;
    private const uint FileShareAll = 0x7;
    private const uint OpenExisting = 3;
    private const uint FileFlagBackupSemantics = 0x02000000;

    [DllImport("kernel32.dll", CharSet = CharSet.Unicode, SetLastError = true)]
    private static extern SafeFileHandle CreateFileW(string name, uint access, uint share, IntPtr security, uint disposition, uint flags, IntPtr template);

    [DllImport("kernel32.dll", CharSet = CharSet.Unicode, SetLastError = true)]
    private static extern uint GetFinalPathNameByHandleW(SafeFileHandle file, StringBuilder path, uint length, uint flags);

    [DllImport("kernel32.dll", CharSet = CharSet.Unicode, SetLastError = true)]
    private static extern bool GetVolumeInformationByHandleW(SafeFileHandle file, StringBuilder? volumeName, int volumeNameSize,
                                                             out uint serial, out uint maximumComponent, out uint flags,
                                                             StringBuilder fileSystemName, int fileSystemNameSize);
}
