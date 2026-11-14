using System.Runtime.InteropServices;
using System.Text;

namespace Plantoir.Core.Models;

/// <summary>
/// The teacher's default web browser, asked BY NAME (#820 item 3,
/// <c>unitPlanning.tab.openInBrowser.rule</c>): the app registered for
/// <c>https:</c> links (Settings ▸ Apps ▸ Default apps), never whatever opens
/// <c>.html</c> or <c>.pdf</c>, which can be an editor or a PDF reader, and for
/// a script would RUN it (the mac's #803 review L3).
/// </summary>
/// <remarks>
/// <para><b>How.</b> <c>AssocQueryString(ASSOCF_IS_PROTOCOL, ASSOCSTR_PROGID, "https")</c>
/// names the ProgId the shell would use for an <c>https:</c> link (the user's
/// choice when there is one), and <c>ShellExecuteEx</c> runs THAT class's
/// <c>open</c> verb with the page's <c>file:</c> address (<c>SEE_MASK_CLASSNAME</c>,
/// 790 plan review M5). The class's own verb is what runs, whether it is a
/// command, a <c>DelegateExecute</c> or a packaged browser's activation; the
/// file's own type is never asked. With no ProgId, or one with no <c>open</c>
/// verb, NOTHING is started and the answer is <see cref="PlanInTheBrowser.Opening.NoBrowser"/>.</para>
///
/// <para>Rejected: reading the ProgId's command line and starting the program
/// it names (a Store browser's ProgId has no command; templates carry
/// <c>%1</c>, <c>%L</c>, <c>%*</c> or DDE, each a parser to get wrong);
/// <c>Process.Start</c> of the <c>file:</c> address with the shell (that is
/// the file type's app); the IApplicationAssociationRegistration COM interface
/// (the same answer through built-in COM, which this app does not otherwise
/// use).</para>
///
/// <para>In a redirected run (<c>--state-dir</c>, the UI tests) nothing is
/// started: the ProgId and the address are appended to
/// <see cref="OpenedFileName"/> in the state folder, as
/// <c>ExternalLinks</c> does for web links, so a test can read what WOULD have
/// opened and no browser comes in front of the person at the desk.</para>
/// </remarks>
public sealed class WindowsDefaultBrowser : PlanInTheBrowser.IBrowser
{
    public static readonly WindowsDefaultBrowser Instance = new();

    /// <summary>Where a redirected run writes what it would have opened: <c>&lt;ProgId&gt; | &lt;address&gt;</c>, one per line.</summary>
    public const string OpenedFileName = "browser-opened.txt";

    private readonly Func<string?> _progId;
    private readonly Func<string, string, bool> _start;
    private readonly Func<bool> _redirected;

    /// <param name="progId">Test seam: the ProgId for <c>https:</c>, or null for none.</param>
    /// <param name="start">Test seam: runs a class's open verb on an address; true when the shell took it.</param>
    /// <param name="redirected">Test seam: whether this is a redirected run (the unit suite always is).</param>
    public WindowsDefaultBrowser(Func<string?>? progId = null, Func<string, string, bool>? start = null, Func<bool>? redirected = null)
    {
        _progId = progId ?? HttpsProgId;
        _start = start ?? StartWithTheClass;
        _redirected = redirected ?? (() => AppDataRoot.IsRedirected);
    }

    public PlanInTheBrowser.Opening Open(string fileUri)
    {
        string? progId;
        try { progId = _progId(); }
        catch { progId = null; }
        if (string.IsNullOrWhiteSpace(progId)) return PlanInTheBrowser.Opening.NoBrowser;
        if (_redirected())
        {
            try
            {
                File.AppendAllText(AppDataRoot.Combine(OpenedFileName), progId + " | " + fileUri + Environment.NewLine);
                return PlanInTheBrowser.Opening.Opened;
            }
            catch { return PlanInTheBrowser.Opening.CouldNotOpen; }
        }
        try { return _start(progId, fileUri) ? PlanInTheBrowser.Opening.Opened : PlanInTheBrowser.Opening.CouldNotOpen; }
        catch { return PlanInTheBrowser.Opening.CouldNotOpen; }
    }

    /// <summary>
    /// The ProgId the shell uses for an <c>https:</c> link, or null when there
    /// is none or it has no way to open anything (no <c>open</c> command and
    /// no <c>DelegateExecute</c>).
    /// </summary>
    public static string? HttpsProgId()
    {
        string? progId = Query(ASSOCF_IS_PROTOCOL, ASSOCSTR_PROGID, "https", null);
        if (string.IsNullOrWhiteSpace(progId)) return null;
        bool opens = !string.IsNullOrEmpty(Query(0, ASSOCSTR_COMMAND, progId, "open"))
                     || !string.IsNullOrEmpty(Query(0, ASSOCSTR_DELEGATEEXECUTE, progId, "open"));
        return opens ? progId : null;
    }

    /// <summary>What the shell says about <paramref name="association"/>, or null.</summary>
    public static string? Query(uint flags, int what, string association, string? verb)
    {
        try
        {
            uint length = 0;
            AssocQueryStringW(flags, what, association, verb, null, ref length);
            if (length == 0) return null;
            var buffer = new StringBuilder((int)length);
            int result = AssocQueryStringW(flags, what, association, verb, buffer, ref length);
            return result == 0 ? buffer.ToString() : null;
        }
        catch { return null; }
    }

    private static bool StartWithTheClass(string progId, string fileUri)
    {
        var info = new ShellExecuteInfo
        {
            cbSize = Marshal.SizeOf<ShellExecuteInfo>(),
            fMask = SEE_MASK_CLASSNAME | SEE_MASK_NOASYNC | SEE_MASK_FLAG_NO_UI,
            lpVerb = "open",
            lpFile = fileUri,
            lpClass = progId,
            nShow = SW_SHOWNORMAL,
        };
        return ShellExecuteExW(ref info);
    }

    private const uint ASSOCF_IS_PROTOCOL = 0x00001000;
    private const int ASSOCSTR_COMMAND = 1;
    private const int ASSOCSTR_DELEGATEEXECUTE = 18;
    private const int ASSOCSTR_PROGID = 20;
    private const uint SEE_MASK_CLASSNAME = 0x00000001;
    private const uint SEE_MASK_NOASYNC = 0x00000100;
    private const uint SEE_MASK_FLAG_NO_UI = 0x00000400;
    private const int SW_SHOWNORMAL = 1;

    [StructLayout(LayoutKind.Sequential, CharSet = CharSet.Unicode)]
    private struct ShellExecuteInfo
    {
        public int cbSize;
        public uint fMask;
        public nint hwnd;
        [MarshalAs(UnmanagedType.LPWStr)] public string? lpVerb;
        [MarshalAs(UnmanagedType.LPWStr)] public string? lpFile;
        [MarshalAs(UnmanagedType.LPWStr)] public string? lpParameters;
        [MarshalAs(UnmanagedType.LPWStr)] public string? lpDirectory;
        public int nShow;
        public nint hInstApp;
        public nint lpIDList;
        [MarshalAs(UnmanagedType.LPWStr)] public string? lpClass;
        public nint hkeyClass;
        public uint dwHotKey;
        public nint hIconOrMonitor;
        public nint hProcess;
    }

    [DllImport("shlwapi.dll", CharSet = CharSet.Unicode)]
    private static extern int AssocQueryStringW(uint flags, int str, string pszAssoc, string? pszExtra,
                                                StringBuilder? pszOut, ref uint pcchOut);

    [DllImport("shell32.dll", CharSet = CharSet.Unicode, SetLastError = true)]
    [return: MarshalAs(UnmanagedType.Bool)]
    private static extern bool ShellExecuteExW(ref ShellExecuteInfo info);
}
