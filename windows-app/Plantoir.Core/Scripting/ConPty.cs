using System.ComponentModel;
using System.Runtime.InteropServices;
using Microsoft.Win32.SafeHandles;

namespace Plantoir.Core.Scripting;

/// <summary>
/// A Windows pseudo console (ConPTY) with a child process attached.
///
/// The toolchain's launchers end in `docker exec -it`, which insists on a
/// real terminal on stdin — plain redirected pipes make that step fail.
/// This is the Windows analogue of the macOS app's openpty()-based
/// PseudoTerminal: the child sees a console; we read its merged output
/// and write its keystrokes.
/// </summary>
public sealed class ConPtyProcess : IDisposable
{
    private readonly SafeFileHandle _inputWrite;   // we write keystrokes here
    private readonly SafeFileHandle _outputRead;   // we read merged output here
    private nint _pseudoConsole;                    // zeroed once closed (ClosePty)
    private readonly nint _processHandle;
    private readonly nint _threadHandle;
    private readonly nint _attributeList;
    private bool _disposed;

    public int ProcessId { get; }

    private ConPtyProcess(SafeFileHandle inputWrite, SafeFileHandle outputRead,
                          nint pseudoConsole, nint processHandle, nint threadHandle,
                          nint attributeList, int processId)
    {
        _inputWrite = inputWrite;
        _outputRead = outputRead;
        _pseudoConsole = pseudoConsole;
        _processHandle = processHandle;
        _threadHandle = threadHandle;
        _attributeList = attributeList;
        ProcessId = processId;
    }

    /// <summary>
    /// Starts <paramref name="commandLine"/> attached to a fresh pseudo console.
    ///
    /// CAUTION (verified live): the child binds its std handles to the new
    /// pseudo console only when THIS process's std handles are clean —
    /// console handles or none, as in a GUI app. A creator whose own stdio
    /// is redirected to pipes leaks those handles into the child, and
    /// wsl.exe then reports "the input device is not a TTY", breaking every
    /// interactive docker exec. Since #155 (bundle 8) Start ZEROES this
    /// process's std handles around CreateProcessW, which measured enough to
    /// bind the child to its pseudo console from a redirected parent
    /// (Plantoir.Tests.ConPtyRedirectedParentTests). Launching harnesses with
    /// their own console (ShellExecute) is still the safer habit.
    /// </summary>
    // 400 columns: ConPTY re-renders soft-wrapped lines with the boundary
    // character duplicated, which corrupts transcript lines and could split
    // a milestone marker. A width no real line reaches sidesteps it.
    public static ConPtyProcess Start(string commandLine, string workingDirectory,
                                      short columns = 400, short rows = 30,
                                      IReadOnlyDictionary<string, string>? extraEnvironment = null)
    {
        // Pipes: child's stdin comes from inputRead; child's stdout/stderr go to outputWrite.
        if (!CreatePipe(out var inputRead, out var inputWrite, nint.Zero, 0))
            throw new Win32Exception(Marshal.GetLastWin32Error(), "CreatePipe (input)");
        if (!CreatePipe(out var outputRead, out var outputWrite, nint.Zero, 0))
            throw new Win32Exception(Marshal.GetLastWin32Error(), "CreatePipe (output)");

        var size = new COORD { X = columns, Y = rows };
        int hr = CreatePseudoConsole(size, inputRead, outputWrite, 0, out var pseudoConsole);
        if (hr != 0) throw new Win32Exception(hr, "CreatePseudoConsole");

        // The pseudo console holds its own duplicates of the child-side ends.
        inputRead.Dispose();
        outputWrite.Dispose();

        // Attribute list carrying the pseudo console handle.
        nint attributeListSize = nint.Zero;
        InitializeProcThreadAttributeList(nint.Zero, 1, 0, ref attributeListSize);
        nint attributeList = Marshal.AllocHGlobal(attributeListSize);
        if (!InitializeProcThreadAttributeList(attributeList, 1, 0, ref attributeListSize))
            throw new Win32Exception(Marshal.GetLastWin32Error(), "InitializeProcThreadAttributeList");
        if (!UpdateProcThreadAttribute(attributeList, 0, PROC_THREAD_ATTRIBUTE_PSEUDOCONSOLE,
                                       pseudoConsole, nint.Size, nint.Zero, nint.Zero))
            throw new Win32Exception(Marshal.GetLastWin32Error(), "UpdateProcThreadAttribute");

        var startupInfo = new STARTUPINFOEX();
        startupInfo.StartupInfo.cb = Marshal.SizeOf<STARTUPINFOEX>();
        startupInfo.lpAttributeList = attributeList;

        string? environmentBlock = BuildEnvironmentBlock(extraEnvironment);

        // #155: a creator whose OWN std handles are pipes (a test host, a
        // shell redirect) hands them to the child instead of the pseudo
        // console — measured: from `dotnet test`'s host (stdout=pipe,
        // stderr=pipe) "cmd /c echo PTY-OK" left only ConPTY's two mode
        // sequences in the transcript; with the handles zeroed around
        // CreateProcessW it arrives. Zeroed under ONE process-wide gate and
        // put back in finally, so two Starts cannot interleave and leave a
        // handle zeroed. Rejected: FreeConsole (#155 — it detaches the whole
        // process), and reusing the per-instance _ptyGate (it would not
        // serialise two Starts). Cost: while the gate is held, another thread
        // writing to Console loses that output; the GUI app writes none.
        bool created;
        PROCESS_INFORMATION processInfo;
        lock (s_stdHandleGate)
        {
            nint savedIn = GetStdHandle(STD_INPUT_HANDLE), savedOut = GetStdHandle(STD_OUTPUT_HANDLE), savedErr = GetStdHandle(STD_ERROR_HANDLE);
            try
            {
                SetStdHandle(STD_INPUT_HANDLE, nint.Zero);
                SetStdHandle(STD_OUTPUT_HANDLE, nint.Zero);
                SetStdHandle(STD_ERROR_HANDLE, nint.Zero);
                created = CreateProcessW(
                    null, commandLine, nint.Zero, nint.Zero, bInheritHandles: false,
                    EXTENDED_STARTUPINFO_PRESENT | CREATE_UNICODE_ENVIRONMENT,
                    environmentBlock, workingDirectory, ref startupInfo, out processInfo);
            }
            finally
            {
                SetStdHandle(STD_INPUT_HANDLE, savedIn);
                SetStdHandle(STD_OUTPUT_HANDLE, savedOut);
                SetStdHandle(STD_ERROR_HANDLE, savedErr);
            }
        }
        if (!created)
        {
            int error = Marshal.GetLastWin32Error();
            Marshal.FreeHGlobal(attributeList);
            ClosePseudoConsole(pseudoConsole);
            throw new Win32Exception(error, $"CreateProcess: {commandLine}");
        }

        return new ConPtyProcess(inputWrite, outputRead, pseudoConsole,
                                 processInfo.hProcess, processInfo.hThread,
                                 attributeList, processInfo.dwProcessId);
    }

    private static string? BuildEnvironmentBlock(IReadOnlyDictionary<string, string>? extra)
    {
        if (extra is null || extra.Count == 0) return null;   // inherit as-is
        var variables = new Dictionary<string, string>(StringComparer.OrdinalIgnoreCase);
        foreach (System.Collections.DictionaryEntry entry in Environment.GetEnvironmentVariables())
            variables[(string)entry.Key] = (string?)entry.Value ?? "";
        foreach (var (key, value) in extra) variables[key] = value;
        var block = new System.Text.StringBuilder();
        foreach (var (key, value) in variables.OrderBy(v => v.Key, StringComparer.OrdinalIgnoreCase))
            block.Append(key).Append('=').Append(value).Append('\0');
        block.Append('\0');
        return block.ToString();
    }

    /// <summary>Reads output bytes; returns 0 at end of stream (console closed or handle disposed).</summary>
    public int ReadOutput(byte[] buffer)
    {
        try
        {
            if (!ReadFile(_outputRead, buffer, buffer.Length, out int read, nint.Zero))
                return 0;   // broken pipe = console closed
            return read;
        }
        catch (ObjectDisposedException)
        {
            return 0;       // the pty was closed/disposed from another thread
        }
    }

    public void WriteInput(ReadOnlySpan<byte> bytes)
    {
        byte[] rented = bytes.ToArray();
        if (!WriteFile(_inputWrite, rented, rented.Length, out _, nint.Zero))
            throw new Win32Exception(Marshal.GetLastWin32Error(), "WriteFile (pty input)");
    }

    public bool HasExited
    {
        get
        {
            if (!GetExitCodeProcess(_processHandle, out uint code)) return true;
            return code != STILL_ACTIVE;
        }
    }

    public int? ExitCode
    {
        get
        {
            if (!GetExitCodeProcess(_processHandle, out uint code)) return null;
            return code == STILL_ACTIVE ? null : unchecked((int)code);
        }
    }

    public bool WaitForExit(int milliseconds) =>
        WaitForSingleObject(_processHandle, (uint)milliseconds) == 0;

    /// <summary>Terminates the child process tree (the script and its docker/wsl children).</summary>
    public void Kill()
    {
        try
        {
            // Kill descendants first — powershell.exe's children (wsl.exe) would
            // otherwise keep the pty open and the read loop alive.
            var self = System.Diagnostics.Process.GetProcessById(ProcessId);
            self.Kill(entireProcessTree: true);
        }
        catch
        {
            TerminateProcess(_processHandle, 1);
        }
    }

    private readonly object _ptyGate = new();

    /// <summary>
    /// Closes the pseudo console. Call after the child exits so the output
    /// read loop observes end-of-stream. Idempotent and safe from any thread —
    /// the watcher and Dispose can both call it.
    /// </summary>
    public void ClosePty()
    {
        lock (_ptyGate)
        {
            if (_pseudoConsole == nint.Zero) return;
            var handle = _pseudoConsole;
            _pseudoConsole = nint.Zero;
            ClosePseudoConsole(handle);
        }
    }

    public void Dispose()
    {
        if (_disposed) return;
        _disposed = true;
        ClosePty();
        _inputWrite.Dispose();
        _outputRead.Dispose();
        if (_attributeList != nint.Zero)
        {
            DeleteProcThreadAttributeList(_attributeList);
            Marshal.FreeHGlobal(_attributeList);
        }
        CloseHandle(_threadHandle);
        CloseHandle(_processHandle);
    }

    private const uint EXTENDED_STARTUPINFO_PRESENT = 0x00080000;
    private const uint CREATE_UNICODE_ENVIRONMENT = 0x00000400;
    private const uint STILL_ACTIVE = 259;
    private const int STD_INPUT_HANDLE = -10;
    private const int STD_OUTPUT_HANDLE = -11;
    private const int STD_ERROR_HANDLE = -12;
    private static readonly nint PROC_THREAD_ATTRIBUTE_PSEUDOCONSOLE = 0x00020016;

    [StructLayout(LayoutKind.Sequential)]
    private struct COORD { public short X; public short Y; }

    [StructLayout(LayoutKind.Sequential)]
    private struct PROCESS_INFORMATION
    {
        public nint hProcess;
        public nint hThread;
        public int dwProcessId;
        public int dwThreadId;
    }

    [StructLayout(LayoutKind.Sequential, CharSet = CharSet.Unicode)]
    private struct STARTUPINFO
    {
        public int cb;
        public string? lpReserved;
        public string? lpDesktop;
        public string? lpTitle;
        public int dwX, dwY, dwXSize, dwYSize, dwXCountChars, dwYCountChars, dwFillAttribute, dwFlags;
        public short wShowWindow, cbReserved2;
        public nint lpReserved2, hStdInput, hStdOutput, hStdError;
    }

    [StructLayout(LayoutKind.Sequential, CharSet = CharSet.Unicode)]
    private struct STARTUPINFOEX
    {
        public STARTUPINFO StartupInfo;
        public nint lpAttributeList;
    }

    [DllImport("kernel32.dll", SetLastError = true)]
    private static extern bool CreatePipe(out SafeFileHandle hReadPipe, out SafeFileHandle hWritePipe, nint lpPipeAttributes, int nSize);

    [DllImport("kernel32.dll", SetLastError = true)]
    private static extern int CreatePseudoConsole(COORD size, SafeFileHandle hInput, SafeFileHandle hOutput, uint dwFlags, out nint phPC);

    [DllImport("kernel32.dll")]
    private static extern int ClosePseudoConsole(nint hPC);

    [DllImport("kernel32.dll", SetLastError = true)]
    private static extern bool InitializeProcThreadAttributeList(nint lpAttributeList, int dwAttributeCount, int dwFlags, ref nint lpSize);

    [DllImport("kernel32.dll", SetLastError = true)]
    private static extern bool UpdateProcThreadAttribute(nint lpAttributeList, uint dwFlags, nint attribute, nint lpValue, nint cbSize, nint lpPreviousValue, nint lpReturnSize);

    [DllImport("kernel32.dll")]
    private static extern void DeleteProcThreadAttributeList(nint lpAttributeList);

    [DllImport("kernel32.dll", SetLastError = true, CharSet = CharSet.Unicode)]
    private static extern bool CreateProcessW(string? lpApplicationName, string lpCommandLine, nint lpProcessAttributes, nint lpThreadAttributes, bool bInheritHandles, uint dwCreationFlags, string? lpEnvironment, string? lpCurrentDirectory, ref STARTUPINFOEX lpStartupInfo, out PROCESS_INFORMATION lpProcessInformation);

    [DllImport("kernel32.dll", SetLastError = true)]
    private static extern bool ReadFile(SafeFileHandle hFile, byte[] lpBuffer, int nNumberOfBytesToRead, out int lpNumberOfBytesRead, nint lpOverlapped);

    [DllImport("kernel32.dll", SetLastError = true)]
    private static extern bool WriteFile(SafeFileHandle hFile, byte[] lpBuffer, int nNumberOfBytesToWrite, out int lpNumberOfBytesWritten, nint lpOverlapped);

    [DllImport("kernel32.dll", SetLastError = true)]
    private static extern bool GetExitCodeProcess(nint hProcess, out uint lpExitCode);

    [DllImport("kernel32.dll", SetLastError = true)]
    private static extern uint WaitForSingleObject(nint hHandle, uint dwMilliseconds);

    [DllImport("kernel32.dll", SetLastError = true)]
    private static extern bool TerminateProcess(nint hProcess, uint uExitCode);

    [DllImport("kernel32.dll", SetLastError = true)]
    private static extern bool CloseHandle(nint hObject);

    [DllImport("kernel32.dll", SetLastError = true)]
    private static extern nint GetStdHandle(int nStdHandle);

    [DllImport("kernel32.dll", SetLastError = true)]
    private static extern bool SetStdHandle(int nStdHandle, nint hHandle);

    private static readonly object s_stdHandleGate = new();
}
