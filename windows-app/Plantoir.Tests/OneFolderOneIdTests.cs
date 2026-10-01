using System;
using System.IO;
using System.Text;
using Plantoir.Core.Models;
using Xunit;
using Xunit.Abstractions;

namespace Plantoir.Tests;

/// <summary>
/// #307 (mac #189): one working folder has one id and compares as one,
/// however it is typed. Measured on NTFS: a different CASE reaches the same
/// folder, and both the id (GetFinalPathNameByHandleW gives the disk's own
/// casing) and every comparison (<see cref="WorkingFolder.IsTheSame"/>,
/// OrdinalIgnoreCase) agree. A different UNICODE FORM does not reach the same
/// folder at all: NTFS stores names as given and does not normalise, so
/// "Café" typed as e + U+0301 names a DIFFERENT (here nonexistent) folder —
/// and there is no second spelling of one folder to disagree about.
/// </summary>
public class OneFolderOneIdTests : IDisposable
{
    private readonly ITestOutputHelper _output;
    private readonly string _root = Directory.CreateTempSubdirectory("one-folder-").FullName;

    public OneFolderOneIdTests(ITestOutputHelper output) => _output = output;
    public void Dispose() { try { Directory.Delete(_root, true); } catch { } }

    [Fact]
    public void ACaseVariantIsTheSameFolderWithTheSameId()
    {
        string made = Path.Combine(_root, "Plantoir Test");
        Directory.CreateDirectory(made);
        string typed = Path.Combine(_root.ToLowerInvariant(), "plantoir test");
        string id = FolderContainers.FolderIdentifier(made), typedId = FolderContainers.FolderIdentifier(typed);
        _output.WriteLine($"'{made}' -> {id}; '{typed}' -> {typedId}");
        Assert.Equal(id, typedId);
        Assert.True(WorkingFolder.IsTheSame(made, typed));
        Assert.Equal(WorkingFolder.Comparer.GetHashCode(made), WorkingFolder.Comparer.GetHashCode(typed));
    }

    [Fact]
    public void AnotherUnicodeFormIsAnotherNameOnNtfs()
    {
        string nfc = Path.Combine(_root, "Café");
        string nfd = Path.Combine(_root, "Café");
        Directory.CreateDirectory(nfc);
        _output.WriteLine($"NFC exists={Directory.Exists(nfc)} id={FolderContainers.FolderIdentifier(nfc)}; " +
                          $"NFD exists={Directory.Exists(nfd)} id={FolderContainers.FolderIdentifier(nfd)}");
        Assert.True(Directory.Exists(nfc));
        Assert.False(Directory.Exists(nfd));   // NTFS does not normalise: not the same folder
        Assert.Equal("Café".Normalize(NormalizationForm.FormC), Path.GetFileName(FolderContainers.PhysicalPath(nfc)));
    }
}
