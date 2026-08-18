namespace Plantoir.Core.Models;

/// <summary>
/// Validating section number inputs in the new-course wizard.
/// </summary>
public static class SectionNumbersRule
{
    public static string? Problem(string text)
    {
        string trimmed = text.Trim();
        if (trimmed.Length == 0) return "Enter at least one section number — e.g. 1, or 1,3.";
        var seen = new HashSet<int>();
        foreach (string rawPiece in trimmed.Split(','))
        {
            string piece = rawPiece.Trim();
            if (piece.Length == 0) return "There’s an empty spot between commas.";
            if (int.TryParse(piece, out int number))
            {
                if (number < 1) return $"“{piece}” isn’t a section number — sections are 1 or higher.";
                if (!seen.Add(number)) return $"Section {number} is listed more than once.";
                continue;
            }
            var subPieces = piece.Split(' ', StringSplitOptions.RemoveEmptyEntries);
            if (subPieces.Length > 1 && subPieces.All(p => int.TryParse(p, out _)))
                return $"Use commas between section numbers — e.g. {string.Join(",", subPieces)}.";
            return $"“{piece}” isn’t a section number — sections are whole numbers, like 1 or 3.";
        }
        return null;
    }

    public static List<int> Parse(string text) =>
        text.Split(',').Select(p => p.Trim())
            .Select(p => int.TryParse(p, out int n) ? n : 0)
            .Where(n => n > 0)
            .Distinct()
            .OrderBy(n => n)
            .ToList();
}
