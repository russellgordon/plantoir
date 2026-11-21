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
}
