using Plantoir.Core.Catalogs;

namespace Plantoir.Core.Models;

/// <summary>
/// Whether a course code names a CLUB rather than a course.
///
/// It decides two things a teacher can see: whether the New Course wizard
/// offers a "Short label" field, and whether custom_short_name is written
/// into course_config.json. Both apps ask it, so it is a contract case
/// (contracts/course-management.json -&gt; courseCode.clubDetection) rather
/// than a private idea inside either wizard. Mirrors the mac's
/// ClubCodeRule.swift.
///
/// It used to be a private idea inside both wizards, and both had the same
/// bug: NewCourseDialog.IsClubCode was one line — "the fourth character of a
/// course code is its grade digit, so a code without one is a club" — which
/// is true of Ontario (ICS3U, MPM2D) and false of British Columbia, whose
/// codes put a letter or a dash there: MTEL-12, MMA--09, MCMPR11. So all 117
/// BC courses were read as clubs, and a real course was offered a club's
/// short-label field.
/// </summary>
public static class ClubCodeRule
{
    /// <summary>
    /// Whether <paramref name="code"/> names a club.
    ///
    /// The catalog is asked FIRST and its answer is final: a code the app
    /// ships a name for is a course, whatever shape it happens to be. Only
    /// when the catalog has never heard of a code does the Ontario-shaped
    /// guess below get a say — which is what it was always for, a
    /// teacher-invented name like CODING or ROBOTICS where there is no
    /// entry to consult and the shape of the code is the only signal.
    /// </summary>
    public static bool IsClub(string code, CourseNameCatalog catalog)
    {
        string trimmed = code.Trim();
        if (catalog.Names(trimmed) is not null) return false;
        if (trimmed.Length < 4) return false;
        return !char.IsDigit(trimmed[3]);
    }
}
