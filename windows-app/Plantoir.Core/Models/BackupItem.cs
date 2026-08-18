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
        _ => "You made this one, so it is kept until you delete it.",
    };

    /// <summary>
    /// Reads a backup's name: &lt;CODE&gt;_backup_&lt;timestamp&gt;.zip for one the
    /// teacher made, and &lt;CODE&gt;_backup_&lt;timestamp&gt;_assistant-section&lt;N&gt;.zip
    /// for one the assistant made. Returns null for anything else — archives
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

        string stamp = pieces[0] + "_" + pieces[1];
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
