using Plantoir.Core.Assist;
using Xunit;

namespace Plantoir.Tests;

/// <summary>
/// The duplicate's twelve sentences, as the mac's #163 made them contract keys
/// (#200 item 1): each rendering asserted against
/// <c>assist-wording.json</c>, with the contract's placeholders and its
/// LITERAL date and backup name.
/// </summary>
public class DuplicationWordingTests
{
    private static readonly System.Text.Json.Nodes.JsonNode Wording =
        ContractLoader.LoadJson("assist-wording.json")["wording"]!;

    private static string Key(string name) => Wording[name]!.ToString();

    private const string Backup = @"C:\x\{course}_backup_2026-09-08_190000.zip";
    private static readonly DateOnly TheDate = new(2026, 9, 14);

    [Fact]
    public void EveryDuplicateSentenceIsTheContracts()
    {
        Assert.Equal(Key("duplicated"), ClassChangeWording.Duplicated("{page}", "{copy}"));
        Assert.Equal(Key("copiedTo"), ClassChangeWording.CopiedTo("{page}", "{copy}", TheDate));
        Assert.Equal(Key("wouldBeCopiedTo"), ClassChangeWording.WouldBeCopiedTo("{page}", "{copy}", TheDate));
        Assert.Equal(Key("theCopyStartsHidden"), ClassChangeWording.TheCopyStartsHidden);
        Assert.Equal(Key("otherClassesWouldMoveAndLinksFollow"), ClassChangeWording.OtherClassesWouldMove(2, 1));
        Assert.Equal(Key("otherClassesWouldMoveKeepingTheirNames"), ClassChangeWording.OtherClassesWouldMove(2, 0));
        Assert.Equal(Key("otherClassesMoved"), ClassChangeWording.OtherClassesMoved(null));
        Assert.Equal(Key("notANumberedClassPage"), ClassChangeWording.NotANumberedClassPage("{page}"));
        Assert.Equal(Key("thePlaceForTheCopyIsStillTaken"), ClassChangeWording.ThePlaceForTheCopyIsStillTaken("{copy}", null));
        Assert.Equal(Key("thePlaceForTheCopyIsStillTakenNamingTheBackup"),
            ClassChangeWording.ThePlaceForTheCopyIsStillTakenNamingTheBackup("{copy}", Backup));
        Assert.Equal(Key("theCopyCouldNotBeMadeHidden"),
            ClassChangeWording.TheCopyCouldNotBeMadeHidden("{page}", "{copy}", null));
        Assert.Equal(Key("theCopyCouldNotBeMadeHiddenNamingTheBackup"),
            ClassChangeWording.TheCopyCouldNotBeMadeHiddenNamingTheBackup("{page}", "{copy}", Backup));
    }
}
