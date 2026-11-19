using Plantoir.Core.Models;

namespace Plantoir.Tests;

/// <summary>
/// #491 item 2: a button that cannot be pressed never looks like the default.
/// The rule is pure; <c>DefaultButtonScanTests</c> holds every dialog to it.
/// </summary>
public class PrimaryButtonLookTests
{
    [Fact]
    public void TheUsualMainButton_IsTheDefaultExactlyWhileItCanBePressed()
    {
        Assert.Equal(new PrimaryButtonLook.Look(DefaultChoice.Primary, false), PrimaryButtonLook.For(true, PrimaryKind.TakesEnterWhenEnabled));
        Assert.Equal(new PrimaryButtonLook.Look(DefaultChoice.None, false), PrimaryButtonLook.For(false, PrimaryKind.TakesEnterWhenEnabled));
    }

    [Fact]
    public void CreateCourse_UntilItIsTheDefault_TakesNoEnterAndWearsNoAccent()
    {
        // The #979 review, as #987 on the mac: an accent Enter does not press
        // looks like the default and is not, so the accent comes off too.
        Assert.Equal(new PrimaryButtonLook.Look(DefaultChoice.None, false), PrimaryButtonLook.For(true, PrimaryKind.NotTheDefaultYet));
        Assert.Equal(new PrimaryButtonLook.Look(DefaultChoice.None, false), PrimaryButtonLook.For(false, PrimaryKind.NotTheDefaultYet));
    }

    [Theory]
    [InlineData(PrimaryKind.TakesEnterWhenEnabled)]
    [InlineData(PrimaryKind.NotTheDefaultYet)]
    [InlineData(PrimaryKind.NotTheDefault)]
    public void NoButtonWearsTheAccentWithoutBeingTheDefault(PrimaryKind kind)
    {
        foreach (bool enabled in new[] { true, false })
        {
            var look = PrimaryButtonLook.For(enabled, kind);
            Assert.False(look.AccentStyle && look.Default != DefaultChoice.Primary,
                         $"{kind}, enabled {enabled}: the accent without being the default");
        }
    }

    [Theory]
    [InlineData(true)]
    [InlineData(false)]
    public void ADestructiveButtonBesideADefaultClose_NeverChangesTheDefault(bool enabled) =>
        Assert.Equal(new PrimaryButtonLook.Look(DefaultChoice.Keep, false), PrimaryButtonLook.For(enabled, PrimaryKind.NotTheDefault));

    [Theory]
    [InlineData(PrimaryKind.TakesEnterWhenEnabled)]
    [InlineData(PrimaryKind.NotTheDefaultYet)]
    [InlineData(PrimaryKind.NotTheDefault)]
    public void ADisabledButton_IsNeverTheDefaultAndNeverAccented(PrimaryKind kind)
    {
        var look = PrimaryButtonLook.For(false, kind);
        Assert.NotEqual(DefaultChoice.Primary, look.Default);
        Assert.False(look.AccentStyle);
    }
}
