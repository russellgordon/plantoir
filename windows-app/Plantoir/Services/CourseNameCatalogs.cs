using Plantoir.Core.Catalogs;

namespace Plantoir.Services;

/// <summary>
/// The one loaded copy of the course-name catalog (Ontario and British
/// Columbia), shared by the New Course wizard's picker and Course Settings'
/// club detection so both agree on the same answer and neither re-reads the
/// bundled JSON on every dialog open.
/// </summary>
public static class CourseNameCatalogs
{
    private static CourseNameCatalog? _shared;
    private static List<CourseCatalogEntry>? _ontario;
    private static List<CourseCatalogEntry>? _britishColumbia;

    public static CourseNameCatalog Shared => _shared ??= CourseNameCatalog.Load(
        BundledToolchain.SupportPath("ontario_secondary_courses.json"),
        BundledToolchain.SupportPath("british_columbia_secondary_courses.json"));

    /// <summary>The per-province lists the course-code picker browses and searches — see CourseCatalog.</summary>
    public static List<CourseCatalogEntry> ForProvince(string province) => province switch
    {
        "BC" => _britishColumbia ??= CourseCatalog.LoadEntries(
            BundledToolchain.SupportPath("british_columbia_secondary_courses.json"), "BC"),
        _ => _ontario ??= CourseCatalog.LoadEntries(
            BundledToolchain.SupportPath("ontario_secondary_courses.json"), "ON"),
    };
}
