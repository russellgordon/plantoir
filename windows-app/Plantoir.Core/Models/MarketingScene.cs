using System;
using System.Collections.Generic;
using System.Linq;

namespace Plantoir.Core.Models;

/// <summary>
/// What <c>Plantoir.exe --stage-scene</c> is asked to stage, read from the
/// command line (#380). The staging itself is the app's
/// (<c>Services/MarketingShotCapturer.cs</c>); the reading is here so it is
/// tested without a window. Developer-only: a teacher's launch carries none of
/// these arguments, and <see cref="Parse"/> returns null for it.
/// </summary>
public sealed record MarketingScene(string Scene, bool Dark, string Folder, string? ReadyFile,
                                    IReadOnlyList<(string Code, string Sections)> Courses,
                                    (string Code, int Year)? ReferenceCopy)
{
    /// <summary>
    /// The scenes, by the name the capture script asks for. <c>provision</c>
    /// makes no picture: it sets a working folder up through the app.
    /// </summary>
    public static readonly IReadOnlyList<string> Scenes = new[]
    {
        "provision", "courses", "new-course", "club", "progress", "preview", "assistant",
        "reference", "start-of-year", "schedule-sheet", "curriculum-settings", "map-ontario",
        "map-college-board", "both-curricula", "hero",
    };

    /// <summary>
    /// The request on the command line, or null when there is none. Throws
    /// <see cref="ArgumentException"/> for one that names a scene but cannot be
    /// carried out — an unknown scene, no folder — so the capture script is
    /// told why rather than photographing whatever opened.
    /// </summary>
    public static MarketingScene? Parse(IReadOnlyList<string> arguments)
    {
        string? scene = After(arguments, "--stage-scene");
        if (scene is null) return null;
        if (!Scenes.Contains(scene))
            throw new ArgumentException($"There is no scene called '{scene}'. The scenes are: {string.Join(", ", Scenes)}.");
        string folder = After(arguments, "--folder")
            ?? throw new ArgumentException("A scene needs --folder, the working folder it is taken in.");
        bool dark = string.Equals(After(arguments, "--theme"), "dark", StringComparison.OrdinalIgnoreCase);
        return new MarketingScene(scene, dark, folder, After(arguments, "--ready-file"),
                                  CourseList(After(arguments, "--courses")), ReferenceCopyOf(After(arguments, "--reference-copy")));
    }

    /// <summary><c>ICS3U:1, 2;ICS4U:1</c> — each course and the section numbers the New Course panel is given.</summary>
    public static IReadOnlyList<(string Code, string Sections)> CourseList(string? text)
    {
        var courses = new List<(string, string)>();
        if (string.IsNullOrWhiteSpace(text)) return courses;
        foreach (string entry in text.Split(';', StringSplitOptions.RemoveEmptyEntries | StringSplitOptions.TrimEntries))
        {
            string[] parts = entry.Split(':', 2, StringSplitOptions.TrimEntries);
            if (parts.Length != 2 || parts[0].Length == 0 || parts[1].Length == 0)
                throw new ArgumentException($"'{entry}' is not CODE:sections.");
            courses.Add((parts[0].ToUpperInvariant(), parts[1]));
        }
        return courses;
    }

    /// <summary><c>ICS3U:2025</c> — keep a copy of that course for reference, filed under that school year.</summary>
    public static (string Code, int Year)? ReferenceCopyOf(string? text)
    {
        if (string.IsNullOrWhiteSpace(text)) return null;
        string[] parts = text.Split(':', 2, StringSplitOptions.TrimEntries);
        if (parts.Length != 2 || parts[0].Length == 0 || !int.TryParse(parts[1], out int year))
            throw new ArgumentException($"'{text}' is not CODE:year.");
        return (parts[0].ToUpperInvariant(), year);
    }

    /// <summary>The folder a reference copy is made under: the code and the year it began, as an import names one.</summary>
    public static string ReferenceFolderName(string code, int year) => $"{code}-{year}";

    private static string? After(IReadOnlyList<string> arguments, string flag)
    {
        for (int i = 0; i < arguments.Count - 1; i++)
            if (arguments[i] == flag) return arguments[i + 1].Trim('"');
        return null;
    }
}
