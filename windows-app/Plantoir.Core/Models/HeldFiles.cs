using System.Runtime.InteropServices;
using Microsoft.Win32.SafeHandles;

namespace Plantoir.Core.Models;

/// <summary>
/// A small file another program has open for a moment (a virus scanner, a
/// sync client, an editor, a build's Python, a second Plantoir window,
/// <c>plantoir-mcp</c>): asked again for a short, fixed time, then the truth
/// (#953, #874). On the mac a rename over an open file succeeds; on Windows it
/// is refused while the file is held, so Windows imitates the mac's OUTCOME:
/// the write lands, or it is reported, never lost in silence.
/// </summary>
/// <remarks>
/// <para><b>One bound, not tuned.</b> <see cref="Pauses"/> is the shape
/// already accepted for the same rename in <c>ObsidianFigureAddOns.Retrying</c>
/// (50, 100, 200, 400 ms, about 0.75 s; #1016's inventory, row 45, "KEEP
/// (bounded)"). When it is spent, the caller is told at once
/// (<see cref="FileInUseException"/>). <c>Retrying</c>,
/// <c>ProblemsAcknowledgements.Patiently</c>, <c>ToolchainReadiness</c>'s
/// marker retry and <c>UndoJournal</c>'s are the ones that should share this
/// helper next; they were left alone in this piece.</para>
///
/// <para><b>Only a hold is asked again.</b> A sharing or lock violation is a
/// hold. An access-denied RENAME is a hold only when <see cref="IsHeld"/>
/// says so: the target (or the temporary) opened for delete access with full
/// sharing meets a sharing violation, because another program has it open
/// without delete sharing. Access denied there too means a permission (a deny
/// rule, a read-only file), which is said as the system says it and never
/// asked again. The pause is a parameter, so a test drives the bound without
/// sleeping and proves "not a hold" by counting zero pauses.</para>
/// </remarks>
public static class HeldFiles
{
    /// <summary>The pauses between tries: four, about 0.75 s in all.</summary>
    public static readonly IReadOnlyList<int> Pauses = [50, 100, 200, 400];

    /// <summary>The pause the app uses: the thread waits that many milliseconds.</summary>
    public static readonly Action<int> Sleep = milliseconds => Thread.Sleep(milliseconds);

    private static readonly AsyncLocal<Action<int>?> PauseInThisFlow = new();

    /// <summary>
    /// A test's own pause for every held-file call made in its flow (and only
    /// there: an <see cref="AsyncLocal{T}"/>, so a test running beside it is
    /// not touched), for the callers that do not take a pause themselves.
    /// Dispose puts the app's pause back.
    /// </summary>
    internal static IDisposable PausingWith(Action<int> pause)
    {
        var before = PauseInThisFlow.Value;
        PauseInThisFlow.Value = pause;
        return new Restore(() => PauseInThisFlow.Value = before);
    }

    private sealed class Restore(Action undo) : IDisposable
    {
        public void Dispose() => undo();
    }

    private static void PauseFor(Action<int>? pause, int milliseconds) =>
        (pause ?? PauseInThisFlow.Value ?? Sleep)(milliseconds);

    private const int SharingViolation = 32;
    private const int LockViolation = 33;

    /// <summary>The words a teacher reads for a held file; the Undo line's own phrase, "is in use by another program".</summary>
    public static string InUseSentence(string fileName) =>
        fileName + " is in use by another program, so nothing was changed.";

    /// <summary>What a read found: the bytes, nothing there, or a hold that outlasted the bound.</summary>
    public enum ReadOutcome { Read, NotThere, CouldNotReadNow }

    /// <summary>A read's answer; <see cref="Data"/> is set only for <see cref="ReadOutcome.Read"/>.</summary>
    public readonly record struct FileBytes(ReadOutcome Outcome, byte[]? Data);

    /// <summary>True for a sharing or lock violation, the system's words for "another program has it open".</summary>
    public static bool IsSharingViolation(Exception error) =>
        error is IOException && (error.HResult & unchecked((int)0xFFFF0000)) == unchecked((int)0x80070000)
        && (error.HResult & 0xFFFF) is SharingViolation or LockViolation;

    /// <summary>
    /// Reads a whole file, asking again while it is held. A file that is not
    /// there is <see cref="ReadOutcome.NotThere"/>; one still held after the
    /// bound is <see cref="ReadOutcome.CouldNotReadNow"/>, never "empty". Any
    /// other refusal (a permission) is thrown as the system raised it.
    /// </summary>
    public static FileBytes ReadBytes(string path, Action<int>? pause = null)
    {
        for (int attempt = 0; ; attempt++)
        {
            try
            {
                if (!File.Exists(path)) return new FileBytes(ReadOutcome.NotThere, null);
                return new FileBytes(ReadOutcome.Read, File.ReadAllBytes(path));
            }
            catch (FileNotFoundException) { return new FileBytes(ReadOutcome.NotThere, null); }
            catch (DirectoryNotFoundException) { return new FileBytes(ReadOutcome.NotThere, null); }
            catch (Exception error) when (IsSharingViolation(error) || (error is UnauthorizedAccessException && IsHeld(path)))
            {
                if (attempt >= Pauses.Count) return new FileBytes(ReadOutcome.CouldNotReadNow, null);
                PauseFor(pause, Pauses[attempt]);
            }
        }
    }

    /// <summary>
    /// Runs <paramref name="replace"/> (the one rename of a temporary onto
    /// <paramref name="target"/>), asking again while either file is held.
    /// Still held after the bound: <see cref="FileInUseException"/>, naming
    /// the target. A refusal that is not a hold is thrown at once, unchanged.
    /// The caller removes its temporary on every failure.
    /// </summary>
    public static void Replace(string temporary, string target, Action replace, Action<int>? pause = null)
    {
        for (int attempt = 0; ; attempt++)
        {
            try { replace(); return; }
            catch (Exception error) when (IsSharingViolation(error)
                                          || (error is UnauthorizedAccessException or IOException && (IsHeld(target) || IsHeld(temporary))))
            {
                if (attempt >= Pauses.Count) throw new FileInUseException(Path.GetFileName(target), error);
                PauseFor(pause, Pauses[attempt]);
            }
        }
    }

    /// <summary>
    /// A hidden temporary of its own beside <paramref name="path"/>: a leading
    /// dot, a unique part and <c>.tmp</c>, the shape of the build's
    /// <c>_a_private_temporary_beside</c>, so discovery and a section's
    /// fingerprint leave it alone and two writers never share one.
    /// </summary>
    public static string TemporaryBeside(string path) =>
        Path.Combine(Path.GetDirectoryName(Path.GetFullPath(path))!,
                     "." + Path.GetFileName(path) + ".plantoir-" + Guid.NewGuid().ToString("N")[..8] + ".tmp");

    /// <summary>
    /// Whether another program holds <paramref name="path"/> open without
    /// letting it be replaced: opened for delete access with full sharing, a
    /// sharing violation means held. Access denied, success, or no file means
    /// not held. Off Windows nothing is held this way (a rename over an open
    /// file succeeds there).
    /// </summary>
    public static bool IsHeld(string path)
    {
        if (!OperatingSystem.IsWindows()) return false;
        using SafeFileHandle probe = CreateFileW(path, Delete, ShareAll, IntPtr.Zero, OpenExisting, BackupSemantics, IntPtr.Zero);
        if (!probe.IsInvalid) return false;
        int code = Marshal.GetLastWin32Error();
        return code is SharingViolation or LockViolation;
    }

    private const uint Delete = 0x00010000;
    private const uint ShareAll = 0x00000007;
    private const uint OpenExisting = 3;
    private const uint BackupSemantics = 0x02000000;

    [DllImport("kernel32.dll", CharSet = CharSet.Unicode, SetLastError = true)]
    private static extern SafeFileHandle CreateFileW(string name, uint access, uint share, IntPtr security,
                                                     uint disposition, uint flags, IntPtr template);

}

/// <summary>
/// A file still held by another program after <see cref="HeldFiles.Pauses"/>:
/// nothing was changed. Its <see cref="Exception.Message"/> is the plain
/// sentence a teacher reads (<see cref="HeldFiles.InUseSentence"/>), so a
/// status line that shows the message after "Could not save: " says it truly;
/// its HResult is the system's sharing violation, so
/// <see cref="AgentGuidance.SystemReason"/> gives the system's own sentence
/// for it, never "Access is denied.".
/// </summary>
public sealed class FileInUseException : IOException
{
    /// <summary>The held file's name, without its folder.</summary>
    public string FileName { get; }

    public FileInUseException(string fileName, Exception? inner = null)
        : base(HeldFiles.InUseSentence(fileName), inner)
    {
        FileName = fileName;
        HResult = unchecked((int)0x80070020);
    }
}
