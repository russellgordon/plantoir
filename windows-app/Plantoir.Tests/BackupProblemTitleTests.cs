using Plantoir.Core.Models;

namespace Plantoir.Tests;

/// <summary>#491 item 9: a backup, restore, deletion or removal problem names its act (the mac's words).</summary>
public class BackupProblemTitleTests
{
    [Fact]
    public void EachTitleNamesItsAct()
    {
        Assert.Equal("Could not back up EXC2O", BackupProblemTitle.BackingUp("EXC2O"));
        Assert.Equal("Could not restore EXC2O", BackupProblemTitle.Restoring("EXC2O"));
        Assert.Equal("Could not delete the backup", BackupProblemTitle.DeletingBackups(1));
        Assert.Equal("Could not delete the backups", BackupProblemTitle.DeletingBackups(2));
        Assert.Equal("Could not delete the archive", BackupProblemTitle.DeletingArchive);
        Assert.Equal("Could not remove EXC2O", BackupProblemTitle.Removing("EXC2O"));
    }

    /// <summary>No problem dialog in the sidebar is titled with a bare verb any more.</summary>
    [Fact]
    public void TheSidebarUsesThem()
    {
        string source = File.ReadAllText(Path.Combine(ContractLoader.RepositoryRoot, "windows-app", "Plantoir", "Views", "SidebarPane.xaml.cs"));
        foreach (string bare in new[] { "\"Could not remove\"", "\"Could not back up\"", "\"Could not restore\"", "\"Could not delete\"", "\"Some backups could not be deleted\"" })
            Assert.DoesNotContain(bare, source);
        foreach (string call in new[] { "BackupProblemTitle.Removing(", "BackupProblemTitle.BackingUp(", "BackupProblemTitle.Restoring(",
                                        "BackupProblemTitle.DeletingBackups(", "BackupProblemTitle.DeletingArchive" })
            Assert.Contains(call, source);
    }
}
