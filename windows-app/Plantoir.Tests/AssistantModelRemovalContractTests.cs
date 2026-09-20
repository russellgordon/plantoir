using System.Text.Json.Nodes;
using Plantoir.Core.Assist;
using Xunit;

namespace Plantoir.Tests;

/// <summary>
/// The removal half of `shared-rules.json` -> `assistantModelChoice`, driven
/// from the contract rather than retyped.
///
/// It lives in its own class, and not in <c>ContractTests</c>, for one
/// reason: it needs a model file on disk, which means
/// <c>LocalModel.ModelDirectoryOverride</c>, <c>AssistModelStores</c> and
/// <c>AssistActivity</c> — three process-wide statics. xUnit parallelises
/// test CLASSES, so it joins <c>SharedLocalModelState</c> alongside
/// <c>AssistModelStoreTests</c> and <c>LocalModelTests</c>. Moving all of
/// <c>ContractTests</c> into that collection would have serialised a few
/// dozen fast, stateless tests to accommodate this one.
///
/// Mirrors the mac's `SharedRulesContractTests.testAssistantModelRemoval`,
/// which reads the same three keys. `AssistModelStoreTests` covers the same
/// guard from the other direction — hand-written cases about behaviour; this
/// one exists so that changing the CONTRACT fails a Windows test, which is
/// the property that keeps the two platforms honest with each other.
/// </summary>
[Collection(SharedLocalModelState.Name)]
public sealed class AssistantModelRemovalContractTests : IDisposable
{
    private readonly string _modelsFolder = Path.Combine(
        Path.GetTempPath(), "plantoir-contract-models-" + Guid.NewGuid().ToString("N"));

    public AssistantModelRemovalContractTests()
    {
        Directory.CreateDirectory(_modelsFolder);
        LocalModel.ModelDirectoryOverride = _modelsFolder;
        AssistModelStores.Reset();
        AssistActivity.Reset();
    }

    public void Dispose()
    {
        AssistActivity.Reset();
        AssistModelStores.Reset();
        LocalModel.ModelDirectoryOverride = null;
        try { Directory.Delete(_modelsFolder, recursive: true); } catch { }
    }

    private void PlaceModel(AssistModelTier tier)
    {
        string path = Path.Combine(_modelsFolder, tier.FileName());
        using var stream = new FileStream(path, FileMode.Create);
        stream.SetLength(tier.DownloadBytes());
    }

    [Fact]
    public void SharedRules_AssistantModelRemoval_MatchesContract()
    {
        JsonNode removal = ContractLoader.LoadJson("shared-rules.json")
            ["assistantModelChoice"]!["removal"]!;

        // The rung a 48 GB machine is given when the teacher has not picked
        // one, so the "may the CHOSEN one be removed" case below is about the
        // chosen one rather than about whichever rung happened to be handy.
        var budget = new AssistHardwareBudget(48L * 1024 * 1024 * 1024);
        AssistModelTier chosen = AssistModelChoice.Resolved(AssistModelChoice.Automatic, budget);
        PlaceModel(chosen);
        AssistModelStore store = AssistModelStores.Store(chosen);
        Assert.True(store.IsReady, "the rung under test has to be downloaded for removal to mean anything");

        if (removal["refusedWhileAnyAssistantWindowIsOpen"]!.GetValue<bool>())
        {
            AssistActivity.Begin(@"C:\contract", "ICS3U", 2);
            Assert.False(store.MayRemove());

            if (removal["messageNamesTheSectionToClose"]!.GetValue<bool>())
            {
                string reason = Assert.IsType<string>(store.ReasonItCannotBeRemoved());
                Assert.Contains("ICS3U", reason);
                Assert.Contains("Section 2", reason);
            }

            // And the refusal is real, not just advice the button follows:
            // Remove() itself is gated, so a stale view cannot get past it.
            store.Remove();
            Assert.True(store.IsReady);

            AssistActivity.End(@"C:\contract", "ICS3U", 2);
        }

        if (removal["theCurrentlyChosenOneMayBeRemoved"]!.GetValue<bool>())
        {
            Assert.True(store.MayRemove(),
                "nothing is open now, and the chosen rung is removable on purpose");
            store.Remove();
            Assert.False(store.IsReady);
        }
    }
}
