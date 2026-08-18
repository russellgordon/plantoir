using System;
using System.Collections.Generic;
using System.Linq;

namespace Plantoir.Core.Models;

public static class CourseCodeValidator
{
    public const int MostCharacters = 12;

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
            if (!isAsciiLetter && !isDigit && !isSpace)
                return ("A course code can only use letters, numbers and spaces.", "Letters, numbers, spaces");
        }

        if (trimmed.Length > MostCharacters)
            return ("A course code can be at most 12 characters.", "12 characters at most");

        string normalized = Normalize(trimmed);
        string? currentNormalized = currentCode is not null ? Normalize(currentCode) : null;

        if (normalized != currentNormalized)
        {
            bool clash = existing.Any(e => Normalize(e).Equals(normalized, StringComparison.OrdinalIgnoreCase));
            if (clash)
                return ($"A course named {normalized} already exists — choose a different code.", $"{normalized} already exists");
        }

        return (null, null);
    }
}
