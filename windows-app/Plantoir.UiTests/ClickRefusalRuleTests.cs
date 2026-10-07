using System.Drawing;

namespace Plantoir.UiTests;

/// <summary>
/// The rule every real click in the suite goes through (#428 review, ruling
/// 1), pinned WITHOUT a desktop beside <see cref="AssertAbsentRuleTests"/>: a
/// click whose point would not land on its element is refused with a named
/// exception rather than sent to whatever is there.
/// </summary>
public class ClickRefusalRuleTests
{
    private static readonly Rectangle Window = new(100, 100, 800, 600);

    [Fact]
    public void AnElementInsideTheWindowIsClickedInItsMiddle() =>
        Assert.Equal(new Point(150, 210), DrivenApp.MiddleWithin(new Rectangle(100, 200, 100, 20), false, Window, "a row"));

    [Fact]
    public void AnOffscreenElementIsRefused() =>
        Assert.Contains("off screen", Assert.Throws<ClickWouldMissException>(() =>
            DrivenApp.MiddleWithin(new Rectangle(100, 200, 100, 20), true, Window, "a row")).Message);

    [Fact]
    public void AnEmptyBoxIsRefusedEvenForAnOpenMenu()
    {
        Assert.Throws<ClickWouldMissException>(() => DrivenApp.MiddleWithin(Rectangle.Empty, false, Window, "a row"));
        Assert.Throws<ClickWouldMissException>(() => DrivenApp.MiddleWithin(Rectangle.Empty, false, null, "a menu item"));
    }

    [Fact]
    public void AMiddleOutsideTheWindowIsRefused() =>
        Assert.Contains("outside Plantoir's window", Assert.Throws<ClickWouldMissException>(() =>
            DrivenApp.MiddleWithin(new Rectangle(1000, 900, 100, 20), false, Window, "a row scrolled out of view")).Message);

    [Fact]
    public void AnOpenMenuItemOutsideTheWindowIsAllowed() =>
        Assert.Equal(new Point(1050, 910), DrivenApp.MiddleWithin(new Rectangle(1000, 900, 100, 20), false, null, "a menu item"));
}
