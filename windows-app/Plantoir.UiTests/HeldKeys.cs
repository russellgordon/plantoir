using System.Diagnostics;
using System.Runtime.InteropServices;
using FlaUI.Core.Input;
using FlaUI.Core.WindowsAPI;

namespace Plantoir.UiTests;

/// <summary>
/// Keys still held DOWN at the operating-system level when a test ends (#638).
///
/// <para><b>Why this exists.</b> FlaUI's key-down-only call sends the key
/// going DOWN and nothing else; the up is a separate call. Measured
/// 2026-10-22: <c>GetAsyncKeyState(VK_SPACE)</c> still read down 400 ms
/// after one. Twenty-four calls in thirteen files never sent the up, so
/// Escape, Return, Tab, Down, Delete, F2 or Space stayed held for the rest
/// of the run, and every later test typed into a keyboard with a key
/// already down. The fix is <c>Keyboard.Type</c> (down and up) or
/// <c>using (Keyboard.Pressing(...))</c> (up on dispose).
/// <see cref="HarnessSourceRuleTests"/> keeps the call from coming back, and
/// this sweep catches a key held any other way.</para>
///
/// <para><b>How it fails, and why not from <see cref="DrivenApp.Dispose"/>.</b>
/// An exception thrown from a <c>using</c>'s Dispose REPLACES the test
/// body's own exception, so a test that failed for a real reason would be
/// reported as a stuck key instead. So <see cref="DrivenApp.Dispose"/>
/// releases the key, says so, and records it here. The collection fixture
/// (<see cref="HeldKeyLedger"/>) fails at the end of the collection, which
/// xUnit reports as a separate cleanup failure naming the keys and the
/// tests that left them down.</para>
///
/// <para>A key a PERSON is holding, or a modifier stuck by a remote-desktop
/// session, reads exactly the same. The message says so.</para>
/// </summary>
public static class HeldKeys
{
    [DllImport("user32.dll")] private static extern short GetAsyncKeyState(int virtualKey);

    /// <summary>The keys the suite sends, plus every modifier in both its generic and left/right forms.</summary>
    public static readonly VirtualKeyShort[] Watched =
    {
        VirtualKeyShort.SHIFT, VirtualKeyShort.LSHIFT, VirtualKeyShort.RSHIFT,
        VirtualKeyShort.CONTROL, VirtualKeyShort.LCONTROL, VirtualKeyShort.RCONTROL,
        VirtualKeyShort.ALT, VirtualKeyShort.LMENU, VirtualKeyShort.RMENU,
        VirtualKeyShort.LWIN, VirtualKeyShort.RWIN,
        VirtualKeyShort.ESCAPE, VirtualKeyShort.RETURN, VirtualKeyShort.TAB, VirtualKeyShort.SPACE,
        VirtualKeyShort.DELETE, VirtualKeyShort.BACK,
        VirtualKeyShort.UP, VirtualKeyShort.DOWN, VirtualKeyShort.LEFT, VirtualKeyShort.RIGHT,
        VirtualKeyShort.F2,
    };

    /// <summary>The watched keys that read DOWN right now.</summary>
    public static List<VirtualKeyShort> Down()
    {
        var down = new List<VirtualKeyShort>();
        foreach (var key in Watched)
            if ((GetAsyncKeyState((int)key) & 0x8000) != 0) down.Add(key);
        return down;
    }

    /// <summary>Releases every watched key that reads down, and returns the ones it found.</summary>
    public static List<VirtualKeyShort> ReleaseAll()
    {
        var down = Down();
        foreach (var key in down)
        {
            try { Keyboard.Release(key); } catch { }
        }
        if (down.Count > 0) Thread.Sleep(100);
        return down;
    }

    public static string Names(IEnumerable<VirtualKeyShort> keys) => string.Join(", ", keys);

    /// <summary>
    /// The test that created a <see cref="DrivenApp"/>: the first caller outside
    /// it in this assembly. A helper that creates one is named rather than the
    /// test above it, which still says where to look.
    /// </summary>
    public static string CallingTest()
    {
        foreach (var frame in new StackTrace().GetFrames())
        {
            var method = frame.GetMethod();
            var type = method?.DeclaringType;
            if (type is null || type.Assembly != typeof(HeldKeys).Assembly) continue;
            if (type == typeof(HeldKeys) || type == typeof(DrivenApp)) continue;
            // A lambda or local function lives in a compiler-made nested type.
            while (type.DeclaringType is not null && type.Name.Contains('<')) type = type.DeclaringType;
            return $"{type.Name}.{method!.Name}";
        }
        return "an unnamed test";
    }

    private static readonly object Gate = new();
    private static readonly List<string> Found = new();

    /// <summary>Records a test's held keys for <see cref="HeldKeyLedger"/> to fail on.</summary>
    public static void Record(string test, IEnumerable<VirtualKeyShort> keys)
    {
        lock (Gate) Found.Add($"{test}: {Names(keys)}");
    }

    /// <summary>What was recorded, emptied as it is read.</summary>
    public static List<string> TakeRecorded()
    {
        lock (Gate)
        {
            var taken = new List<string>(Found);
            Found.Clear();
            return taken;
        }
    }

    /// <summary>The cleanup failure's message, apart from xUnit so a plain test can pin it.</summary>
    public static string FailureMessage(IReadOnlyList<string> recorded) =>
        "Keys were still held down when these tests ended, and were released by the harness: " +
        string.Join("; ", recorded) + ". Send keys with Keyboard.Type (down and up) or " +
        "using (Keyboard.Pressing(...)), never a key-down with no key-up (#638). " +
        "A key a person was holding, or a modifier stuck by a remote-desktop session, reads the same.";
}

/// <summary>
/// The collection fixture of "drives the real app" (#638): fails once, at the
/// end of the collection, if any test left a key held down. A cleanup failure
/// of its own, rather than an exception from a test's Dispose that would hide
/// the test's real one.
/// </summary>
public sealed class HeldKeyLedger : IDisposable
{
    public void Dispose()
    {
        var recorded = HeldKeys.TakeRecorded();
        if (recorded.Count > 0) throw new Xunit.Sdk.XunitException(HeldKeys.FailureMessage(recorded));
    }
}
