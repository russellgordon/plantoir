namespace Plantoir.Views;

/// <summary>
/// Segoe Fluent Icons code points as C# unicode escapes, so a literal glyph
/// character can never be lost or mangled in the source (which left several
/// buttons showing empty boxes).
/// </summary>
public static class Glyphs
{
    public const string Add = "\uE710";   // plus
    public const string Remove = "\uE738";   // minus
    public const string Edit = "\uE70F";   // pencil (Obsidian)
    public const string Back = "\uE72B";
    public const string Forward = "\uE72A";
    public const string Refresh = "\uE72C";
    public const string Play = "\uE768";   // Preview
    public const string Stop = "\uE71A";
    public const string Send = "\uE724";   // Deploy / publish
    public const string Globe = "\uE774";   // open in browser / no-preview
    public const string Library = "\uE8F1";   // course (books)
    public const string Document = "\uE8A5";   // section
    public const string Archive = "\uE7B8";   // archived group
    public const string Terminal = "\uE756";
    public const string Explorer = "\uEC50";   // show in File Explorer
    public const string Restore = "\uE7A7";   // restore
    public const string ChevronUp = "\uE70E";
    public const string ChevronDown = "\uE70D";
    public const string ChevronRight = "\uE76C";
    public const string CheckMark = "\uE73E";   // Done
    public const string Cancel = "\uE711";   // cancelled / failed
    public const string Search = "\uE721";

    /// <summary>
    /// The ⓘ that REPLACES the minus on a row that cannot be removed.
    /// Checked present in the installed Segoe Fluent Icons on this machine by
    /// rendering it and counting ink pixels (63, against 33 for the known-good
    /// Cancel glyph) — "documented" is not the same as "there", as the absent
    /// Sparkle at U+E45E already taught this file.
    /// </summary>
    public const string Info = "\uE946";
    public const string QuestionBubble = "\uE897";   // awaiting your answer

    /// <summary>
    /// An outline star (FavoriteStar), for the two "revise with\u2026" items.
    /// Checked present in the installed SegoeIcons.ttf and segmdl2.ttf, so it
    /// draws in the ordinary icon font like everything else here. It replaced
    /// a sparkle EMOJI, which needed its own font and its own colour \u2014 the
    /// only coloured icon in the menu, and it read as noise. (The documented
    /// Fluent "Sparkle" at U+E45E is simply not in the font on Windows 11 (the
    /// whole U+E45A to E460 neighbourhood is absent), which is how the emoji
    /// got in.)
    /// </summary>
    public const string Star = "\uE734";

    /// <summary>A clock — a section with a deploy waiting to fire. Checked present in SegoeIcons.ttf.</summary>
    public const string Clock = "";
}
