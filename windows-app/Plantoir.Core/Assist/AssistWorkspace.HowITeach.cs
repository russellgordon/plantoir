using System;
using System.IO;
using System.Linq;
using System.Text;
using Plantoir.Core.Models;
using Plantoir.Core.Scripting;

namespace Plantoir.Core.Assist;

/// <summary>
/// The How I Teach page from the outside door (#340, mac #209): the three
/// MCP-only tools' half that touches the disk. A port of the mac's
/// <c>AssistToolRunner.readHowITeach</c> / <c>planWriteHowITeach</c> /
/// <c>writeHowITeach</c>; <c>contracts/shared-rules.json</c> â†’
/// <c>howITeachPage</c> is the rule both are held to.
/// </summary>
public sealed partial class AssistWorkspace
{
    /// <summary>Set by Plantoir's own window when it starts this server (<see cref="ServesTheLocalWindow"/>).</summary>
    public const string LocalWindowVariable = "PLANTOIR_LOCAL_WINDOW";

    /// <summary>
    /// Whether this server answers Plantoir's own assistant window rather than
    /// an outside door. Only list_courses asks: the window's answer never
    /// carries the How I Teach line (<c>howITeachPage.listCoursesLine</c>).
    /// </summary>
    public bool ServesTheLocalWindow { get; init; }

    /// <summary>list_courses' How I Teach line for one course, or null for the local window.</summary>
    public string? HowITeachListingLine(Course course) =>
        ServesTheLocalWindow ? null
        : HowITeachPage.WrittenPath(course.DirectoryPath) is not null
            ? AssistWording.HowITeachListedAsWritten
            : AssistWording.HowITeachListedAsNotWritten;

    /// <summary>What <c>plan_write_how_i_teach</c> and <c>write_how_i_teach</c> both work from.</summary>
    private sealed record PlannedHowITeach(
        Course Course, string Text, string? ExistingPath, string? ExistingText, string? ExistingMark,
        string Replacing, bool ExistingIsWritten);

    /// <summary><c>read_how_i_teach</c>: the page, or where it would go and how to offer a draft.</summary>
    public string ReadHowITeach(string courseCode)
    {
        var course = Course(courseCode);
        string? path = HowITeachPage.ExistingPath(course.DirectoryPath);
        if (path is null)
        {
            NoteHowITeachRead(course, HowITeachPage.TrailLineForARead(null, false));
            return AssistWording.HowITeachMissing(course.Code) + "\n\n" + AssistWording.HowITeachDraftingBrief;
        }
        if (HowITeachPage.TextOf(File.ReadAllBytes(path)) is not { } text)
            throw new AssistRefusal($"â€œ{HowITeachPage.Title}â€ couldnâ€™t be read as text.");
        if (!HowITeachPage.HasWords(text))
        {
            NoteHowITeachRead(course, HowITeachPage.TrailLineForARead(null, false, empty: true));
            return AssistWording.HowITeachEmpty(course.Code) + "\n\n" + AssistWording.HowITeachDraftingBrief;
        }

        string body = HowITeachPage.Trimmed(HowITeachPage.Body(text));
        bool cutShort = body.Length > HowITeachPage.MostCharacters;
        string shown = cutShort
            ? body[..HowITeachPage.MostCharacters] + "\n\n" + AssistWording.HowITeachCutShort(course.Code, Relative(path))
            : body;
        NoteHowITeachRead(course, HowITeachPage.TrailLineForARead(HowITeachPage.WordCount(text), cutShort));
        return AssistWording.HowITeachRead(course.Code, shown);
    }

    /// <summary>
    /// The refusals the plan and the write SHARE (<c>planAndWriteAgree</c>).
    /// No reference-course gate: this app has no courses kept for reference
    /// yet (#241); when it does, the plan must refuse one here.
    /// </summary>
    private PlannedHowITeach PlanHowITeach(string courseCode, string text, string replacing)
    {
        var course = Course(courseCode);
        text ??= "";
        if (text.Trim().Length == 0) throw new AssistRefusal(AssistWording.HowITeachNeedsWords);
        if (text.Length > HowITeachPage.MostCharacters) throw new AssistRefusal(AssistWording.HowITeachTooLong);
        if (HowITeachPage.OpensWithAFence(text)) throw new AssistRefusal(AssistWording.HowITeachCarriesNoSettings);

        string mark = (replacing ?? "").Trim().ToLowerInvariant();
        string? path = HowITeachPage.ExistingPath(course.DirectoryPath);
        string? existing = null, existingMark = null;
        if (path is not null)
        {
            byte[] bytes = File.ReadAllBytes(path);
            existing = HowITeachPage.TextOf(bytes)
                       ?? throw new AssistRefusal($"â€œ{HowITeachPage.Title}â€ couldnâ€™t be read as text.");
            existingMark = HowITeachPage.MarkOf(bytes);
            if (mark.Length > 0 && mark != existingMark)
                throw new AssistRefusal(AssistWording.HowITeachChangedSincePlanned(course.Code));
        }
        return new PlannedHowITeach(course, text, path, existing, existingMark, mark,
                                    existing is not null && HowITeachPage.HasWords(existing));
    }

    /// <summary><c>plan_write_how_i_teach</c>: where it would go, and what it would replace. Changes nothing.</summary>
    public string PlanWriteHowITeach(string courseCode, string text, string replacing)
    {
        var planned = PlanHowITeach(courseCode, text, replacing);
        if (!planned.ExistingIsWritten || planned.ExistingPath is null)
        {
            string where = Relative(planned.ExistingPath ?? Path.Combine(planned.Course.DirectoryPath, HowITeachPage.FileName));
            return AssistWording.HowITeachPlanCreates(planned.Course.Code, where);
        }
        string changed;
        try { changed = DateText.Iso(DateOnly.FromDateTime(File.GetLastWriteTime(planned.ExistingPath))); }
        catch { changed = "at a time that could not be read"; }
        return AssistWording.HowITeachPlanReplaces(planned.Course.Code, Relative(planned.ExistingPath),
            HowITeachPage.WordCount(planned.ExistingText!).ToString(), changed, planned.ExistingMark!);
    }

    /// <summary>
    /// <c>write_how_i_teach</c>: save what the teacher agreed to. Never over a
    /// written page without its mark; backs the course up first (once per
    /// conversation); keeps a replaced page's settings byte for byte, BOM and
    /// CRLF included; ONE undo entry. Nothing here touches a preview: the
    /// page is never on the site.
    /// </summary>
    public AssistResult WriteHowITeach(string courseCode, string text, string replacing)
    {
        var planned = PlanHowITeach(courseCode, text, replacing);
        if (planned.ExistingIsWritten && planned.Replacing.Length == 0)
            throw new AssistRefusal(AssistWording.HowITeachAlreadyWritten(planned.Course.Code));

        RefuseIfPlantoirIsBuilding(planned.Course);
        string path = planned.ExistingPath ?? Path.Combine(planned.Course.DirectoryPath, HowITeachPage.FileName);
        string newText = planned.ExistingText is { } existing &&
                         (HowITeachPage.SettingsBlock(existing) is not null || planned.ExistingIsWritten)
            ? HowITeachPage.ReplacedPageText(existing, planned.Text)
            : HowITeachPage.NewPageText(planned.Text);

        // A backup wants a section; the page is the course's, so the lowest
        // stands in (the mac's choice; the zip holds the whole course). A copy
        // that cannot be made does not stop the save â€” the trail says so, as
        // the mac's does.
        int standIn = planned.Course.SectionNumbers.DefaultIfEmpty(1).Min();
        string? backup = null;
        try { backup = BackUpOnceForThisConversation(planned.Course, standIn); }
        catch (Exception) { /* recorded on the trail below */ }

        // The backup can take a while; the page must still be the one planned.
        string? nowPath = HowITeachPage.ExistingPath(planned.Course.DirectoryPath);
        bool movedOn = planned.ExistingPath is null
            ? nowPath is not null
            : nowPath is null || Path.GetFileName(nowPath) != Path.GetFileName(planned.ExistingPath) ||
              HowITeachPage.MarkOf(File.ReadAllBytes(nowPath)) != planned.ExistingMark;
        if (movedOn) throw new AssistRefusal(AssistWording.HowITeachChangedSincePlanned(planned.Course.Code));

        bool created = !planned.ExistingIsWritten;
        using (var recording = UndoHistory.Record(_undo,
                   created ? "wrote a new How I Teach page" : "replaced the How I Teach page"))
        {
            _undo?.Touch(path, planned.ExistingText);
            File.WriteAllText(path, newText, new UTF8Encoding(encoderShouldEmitUTF8Identifier: false));
            // As the undo will READ it back (ReadAllText drops a BOM), or the
            // undo would see the page as "edited since" and leave it alone.
            _undo?.Wrote(path, File.ReadAllText(path));
            recording.Done();
        }

        int? wordsBefore = planned.ExistingIsWritten ? HowITeachPage.WordCount(planned.ExistingText!) : null;
        ActivityTrail.Note(ActivityTrail.Event.HowITeachPageWritten,
            $"{planned.Course.Code} Â· " + HowITeachPage.TrailLineForAWrite(
                wordsBefore, HowITeachPage.WordCount(newText), backup is null ? null : Path.GetFileName(backup)));

        return new AssistResult(true, AssistWording.HowITeachSaved(planned.Course.Code), backup);
    }

    /// <summary>Whether a section's page listing leaves this file out (<c>notListedAsAPage</c>).</summary>
    internal static bool ListsAsAPage(Course course, string fullPath) =>
        !HowITeachPage.IsTheHowITeachPage(fullPath, course.DirectoryPath);

    private static void NoteHowITeachRead(Course course, string line) =>
        ActivityTrail.Note(ActivityTrail.Event.HowITeachPageRead, $"{course.Code} Â· {line}");
}
