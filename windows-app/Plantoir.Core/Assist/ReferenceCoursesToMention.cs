using Plantoir.Core.Models;

namespace Plantoir.Core.Assist;

/// <summary>
/// The courses a Revise door's greeting names as kept for reference
/// (<c>app-rules.json</c> → <c>outsideAgents.greetingReferenceCourses</c>,
/// GitHub #856; on Windows #880's first item): earlier courses with the same
/// code, there to read and build on, never deployed or changed. The mac has
/// said it since v1.3.0.
/// </summary>
/// <remarks>
/// <para><b>Read at the click, by the door.</b> Each door's <c>Open</c> calls
/// <see cref="ReadFor"/> itself, so no caller can forget it and a third door
/// inherits it by calling the same function. The mac passes its sidebar's
/// in-memory course list instead; the difference is Windows' own, and the
/// sentence is the same either way. Measured on a Lenovo 20QES70500 (i5-8365U):
/// 32 ms for 40 courses, beside the 1.2–1.5 s a door already takes to start.</para>
/// <para><b>Never cut.</b> The contract has no words for a shortened list, so
/// the sentence names every course. When a list is too long for the command
/// line, <see cref="OutsideDoor.GreetingThatFits"/> drops unit-plan names
/// first and the door then refuses, as it does for a long unit name.</para>
/// </remarks>
public static class ReferenceCoursesToMention
{
    /// <summary><c>greetingReferenceCourses.sentence</c>: <c>{course}</c> is the greeting's code, <c>{courses}</c> the list.</summary>
    public const string SentenceTemplate =
        "I also keep earlier {course} courses for reference: {courses}. You can read them and build on what is there; they are never deployed, and nothing in them can be changed.";

    /// <summary><c>greetingReferenceCourses.separator</c>.</summary>
    public const string Separator = ", ";

    /// <summary>The sentence for <paramref name="courses"/>, or null when there are none (no sentence at all).</summary>
    public static string? Sentence(string courseCode, IReadOnlyList<string>? courses)
    {
        if (courses is null || courses.Count == 0) return null;
        return SentenceTemplate.Replace("{course}", courseCode).Replace("{courses}", string.Join(Separator, courses));
    }

    /// <summary>
    /// <c>greetingReferenceCourses.eachCourse</c>: every course in
    /// <paramref name="others"/> kept for reference whose shown code is
    /// <paramref name="course"/>'s, ignoring case, as "{folder} ({year})"
    /// with the sidebar's year label or "Other", sorted ordinal. Nothing
    /// for a course that is itself kept for reference.
    /// </summary>
    public static IReadOnlyList<string> For(Course course, IEnumerable<Course> others, DateOnly today)
    {
        if (ReferenceCourse.IsKeptForReference(course)) return Array.Empty<string>();
        string code = ReferenceCourse.ShownCode(course);
        var listed = new List<string>();
        foreach (var other in others)
        {
            if (ReferenceEquals(other, course) || !ReferenceCourse.IsKeptForReference(other)) continue;
            if (!string.Equals(ReferenceCourse.ShownCode(other), code, StringComparison.OrdinalIgnoreCase)) continue;
            int? year = SchoolYear.Read(other.Configuration.StoredReferenceSchoolYear, today);
            listed.Add($"{other.Code} ({(year is int y ? SchoolYear.Label(y) : SchoolYear.OtherGroupName)})");
        }
        listed.Sort(StringComparer.Ordinal);
        return listed;
    }

    /// <summary>
    /// The list for the course whose folder is <paramref name="courseCode"/>
    /// in <paramref name="workspacePath"/>, read from the folder now. A course
    /// not found is read as a live course with that code. Never throws: a
    /// folder that cannot be read answers an empty list, so the greeting
    /// loses the sentence and the door still opens.
    /// </summary>
    public static IReadOnlyList<string> ReadFor(string workspacePath, string courseCode, DateOnly today)
    {
        try
        {
            var courses = Workspace.DiscoverCourses(workspacePath);
            var course = courses.FirstOrDefault(c => string.Equals(c.Code, courseCode, StringComparison.OrdinalIgnoreCase))
                         ?? new Course(courseCode, Path.Combine(Workspace.CoursesDirectory(workspacePath), courseCode),
                                       CourseConfiguration.FromDictionary(new Newtonsoft.Json.Linq.JObject()));
            return For(course, courses, today);
        }
        catch { return Array.Empty<string>(); }
    }
}
