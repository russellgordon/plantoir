using System.IO.Compression;

namespace Plantoir.Core.Models;

/// <summary>
/// A one-section restore (#911, the mac's <c>OneSectionRestore</c>): what it
/// does with each of a section's files outside its folder. The list is
/// <c>contracts/course-management.json</c> →
/// <c>backups.restoreOneSection.filesOutsideTheSection</c>, held against this
/// copy by <c>OneSectionRestoreContractTests</c> (the app reads no contract at
/// run time).
/// </summary>
public static class OneSectionRestore
{
    /// <summary>What a one-section restore does with one of a section's files outside its folder.</summary>
    public enum Treatment
    {
        /// <summary>Put back as the backup has it, and removed when the backup has none.</summary>
        FromTheBackup,
        /// <summary>Removed, because the build writes it again from the pages.</summary>
        Discarded,
        /// <summary>Left exactly as it is, because it describes the live website.</summary>
        LeftAsItIs,
    }

    /// <summary>One of a section's files outside its folder, by its path inside the course folder with <c>{N}</c> for the section number.</summary>
    public sealed record OutsideFile(string PathTemplate, bool IsFolder, Treatment Treatment)
    {
        /// <summary>The path inside the course folder for one section, with Windows separators.</summary>
        public string PathFor(int sectionNumber) =>
            PathTemplate.Replace("{N}", sectionNumber.ToString(System.Globalization.CultureInfo.InvariantCulture))
                        .Replace('/', Path.DirectorySeparatorChar);
    }

    /// <summary>Every file of one section that lives outside <c>section&lt;N&gt;\</c>, and what a one-section restore does with it: the mac's nine, in its order.</summary>
    public static readonly IReadOnlyList<OutsideFile> FilesOutsideTheSection = new[]
    {
        new OutsideFile(".internal/timetable/section{N}.json", false, Treatment.FromTheBackup),
        new OutsideFile(".publish_state/section{N}.published-pages", true, Treatment.FromTheBackup),
        new OutsideFile(".publish_state/section{N}.links-checklist-answered.json", false, Treatment.FromTheBackup),
        new OutsideFile(".publish_state/section{N}.later-classes-kept.json", false, Treatment.FromTheBackup),
        new OutsideFile(".publish_state/section{N}.front-page-not-today.json", false, Treatment.FromTheBackup),
        new OutsideFile(".publish_state/section{N}.links-checklist.json", false, Treatment.Discarded),
        new OutsideFile(".publish_state/section{N}.json", false, Treatment.LeftAsItIs),
        new OutsideFile(".netlify_sites/section{N}.json", false, Treatment.LeftAsItIs),
        new OutsideFile(".cloudflare_sites/section{N}.json", false, Treatment.LeftAsItIs),
    };

    /// <summary>What a one-section restore from the menu did, for the finished sentence and the trail (the mac's <c>Outcome</c>).</summary>
    /// <param name="PagesNotPutBack">Shared pages whose setting for this section could not be put back: no column-0 place for a new key (#186's shape).</param>
    /// <param name="PagesNotSaved">Shared pages whose new text could not be saved, so they are as they were.</param>
    /// <param name="PagesMadeSinceHidden">Shared pages made after the backup that were visible to this section and are now hidden from it.</param>
    /// <param name="WebsiteRecordDiffers">The backup's record of this section's website differs from the live one, which is left as it is.</param>
    public sealed record Outcome(int PagesNotPutBack, int PagesNotSaved, int PagesMadeSinceHidden, bool WebsiteRecordDiffers);

    /// <summary>
    /// The folders at the TOP of a course that Quartz never publishes
    /// (<c>shared-rules.json</c> → <c>geogebraFences.files.notPublished.folders</c>,
    /// held against this copy by <c>OneSectionRestoreContractTests</c>): a page
    /// in one is never given a key by the restore, because a template made
    /// since the backup and hidden here would hide every page later made from it.
    /// </summary>
    public static readonly IReadOnlyList<string> FoldersNeverPublished = new[] { "private", "templates", ".obsidian" };

    /// <summary>Whether a page, by its path inside the course folder, is one Quartz publishes: not under a top folder <see cref="FoldersNeverPublished"/> names, and no part of its path starting with a dot (the mac's <c>isPublishable</c>).</summary>
    public static bool IsPublishable(string relativePath)
    {
        string[] parts = relativePath.Split(new[] { '/', '\\' }, StringSplitOptions.RemoveEmptyEntries);
        if (parts.Length > 0 && FoldersNeverPublished.Contains(parts[0])) return false;
        foreach (string part in parts)
            if (part.StartsWith('.')) return false;
        return true;
    }

    // ---- When one section is offered (step 2 of #911) ----------------------

    /// <summary>Why a backup's naming does not fit the course now.</summary>
    public enum NamingDifference
    {
        /// <summary>The word for a unit, the class page scheme or the class folder.</summary>
        ClassPages,
        /// <summary>A folder the backup lists has been renamed or removed since.</summary>
        Folders,
    }

    /// <summary>
    /// The facts about naming that decide whether a backup's class pages
    /// still mean anything in the course as it is now (the mac's
    /// <c>OneSectionRestore.Naming</c>).
    /// </summary>
    public sealed record Naming(string Word, ClassPageScheme Scheme, string ClassFolder,
                                IReadOnlyList<string> SharedFolders, IReadOnlyList<string> PerSectionFolders)
    {
        /// <summary>The naming a course's settings record.</summary>
        public static Naming Of(CourseConfiguration configuration) => new(
            configuration.UnitWord,
            ClassPageSchemes.Reading(configuration.ClassPageSchemeRaw),
            ClassFolderRule.Name(configuration.ClassFolder, configuration.PerSectionFolders),
            configuration.SharedFolders,
            configuration.PerSectionFolders);

        /// <summary>
        /// What stands between a backup made under <paramref name="backup"/>
        /// and a course named as this one now, or null when one section can be
        /// put back. A folder ADDED since never counts: every preview build
        /// adds new top-level folders to these lists
        /// (<c>build_site.preflight_update_course_config</c>, measured on the
        /// mac), so an exact comparison would withdraw the offer after any new
        /// folder. A folder the backup lists that is gone now does: a rename
        /// rewrote every page's links to the new name.
        /// </summary>
        public NamingDifference? DifferenceFromBackup(Naming backup)
        {
            if (Word != backup.Word || Scheme != backup.Scheme || ClassFolder != backup.ClassFolder)
                return NamingDifference.ClassPages;
            foreach (string folder in backup.SharedFolders)
                if (!SharedFolders.Contains(folder)) return NamingDifference.Folders;
            foreach (string folder in backup.PerSectionFolders)
                if (!PerSectionFolders.Contains(folder)) return NamingDifference.Folders;
            return null;
        }
    }

    /// <summary>What a backup zip holds that the offer needs: its <c>section&lt;N&gt;\</c> folders, and its naming (null when its settings could not be read).</summary>
    public sealed record BackupFacts(IReadOnlySet<int> SectionsInside, Naming? Naming);

    /// <summary>
    /// The section a backup offers to put back on its own, or null for
    /// today's whole-course question (the mac's <c>offeredSection</c>,
    /// <c>offerCases</c>): the backup was made for ONE section, by the
    /// Section menu or the assistant; that section is in the course now; the
    /// course is not kept for reference; no rename is half done; the zip holds
    /// the section's folder; and the course names its class pages the way the
    /// backup did.
    /// </summary>
    public static int? OfferedSection(BackupMaker maker, bool sectionExistsNow, bool keptForReference,
                                      bool renameUnfinished, bool backupHasTheSection, bool namingSameAsNow)
    {
        int? madeFor = maker switch
        {
            BackupMaker.Assistant assistant => assistant.SectionNumber,
            BackupMaker.Menu menu => menu.SectionNumber,
            _ => null,
        };
        if (madeFor is null) return null;
        if (!sectionExistsNow || keptForReference || renameUnfinished) return null;
        if (!backupHasTheSection || !namingSameAsNow) return null;
        return madeFor;
    }

    /// <summary>The section a backup was made for, or null for a teacher's own copy of the whole course.</summary>
    public static int? MadeFor(BackupMaker maker) => maker switch
    {
        BackupMaker.Assistant assistant => assistant.SectionNumber,
        BackupMaker.Menu menu => menu.SectionNumber,
        _ => null,
    };

    /// <summary>
    /// The section Restore from Backup… offers for this backup, or null for
    /// today's two-button question (the mac's <c>WorkspaceModel.oneSectionRestoreOffer</c>,
    /// which gathers the facts <see cref="OfferedSection"/> decides on).
    /// <paramref name="course"/> is the course as loaded; its naming is asked
    /// of the settings as SAVED, as the restorer asks them, because a build
    /// may have added a folder since the window last read them.
    /// <paramref name="facts"/> is read once per backup by the caller
    /// (<see cref="ReadFacts"/>), before the dialog opens.
    /// </summary>
    public static int? OfferFor(BackupItem item, Course? course, BackupFacts facts)
    {
        if (MadeFor(item.Maker) is not int section || course is null) return null;
        bool sectionExistsNow = course.Configuration.SectionNumbers.Contains(section) && Directory.Exists(course.SectionDirectory(section));
        bool namingSameAsNow = facts.Naming is { } backedUp && Naming.Of(SavedConfiguration(course)).DifferenceFromBackup(backedUp) is null;
        return OfferedSection(item.Maker, sectionExistsNow, ReferenceCourse.IsKeptForReference(course),
            RenameIsUnfinished(course.DirectoryPath), facts.SectionsInside.Contains(section), namingSameAsNow);
    }

    /// <summary>
    /// Why this section may not be put back on its own from this backup,
    /// asked again at the click, before the archive, or null when it may (the
    /// mac's <c>oneSectionRestoreRefusal</c>, reason for reason, in its
    /// order). Each is a reason <see cref="OfferedSection"/> would have
    /// withheld the offer for, so a click refused here leaves nothing in Archived.
    /// </summary>
    public static string? RefusalAtTheClick(int section, BackupItem item, Course? course, BackupFacts facts)
    {
        if (MadeFor(item.Maker) != section) return OneSectionRestoreWording.NotMadeForThisSection(section);
        if (course is null)
            return $"{item.CourseCode} is not in Courses & Clubs. Restore the course first, then restore this section into it.";
        if (ReferenceCourse.IsKeptForReference(course)) return ReferenceCourse.StaysAsItIs(ReferenceCourse.ShownCode(course));
        if (!course.Configuration.SectionNumbers.Contains(section) || !Directory.Exists(course.SectionDirectory(section)))
            return OneSectionRestoreWording.SectionNotInCourse(section, item.CourseCode);
        if (RenameIsUnfinished(course.DirectoryPath)) return OneSectionRestoreWording.RenameUnfinished(section, item.CourseCode);
        if (!facts.SectionsInside.Contains(section)) return CourseRestorer.SectionMissingFromBackup(item.CourseCode, section);
        if (facts.Naming is not { } backedUp) return CourseRestorer.ArchiveUnreadable("its course settings could not be read");
        return Naming.Of(SavedConfiguration(course)).DifferenceFromBackup(backedUp) switch
        {
            NamingDifference.Folders => OneSectionRestoreWording.FoldersChanged(section, item.CourseCode),
            NamingDifference.ClassPages => OneSectionRestoreWording.NamingChanged(section, item.CourseCode),
            _ => null,
        };
    }

    /// <summary>The course's settings as saved now, or as loaded when the file cannot be read.</summary>
    private static CourseConfiguration SavedConfiguration(Course course)
    {
        try { return CourseConfiguration.Load(course.ConfigFilePath); }
        catch (Exception) { return course.Configuration; }
    }

    /// <summary>
    /// Whether a rename of the course's word for a unit, or of its folders,
    /// did not finish: its record is still on disk. The cheap fact, as the
    /// mac asks it, never the walk that can clear the record.
    /// </summary>
    public static bool RenameIsUnfinished(string courseDirectory) =>
        File.Exists(UnitWordRenamer.RenameMarkerPath(courseDirectory))
        || File.Exists(SpecialFolderRenamer.RenameRecordPath(courseDirectory));

    /// <summary>
    /// Reads what the offer needs from a backup zip, once, when the dialog is
    /// about to open (never while it draws): which section folders its
    /// listing holds, and its naming from its <c>course_config.json</c> entry
    /// alone, read from the entry's stream. Nothing is unpacked. A zip that
    /// cannot be read holds nothing, so it is never offered.
    /// </summary>
    public static BackupFacts ReadFacts(string zipPath)
    {
        var sections = new HashSet<int>();
        try
        {
            using var archive = ZipFile.OpenRead(zipPath);
            ZipArchiveEntry? settings = null;
            foreach (var entry in archive.Entries)
            {
                string name = entry.FullName.Replace('\\', '/');
                string[] parts = name.Split('/', StringSplitOptions.RemoveEmptyEntries);
                if (parts.Length == 2 && parts[1] == "course_config.json" && !name.EndsWith('/')) settings = entry;
                // "ICS3U/section2/" (the folder's own entry) or anything inside
                // it; a FILE called "section2" at the course's root is not one.
                bool isTheFolderItself = parts.Length == 2 && name.EndsWith('/');
                if ((isTheFolderItself || parts.Length >= 3) && CourseRestorer.NamesASectionFolder(parts[1])
                    && int.TryParse(parts[1].AsSpan("section".Length), System.Globalization.NumberStyles.None,
                                    System.Globalization.CultureInfo.InvariantCulture, out int number))
                    sections.Add(number);
            }
            Naming? naming = null;
            if (settings is not null)
            {
                try
                {
                    using var stream = settings.Open();
                    using var bytes = new MemoryStream();
                    stream.CopyTo(bytes);
                    naming = Naming.Of(CourseConfiguration.FromBytes(bytes.ToArray()));
                }
                catch (Exception) { naming = null; }
            }
            return new BackupFacts(sections, naming);
        }
        catch (Exception)
        {
            return new BackupFacts(new HashSet<int>(), null);
        }
    }
}
