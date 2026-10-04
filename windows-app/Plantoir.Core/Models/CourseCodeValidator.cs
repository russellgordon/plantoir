using System;
using System.Collections.Generic;
using System.Linq;

namespace Plantoir.Core.Models;

public static class CourseCodeValidator
{
    public const int MostCharacters = 12;

    /// <summary>The one whole code kept for Plantoir's own use (#101, <c>course-management.json → courseCode.problems</c>).</summary>
    public const string KeptName = "WORK";

    public static string Normalize(string typed) => typed.Trim().ToUpperInvariant();

    public static string? Problem(string typed, IEnumerable<string> existing, string? currentCode = null) =>
        Validate(typed, existing, currentCode).Problem;

    public static string? ShortProblem(string typed, IEnumerable<string> existing, string? currentCode = null) =>
        Validate(typed, existing, currentCode).ShortProblem;

    public static (string? Problem, string? ShortProblem) Validate(
        string typed,
        IEnumerable<string> existing,
        string? currentCode = null)
    {
        string trimmed = typed.Trim();
        if (string.IsNullOrEmpty(trimmed))
            return (null, null);

        if (trimmed.Contains("  "))
            return ("A course code can’t have two spaces in a row.", "No double spaces");

        foreach (char c in trimmed)
        {
            bool isAsciiLetter = (c >= 'a' && c <= 'z') || (c >= 'A' && c <= 'Z');
            bool isDigit = (c >= '0' && c <= '9');
            bool isSpace = (c == ' ');
            bool isDash = (c == '-');
            if (!isAsciiLetter && !isDigit && !isSpace && !isDash)
                return ("A course code can only use letters, numbers, spaces and dashes.", "Letters, numbers, dashes");
        }

        if (trimmed.Length > MostCharacters)
            return ("A course code can be at most 12 characters.", "12 characters at most");

        string normalized = Normalize(trimmed);
        string? currentNormalized = currentCode is not null ? Normalize(currentCode) : null;

        // Kept for Plantoir itself (#101): the native build makes its preview
        // in <buildRoot>\work beside every course's built website, so a course
        // of that code would share a folder with the build. Checked BEFORE the
        // clash, so a folder already called WORK does not turn the answer into
        // "keep a copy for reference". A course that already carries the name
        // may have its own code re-typed while renaming; it cannot be GIVEN it.
        if (normalized == KeptName && normalized != currentNormalized)
            return ($"{KeptName} is a name Plantoir keeps for its own use. Choose a different course code.",
                    "Kept for Plantoir’s use");

        if (normalized != currentNormalized)
        {
            bool clash = existing.Any(e => Normalize(e).Equals(normalized, StringComparison.OrdinalIgnoreCase));
            // Points at the way out since #241 (mac #206): a clash with last
            // year's course is the ordinary case, and the answer is to keep a
            // copy of it for reference and then remove it.
            if (clash)
                return ($"A course named {normalized} already exists. If that's last year's, keep a copy of it for reference and then remove it.",
                        $"{normalized} already exists");
        }

        return (null, null);
    }
}
