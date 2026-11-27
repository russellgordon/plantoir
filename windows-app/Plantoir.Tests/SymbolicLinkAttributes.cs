using System.Runtime.InteropServices;
using System.Text;
using Microsoft.Win32.SafeHandles;

namespace Plantoir.Tests;

/// <summary>
/// Whether this account may make a symbolic link (Developer Mode, or an
/// administrator's token): null when it may, else why not. The VMs have
/// Developer Mode off (Russell, 2026-11-26), so there every test that needs a
/// symbolic link holding a target as written is SKIPPED with this reason; a
/// junction holds only an absolute target, so it cannot stand in.
/// </summary>
internal static class UndoSymbolicLinks
{
    private static readonly Lazy<string?> WhyNot = new(Probe);

    internal static string? CannotBeMade => WhyNot.Value;

    private static string? Probe()
    {
        if (!OperatingSystem.IsWindows()) return "Windows only";
        string probe = Path.Combine(Path.GetTempPath(), "plantoir-undo-symlink-probe-" + Guid.NewGuid().ToString("N"));
        try
        {
            Directory.CreateSymbolicLink(probe, "../library");
            return null;
        }
        catch (Exception error)
        {
            return "this account cannot make a symbolic link (Developer Mode is off, as in the VMs: " + error.Message.Trim()
                 + "), so a link holding its target as written (../library) cannot be laid on the disk here";
        }
        finally
        {
            try { if (Directory.Exists(probe)) Directory.Delete(probe); } catch { }
        }
    }
}

/// <summary>A fact that needs a symbolic link: SKIPPED, saying why, where this account cannot make one.</summary>
public sealed class SymbolicLinkFactAttribute : FactAttribute
{
    public SymbolicLinkFactAttribute()
    {
        if (UndoSymbolicLinks.CannotBeMade is { } why) Skip = why;
    }
}

/// <summary>A theory whose rows each need a symbolic link: SKIPPED, saying why, where this account cannot make one.</summary>
public sealed class SymbolicLinkTheoryAttribute : TheoryAttribute
{
    public SymbolicLinkTheoryAttribute()
    {
        if (UndoSymbolicLinks.CannotBeMade is { } why) Skip = why;
    }
}

/// <summary>A fact that sets a reparse point of its own on a file: SKIPPED, saying why, where the volume or this account refuses it.</summary>
public sealed class ReparsePointFactAttribute : FactAttribute
{
    private static readonly Lazy<string?> WhyNot = new(() =>
    {
        if (!OperatingSystem.IsWindows()) return "Windows only";
        string probe = Path.Combine(Path.GetTempPath(), "plantoir-undo-reparse-probe-" + Guid.NewGuid().ToString("N"));
        try { return UndoReparsePoints.Make(probe, UndoReparsePoints.NotALink, new byte[16]); }
        finally { try { File.Delete(probe); } catch { } }
    });

    public ReparsePointFactAttribute()
    {
        if (WhyNot.Value is { } why) Skip = "a reparse point of the test's own cannot be set here: " + why;
    }
}

/// <summary>
/// A reparse point set on an empty file by <c>FSCTL_SET_REPARSE_POINT</c>, for
/// the two kinds no junction or symbolic link gives: WSL's own link
/// (<c>IO_REPARSE_TAG_LX_SYMLINK</c>, a name surrogate whose target .NET does
/// not read) and a tag that is not a name surrogate (<c>IO_REPARSE_TAG_DEDUP</c>,
/// standing in for OneDrive's, whose filter refuses a tag set by hand).
/// </summary>
internal static class UndoReparsePoints
{
    internal const uint WslLink = 0xA000001D;
    internal const uint NotALink = 0x80000013;

    /// <summary>WSL's link data: a version (2), then the target as UTF-8.</summary>
    internal static byte[] WslLinkData(string target)
    {
        byte[] text = Encoding.UTF8.GetBytes(target);
        byte[] data = new byte[4 + text.Length];
        BitConverter.GetBytes(2u).CopyTo(data, 0);
        text.CopyTo(data, 4);
        return data;
    }

    /// <summary>Makes an empty file at <paramref name="file"/> and sets the reparse point on it: null when made, else why not.</summary>
    internal static string? Make(string file, uint tag, byte[] data)
    {
        Directory.CreateDirectory(Path.GetDirectoryName(file)!);
        File.WriteAllBytes(file, []);
        using SafeFileHandle handle = CreateFileW(file, GenericWrite, 0, IntPtr.Zero, OpenExisting, BackupSemantics | OpenReparsePoint, IntPtr.Zero);
        if (handle.IsInvalid) return "the file could not be opened (" + Marshal.GetLastWin32Error() + ")";
        byte[] buffer = new byte[8 + data.Length];
        BitConverter.GetBytes(tag).CopyTo(buffer, 0);
        BitConverter.GetBytes((ushort)data.Length).CopyTo(buffer, 4);
        data.CopyTo(buffer, 8);
        if (!DeviceIoControl(handle, SetReparsePoint, buffer, buffer.Length, IntPtr.Zero, 0, out _, IntPtr.Zero))
            return "FSCTL_SET_REPARSE_POINT answered " + Marshal.GetLastWin32Error();
        return null;
    }

    private const uint GenericWrite = 0x40000000;
    private const uint OpenExisting = 3;
    private const uint BackupSemantics = 0x02000000;
    private const uint OpenReparsePoint = 0x00200000;
    private const uint SetReparsePoint = 0x000900A4;

    [DllImport("kernel32.dll", CharSet = CharSet.Unicode, SetLastError = true)]
    private static extern SafeFileHandle CreateFileW(string name, uint access, uint share, IntPtr security, uint disposition, uint flags, IntPtr template);

    [DllImport("kernel32.dll", SetLastError = true)]
    private static extern bool DeviceIoControl(SafeFileHandle device, uint code, byte[] input, int inputSize, IntPtr output, int outputSize, out int returned, IntPtr overlapped);
}
