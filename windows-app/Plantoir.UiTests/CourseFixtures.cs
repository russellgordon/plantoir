using System.Text;
using System.Text.Json.Nodes;

namespace Plantoir.UiTests;

/// <summary>
/// Courses written from scratch for a test run — never a copy of a real one.
///
/// <para>Two, not seven. The unit suite
/// (<c>SpecialFoldersHelpContractTests</c>) already runs every case in the
/// contract against the rule; putting the same sweep through a slow, real
/// window would re-prove it and add nothing but minutes and flakiness. These
/// two exist for the things a unit test cannot see: that the dialog shows the
/// SELECTED course, and that switching courses changes what it shows.</para>
///
/// <para>Their folder names are deliberately unlike each other, so a stale
/// view showing the previous course is obvious rather than plausible.</para>
/// </summary>
public static class CourseFixtures
{
    /// <summary>Everything renamed, and every question answered.</summary>
    public const string Renamed = "ICS3U";

    /// <summary>Never asked about marks, and never recorded a curriculum
    /// folder — the course that proves the sheet resolves rather than reads
    /// the raw keys, which is where the mac is currently wrong.</summary>
    public const string NeverAsked = "MCR3U";

    public static void WriteBoth(string coursesDir)
    {
        Write(coursesDir, Renamed, new JsonObject
        {
            ["course_code"] = Renamed,
            ["course_name"] = "Introduction to Computer Science",
            ["shared_folders"] = new JsonArray("Concepts", "Tests", "Expectations"),
            ["per_section_folders"] = new JsonArray("Lessons"),
            ["graded_folders"] = new JsonArray("Tests"),
            ["curriculum_folder"] = "Expectations",
        });

        // No graded_folders key AT ALL, and no curriculum_folder: absent is not
        // empty, and the sheet must still name "Tasks" and "Ontario
        // Curriculum" because that is what the build would use.
        Write(coursesDir, NeverAsked, new JsonObject
        {
            ["course_code"] = NeverAsked,
            ["course_name"] = "Functions",
            ["shared_folders"] = new JsonArray("Concepts", "Tasks", "Ontario Curriculum"),
            ["per_section_folders"] = new JsonArray("All Classes"),
        });
    }

    private static void Write(string coursesDir, string code, JsonObject config)
    {
        config["num_sections"] = 1;
        config["section_numbers"] = new JsonArray(1);
        config["shared_files"] ??= new JsonArray();
        config["per_section_files"] ??= new JsonArray();

        string dir = Path.Combine(coursesDir, code);
        Directory.CreateDirectory(Path.Combine(dir, "section1"));

        // The folders have to EXIST: the curriculum folder is resolved against
        // the course's own list, and the marks list is drawn from folders on
        // disk, so a config naming folders that are not there tests nothing.
        foreach (var name in config["shared_folders"]!.AsArray())
            Directory.CreateDirectory(Path.Combine(dir, name!.ToString()));
        foreach (var name in config["per_section_folders"]!.AsArray())
            Directory.CreateDirectory(Path.Combine(dir, "section1", name!.ToString()));
        Directory.CreateDirectory(Path.Combine(dir, "Media"));
        File.WriteAllText(Path.Combine(dir, "section1", "index.md"), $"# {code}\n", new UTF8Encoding(false));

        File.WriteAllText(Path.Combine(dir, "course_config.json"),
                          config.ToJsonString(new System.Text.Json.JsonSerializerOptions { WriteIndented = true }),
                          new UTF8Encoding(false));
    }
}
