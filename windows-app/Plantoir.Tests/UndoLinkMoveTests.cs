using System.Runtime.InteropServices;
using System.Security.Cryptography;
using System.Text;
using System.Text.Json;
using System.Text.Json.Nodes;
using Microsoft.Win32.SafeHandles;
using Plantoir.Core.Undo;

namespace Plantoir.Tests;

/// <summary>
/// A link moved as itself (#899 W8-6; the mac's U4b2-14, <c>opKinds.move</c>'s
/// <c>linkSha</c>): a <c>move</c> with <c>linkSha</c> moves a junction or a
/// symbolic link (a name-surrogate reparse point, <see cref="UndoLinks.Look"/>)
/// by one rename of the link, judged on each side by the SHA-256 of the target
/// it holds as stored, never followed: what it leads to is never read, listed
/// or touched, and the check that its place stays inside the working folder
/// resolves only the folder above it.
/// </summary>
public sealed class UndoLinkMoveTests : IDisposable
{
    private const string Section = "courses/TST1O/section1";
    private const string Media = Section + "/media";
    private const string Renamed = Section + "/renamed";
    private const string Library = "courses/TST1O/library";

    private readonly string _folder = RunOwnedTempFolders.Create("plantoir-undo-link-move-");

    public void Dispose()
    {
        try { Directory.Delete(_folder, recursive: true); } catch { }
    }

    internal static string ShaOfTarget(string target) => Convert.ToHexStringLower(SHA256.HashData(Encoding.UTF8.GetBytes(target)));

    private static UndoOp Op(JsonObject json)
    {
        using JsonDocument document = JsonDocument.Parse(json.ToJsonString());
        return UndoFormat.ReadOp(document.RootElement);
    }

    private static JsonObject LinkMove(string target) => new()
    {
        ["kind"] = "move", ["from"] = Media, ["to"] = Renamed, ["linkSha"] = ShaOfTarget(target),
    };

    /// <summary>The library the link leads to, made in the course: a.md and pictures/b.md.</summary>
    private static string MakeTheLibrary(UndoScribe scribe, string relative = Library)
    {
        scribe.WritePage("A", relative + "/a.md", "A\n"u8.ToArray());
        scribe.WritePage("A", relative + "/pictures/b.md", "B\n"u8.ToArray());
        return scribe.FullPath("A", relative);
    }

    /// <summary>What a folder holds, for "untouched": its listing's hash and the identity of the folder and of each file.</summary>
    private static string Untouched(string folder)
    {
        var said = new StringBuilder(UndoTreeReading.Read(folder).ListingSha ?? "no listing");
        said.Append(' ').Append(UndoFileIdentity.OfPlace(folder));
        foreach (string file in Directory.EnumerateFiles(folder, "*", SearchOption.AllDirectories).Order(StringComparer.Ordinal))
            said.Append(' ').Append(UndoFileIdentity.OfPlace(file));
        return said.ToString();
    }

    // ---- Measured --------------------------------------------------------

    /// <summary>
    /// Measured on the PC (NTFS): a junction made by <c>mklink /J</c> holds
    /// its target as the full path given (LinkTarget, no <c>\??\</c>), and
    /// MoveFileEx without MOVEFILE_REPLACE_EXISTING on it moves the junction
    /// alone: the folder it leads to keeps its identity and listing.
    /// </summary>
    [Fact]
    public void AJunctionHoldsItsFullTargetAndOneRenameMovesTheJunctionAlone()
    {
        string library = Path.Combine(_folder, "library");
        Directory.CreateDirectory(Path.Combine(library, "pictures"));
        File.WriteAllText(Path.Combine(library, "a.md"), "A\n");
        string media = Path.Combine(_folder, "media");
        UndoKindsForTheCases.MakeAJunction(media, library);
        Assert.Equal(library, new DirectoryInfo(media).LinkTarget);
        string before = Untouched(library);

        Assert.Equal(0, UndoSwap.Rename(media, Path.Combine(_folder, "renamed"), replace: false));
        Assert.Equal(UndoLinks.What.Nothing, UndoLinks.Look(media));
        Assert.Equal(library, new DirectoryInfo(Path.Combine(_folder, "renamed")).LinkTarget);
        Assert.Equal(before, Untouched(library));
    }

    /// <summary>The same for a folder symbolic link made with <c>../library</c>, where this account may make one: held as written, moved alone.</summary>
    [SymbolicLinkFact]
    public void ASymbolicLinkHoldsItsTargetAsWrittenAndOneRenameMovesTheLinkAlone()
    {
        string library = Path.Combine(_folder, "library");
        Directory.CreateDirectory(library);
        File.WriteAllText(Path.Combine(library, "a.md"), "A\n");
        string section = Path.Combine(_folder, "section1");
        Directory.CreateDirectory(section);
        string media = Path.Combine(section, "media");
        Directory.CreateSymbolicLink(media, "../library");
        Assert.Equal("../library", new DirectoryInfo(media).LinkTarget);
        string before = Untouched(library);

        Assert.Equal(0, UndoSwap.Rename(media, Path.Combine(section, "renamed"), replace: false));
        Assert.Equal("../library", new DirectoryInfo(Path.Combine(section, "renamed")).LinkTarget);
        Assert.Equal(before, Untouched(library));
    }

    // ---- The format -----------------------------------------------------

    /// <summary>Readable with exactly one of sha, listingSha and linkSha; linkSha is never a blob, and must be a blob's name.</summary>
    [Fact]
    public void ALinksMoveIsReadableWithExactlyOneContentAndItsLinkShaIsNoBlob()
    {
        UndoOp alone = Op(LinkMove("../library"));
        Assert.True(alone.Readable);
        Assert.Equal(ShaOfTarget("../library"), alone.LinkSha);
        Assert.Empty(alone.Blobs);

        JsonObject withListing = LinkMove("../library");
        withListing["listingSha"] = new UndoTreeListing([], []).Sha;
        Assert.False(Op(withListing).Readable);

        JsonObject withSha = LinkMove("../library");
        withSha["sha"] = ShaOfTarget("a file");
        Assert.False(Op(withSha).Readable);

        JsonObject notAName = LinkMove("../library");
        notAName["linkSha"] = "../library";
        Assert.False(Op(notAName).Readable);
    }

    /// <summary>A link's move carries no edit: one at or inside its to is outside wholeOps' one exception, so the step is not readable, from its shape.</summary>
    [Fact]
    public void AnEditInsideALinksNewPlaceIsAStepThatCannotBeRead()
    {
        UndoOp move = Op(LinkMove("../library"));
        var edit = new JsonObject
        {
            ["kind"] = "replaceText", ["path"] = Renamed + "/a.md", ["before"] = "old", ["after"] = "new",
            ["contextBefore"] = "Line one: ", ["contextAfter"] = ".\n",
        };
        Assert.False(UndoOp.MoveCarries(move, Op(edit)));
        Assert.False(UndoStep.WholeOpsStandAlone([move, Op(edit)]));

        using var scribe = new UndoScribe();
        MakeTheLibrary(scribe);
        string media = scribe.FullPath("A", Media);
        UndoKindsForTheCases.MakeAJunction(media, scribe.FullPath("A", Library));
        JsonObject recorded = LinkMove(new DirectoryInfo(media).LinkTarget!);
        UndoOutcome refused = scribe.Door().Perform(scribe.OpsDraft("A", new JsonArray(recorded, edit), []));
        Assert.Equal("notReadable", refused.Word);
        Assert.Equal(UndoLinks.What.Link, UndoLinks.Look(media));
    }

    // ---- Moving ---------------------------------------------------------

    /// <summary>
    /// A junction to a folder in the course, moved to a new name and put back:
    /// one rename of the junction each way, judged by the target it holds; the
    /// folder it leads to keeps its listing and every identity byte for byte.
    /// </summary>
    [Fact]
    public void AJunctionIsMovedAndPutBackAsItselfTheFolderItLeadsToUntouched()
    {
        using var scribe = new UndoScribe();
        string library = MakeTheLibrary(scribe);
        string media = scribe.FullPath("A", Media);
        string renamed = scribe.FullPath("A", Renamed);
        UndoKindsForTheCases.MakeAJunction(media, library);
        string target = new DirectoryInfo(media).LinkTarget!;
        string before = Untouched(library);

        UndoOutcome made = scribe.Door().Perform(scribe.OpsDraft("A", new JsonArray(LinkMove(target)), []));
        Assert.Equal(UndoOutcomeKind.Applied, made.Kind);
        Assert.Equal(UndoLinks.What.Nothing, UndoLinks.Look(media));
        Assert.Equal(UndoLinks.What.Link, UndoLinks.Look(renamed));
        Assert.Equal(target, new DirectoryInfo(renamed).LinkTarget);
        Assert.Equal(before, Untouched(library));

        Assert.Equal("undone", scribe.Undo().Name);
        Assert.Equal(UndoLinks.What.Link, UndoLinks.Look(media));
        Assert.Equal(UndoLinks.What.Nothing, UndoLinks.Look(renamed));
        Assert.Equal(target, new DirectoryInfo(media).LinkTarget);
        Assert.Equal(before, Untouched(library));

        Assert.Equal("redone", scribe.Redo().Name);
        Assert.Equal(UndoLinks.What.Link, UndoLinks.Look(renamed));
        Assert.Equal(before, Untouched(library));
        Assert.Empty(scribe.StagedLeftovers("A"));
    }

    /// <summary>A link given another target since is changed since: refused, nothing moved, neither folder touched.</summary>
    [Fact]
    public void ALinkGivenAnotherTargetSinceIsChangedSince()
    {
        using var scribe = new UndoScribe();
        string library = MakeTheLibrary(scribe);
        string elsewhere = MakeTheLibrary(scribe, "courses/TST1O/elsewhere");
        string media = scribe.FullPath("A", Media);
        string renamed = scribe.FullPath("A", Renamed);
        UndoKindsForTheCases.MakeAJunction(media, library);
        Assert.Equal(UndoOutcomeKind.Applied, scribe.Door().Perform(scribe.OpsDraft("A", new JsonArray(LinkMove(new DirectoryInfo(media).LinkTarget!)), [])).Kind);

        Directory.Delete(renamed);
        UndoKindsForTheCases.MakeAJunction(renamed, elsewhere);
        string before = Untouched(library) + " | " + Untouched(elsewhere);
        Assert.Equal("changedSince", scribe.Undo().Name);
        Assert.Equal(UndoLinks.What.Nothing, UndoLinks.Look(media));
        Assert.Equal(Path.GetFullPath(elsewhere), Path.GetFullPath(new DirectoryInfo(renamed).LinkTarget!));
        Assert.Equal(before, Untouched(library) + " | " + Untouched(elsewhere));
    }

    /// <summary>A plain folder where the link was, holding what the link led to, is something else: changed since, nothing moved.</summary>
    [Fact]
    public void APlainFolderWhereTheLinkWasIsChangedSince()
    {
        using var scribe = new UndoScribe();
        string library = MakeTheLibrary(scribe);
        string media = scribe.FullPath("A", Media);
        string renamed = scribe.FullPath("A", Renamed);
        UndoKindsForTheCases.MakeAJunction(media, library);
        Assert.Equal(UndoOutcomeKind.Applied, scribe.Door().Perform(scribe.OpsDraft("A", new JsonArray(LinkMove(new DirectoryInfo(media).LinkTarget!)), [])).Kind);

        Directory.Delete(renamed);
        MakeTheLibrary(scribe, Renamed);
        Assert.Equal("changedSince", scribe.Undo().Name);
        Assert.Equal(UndoLinks.What.Nothing, UndoLinks.Look(media));
        Assert.Equal(UndoLinks.What.Folder, UndoLinks.Look(renamed));
    }

    /// <summary>
    /// A junction leading out of the working folder is moved like any other:
    /// only the folder above it is resolved, and the folder it leads to is
    /// never read or touched.
    /// </summary>
    [Fact]
    public void AJunctionLeadingOutIsMovedLikeAnyOtherWhatItLeadsToNeverTouched()
    {
        using var scribe = new UndoScribe();
        string outside = scribe.FullPath("A", "").TrimEnd(Path.DirectorySeparatorChar) + "-outside-link";
        Directory.CreateDirectory(Path.Combine(outside, "pictures"));
        File.WriteAllText(Path.Combine(outside, "a.md"), "outside\n");
        try
        {
            scribe.WritePage("A", Section + "/page.md", "P\n"u8.ToArray());
            string media = scribe.FullPath("A", Media);
            UndoKindsForTheCases.MakeAJunction(media, outside);
            string before = Untouched(outside);

            UndoOutcome made = scribe.Door().Perform(scribe.OpsDraft("A", new JsonArray(LinkMove(new DirectoryInfo(media).LinkTarget!)), []));
            Assert.Equal(UndoOutcomeKind.Applied, made.Kind);
            Assert.Equal(UndoLinks.What.Link, UndoLinks.Look(scribe.FullPath("A", Renamed)));
            Assert.Equal("undone", scribe.Undo().Name);
            Assert.Equal(UndoLinks.What.Link, UndoLinks.Look(media));
            Assert.Equal(before, Untouched(outside));
        }
        finally
        {
            try { Directory.Delete(outside, recursive: true); } catch { }
        }
    }

    /// <summary>
    /// A symbolic link holding a relative target, as the mac writes one: its
    /// target is held as written (<c>../library</c>, forward slash kept), so
    /// its linkSha is the mac's, and it is moved and put back as itself.
    /// </summary>
    [SymbolicLinkFact]
    public void ASymbolicLinkKeepsItsTargetAsWrittenAndIsMovedAsItself()
    {
        using var scribe = new UndoScribe();
        string library = MakeTheLibrary(scribe);
        string media = scribe.FullPath("A", Media);
        Directory.CreateDirectory(Path.GetDirectoryName(media)!);
        Directory.CreateSymbolicLink(media, "../library");
        Assert.Equal("../library", new DirectoryInfo(media).LinkTarget);
        string before = Untouched(library);

        Assert.Equal(UndoOutcomeKind.Applied, scribe.Door().Perform(scribe.OpsDraft("A", new JsonArray(LinkMove("../library")), [])).Kind);
        Assert.Equal("../library", new DirectoryInfo(scribe.FullPath("A", Renamed)).LinkTarget);
        Assert.Equal("undone", scribe.Undo().Name);
        Assert.Equal("../library", new DirectoryInfo(media).LinkTarget);
        Assert.Equal(before, Untouched(library));
    }

    // ---- Reparse points that are not a link it can read ------------------

    /// <summary>A WSL-style link (a name surrogate whose target .NET does not read) where the link is: cannot tell now, never changed since.</summary>
    [ReparsePointFact]
    public void ALinkWhoseTargetCannotBeReadIsCannotTellNow()
    {
        string place = Path.Combine(_folder, "renamed");
        Assert.Null(UndoReparsePoints.Make(place, UndoReparsePoints.WslLink, UndoReparsePoints.WslLinkData("../library")));
        Assert.Equal(UndoLinks.What.Link, UndoLinks.Look(place));
        Assert.Null(UndoLinks.LinkSha(place));
        Assert.Equal(UndoMoveSide.CannotRead, UndoMoveSides.Read(Op(LinkMove("../library")), place));
    }

    /// <summary>A reparse point that is not a name surrogate (as OneDrive's placeholders are not) is a file of the teacher's, never the link: something else.</summary>
    [ReparsePointFact]
    public void AReparsePointThatIsNotALinkIsSomethingElse()
    {
        string place = Path.Combine(_folder, "renamed");
        Assert.Null(UndoReparsePoints.Make(place, UndoReparsePoints.NotALink, new byte[16]));
        Assert.Equal(UndoLinks.What.File, UndoLinks.Look(place));
        Assert.Equal(UndoMoveSide.HoldsSomethingElse, UndoMoveSides.Read(Op(LinkMove("../library")), place));
    }
}

/// <summary>
/// Whether this account may make a symbolic link (Developer Mode, or an
/// administrator's token): null when it may, else why not. The VMs have
/// Developer Mode off (Russell, 2026-11-26), so there every test that needs a
/// symbolic link holding a target as written is SKIPPED with this reason; a
/// junction holds only an absolute target, so it cannot stand in.
/// </summary>
internal static class UndoSymbolicLinks
{
    private static readonly Lazy<string?> WhyNot = new(Probe);

    internal static string? CannotBeMade => WhyNot.Value;

    private static string? Probe()
    {
        if (!OperatingSystem.IsWindows()) return "Windows only";
        string probe = Path.Combine(Path.GetTempPath(), "plantoir-undo-symlink-probe-" + Guid.NewGuid().ToString("N"));
        try
        {
            Directory.CreateSymbolicLink(probe, "../library");
            return null;
        }
        catch (Exception error)
        {
            return "this account cannot make a symbolic link (Developer Mode is off, as in the VMs: " + error.Message.Trim()
                 + "), so a link holding its target as written (../library) cannot be laid on the disk here";
        }
        finally
        {
            try { if (Directory.Exists(probe)) Directory.Delete(probe); } catch { }
        }
    }
}

/// <summary>A fact that needs a symbolic link: SKIPPED, saying why, where this account cannot make one.</summary>
public sealed class SymbolicLinkFactAttribute : FactAttribute
{
    public SymbolicLinkFactAttribute()
    {
        if (UndoSymbolicLinks.CannotBeMade is { } why) Skip = why;
    }
}

/// <summary>A theory whose rows each need a symbolic link: SKIPPED, saying why, where this account cannot make one.</summary>
public sealed class SymbolicLinkTheoryAttribute : TheoryAttribute
{
    public SymbolicLinkTheoryAttribute()
    {
        if (UndoSymbolicLinks.CannotBeMade is { } why) Skip = why;
    }
}

/// <summary>A fact that sets a reparse point of its own on a file: SKIPPED, saying why, where the volume or this account refuses it.</summary>
public sealed class ReparsePointFactAttribute : FactAttribute
{
    private static readonly Lazy<string?> WhyNot = new(() =>
    {
        if (!OperatingSystem.IsWindows()) return "Windows only";
        string probe = Path.Combine(Path.GetTempPath(), "plantoir-undo-reparse-probe-" + Guid.NewGuid().ToString("N"));
        try { return UndoReparsePoints.Make(probe, UndoReparsePoints.NotALink, new byte[16]); }
        finally { try { File.Delete(probe); } catch { } }
    });

    public ReparsePointFactAttribute()
    {
        if (WhyNot.Value is { } why) Skip = "a reparse point of the test's own cannot be set here: " + why;
    }
}

/// <summary>
/// A reparse point set on an empty file by <c>FSCTL_SET_REPARSE_POINT</c>, for
/// the two kinds no junction or symbolic link gives: WSL's own link
/// (<c>IO_REPARSE_TAG_LX_SYMLINK</c>, a name surrogate whose target .NET does
/// not read) and a tag that is not a name surrogate (<c>IO_REPARSE_TAG_DEDUP</c>,
/// standing in for OneDrive's, whose filter refuses a tag set by hand).
/// </summary>
internal static class UndoReparsePoints
{
    internal const uint WslLink = 0xA000001D;
    internal const uint NotALink = 0x80000013;

    /// <summary>WSL's link data: a version (2), then the target as UTF-8.</summary>
    internal static byte[] WslLinkData(string target)
    {
        byte[] text = Encoding.UTF8.GetBytes(target);
        byte[] data = new byte[4 + text.Length];
        BitConverter.GetBytes(2u).CopyTo(data, 0);
        text.CopyTo(data, 4);
        return data;
    }

    /// <summary>Makes an empty file at <paramref name="file"/> and sets the reparse point on it: null when made, else why not.</summary>
    internal static string? Make(string file, uint tag, byte[] data)
    {
        Directory.CreateDirectory(Path.GetDirectoryName(file)!);
        File.WriteAllBytes(file, []);
        using SafeFileHandle handle = CreateFileW(file, GenericWrite, 0, IntPtr.Zero, OpenExisting, BackupSemantics | OpenReparsePoint, IntPtr.Zero);
        if (handle.IsInvalid) return "the file could not be opened (" + Marshal.GetLastWin32Error() + ")";
        byte[] buffer = new byte[8 + data.Length];
        BitConverter.GetBytes(tag).CopyTo(buffer, 0);
        BitConverter.GetBytes((ushort)data.Length).CopyTo(buffer, 4);
        data.CopyTo(buffer, 8);
        if (!DeviceIoControl(handle, SetReparsePoint, buffer, buffer.Length, IntPtr.Zero, 0, out _, IntPtr.Zero))
            return "FSCTL_SET_REPARSE_POINT answered " + Marshal.GetLastWin32Error();
        return null;
    }

    /// <summary>Sets the reparse point on the EMPTY folder at <paramref name="folder"/>: null when set, else why not (#899 W8b-15a).</summary>
    internal static string? MakeOnAFolder(string folder, uint tag, byte[] data)
    {
        using SafeFileHandle handle = CreateFileW(folder, GenericWrite, 0, IntPtr.Zero, OpenExisting, BackupSemantics | OpenReparsePoint, IntPtr.Zero);
        if (handle.IsInvalid) return "the folder could not be opened (" + Marshal.GetLastWin32Error() + ")";
        byte[] buffer = new byte[8 + data.Length];
        BitConverter.GetBytes(tag).CopyTo(buffer, 0);
        BitConverter.GetBytes((ushort)data.Length).CopyTo(buffer, 4);
        data.CopyTo(buffer, 8);
        if (!DeviceIoControl(handle, SetReparsePoint, buffer, buffer.Length, IntPtr.Zero, 0, out _, IntPtr.Zero))
            return "FSCTL_SET_REPARSE_POINT answered " + Marshal.GetLastWin32Error();
        return null;
    }

    private const uint GenericWrite = 0x40000000;
    private const uint OpenExisting = 3;
    private const uint BackupSemantics = 0x02000000;
    private const uint OpenReparsePoint = 0x00200000;
    private const uint SetReparsePoint = 0x000900A4;

    [DllImport("kernel32.dll", CharSet = CharSet.Unicode, SetLastError = true)]
    private static extern SafeFileHandle CreateFileW(string name, uint access, uint share, IntPtr security, uint disposition, uint flags, IntPtr template);

    [DllImport("kernel32.dll", SetLastError = true)]
    private static extern bool DeviceIoControl(SafeFileHandle device, uint code, byte[] input, int inputSize, IntPtr output, int outputSize, out int returned, IntPtr overlapped);
}
