using System;
using System.Collections.Generic;
using System.Linq;
using System.Runtime.InteropServices;

namespace Plantoir.Core.Scripting;

/// <summary>
/// Whether this process was started with its std handles redirected (#155).
/// The app is a GUI process and normally has none; started by a test host
/// with pipes for stdio, it passes them on to every ConPTY child, whose output
/// then never reaches the console Plantoir reads — preview, publish and setup
/// show nothing. One line in <c>startup.log</c> says so for the DEVELOPER; it
/// is not a trail event and a teacher never sees it.
/// </summary>
public static class StdioState
{
    public const int StdInput = -10;
    public const int StdOutput = -11;
    public const int StdError = -12;

    public const uint FileTypeUnknown = 0;
    public const uint FileTypeDisk = 1;
    public const uint FileTypeChar = 2;
    public const uint FileTypePipe = 3;

    /// <summary>
    /// The startup.log line, or null when no handle is a pipe or a file.
    /// <paramref name="fileType"/> answers GetFileType for a std handle id —
    /// a parameter so the rule is tested without redirecting anything.
    /// </summary>
    public static string? Describe(Func<int, uint> fileType)
    {
        var named = new List<(string Name, int Id)> { ("stdout", StdOutput), ("stderr", StdError), ("stdin", StdInput) };
        var redirected = named
            .Select(n => (n.Name, Type: fileType(n.Id)))
            .Where(n => n.Type is FileTypePipe or FileTypeDisk)
            .Select(n => $"{n.Name}={(n.Type == FileTypePipe ? "pipe" : "disk")}")
            .ToList();
        return redirected.Count == 0
            ? null
            : $"Started with its output redirected ({string.Join(", ", redirected)}); " +
              "preview, publish and setup will not show their output in this run.";
    }

    /// <summary>GetFileType of this process's std handle (FILE_TYPE_UNKNOWN when there is none).</summary>
    public static uint FileTypeOf(int stdHandleId)
    {
        nint handle = GetStdHandle(stdHandleId);
        return handle == 0 || handle == -1 ? FileTypeUnknown : GetFileType(handle);
    }

    [DllImport("kernel32.dll")]
    private static extern nint GetStdHandle(int nStdHandle);

    [DllImport("kernel32.dll")]
    private static extern uint GetFileType(nint hFile);
}
