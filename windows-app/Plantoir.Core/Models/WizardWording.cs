namespace Plantoir.Core.Models;

/// <summary>
/// What the New Course wizard says.
///
/// <para>Pinned against <c>contracts/shared-rules.json</c> → <c>wizard</c> by
/// <c>WizardWordingTests</c>, so the two apps say the same thing. The mac reads
/// the same key from its own <c>WizardWording</c>.</para>
/// </summary>
/// <remarks>
/// <para><b>Why this class exists at all, for one string.</b> The label lived
/// as a literal in <c>NewCourseDialog</c>, and the only thing pinning it on
/// this side was <c>NewCourseWizardUiTests</c> — which carries <c>[UiFact]</c>
/// and skips unless <c>PLANTOIR_UI_TESTS=1</c>, so a plain <c>dotnet test</c>
/// built it and ran nothing. The first thing a teacher presses had no gate
/// behind it.</para>
///
/// <para>It could not simply be asserted where it was: <c>Plantoir.Tests</c>
/// targets <c>net9.0</c> and references <c>Plantoir.Core</c> and
/// <c>Plantoir.Mcp</c> only, so it cannot see the WinUI app at all — and a
/// <c>ContentDialog</c> cannot be constructed off a XAML thread even if it
/// could. Anything that must FAIL in an ordinary run has to live in Core.
/// That is the general shape, not a fact about this string.</para>
///
/// <para><b>What this does and does not prove.</b> It pins the CONSTANT, not
/// the rendered button — a view that went back to a literal would leave this
/// unused and green. Only the UI suite sees the button itself, and it is
/// opt-in. The mac has exactly the same arrangement, which
/// <c>shared-rules.json</c> → <c>wizard.gatedTests</c> says in as many words.
/// So the UI test keeps its assertion, reading the contract rather than a
/// literal: the two check different things.</para>
///
/// <para>AUTHORED rather than generated, and that is the point of the contract
/// entry. A readout emitted by <c>--write-contracts</c> would simply be
/// rewritten to match whatever the button now says, and the pin would be
/// worthless. GitHub issue #119.</para>
/// </remarks>
public static class WizardWording
{
    /// <summary>
    /// The button that creates the course — the first thing a teacher presses
    /// in this app.
    /// </summary>
    public const string CreateCourseButton = "Create Course";
}
