namespace Plantoir.UiTests;

/// <summary>
/// A test that drives the real app, and therefore needs a desktop session, a
/// built x64 binary, and permission to put a window on screen.
///
/// <para>Skipped unless <c>PLANTOIR_UI_TESTS=1</c>. That is not shyness about
/// running them — it is the difference between a suite that is COMPILED on
/// every build and one that is RUN by accident. `dotnet test` is the ordinary
/// gate and must stay fast, offline and headless; these are the opt-in kind,
/// the same posture <c>verify-deploy.ps1</c> has for publishing. Run them with
/// <c>run-ui-tests.ps1</c>.</para>
/// </summary>
public sealed class UiFactAttribute : FactAttribute
{
    public UiFactAttribute()
    {
        if (Environment.GetEnvironmentVariable("PLANTOIR_UI_TESTS") != "1")
            Skip = "UI test — set PLANTOIR_UI_TESTS=1 (or run run-ui-tests.ps1) to drive the real app.";
    }
}
