using System.Text;
using Plantoir.Core.Catalogs;
using Plantoir.Core.Models;
using Xunit;

namespace Plantoir.Tests;

public class WorkspaceClassifyTests
{
    [Fact]
    public void ReadyWhenLauncherPresent()
    {
        string root = Temp();
        try
        {
            File.WriteAllText(Path.Combine(root, "preview.ps1"), "x");
            Assert.Equal(WorkspaceState.Ready, Workspace.Classify(root));
        }
        finally { try { Directory.Delete(root, true); } catch { } }
    }

    [Fact]
    public void EmptyFolderCanBeInitializedIgnoringShellDroppings()
    {
        string root = Temp();
        try
        {
            File.WriteAllText(Path.Combine(root, "desktop.ini"), "x");
            File.WriteAllText(Path.Combine(root, "Thumbs.db"), "x");
            Assert.Equal(WorkspaceState.CanBeInitialized, Workspace.Classify(root));
        }
        finally { try { Directory.Delete(root, true); } catch { } }
    }

    [Fact]
    public void NonEmptyNonWorkspaceIsUnrecognized()
    {
        string root = Temp();
        try
        {
            File.WriteAllText(Path.Combine(root, "my-thesis.docx"), "x");
            Assert.Equal(WorkspaceState.Unrecognized, Workspace.Classify(root));
        }
        finally { try { Directory.Delete(root, true); } catch { } }
    }

    [Fact]
    public void NoMatchesMessageOnlyWhenSomethingWasHidden()
    {
        Assert.True(Workspace.ShowsNoFilterMatches("MPM2D", courseCount: 3, matchCount: 0));
        Assert.False(Workspace.ShowsNoFilterMatches("MPM2D", courseCount: 0, matchCount: 0));   // empty workspace
        Assert.False(Workspace.ShowsNoFilterMatches("  ", courseCount: 3, matchCount: 0));       // blank filter
        Assert.False(Workspace.ShowsNoFilterMatches("ICS", courseCount: 3, matchCount: 2));      // has matches
    }

    [Fact]
    public void NewWindowFolderRule()
    {
        Assert.Null(Workspace.FolderForNewWindow(System.Array.Empty<string>(), null));
        Assert.Equal(@"C:\b", Workspace.FolderForNewWindow(new[] { @"C:\a", @"C:\b" }, @"C:\b"));
        Assert.Equal(@"C:\a", Workspace.FolderForNewWindow(new[] { @"C:\a", @"C:\b" }, @"C:\gone"));
    }

    private static string Temp()
    {
        string path = Path.Combine(Path.GetTempPath(), "ws-" + System.Guid.NewGuid());
        Directory.CreateDirectory(path);
        return path;
    }
}

public class ToolchainMirrorTests
{
    [Fact]
    public void SyncDirectoryRemovesExtraneousFiles()
    {
        string root = Path.Combine(Path.GetTempPath(), "mirror-" + System.Guid.NewGuid());
        try
        {
            string source = Path.Combine(root, "src");
            string dest = Path.Combine(root, "dest");
            Directory.CreateDirectory(source);
            Directory.CreateDirectory(dest);
            File.WriteAllText(Path.Combine(source, "keep.txt"), "new");
            File.WriteAllText(Path.Combine(dest, "keep.txt"), "old");
            File.SetLastWriteTimeUtc(Path.Combine(dest, "keep.txt"), DateTime.UtcNow.AddMinutes(-10));
            File.WriteAllText(Path.Combine(dest, "stale.txt"), "remove me");   // changes the hash for nothing

            int changed = ToolchainMirror.SyncDirectory(source, dest);

            Assert.Equal("new", File.ReadAllText(Path.Combine(dest, "keep.txt")));
            Assert.False(File.Exists(Path.Combine(dest, "stale.txt")));   // extraneous file gone
            Assert.Equal(2, changed);   // one copy, one delete
        }
        finally { try { Directory.Delete(root, true); } catch { } }
    }


    [Fact]
    public void RefreshLaunchersOnlyTouchesExistingDifferingFiles()
    {
        string root = Path.Combine(Path.GetTempPath(), "mirror-" + System.Guid.NewGuid());
        try
        {
            string bundled = Path.Combine(root, "bundled");
            string workspace = Path.Combine(root, "ws");
            Directory.CreateDirectory(bundled);
            Directory.CreateDirectory(workspace);
            File.WriteAllText(Path.Combine(bundled, "preview.ps1"), "new version");
            File.WriteAllText(Path.Combine(bundled, "setup.ps1"), "new setup");
            // Only preview.ps1 exists in the workspace — setup.ps1 must NOT be created.
            File.WriteAllText(Path.Combine(workspace, "preview.ps1"), "old version");

            var refreshed = ToolchainMirror.RefreshLaunchers(workspace, bundled);

            Assert.Contains("preview.ps1", refreshed);
            Assert.DoesNotContain("setup.ps1", refreshed);
            Assert.False(File.Exists(Path.Combine(workspace, "setup.ps1")));
            Assert.Equal("new version", File.ReadAllText(Path.Combine(workspace, "preview.ps1")));
        }
        finally { try { Directory.Delete(root, true); } catch { } }
    }
}

public class CatalogTests
{
    [Fact]
    public void TwelvePresetEmojis() => Assert.Equal(12, EmojiCatalog.Presets.Count);

    [Fact]
    public void EighteenBundledFonts() => Assert.Equal(18, FontCatalog.BundledFontFiles.Count);

    [Fact]
    public void LocaleDisplayNames()
    {
        Assert.Equal(27, LocaleCatalog.Codes.Count);
        Assert.Equal("nb-NO", LocaleCatalog.Codes[0]);   // deliberately first
        Assert.Equal("en-US — English (United States)", LocaleCatalog.DisplayName("en-US"));
    }

    [Fact]
    public void FontFileNameStripsSpaces() => Assert.Equal("SourceSans3", FontCatalog.FileBaseName("Source Sans 3"));

    [Fact]
    public void SystemPairingLabel() =>
        Assert.Equal("System fonts (Helvetica, Arial)", FontCatalog.PairingLabel("Helvetica, Arial", "Helvetica, Arial"));

    [Fact]
    public void ColourSchemeParsesArrayOrWrappedAndSwatches()
    {
        string json = """
            [{"id":"quartz-standard","name":"Quartz","colors":{"lightMode":{
              "secondary":"#284b63","tertiary":"#84a59d","dark":"#2b2b2b","light":"#faf8f8"}}}]
            """;
        var schemes = ColourSchemeCatalog.Parse(Encoding.UTF8.GetBytes(json));
        Assert.Single(schemes);
        Assert.Equal(new[] { "#284b63", "#84a59d", "#2b2b2b", "#faf8f8" }, schemes[0].SwatchValues);
    }
}
