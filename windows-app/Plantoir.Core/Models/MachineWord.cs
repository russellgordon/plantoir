namespace Plantoir.Core.Models;

/// <summary>
/// The teacher's computer, named in a sentence the contract writes ONCE:
/// <c>shared-rules.json → specialNames.platformWording.machine</c> (#418,
/// #410, #438; Russell, 2026-10-03). A contract sentence outside
/// <c>specialNames</c> that names the computer says <c>{machine}</c> where the
/// noun goes and keeps its own determiner ("on this {machine}", "restarting
/// your {machine}"); each app puts in its own word. The mac says "Mac"; this
/// app says "PC".
///
/// <para>Before it, Windows carried its own copy of each such sentence
/// (<c>appUpdates.windowsWording.elsewhereWorkOnWindows</c>,
/// <c>previewPorts.whenNoBlockIsFree.sentenceOnWindows</c>) or substituted
/// "your Mac" → "your PC" in a test, and a sentence reworded on one side left
/// the other copy standing. <c>MachineWordContractTests</c> walks
/// <c>machine.usedIn</c> and fails for a sentence this app does not say
/// filled.</para>
/// </summary>
public static class MachineWord
{
    /// <summary><c>machine.placeholder</c>.</summary>
    public const string Placeholder = "{machine}";

    /// <summary><c>machine.windows</c>: the noun only, never "this PC".</summary>
    public const string Name = "PC";

    /// <summary>The contract's sentence with this app's word for the computer.</summary>
    public static string Fill(string sentence) => sentence.Replace(Placeholder, Name);
}
