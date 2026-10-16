using System.Globalization;

namespace Plantoir.Core.Models;

/// <summary>
/// A saved copy of a whole course, made on purpose before risky editing —
/// handing a pile of pages to an LLM, say — so there is always a way back.
///
/// Backups live beside the archives in courses/_backups/&lt;CODE&gt;/, told
/// apart by name: a backup is &lt;CODE&gt;_backup_&lt;timestamp&gt;.zip, an archive is
/// &lt;CODE&gt;_&lt;timestamp&gt;.zip, and the setup wizard's automatic zips are
/// &lt;timestamp&gt;.zip alone. Each parser accepts only its own form, so the
/// three kinds can never appear in each other's lists.
/// </summary>
public abstract record BackupMaker
{
    public sealed record Teacher : BackupMaker
    {
        public override string Description => "made by you";
        public override string NameSuffix => "";
    }

    public sealed record Assistant(int SectionNumber) : BackupMaker
    {
        public override string Description => $"before an assistant chat about Section {SectionNumber}";
        public override string NameSuffix => $"_assistant-section{SectionNumber}";
    }

    /// <summary>
    /// The Section menu made it, before ONE change it made to this section
    /// (#489, the mac's #457 batch B) — Publish Pages…, Hide Pages… and the
    /// rest of the assistant's functions run from the menu bar. One per
    /// change, so it clears up after itself as the assistant does: its five
    /// most recent of a course are kept, counted apart from the assistant's
    /// (<c>course-management.json</c> → <c>backups.pruneCases</c>). Never named
    /// <c>_assistant-section</c>: a teacher who declined the assistant must not
    /// find a copy said to be from a chat they never had.
    /// </summary>
    public sealed record Menu(int SectionNumber) : BackupMaker
    {
        public override string Description => $"before a change from the Section menu to Section {SectionNumber}";
        public override string NameSuffix => $"_menu-section{SectionNumber}";
    }

    public abstract string Description { get; }
    public abstract string NameSuffix { get; }

    public static readonly BackupMaker DefaultTeacher = new Teacher();

    public static BackupMaker? Reading(string piece)
    {
        const string assistantPrefix = "assistant-section";
        if (piece.StartsWith(assistantPrefix, StringComparison.Ordinal))
        {
            if (int.TryParse(piece[assistantPrefix.Length..], out int sectionNumber))
                return new Assistant(sectionNumber);
        }
        const string menuPrefix = "menu-section";
        if (piece.StartsWith(menuPrefix, StringComparison.Ordinal))
        {
            if (int.TryParse(piece[menuPrefix.Length..], NumberStyles.None, CultureInfo.InvariantCulture, out int sectionNumber))
                return new Menu(sectionNumber);
        }
        return null;
    }
}

public sealed record BackupItem(string CourseCode, DateTime BackedUpAt, string FilePath, BackupMaker Maker)
{
    public BackupItem(string courseCode, DateTime backedUpAt, string filePath)
        : this(courseCode, backedUpAt, filePath, BackupMaker.DefaultTeacher)
    {
    }

    public string Id => FilePath;

    public string Title => CourseCode;

    /// <summary>
    /// "11 August 2026 at 10:15 PM" — the moment alone, with the time,
    /// because a careful teacher may make several backups in one evening.
    /// </summary>
    public string WhenDescription =>
        BackedUpAt.ToString("d MMMM yyyy 'at' h:mm tt", CultureInfo.CurrentCulture);

    public string Subtitle => $"Backed up {WhenDescription} · {Maker.Description}";

    public string KeptDescription => Maker switch
    {
        BackupMaker.Assistant => "The assistant made this one; its five most recent are kept.",
        BackupMaker.Menu => "The Section menu made this one before a change; its five most recent are kept.",
        _ => "You made this one, so it is kept until you delete it.",
    };

    /// <summary>
    /// Reads a backup's name: &lt;CODE&gt;_backup_&lt;timestamp&gt;.zip for one the
    /// teacher made, and &lt;CODE&gt;_backup_&lt;timestamp&gt;_assistant-section&lt;N&gt;.zip
    /// for one the assistant made, &lt;…&gt;_menu-section&lt;N&gt;.zip for one the
    /// Section menu made. Returns null for anything else — archives
    /// and the wizard's automatic zips included.
    /// </summary>
    public static BackupItem? From(string filePath, string courseCode)
    {
        if (!filePath.EndsWith(".zip", StringComparison.OrdinalIgnoreCase)) return null;
        string name = Path.GetFileNameWithoutExtension(filePath);
        string expectedPrefix = courseCode + "_backup_";
        if (!name.StartsWith(expectedPrefix, StringComparison.Ordinal)) return null;

        string remainder = name[expectedPrefix.Length..];
        string[] pieces = remainder.Split('_');
        if (pieces.Length < 2 || pieces.Length > 3) return null;

        // A second copy saved within the same second carries "-2" (then "-3")
        // after its time — the mac's CourseArchiver.unusedBackupName (#489,
        // mac #457 batch B; course-management.json → zipNames). Read past it
        // as the same moment, and nothing else: "-1" and "-x" leave the whole
        // name unrecognised. This app's own writer still WAITS for the next
        // second instead (#187); it reads the mac's form so a copy the mac
        // made is listed, restored and counted here.
        string timePiece = pieces[1];
        int dash = timePiece.IndexOf('-');
        if (dash >= 0)
        {
            if (!int.TryParse(timePiece[(dash + 1)..], NumberStyles.None, CultureInfo.InvariantCulture, out int counter)
                || counter < 2)
                return null;
            timePiece = timePiece[..dash];
        }
        string stamp = pieces[0] + "_" + timePiece;
        if (!DateTime.TryParseExact(stamp, ArchivedItem.StampFormat, CultureInfo.InvariantCulture,
                                    DateTimeStyles.None, out DateTime backedUpAt))
            return null;

        BackupMaker maker = BackupMaker.DefaultTeacher;
        if (pieces.Length == 3)
        {
            if (BackupMaker.Reading(pieces[2]) is not { } namedMaker)
                return null;
            maker = namedMaker;
        }

        return new BackupItem(courseCode, backedUpAt, filePath, maker);
    }
}
