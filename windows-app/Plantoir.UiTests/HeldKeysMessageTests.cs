namespace Plantoir.UiTests;

/// <summary>
/// The held-key cleanup failure's message (#638), a plain fact needing no
/// desktop. The source rules that keep a key from being left down live in
/// <c>Plantoir.Tests.HarnessSourceRuleTests</c>, where the merge gate runs
/// them (#1035).
/// </summary>
public class HeldKeysMessageTests
{
    [Fact]
    public void TheHeldKeyMessageNamesTheTestsAndTheFix()
    {
        string message = HeldKeys.FailureMessage(new[] { "PlanTableUiTests.Tab: TAB" });
        Assert.Contains("PlanTableUiTests.Tab: TAB", message);
        Assert.Contains("Keyboard.Type", message);
        Assert.Contains("remote-desktop", message);
    }
}
