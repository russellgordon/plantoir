using System.Globalization;
using System.IO.Compression;
using Plantoir.Core.Scripting;
using Plantoir.Core.Undo;

namespace Plantoir.Core.Models;

/// <summary>
/// Brings an archived course or section back. Nothing is ever written over —
/// what is in the way may be newer work, so the restore refuses and explains.
/// </summary>
public static class CourseRestorer
{
    public class RestoreException(string message) : Exception(message);

    /// <summary>
    /// A one-section restore moved a file and then could not move every file
    /// back (#911, the mac's <c>sectionRestoreStoppedPartWay</c>): the message
    /// is the whole sentence, <c>wording.stoppedPartWay</c> or
    /// <c>stoppedPartWayNothingToOpen</c>, so a caller says it as it is and
    /// never puts "Nothing was put back:" in front.
    /// </summary>
    public sealed class SectionRestoreStoppedPartWay(string message) : RestoreException(message);

    public static void Restore(ArchivedItem item, string coursesDirectory, IReadOnlyList<Course> courses)
    {
        if (item.SectionNumber is int section)
        {
            Course? course = courses.FirstOrDefault(c => c.Code == item.CourseCode);
            if (course is null)
                throw new RestoreException(
                    $"{item.CourseCode} is not in Courses & Clubs. Restore the course first, then restore this section into it.");
            if (ReferenceCourse.IsKeptForReference(course))
                throw new RestoreException(ReferenceCourse.StaysAsItIs(ReferenceCourse.ShownCode(course)));
            string sectionDir = course.SectionDirectory(section);
            if (Directory.Exists(sectionDir))
                throw new RestoreException(
                    $"Section {section} of {item.CourseCode} already exists. Remove it first if you want the archived copy back.");
            Extract(item.FilePath, "section" + section, course.DirectoryPath);
            PutSectionBack(course, section);
            // The restored section's notes can be OLDER than a built site left
            // standing outside the working folder, which would read as "already
            // up to date" and publish the site this section used to have.
            CourseArchiver.DiscardBuilds(coursesDirectory, item.CourseCode, section);
        }
        else
        {
            string courseDir = Path.Combine(coursesDirectory, item.CourseCode);
            if (Directory.Exists(courseDir))
                throw new RestoreException(
                    $"{item.CourseCode} is already in Courses & Clubs. Remove it first if you want the archived copy back.");
            Extract(item.FilePath, item.CourseCode, coursesDirectory);
            CourseArchiver.DiscardBuilds(coursesDirectory, item.CourseCode);
            LockAgainIfKeptForReference(courseDir);
        }
        // A restored thing is no longer archived (failure to delete is not fatal).
        try { File.Delete(item.FilePath); } catch { }
    }

    /// <summary>The whole-course restore's busy refusal: its title, while a preview or deploy of the course uses its folders.</summary>
    public static string BusyTitle(string courseCode) => $"{courseCode} is busy right now";

    /// <summary>The whole-course restore's busy refusal: what it says under <see cref="BusyTitle"/>.</summary>
    public const string BusyMessage =
        "Restoring replaces the course's folders and files, and a preview or deploy " +
        "of this course is still using them. Try again when it finishes.";

    /// <summary>
    /// The whole-course restore Restore from Backup… and Get Ready's Restore
    /// Course both run (#899 W8c-2b; never a second restore): the course as it
    /// is now archived first and left in place, then <see cref="RestoreBackup"/>,
    /// then the trail line, once it has happened. Throws as they do.
    /// </summary>
    public static void RestoreWholeCourse(BackupItem item, Course? current, string coursesDirectory)
    {
        string? archivedFirst = null;
        if (current is not null)
            archivedFirst = CourseArchiver.ArchiveCourseWithoutRemoving(current, coursesDirectory);
        RestoreBackup(item, coursesDirectory);
        ActivityTrail.Note(ActivityTrail.Event.CourseRestoredFromABackup,
            RestoredTrailLine(item, archivedFirst, coursesDirectory));
    }

    /// <summary>
    /// Puts a backup's contents back (row 106). The current version was
    /// already archived by the caller — even a restore has an undo — and the
    /// backup zip STAYS: only deleting removes it.
    ///
    /// When the course folder still exists, its CONTENTS are replaced rather
    /// than the folder itself: the folder is Obsidian's vault, and Obsidian's
    /// file watcher is anchored to it — swap the folder and Obsidian shows
    /// stale files until the vault is reopened; swap the contents and it
    /// refreshes on its own. Unpacked and verified BEFORE anything is
    /// touched, so an unreadable zip can never leave an emptied folder.
    /// </summary>
    public static void RestoreBackup(BackupItem item, string coursesDirectory)
    {
        string destination = Path.Combine(coursesDirectory, item.CourseCode);
        if (!Directory.Exists(destination))
        {
            Extract(item.FilePath, item.CourseCode, coursesDirectory);
            // The built sites go and the kept copies of geogebra.org sketches
            // stay (#805, the mac's discardBuiltSites): a copy is named by its
            // fence, so it is right for the pages that come back.
            CourseArchiver.DiscardBuiltSites(coursesDirectory, item.CourseCode);
            LockAgainIfKeptForReference(destination);
            return;
        }

        string staging = Path.Combine(Path.GetTempPath(), "restore-" + Guid.NewGuid());
        Directory.CreateDirectory(staging);
        try
        {
            string payload = Unpack(item.FilePath, item.CourseCode, staging);

            // A reference course is locked (#241): unlock what is about to be
            // written over, and lock again below — asked of the settings AFTER
            // the restore, so a backup made before the course was kept for
            // reference restores a course that is not one.
            ReferenceLock.Unlock(destination);

            // Out with the current contents (hidden files included — the
            // backup carries its own .obsidian), in with the backup's.
            foreach (string child in Directory.EnumerateFileSystemEntries(destination))
                DeleteTree(child);
            foreach (string child in Directory.EnumerateFileSystemEntries(payload))
            {
                string target = Path.Combine(destination, Path.GetFileName(child));
                if (Directory.Exists(child)) Directory.Move(child, target);
                else File.Move(child, target);
            }
        }
        finally
        {
            // Whatever happened to the contents, the built site no longer
            // matches them: a backup's pages are by definition older than the
            // ones just replaced, so a build left standing would read as newer
            // and publish what the course used to say. The kept copies of
            // geogebra.org sketches stay (#805): each is named by the fence
            // that asked for it, which no restore can make older.
            CourseArchiver.DiscardBuiltSites(coursesDirectory, item.CourseCode);
            // A restored course no longer holds what a stopped rename of its
            // word for a unit was part way through (#158, as the mac does).
            UnitWordRenamer.ClearRenameRecord(destination);
            LockAgainIfKeptForReference(destination);
            try { Directory.Delete(staging, recursive: true); } catch { }
        }
    }


    /// <summary>
    /// Puts ONE section back to how a backup has it, and touches no other:
    /// the built-in assistant window's "Restore Section N…" (the mac's
    /// <c>restoreSection</c>).
    ///
    /// <para>Whole-course restore was rejected for this job for the reason
    /// the mac's <c>AssistSectionRestore</c> gives: a teacher can be marking
    /// Section 2 in Obsidian while they chat about Section 1, and a
    /// whole-course rollback destroys that work. So: the section's own folder
    /// is replaced wholesale, hidden files included; the course's SHARED pages
    /// keep every byte except this section's own per-section frontmatter keys
    /// (<c>publishForSection1:</c> and its relatives), which go back to what
    /// the backup had; and the section's built site is discarded, because
    /// a build left standing would read as newer than the pages just put back.</para>
    ///
    /// <para><b>Staged, then swapped, with a way back (#911, the mac's #897 C,
    /// by Russell's ruling on #897 for this route too).</b> The backup is
    /// unpacked into <c>courses\.internal\restoring\&lt;id&gt;\</c>, on the
    /// courses' own volume, so every move is a rename (<c>%TEMP%</c> can be
    /// another volume, where <c>Directory.Move</c> refuses: #873's first
    /// fault). Nothing in the course moves until the backup is unpacked and
    /// checked; then <see cref="SwapSectionInPlace"/> moves the live children
    /// aside, moves the backup's in, and on a failure moves every moved file
    /// back. Before this the section folder was EMPTIED first and refilled,
    /// and a move that failed part way (a file Obsidian or an editor holds
    /// open) left it half empty.</para>
    /// </summary>
    /// <param name="hooks">The moves and the points a test or the kill harness stops at; <see cref="SectionSwapHooks.Real"/> otherwise.</param>
    /// <returns>How many shared pages kept their current setting because there was nowhere on them to put the backup's back (#308).</returns>
    public static int RestoreSection(int sectionNumber, BackupItem item, string coursesDirectory, SectionSwapHooks? hooks = null)
    {
        hooks ??= SectionSwapHooks.Real;
        string courseDir = Path.Combine(coursesDirectory, item.CourseCode);
        if (!Directory.Exists(courseDir))
            throw new RestoreException($"{item.CourseCode} is not in Courses & Clubs, so there is nowhere to put Section {sectionNumber} back.");
        if (ReadsAsKeptForReference(courseDir) is { } shown)
            throw new RestoreException(ReferenceCourse.StaysAsItIs(shown));

        var staging = new RestoreStaging(coursesDirectory);
        try
        {
            string payload = staging.Unpack(item, hooks);
            string folderName = "section" + sectionNumber;
            if (!Directory.Exists(Path.Combine(payload, folderName)))
                throw new RestoreException($"The copy of {item.CourseCode} does not hold a Section {sectionNumber}.");
            hooks.Reached(SwapPoint.Staged);

            try
            {
                SwapSectionInPlace(sectionNumber, courseDir, payload, Array.Empty<OneSectionRestore.OutsideFile>(), staging.Aside, hooks);
            }
            catch (WayBackDidNotFinish)
            {
                // The window makes no archive first, so it may not say one is in Archived.
                var kept = KeepTheSetAsideFiles(staging.Aside, sectionNumber, item.CourseCode, coursesDirectory);
                staging.KeepAside = kept.IsStillInStaging;
                throw new SectionRestoreStoppedPartWay(StoppedPartWaySentence(sectionNumber, kept.PathToSay, archived: false));
            }
            int notPutBack = RestorePerSectionKeys(sectionNumber, courseDir, payload);
            // The course's kept copies of geogebra.org sketches live at course
            // level (builds\<id>\<CODE>\.geogebra-cache), so a section's discard
            // never reaches them (#805; KeptCopiesTests).
            CourseArchiver.DiscardBuilds(coursesDirectory, item.CourseCode, sectionNumber);
            return notPutBack;
        }
        finally
        {
            staging.Finish();
        }
    }

    /// <summary>
    /// Puts ONE section back from a backup made for it, from Restore from
    /// Backup…'s "Restore Section N" (#911 step 3, the mac's
    /// <c>restoreSectionFromTheMenu</c>, case for case). The caller has
    /// archived the whole course first and asked every refusal again.
    ///
    /// <para>Staged, swapped, with a way back, like <see cref="RestoreSection"/>,
    /// and four things more, each a fault that reported success, each for this
    /// route only (the assistant window's is the mac's frozen one): the
    /// section's files outside its folder (<see cref="OneSectionRestore.FilesOutsideTheSection"/>,
    /// each from the backup, discarded or left as it is); a shared page made
    /// since the backup hidden from this section unless it already is
    /// (<see cref="HidingAPageMadeSinceTheBackup"/>; pages Quartz never
    /// publishes excepted); the course's naming asked again of the UNPACKED
    /// backup; and the legacy website marker in the section's built output
    /// kept across the discarded build.</para>
    ///
    /// <para><paramref name="keepingWhatWasReplaced"/> is the seam for Undo
    /// (W9, the mac's #899 U5): handed the folder holding everything the swap
    /// moved aside, after the swap and before that folder is removed. No
    /// caller passes it yet.</para>
    /// </summary>
    public static OneSectionRestore.Outcome RestoreSectionFromTheMenu(int sectionNumber, BackupItem item, string coursesDirectory,
        SectionSwapHooks? hooks = null, Action<string>? keepingWhatWasReplaced = null) =>
        RestoreSectionFromTheMenu(sectionNumber, item, coursesDirectory, UndoListForARestore.OfThisProcess, hooks, keepingWhatWasReplaced);

    /// <summary>The same, holding <paramref name="theList"/> (this process's list in the app; a test's own in a test).</summary>
    internal static OneSectionRestore.Outcome RestoreSectionFromTheMenu(int sectionNumber, BackupItem item, string coursesDirectory,
        Func<UndoListForARestore> theList, SectionSwapHooks? hooks = null, Action<string>? keepingWhatWasReplaced = null)
    {
        hooks ??= SectionSwapHooks.Real;
        string courseDir = Path.Combine(coursesDirectory, item.CourseCode);
        if (!Directory.Exists(courseDir))
            throw new RestoreException($"{item.CourseCode} is not in Courses & Clubs. Restore the course first, then restore this section into it.");
        CourseConfiguration liveConfiguration;
        try { liveConfiguration = CourseConfiguration.Load(Path.Combine(courseDir, "course_config.json")); }
        catch (Exception error) { throw new RestoreException($"The course settings of {item.CourseCode} could not be read: {error.Message}"); }
        var liveCourse = new Course(item.CourseCode, courseDir, liveConfiguration);
        if (ReferenceCourse.IsKeptForReference(liveCourse))
            throw new RestoreException(ReferenceCourse.StaysAsItIs(ReferenceCourse.ShownCode(liveCourse)));
        if (!liveConfiguration.SectionNumbers.Contains(sectionNumber))
            throw new RestoreException(OneSectionRestoreWording.SectionNotInCourse(sectionNumber, item.CourseCode));

        var staging = new RestoreStaging(coursesDirectory);
        try
        {
            // Unpack and check BEFORE anything in the course moves.
            string payload = staging.Unpack(item, hooks);
            if (!Directory.Exists(Path.Combine(payload, "section" + sectionNumber)))
                throw new RestoreException(SectionMissingFromBackup(item.CourseCode, sectionNumber));
            CourseConfiguration backedUpConfiguration;
            try { backedUpConfiguration = CourseConfiguration.Load(Path.Combine(payload, "course_config.json")); }
            catch (Exception) { throw new RestoreException(ArchiveUnreadable("its course settings could not be read")); }
            switch (OneSectionRestore.Naming.Of(liveConfiguration).DifferenceFromBackup(OneSectionRestore.Naming.Of(backedUpConfiguration)))
            {
                case OneSectionRestore.NamingDifference.ClassPages:
                    throw new RestoreException(OneSectionRestoreWording.NamingChanged(sectionNumber, item.CourseCode));
                case OneSectionRestore.NamingDifference.Folders:
                    throw new RestoreException(OneSectionRestoreWording.FoldersChanged(sectionNumber, item.CourseCode));
            }
            bool websiteRecordDiffers = WebsiteRecordDiffers(sectionNumber, courseDir, payload);
            hooks.Reached(SwapPoint.Staged);

            try
            {
                SwapSectionInPlace(sectionNumber, courseDir, payload, OneSectionRestore.FilesOutsideTheSection, staging.Aside, hooks, keepingWhatWasReplaced);
            }
            catch (WayBackDidNotFinish)
            {
                var kept = KeepTheSetAsideFiles(staging.Aside, sectionNumber, item.CourseCode, coursesDirectory);
                staging.KeepAside = kept.IsStillInStaging;
                throw new SectionRestoreStoppedPartWay(StoppedPartWaySentence(sectionNumber, kept.PathToSay, archived: true));
            }

            var keys = RestorePerSectionKeysFromTheMenu(sectionNumber, courseDir, payload);
            DiscardBuiltSiteKeepingItsWebsiteMarker(sectionNumber, item.CourseCode, coursesDirectory);
            return new OneSectionRestore.Outcome(keys.NotPutBack, keys.NotSaved, keys.MadeSinceHidden, websiteRecordDiffers);
        }
        finally
        {
            staging.Finish();
        }
    }

    /// <summary>The mac's <c>Problem.sectionMissingFromBackup</c>.</summary>
    public static string SectionMissingFromBackup(string courseCode, int sectionNumber) =>
        $"That copy of {courseCode} has no Section {sectionNumber} in it, so there is nothing to put back.";

    /// <summary>The mac's <c>Problem.archiveUnreadable</c>.</summary>
    public static string ArchiveUnreadable(string reason) => $"The archive could not be opened: {reason}";

    /// <summary>
    /// Whether the backup's record of where this section's website is differs
    /// from the live one (the mac's <c>websiteRecordDiffers</c>): the
    /// <c>leftAsItIs</c> markers outside <c>.publish_state</c> (the deploy
    /// stamp says when, not where), compared as parsed JSON. With no live
    /// marker that reads, nothing is said: the section then has no address
    /// until its next deploy makes one.
    /// </summary>
    private static bool WebsiteRecordDiffers(int sectionNumber, string courseDir, string payload)
    {
        foreach (var file in OneSectionRestore.FilesOutsideTheSection)
        {
            if (file.Treatment != OneSectionRestore.Treatment.LeftAsItIs) continue;
            if (file.PathTemplate.StartsWith(".publish_state/", StringComparison.Ordinal)) continue;
            string relative = file.PathFor(sectionNumber);
            if (ParsedMarker(Path.Combine(courseDir, relative)) is not { } live) continue;
            var backedUp = ParsedMarker(Path.Combine(payload, relative));
            if (backedUp is null || !Newtonsoft.Json.Linq.JToken.DeepEquals(live, backedUp)) return true;
        }
        return false;
    }

    private static Newtonsoft.Json.Linq.JToken? ParsedMarker(string path)
    {
        try { return File.Exists(path) ? Newtonsoft.Json.Linq.JToken.Parse(File.ReadAllText(path)) : null; }
        catch { return null; }
    }

    /// <summary>
    /// The section's built site discarded, keeping the one file in it that is
    /// not derived from its pages: the legacy Netlify marker
    /// (<c>.netlify_site.json</c>, which <c>deploy.py</c> still reads), so the
    /// next deploy goes to the site the section already has (the mac's
    /// <c>discardBuiltSiteKeepingItsWebsiteMarker</c>). On Windows it lives in
    /// the section's build root (<see cref="BuildOutputLocation.ForSection"/>),
    /// where the launchers put it.
    /// </summary>
    private static void DiscardBuiltSiteKeepingItsWebsiteMarker(int sectionNumber, string courseCode, string coursesDirectory)
    {
        string? marker = CourseArchiver.BuildsRootOf(coursesDirectory) is { } root
            ? Path.Combine(BuildOutputLocation.ForSection(root, courseCode, sectionNumber), ".netlify_site.json")
            : null;
        byte[]? kept = null;
        try { if (marker is not null && File.Exists(marker)) kept = File.ReadAllBytes(marker); } catch { kept = null; }
        CourseArchiver.DiscardBuilds(coursesDirectory, courseCode, sectionNumber);
        if (kept is null || marker is null) return;
        try
        {
            Directory.CreateDirectory(Path.GetDirectoryName(marker)!);
            File.WriteAllBytes(marker, kept);
        }
        catch { /* as the mac's try?: the build writes a site of its own next */ }
    }

    /// <summary>
    /// The shared pages' per-section keys for this section put back as the
    /// backup had them (as <see cref="RestorePerSectionKeys"/>), and the two
    /// things the menu's route adds (the mac's <c>restorePerSectionKeys(…,
    /// fromTheMenu: true)</c>): a shared page the backup LACKS is hidden from
    /// this section unless it already is (never a page Quartz does not
    /// publish), and a page whose rewrite fails is counted, not passed over.
    /// Identity is the path, so a page renamed since counts as made since.
    /// </summary>
    private static (int NotPutBack, int NotSaved, int MadeSinceHidden) RestorePerSectionKeysFromTheMenu(int sectionNumber, string courseDir, string payload)
    {
        int notPutBack = 0, notSaved = 0, madeSinceHidden = 0;
        foreach (string page in SharedMarkdownPages(courseDir))
        {
            string relative = Path.GetRelativePath(courseDir, page);
            string backedUpPage = Path.Combine(payload, relative);
            if (!File.Exists(backedUpPage))
            {
                if (!OneSectionRestore.IsPublishable(relative)) continue;
                string madeSince;
                try { madeSince = File.ReadAllText(page); }
                catch (IOException) { continue; }
                catch (UnauthorizedAccessException) { continue; }
                var hiding = HidingAPageMadeSinceTheBackup(sectionNumber, madeSince);
                if (hiding.NoRoomForAKey) { notPutBack++; continue; }
                if (hiding.Text is not { } hidden) continue;
                try { File.WriteAllText(page, hidden); madeSinceHidden++; }
                catch (IOException) { notSaved++; }
                catch (UnauthorizedAccessException) { notSaved++; }
                continue;
            }
            string liveText, backupText;
            try
            {
                backupText = File.ReadAllText(backedUpPage);
                liveText = File.ReadAllText(page);
            }
            catch (IOException) { continue; }
            catch (UnauthorizedAccessException) { continue; }
            var (rewritten, couldNotBePutBack) = SettingPerSectionKeys(sectionNumber, liveText, backupText);
            if (couldNotBePutBack) notPutBack++;
            if (rewritten == liveText) continue;
            try { File.WriteAllText(page, rewritten); }
            catch (IOException) { notSaved++; }
            catch (UnauthorizedAccessException) { notSaved++; }
        }
        return (notPutBack, notSaved, madeSinceHidden);
    }

    /// <summary>
    /// What hiding a shared page made since the backup comes to (the mac's
    /// <c>hidingAPageMadeSinceTheBackup</c>): null text and no "no room" when
    /// the build already reads it as hidden for this section; otherwise the
    /// page with <c>publishForSection&lt;N&gt;: false</c> written by the
    /// ordinary setter, or "no room" when its settings have no column-0 place
    /// for a key. Rejected (the mac's amendment 18): taking this section's
    /// keys OFF the page, which would PUBLISH a page whose plain
    /// <c>publish:</c> is true and that the teacher hid for this section.
    /// </summary>
    public static (string? Text, bool NoRoomForAKey) HidingAPageMadeSinceTheBackup(int sectionNumber, string liveText)
    {
        if (PageFrontmatter.IsDraft(liveText, sectionNumber)) return (null, false);
        var (after, edit) = PageFrontmatter.SetDraft(liveText, PageFrontmatter.PublishKeyFor(sectionNumber, isSectionLocal: false), true, sectionNumber);
        if (edit.NoRoomForAKey) return (null, true);
        return after == liveText ? (null, false) : (after, false);
    }

    // ---- The staged swap of one section (#911, the mac's #897 C) ----------

    /// <summary>
    /// Points a test, or the kill harness, can stop a one-section restore at
    /// (the mac's <c>SwapPoint</c>).
    /// </summary>
    public enum SwapPoint
    {
        /// <summary>The backup is unpacked and checked; nothing in the course has moved.</summary>
        Staged,
        /// <summary>Every live file the swap replaces is aside and none of the backup's is in: the moment the old code had an EMPTY section folder.</summary>
        SetAside,
        /// <summary>The shared pages' per-section keys are written (the mac's <c>perSectionKeysPutBack</c>), inside the list's lock.</summary>
        PerSectionKeysPutBack,
    }

    /// <summary>
    /// How a one-section restore moves an entry, and what it does at each
    /// <see cref="SwapPoint"/> (the mac's <c>SectionSwapHooks</c>).
    /// <see cref="Real"/> everywhere but the tests: the double-failure sweep
    /// throws from <see cref="Move"/>, the real-fault tests only interleave a
    /// real file handle with it, and the kill harness blocks in it.
    /// </summary>
    public sealed class SectionSwapHooks
    {
        public required Action<string, string> Move { get; init; }
        public required Action<SwapPoint> Reached { get; init; }
        /// <summary>Called after each entry of the backup is unpacked, with how many are out so far: where the kill harness stops part way through the unpack.</summary>
        public Action<int> UnpackedAnEntry { get; init; } = _ => { };

        public static SectionSwapHooks Real { get; } = new() { Move = MoveEntry, Reached = _ => { } };
    }

    /// <summary>
    /// Renames one entry: a folder (or a junction or folder link, which moves
    /// AS a link) with <c>Directory.Move</c>, anything else with
    /// <c>File.Move</c>. Never a copy: both refuse another volume, which the
    /// staging folder beside the courses makes impossible.
    /// </summary>
    public static void MoveEntry(string source, string destination)
    {
        if ((File.GetAttributes(source) & FileAttributes.Directory) != 0) Directory.Move(source, destination);
        else File.Move(source, destination);
    }

    /// <summary>Thrown by <see cref="SwapSectionInPlace"/> when a move failed AND a move back failed too.</summary>
    private sealed class WayBackDidNotFinish : Exception;

    /// <summary>
    /// A restore's working folder, <c>courses\.internal\restoring\&lt;id&gt;\</c>
    /// (the mac's <c>stagingFolderBesideTheCourses</c>), holding <c>backup\</c>
    /// (the unpacked zip) and <c>as-it-was\</c> (what the swap moves aside).
    /// The mac uses two separate id folders for the assistant's route; one
    /// with two inner folders is the same promise and one place to name.
    /// </summary>
    private sealed class RestoreStaging
    {
        private readonly string _root;
        private readonly string _unpacked;

        public RestoreStaging(string coursesDirectory)
        {
            _root = Path.Combine(coursesDirectory, ".internal", "restoring", Guid.NewGuid().ToString("D").ToUpperInvariant());
            _unpacked = Path.Combine(_root, "backup");
            Aside = Path.Combine(_root, "as-it-was");
        }

        public string Aside { get; }

        /// <summary>True when the aside folder holds the only copy of something and must stay.</summary>
        public bool KeepAside { get; set; }

        /// <summary>
        /// Unpacks the backup into <c>backup\</c>, one entry at a time so the
        /// kill harness can stop part way through (<see cref="SectionSwapHooks.UnpackedAnEntry"/>),
        /// with <c>ZipFile.ExtractToDirectory</c>'s own guard: an entry whose
        /// path would land outside the folder refuses the whole backup.
        /// </summary>
        public string Unpack(BackupItem item, SectionSwapHooks hooks)
        {
            Directory.CreateDirectory(_unpacked);
            string root = Path.GetFullPath(_unpacked) + Path.DirectorySeparatorChar;
            try
            {
                using var archive = ZipFile.OpenRead(item.FilePath);
                int count = 0;
                foreach (var entry in archive.Entries)
                {
                    string target = Path.GetFullPath(Path.Combine(root, entry.FullName));
                    if (!target.StartsWith(root, StringComparison.OrdinalIgnoreCase))
                        throw new IOException("an entry would land outside the folder it is unpacked into");
                    if (entry.FullName.EndsWith('/') || entry.FullName.EndsWith('\\'))
                    {
                        Directory.CreateDirectory(target);
                    }
                    else
                    {
                        Directory.CreateDirectory(Path.GetDirectoryName(target)!);
                        entry.ExtractToFile(target, overwrite: false);
                    }
                    count++;
                    hooks.UnpackedAnEntry(count);
                }
            }
            catch (Exception error)
            {
                throw new RestoreException($"The archive could not be opened: {error.Message}");
            }
            return PayloadIn(_unpacked, item.CourseCode);
        }

        /// <summary>
        /// The unpacked backup always goes. The aside folder goes unless it
        /// must stay: kept by a way back that did not finish, or holding
        /// something backups leave out that went aside inside a folder of the
        /// section (a deeper <c>.git</c>: invariant 2 of the brief, "an only
        /// copy is never deleted"; the question is parked in the notes). Then
        /// <c>restoring</c> and <c>.internal</c>, each only when empty
        /// (<c>Directory.Delete</c> non-recursive refuses a folder that is not,
        /// so a lease written into <c>.internal\activity</c> meanwhile is safe:
        /// the mac's <c>rmdir</c>).
        /// </summary>
        public void Finish()
        {
            try { if (Directory.Exists(_unpacked)) DeleteTree(_unpacked); } catch { /* litter, never loss */ }
            bool keep = KeepAside || HoldsSomethingBackupsLeaveOut(Aside);
            if (!keep)
            {
                try { if (Directory.Exists(Aside)) DeleteTree(Aside); } catch { return; }
            }
            string? folder = _root;
            for (int level = 0; level < 3 && folder is not null; level++)
            {
                try { Directory.Delete(folder, recursive: false); }
                catch { return; }
                folder = Path.GetDirectoryName(folder);
            }
        }
    }

    /// <summary>
    /// The names in <see cref="CourseArchiver.ExcludedFromArchives"/> that are
    /// a teacher's WORK when they turn up deeper inside a section folder: a
    /// project's history (<c>.git</c>), its installed packages
    /// (<c>node_modules</c>) and what its own tools made (<c>dist</c>,
    /// <c>build</c>, <c>out</c>), which a backup leaves out and so cannot put
    /// back. The rest of the list is litter the system or a tool makes again
    /// on its own (<c>.DS_Store</c>, <c>__pycache__</c>, <c>.cache</c>,
    /// <c>.quartz-cache</c>, <c>.merged_output</c>), which never keeps a
    /// replaced section aside: a course made on a Mac has a <c>.DS_Store</c>
    /// at every depth, and keeping one section's full copy per restore for it
    /// is growth nobody would miss losing (the review of steps 1 and 2, LOW 3).
    /// </summary>
    internal static readonly IReadOnlySet<string> LeftOutWork =
        new HashSet<string>(StringComparer.Ordinal) { ".git", "node_modules", "dist", "build", "out" };

    /// <summary>Whether anything at any depth of <paramref name="folder"/> is work a backup leaves out (<see cref="LeftOutWork"/>), so the folder must be kept.</summary>
    private static bool HoldsSomethingBackupsLeaveOut(string folder)
    {
        if (!Directory.Exists(folder)) return false;
        var pending = new Stack<string>();
        pending.Push(folder);
        while (pending.Count > 0)
        {
            string current = pending.Pop();
            IEnumerable<FileSystemInfo> entries;
            try { entries = new DirectoryInfo(current).EnumerateFileSystemInfos("*", ReferenceLock.Unfiltered).ToList(); }
            catch { return true; }                                   // cannot tell: keep it
            foreach (var entry in entries)
            {
                if (LeftOutWork.Contains(entry.Name)) return true;
                if ((entry.Attributes & FileAttributes.Directory) != 0 && (entry.Attributes & FileAttributes.ReparsePoint) == 0)
                    pending.Push(entry.FullName);
            }
        }
        return false;
    }

    /// <summary>
    /// Swaps a section's folder contents, and the files of it that live
    /// outside the folder, for the backup's, with a way back (the mac's
    /// <c>swapSectionInPlace</c>, move for move).
    ///
    /// <para>Out first, then in: every live child of <c>section&lt;N&gt;\</c>
    /// and every live outside file the list does not leave alone moves into
    /// <paramref name="aside"/>; then the backup's move into place. The folder
    /// <c>section&lt;N&gt;</c> itself never moves (Obsidian's watcher holds on
    /// to it). If any move fails, every move already made is made backwards,
    /// last first, and <c>wording.leftAsItWas</c> is thrown; if one of THOSE
    /// fails, <see cref="WayBackDidNotFinish"/> is thrown and the aside folder
    /// must be kept, because it then holds the only copy of what the section
    /// had.</para>
    ///
    /// <para><b>One difference from the mac, on purpose:</b> a child of the
    /// section folder named as backups leave out
    /// (<see cref="CourseArchiver.ExcludedFromArchives"/>, <c>.git</c> and
    /// <c>node_modules</c> among them) is in neither the backup nor the
    /// archive made first, so it is LEFT WHERE IT IS: never moved aside, never
    /// deleted (Russell's ruling on #909, "a restore never deletes a course's
    /// <c>.git</c>"). The mac's swap on <c>dev</c> moves it aside and deletes
    /// it with the aside folder (documentation 09, "Two edges").</para>
    /// </summary>
    private static void SwapSectionInPlace(int sectionNumber, string courseDir, string payload,
        IReadOnlyList<OneSectionRestore.OutsideFile> outsideFiles, string aside, SectionSwapHooks hooks,
        Action<string>? keepingWhatWasReplaced = null)
    {
        string folderName = "section" + sectionNumber;
        string liveSection = Path.Combine(courseDir, folderName);
        string backedUpSection = Path.Combine(payload, folderName);
        string asideSection = Path.Combine(aside, folderName);
        string asideOutside = Path.Combine(aside, "outside");
        Directory.CreateDirectory(liveSection);
        Directory.CreateDirectory(asideSection);
        Directory.CreateDirectory(asideOutside);

        var done = new List<(string From, string To)>();
        try
        {
            // Out: the section's own entries, hidden ones included.
            foreach (var child in new DirectoryInfo(liveSection).EnumerateFileSystemInfos("*", ReferenceLock.Unfiltered).ToList())
            {
                if (CourseArchiver.ExcludedFromArchives.Contains(child.Name)) continue;
                string destination = Path.Combine(asideSection, child.Name);
                hooks.Move(child.FullName, destination);
                done.Add((child.FullName, destination));
            }
            // Out: the section's files outside its folder.
            foreach (var file in outsideFiles)
            {
                if (file.Treatment == OneSectionRestore.Treatment.LeftAsItIs) continue;
                string relative = file.PathFor(sectionNumber);
                string live = Path.Combine(courseDir, relative);
                if (!File.Exists(live) && !Directory.Exists(live)) continue;
                string destination = Path.Combine(asideOutside, relative);
                Directory.CreateDirectory(Path.GetDirectoryName(destination)!);
                hooks.Move(live, destination);
                done.Add((live, destination));
            }
            hooks.Reached(SwapPoint.SetAside);
            // In: the backup's section entries.
            foreach (var child in new DirectoryInfo(backedUpSection).EnumerateFileSystemInfos("*", ReferenceLock.Unfiltered).ToList())
            {
                string destination = Path.Combine(liveSection, child.Name);
                hooks.Move(child.FullName, destination);
                done.Add((child.FullName, destination));
            }
            // In: the backup's files outside the folder, where it has them.
            foreach (var file in outsideFiles)
            {
                if (file.Treatment != OneSectionRestore.Treatment.FromTheBackup) continue;
                string relative = file.PathFor(sectionNumber);
                string backedUp = Path.Combine(payload, relative);
                if (!File.Exists(backedUp) && !Directory.Exists(backedUp)) continue;
                string destination = Path.Combine(courseDir, relative);
                Directory.CreateDirectory(Path.GetDirectoryName(destination)!);
                hooks.Move(backedUp, destination);
                done.Add((backedUp, destination));
            }
        }
        catch (Exception error) when (error is not WayBackDidNotFinish)
        {
            bool everyFileIsBack = true;
            for (int index = done.Count - 1; index >= 0; index--)
            {
                try { hooks.Move(done[index].To, done[index].From); }
                catch { everyFileIsBack = false; }
            }
            if (!everyFileIsBack) throw new WayBackDidNotFinish();
            throw new RestoreException(OneSectionRestoreWording.LeftAsItWas(sectionNumber, error.Message));
        }
        keepingWhatWasReplaced?.Invoke(aside);
    }

    /// <summary>Where a stopped restore kept what it set aside, and whether a teacher would find anything there.</summary>
    internal sealed record SetAsideFiles(string Path, bool HoldsSomethingToOpen, bool IsStillInStaging)
    {
        /// <summary>The path the teacher is told, or null when there is nothing there to open.</summary>
        public string? PathToSay => HoldsSomethingToOpen ? Path : null;
    }

    /// <summary>
    /// Moves the files a stopped restore set aside to
    /// <c>courses\_backups\&lt;CODE&gt;\Section N before a restore &lt;stamp&gt;</c>
    /// (the mac's <c>keepTheSetAsideFiles</c>): the one place in a working
    /// folder that already holds copies of the course, on the same volume (a
    /// rename), where nothing reads a FOLDER (<see cref="Workspace"/>'s
    /// backup and archive lists read top-level <c>.zip</c> names only). When
    /// that move fails, the files stay in <c>courses\.internal\restoring\</c>
    /// and that path is what is said. Writes <c>section restore stopped part
    /// way</c>: the course, the section and the path, never a page.
    /// </summary>
    internal static SetAsideFiles KeepTheSetAsideFiles(string aside, int sectionNumber, string courseCode, string coursesDirectory)
    {
        string trimmed = coursesDirectory.TrimEnd(Path.DirectorySeparatorChar, Path.AltDirectorySeparatorChar);
        string workingFolder = Path.GetDirectoryName(trimmed) ?? trimmed;
        string shelf = Path.Combine(trimmed, "_backups", courseCode);
        // No comma: the sentence that names it puts punctuation after it.
        string name = $"Section {sectionNumber} before a restore " + DateTime.Now.ToString(ArchivedItem.StampFormat, CultureInfo.InvariantCulture);
        string kept = aside;
        try
        {
            Directory.CreateDirectory(shelf);
            string destination = Path.Combine(shelf, name);
            Directory.Move(aside, destination);
            kept = destination;
        }
        catch
        {
            kept = aside;
        }
        string keptAt = Path.GetRelativePath(workingFolder, kept);
        ActivityTrail.Note(ActivityTrail.Event.SectionRestoreStoppedPartWay,
            ActivityTrail.SectionRestoreStoppedPartWayLine(keptAt), courseCode, sectionNumber);
        return new SetAsideFiles(keptAt, HoldsAFileATeacherWouldOpen(kept), string.Equals(kept, aside, StringComparison.OrdinalIgnoreCase));
    }

    /// <summary>
    /// Whether a folder holds a file whose path inside it has no part starting
    /// with a dot (the mac's <c>holdsAFileFinderShows</c>, the same rule:
    /// what is left otherwise is Plantoir's own records, such as
    /// <c>outside\.internal\timetable\section2.json</c>, and not a page).
    /// Explorer does show dot-named files; the rule is kept as the mac's so
    /// the two apps choose the same sentence for the same folder.
    /// </summary>
    private static bool HoldsAFileATeacherWouldOpen(string folder)
    {
        if (!Directory.Exists(folder)) return false;
        foreach (string file in Directory.EnumerateFiles(folder, "*", new EnumerationOptions { RecurseSubdirectories = true, AttributesToSkip = 0, IgnoreInaccessible = true }))
        {
            string relative = Path.GetRelativePath(folder, file);
            bool hidden = false;
            foreach (string part in relative.Split(Path.DirectorySeparatorChar))
                if (part.StartsWith('.')) hidden = true;
            if (!hidden) return true;
        }
        return false;
    }

    /// <summary>The sentence for a restore whose way back did not finish (the mac's <c>Problem.sectionRestoreStoppedPartWay</c>).</summary>
    internal static string StoppedPartWaySentence(int sectionNumber, string? keptAt, bool archived)
    {
        string said = keptAt is null
            ? OneSectionRestoreWording.StoppedPartWayNothingToOpen(sectionNumber)
            : OneSectionRestoreWording.StoppedPartWay(sectionNumber, keptAt);
        return archived ? said + " " + OneSectionRestoreWording.StoppedPartWayArchived : said;
    }

    /// <summary>The code a teacher reads, when the course at <paramref name="courseDir"/> is kept for reference; otherwise null.</summary>
    private static string? ReadsAsKeptForReference(string courseDir)
    {
        try
        {
            var configuration = CourseConfiguration.Load(Path.Combine(courseDir, "course_config.json"));
            var course = new Course(Path.GetFileName(courseDir), courseDir, configuration);
            return ReferenceCourse.IsKeptForReference(course) ? ReferenceCourse.ShownCode(course) : null;
        }
        catch { return null; }
    }

    /// <summary>
    /// A zip carries no lock, so a restored reference course arrives thawed;
    /// the MARKER, which travels in the settings, is what puts it back.
    /// </summary>
    private static void LockAgainIfKeptForReference(string courseDir)
    {
        if (ReadsAsKeptForReference(courseDir) is not null) ReferenceLock.Lock(courseDir);
    }

    /// <summary>
    /// Every shared page of the course gets this section's per-section keys
    /// back as the backup had them, and nothing else about it changes.
    /// </summary>
    private static int RestorePerSectionKeys(int sectionNumber, string courseDir, string payload)
    {
        int notPutBack = 0;
        foreach (string page in SharedMarkdownPages(courseDir))
        {
            string relative = Path.GetRelativePath(courseDir, page);
            string backedUpPage = Path.Combine(payload, relative);
            string liveText, backupText;
            try
            {
                if (!File.Exists(backedUpPage)) continue;
                backupText = File.ReadAllText(backedUpPage);
                liveText = File.ReadAllText(page);
            }
            catch (IOException) { continue; }
            catch (UnauthorizedAccessException) { continue; }
            var (rewritten, couldNotBePutBack) = SettingPerSectionKeys(sectionNumber, liveText, backupText);
            if (couldNotBePutBack) notPutBack++;
            if (rewritten != liveText)
            {
                try { File.WriteAllText(page, rewritten); } catch (IOException) { } catch (UnauthorizedAccessException) { }
            }
        }
        return notPutBack;
    }

    /// <summary>The course's Markdown pages outside every section folder and every excluded folder.</summary>
    private static IEnumerable<string> SharedMarkdownPages(string directory)
    {
        IEnumerable<string> entries;
        try { entries = Directory.EnumerateFileSystemEntries(directory).ToList(); }
        catch (IOException) { yield break; }
        catch (UnauthorizedAccessException) { yield break; }
        foreach (string entry in entries)
        {
            string name = Path.GetFileName(entry);
            if (Directory.Exists(entry))
            {
                if (NamesASectionFolder(name) || CourseArchiver.ExcludedFromArchives.Contains(name)) continue;
                foreach (string inner in SharedMarkdownPages(entry)) yield return inner;
            }
            else if (string.Equals(Path.GetExtension(entry), ".md", StringComparison.OrdinalIgnoreCase))
            {
                yield return entry;
            }
        }
    }

    public static bool NamesASectionFolder(string name)
    {
        const string prefix = "section";
        if (!name.StartsWith(prefix, StringComparison.Ordinal) || name.Length == prefix.Length) return false;
        for (int index = prefix.Length; index < name.Length; index++)
            if (!char.IsAsciiDigit(name[index])) return false;
        return true;
    }

    /// <summary>
    /// The live page's text with this section's per-section keys as the
    /// backup had them — the mac's <c>settingPerSectionKeys</c>, line for
    /// line, pinned by <c>course-management.json →
    /// backups.restoringOneSectionsKeys</c> (compared as bytes).
    /// </summary>
    /// <remarks>
    /// <para>This section's lines are replaced by the backup's (or dropped when
    /// the backup had none), each key WITH the lines it owns
    /// (<see cref="PageVisibilityReader.LinesOwnedByKey"/>, #182): copying key
    /// LINES only brought a backup's <c>publishForSection1: &gt;-</c> back as
    /// <c>&gt;-</c> alone — PUBLISHED. With none of its own left on the page,
    /// the restored lines go after the last line any per-section key OWNS, never
    /// between another section's key and its value.</para>
    /// <para>The block is found with the shared finder (#177, decided
    /// 2026-09-19 and again 2026-09-25: Windows matches the mac), so a restore
    /// reaches the same pages the build reads — a <c>----</c> fence, a blank
    /// line before the fence (which the restored page drops, as the mac's
    /// does — Russell, 2026-10-01). Rejected: both apps going strict (restore would
    /// then disagree with hide and show on the same page), and leaving the
    /// divergence. The old <c>liveText.Contains("\n---")</c> refuse-to-prepend
    /// guard went with the strict finder, which is what it compensated for.</para>
    /// <para>When the page has no line of this section and its block has no
    /// column-0 level for a new key (#186's shape), the page is left byte for
    /// byte and <c>CouldNotBePutBack</c> is true: the caller counts it, says
    /// so, and records <c>page settings left as they were</c>.</para>
    /// </remarks>
    public static (string Text, bool CouldNotBePutBack) SettingPerSectionKeys(
        int sectionNumber, string liveText, string backupText)
    {
        var backupLines = backupText.Split('\n');
        var restoredLines = PerSectionLineIndices(sectionNumber, backupText)
            .Select(index => PageVisibilityReader.TrimCarriageReturn(backupLines[index]))
            .ToList();

        if (PageVisibilityReader.FenceIndices(liveText) is not { } liveBlock)
        {
            if (restoredLines.Count == 0) return (liveText, false);
            return ("---\n" + string.Join("\n", restoredLines) + "\n---\n" + liveText, false);
        }

        var lines = liveText.Split('\n');
        var doomed = PerSectionLineIndices(sectionNumber, liveText).ToHashSet();
        int lastPerSectionIndex = PerSectionLineIndices(null, liveText).DefaultIfEmpty(-1).Max();

        // The rebuilt page starts AT the opening fence: blank lines before it
        // (the only thing that can stand there) are dropped, as the mac's
        // settingPerSectionKeys drops them. Windows kept them from bundle 2
        // until Russell chose to match on 2026-10-01; either is harmless to
        // the build, and one behaviour is one less difference to explain.
        var rebuilt = new List<string> { lines[liveBlock.Open] };
        bool placed = false;
        for (int index = liveBlock.Open + 1; index < liveBlock.Close; index++)
        {
            if (doomed.Contains(index))
            {
                if (!placed) { rebuilt.AddRange(restoredLines); placed = true; }
                continue;
            }
            rebuilt.Add(lines[index]);
            if (index == lastPerSectionIndex && !placed) { rebuilt.AddRange(restoredLines); placed = true; }
        }
        if (!placed && restoredLines.Count > 0)
        {
            // A brand-new key: only where the block has a column-0 level for it.
            if (PageVisibilityReader.PlaceForANewTopLevelKey(lines, liveBlock.Open, liveBlock.Close) is null)
                return (liveText, true);
            rebuilt.AddRange(restoredLines);
        }
        rebuilt.AddRange(lines.Skip(liveBlock.Close));
        return (string.Join("\n", rebuilt), false);
    }

    /// <summary>
    /// The indices of every line of the page's block that is a per-section key
    /// for <paramref name="sectionNumber"/> (or for any section, when null) or
    /// a line such a key OWNS, in file order.
    /// </summary>
    internal static List<int> PerSectionLineIndices(int? sectionNumber, string pageText)
    {
        var found = new List<int>();
        if (PageVisibilityReader.FenceIndices(pageText) is not { } block) return found;
        var lines = pageText.Split('\n');
        for (int index = block.Open + 1; index < block.Close; index++)
        {
            string bare = PageVisibilityReader.TrimCarriageReturn(lines[index]);
            if (SectionAdder.PerSectionKey(bare) is not { } named) continue;
            if (sectionNumber is { } wanted && named.Number != wanted) continue;
            found.Add(index);
            // Asked of the key's own line as it stands: nothing here is rewritten.
            string key = named.Key;
            bool wasEmpty = PageVisibilityReader.ValuePart(key, bare) is { } value
                && PageVisibilityReader.TrimYamlSpaces(value).Length == 0;
            found.AddRange(PageVisibilityReader.LinesOwnedByKey(lines, index, block.Close, wasEmpty));
        }
        return found;
    }

    /// <summary>
    /// A delete that survives what a course folder really holds: the
    /// container leaves links inside .merged_output that
    /// Directory.Delete(recursive) cannot traverse (the restore died on
    /// content\Media before touching anything else), and readonly files stop
    /// it too. Reparse points are deleted AS LINKS, never followed.
    ///
    /// Shared with <see cref="CourseArchiver"/>, which learned the same
    /// lesson separately: the Quartz project copied into .merged_output can
    /// carry a .git whose pack files are readonly, and removing a course
    /// died on the first one — "Access to the path 'pack-….idx' is denied"
    /// — leaving the folder half-deleted behind an archive that had already
    /// succeeded.
    /// </summary>
    internal static void DeleteTree(string path)
    {
        FileAttributes attributes;
        try { attributes = File.GetAttributes(path); }
        catch { attributes = FileAttributes.Normal; }

        if ((attributes & FileAttributes.Directory) != 0)
        {
            if ((attributes & FileAttributes.ReparsePoint) == 0)
                foreach (string child in Directory.EnumerateFileSystemEntries(path))
                    DeleteTree(child);
            Directory.Delete(path, recursive: false);
        }
        else
        {
            if ((attributes & FileAttributes.ReadOnly) != 0)
                File.SetAttributes(path, attributes & ~FileAttributes.ReadOnly);
            File.Delete(path);
        }
    }

    /// <summary>The app's one true deletion — the confirmation lives with the caller.</summary>
    // ---- The trail line of a whole-course restore ("course restored from a backup")

    /// <summary>
    /// The line a whole course put back from one of its backups leaves, once
    /// it has been put back (the mac's <c>restoredTrailLine</c>, #572): the
    /// code it shows and its folder, the backup's file name, the archive the
    /// caller made of the course as it was first or that there was none to
    /// make, and whether the course that came back is kept for reference, as
    /// its settings say NOW. Never a page.
    /// </summary>
    /// <param name="archivePath">The archive made first, or null when the folder held no course to archive.</param>
    public static string RestoredTrailLine(BackupItem item, string? archivePath, string coursesDirectory)
    {
        string line = Restored(item.CourseCode, coursesDirectory, out bool kept) + " from " + Path.GetFileName(item.FilePath);
        line += archivePath is null
            ? " — there was no course in that folder to archive first"
            : " — the course as it was is in Archived as " + Path.GetFileName(archivePath);
        return line + (kept ? "; kept for reference" : "; a course you teach");
    }

    /// <summary>
    /// The line a whole course put back from Archived leaves (the mac's
    /// <c>restoredFromArchivedTrailLine</c>, #572 review L5): the archive's
    /// file name and what became of it. <see cref="Restore"/> deletes it and
    /// does not fail when it cannot, so the line says which happened.
    /// </summary>
    public static string RestoredFromArchivedTrailLine(ArchivedItem item, string coursesDirectory)
    {
        string line = Restored(item.CourseCode, coursesDirectory, out bool kept) + " from Archived, " + Path.GetFileName(item.FilePath);
        line += File.Exists(item.FilePath)
            ? " — that archive could not be removed and is still listed"
            : " — that archive is used up";
        return line + (kept ? "; kept for reference" : "; a course you teach");
    }

    /// <summary>"restored ICS3U (ICS3U-2025)": the code a teacher reads, as the restored settings say, and the folder.</summary>
    private static string Restored(string folderName, string coursesDirectory, out bool kept)
    {
        string? shown = ReferenceCourse.KeptOnDisk(Path.Combine(coursesDirectory, folderName));
        kept = shown is not null;
        return $"restored {shown ?? folderName} ({folderName})";
    }

    public static void DeleteBackup(BackupItem item) => File.Delete(item.FilePath);

    /// <summary>Archives are deletable too (row 106 round two) — same rule.</summary>
    public static void DeleteArchive(ArchivedItem item) => File.Delete(item.FilePath);

    /// <summary>Archiving took the number out; restoring must put it back.</summary>
    private static void PutSectionBack(Course course, int section)
    {
        var numbers = course.Configuration.SectionNumbers;
        if (!numbers.Contains(section)) numbers.Add(section);
        numbers.Sort();
        course.Configuration.SetSectionNumbers(numbers);
        course.Configuration.Write(course.ConfigFilePath);
    }

    /// <summary>
    /// Extract expecting the named folder at the archive root; when it is
    /// absent but the archive holds exactly one folder, use that one (so
    /// archives made by another version still restore).
    /// </summary>
    private static void Extract(string archivePath, string expectedName, string destinationParent)
    {
        string staging = Path.Combine(Path.GetTempPath(), "restore-" + Guid.NewGuid());
        Directory.CreateDirectory(staging);
        try
        {
            string payload = Unpack(archivePath, expectedName, staging);
            Directory.CreateDirectory(destinationParent);
            Directory.Move(payload, Path.Combine(destinationParent, expectedName));
        }
        finally
        {
            try { Directory.Delete(staging, recursive: true); } catch { }
        }
    }

    /// <summary>
    /// Unzips into the staging folder and returns the payload — the folder
    /// the archive's name promised, or the single folder it holds (so an
    /// archive made by another version still restores).
    /// </summary>
    private static string Unpack(string archivePath, string expectedName, string staging)
    {
        try { ZipFile.ExtractToDirectory(archivePath, staging); }
        catch (Exception error)
        {
            throw new RestoreException($"The archive could not be opened: {error.Message}");
        }

        return PayloadIn(staging, expectedName);
    }

    /// <summary>The folder the archive's name promised inside <paramref name="staging"/>, or the single folder it holds.</summary>
    private static string PayloadIn(string staging, string expectedName)
    {
        string payload = Path.Combine(staging, expectedName);
        if (!Directory.Exists(payload))
        {
            var entries = Directory.EnumerateFileSystemEntries(staging)
                .Where(e => !Path.GetFileName(e).StartsWith('.'))
                .ToList();
            if (entries.Count == 1) payload = entries[0];
            else throw new RestoreException($"The archive could not be opened: it does not contain {expectedName}");
        }
        return payload;
    }
}
