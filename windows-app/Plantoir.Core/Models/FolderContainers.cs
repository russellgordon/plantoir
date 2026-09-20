using System.ComponentModel;
using System.Runtime.InteropServices;
using System.Security.Cryptography;
using System.Text;
using Microsoft.Win32.SafeHandles;

namespace Plantoir.Core.Models;

/// <summary>
/// Names the Docker container for a working folder and frees resources when
/// folders and the app are done with them.
///
/// The name must agree BYTE FOR BYTE with what the .ps1 launchers derive:
/// SHA-256 of the folder's PHYSICAL path (true on-disk casing via
/// GetFinalPathNameByHandle, symlinks resolved) plus a trailing newline,
/// first 8 lowercase hex characters, prefixed "teaching-quartz-".
/// </summary>
public static class FolderContainers
{
    public static string ContainerName(string folderPath) =>
        "teaching-quartz-" + FolderIdentifier(folderPath);

    /// <summary>
    /// The eight hex characters that identify a working folder — SHA-256 over
    /// its PHYSICAL path plus a trailing newline, which is exactly
    /// <c>pwd -P | shasum -a 256 | cut -c1-8</c> and exactly what
    /// <c>preview.ps1</c> computes as <c>$WORKDIR_ID</c>.
    ///
    /// <para>Named separately because it identifies the folder for TWO things
    /// that must agree: the container (historically) and the folder its built
    /// websites are kept in (<see cref="BuildOutputLocation"/>). Deriving it
    /// twice is how the two would come apart, and CLAUDE.md warns about this
    /// derivation by name.</para>
    /// </summary>
    public static string FolderIdentifier(string folderPath)
    {
        string physical = PhysicalPath(folderPath);
        byte[] hash = SHA256.HashData(Encoding.UTF8.GetBytes(physical + "\n"));
        return Convert.ToHexString(hash).ToLowerInvariant()[..8];
    }

    /// <summary>
    /// The path with true on-disk casing and symlinks resolved — the same
    /// value the launchers' Get-PhysicalPath produces. Falls back to a plain
    /// full path when the folder cannot be opened.
    /// </summary>
    public static string PhysicalPath(string path)
    {
        try
        {
            using SafeFileHandle handle = CreateFileW(path, 0,
                FILE_SHARE_READ | FILE_SHARE_WRITE | FILE_SHARE_DELETE,
                nint.Zero, OPEN_EXISTING, FILE_FLAG_BACKUP_SEMANTICS, nint.Zero);
            if (!handle.IsInvalid)
            {
                var buffer = new StringBuilder(4096);
                uint length = GetFinalPathNameByHandleW(handle, buffer, (uint)buffer.Capacity, 0);
                if (length > 0)
                {
                    string result = buffer.ToString();
                    if (result.StartsWith(@"\\?\UNC\", StringComparison.Ordinal)) result = @"\\" + result[8..];
                    else if (result.StartsWith(@"\\?\", StringComparison.Ordinal)) result = result[4..];
                    return result.TrimEnd('\\');
                }
            }
        }
        catch (Exception e) when (e is Win32Exception or IOException) { }
        return Path.GetFullPath(path).TrimEnd('\\');
    }

    /// <summary>Hook for tests: replaces the real shell-out with a recorder.</summary>
    public static Action<string[]>? CommandRunnerOverride { get; set; }

    /// <summary>
    /// Stops a folder's container when its last window closes. `stop`, never
    /// `rm` — a restart takes about a second. -t 2 because the container's
    /// main process is an idle `tail` that ignores SIGTERM.
    /// </summary>
    public static void StopContainer(string folderPath)
    {
        // A native-toolchain build has no containers to stop, and on a
        // machine with no WSL the stub wsl.exe invoked interactively offers
        // to INSTALL it — precisely the machinery this design removed.
        if (Scripting.NativeRuntime.Directory is not null) return;
        string name = ContainerName(folderPath);
        RunDetached("wsl", "-e", "docker", "stop", "-t", "2", name);
    }

    /// <summary>
    /// Quit-time release: stop this app's containers, then shut the WSL
    /// distro down ONLY if nothing at all is left running in Docker — WSL is
    /// shared, and another project's containers must never lose their engine.
    /// The next preview restarts everything on its own.
    /// </summary>
    public static void ReleaseEverythingAtQuit(IEnumerable<string> folderPaths)
    {
        // Same rule as StopContainer: nothing to release on a native build.
        if (Scripting.NativeRuntime.Directory is not null) return;
        var names = folderPaths.Select(ContainerName).Distinct().ToList();
        string stopPart = names.Count > 0
            ? $"docker stop -t 2 {string.Join(' ', names)} >/dev/null 2>&1; "
            : "";
        // The emptiness check runs AFTER our own containers stop, or it could
        // never pass. `wsl --terminate` must come from the Windows side, so
        // the inner script only reports; the outer decides.
        string script = stopPart + "if [ -z \"$(docker ps -q 2>/dev/null)\" ]; then echo IDLE; fi";
        RunDetached("powershell", "-NoProfile", "-WindowStyle", "Hidden", "-Command",
            $"$out = wsl -u root -e sh -c '{script}'; " +
            "if ($out -match 'IDLE') { wsl --terminate (wsl -l -q | Select-Object -First 1) }");
    }

    private static void RunDetached(params string[] command)
    {
        if (CommandRunnerOverride is not null) { CommandRunnerOverride(command); return; }
        var info = new System.Diagnostics.ProcessStartInfo(command[0])
        {
            UseShellExecute = false,
            CreateNoWindow = true,
        };
        foreach (string arg in command.Skip(1)) info.ArgumentList.Add(arg);
        try { System.Diagnostics.Process.Start(info); } catch { }
    }

    private const uint FILE_SHARE_READ = 1, FILE_SHARE_WRITE = 2, FILE_SHARE_DELETE = 4;
    private const uint OPEN_EXISTING = 3;
    private const uint FILE_FLAG_BACKUP_SEMANTICS = 0x02000000;

    [DllImport("kernel32.dll", SetLastError = true, CharSet = CharSet.Unicode)]
    private static extern SafeFileHandle CreateFileW(string lpFileName, uint dwDesiredAccess, uint dwShareMode,
        nint lpSecurityAttributes, uint dwCreationDisposition, uint dwFlagsAndAttributes, nint hTemplateFile);

    [DllImport("kernel32.dll", SetLastError = true, CharSet = CharSet.Unicode)]
    private static extern uint GetFinalPathNameByHandleW(SafeFileHandle hFile, StringBuilder lpszFilePath,
        uint cchFilePath, uint dwFlags);
}
