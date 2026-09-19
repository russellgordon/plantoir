using Plantoir.Core.Assist;

namespace Plantoir.Tests;

/// <summary>
/// What each class-planning tool puts on the undo list, and what it
/// deliberately does not.
///
/// <para><b>Why these exist.</b> Until 2026-09-18 three tools —
/// <c>add_curriculum_mentions</c>, <c>make_room_for_classes</c> and
/// <c>add_classes</c> / <c>add_next_class</c> — called
/// <c>UndoHistory.Begin</c> and never <c>End</c>. <c>Begin</c> ignores a
/// nested call, so the consequence was two-sided and entirely silent: the
/// tool recorded NO undo entry (while <c>add_next_class</c>'s own reply
/// promised the page could be taken back), and the NEXT operation's files
/// were swallowed into the still-open entry and committed under the WRONG
/// description. Nothing in either suite could see it, because every undo test
/// there was drove <see cref="UndoHistory"/> directly rather than a real
/// workspace apply.</para>
///
/// <para>So these drive the real tools against real files and then really
/// undo, which is the only way the pairing can be checked at all.</para>
/// </summary>
public sealed class UndoAcrossToolsTests : IDisposable
{
    private readonly string _folder = Path.Combine(Path.GetTempPath(),
        "plantoir-undo-" + Guid.NewGuid().ToString("N"));
    private readonly FakeLauncher _launcher = new();
    private readonly UndoHistory _history = new();

    public UndoAcrossToolsTests()
    {
        Directory.CreateDirectory(Path.Combine(_folder, "courses", "ICS3U", "section1", "All Classes"));
        File.WriteAllText(Path.Combine(_folder, "preview.ps1"), "# marker");
        File.WriteAllText(Path.Combine(_folder, "deploy.ps1"), "# marker");
        File.WriteAllText(Path.Combine(_folder, "courses", "ICS3U", "course_config.json"),
            """
            {
              "course_code": "ICS3U",
              "course_name": "Computer Science",
              "deploy_target": "netlify",
              "num_sections": 1,
              "per_section_folders": ["All Classes"],
              "per_section_files": [],
              "section_numbers": [1]
            }
            """);

        TimetableMemory.Write(_folder, "ICS3U", 1,
            Enumerable.Range(0, 12).Select(i => new DateOnly(2026, 9, 8).AddDays(i * 2)),
            "block H", new DateOnly(2026, 8, 14));
    }

    public void Dispose()
    {
        try { Directory.Delete(_folder, recursive: true); } catch { }
    }

    private AssistWorkspace Open() => new(_folder, _launcher, undo: _history);

    private string ClassPath(string title) =>
        Path.Combine(_folder, "courses", "ICS3U", "section1", "All Classes", title + ".md");

    /// <summary>Four classes: Unit 1 Days 1–2, Unit 2 Days 1–2, on consecutive meeting days.</summary>
    private void FourClasses()
    {
        var dates = new[] { "2026-09-08", "2026-09-10", "2026-09-12", "2026-09-14" };
        string[] titles = ["Unit 1, Day 1", "Unit 1, Day 2", "Unit 2, Day 1", "Unit 2, Day 2"];
        for (int i = 0; i < titles.Length; i++)
            File.WriteAllText(ClassPath(titles[i]),
                $"---\ntitle: {titles[i]}\npublish: false\ncreated: {dates[i]}T07:00:00.000-0400\n---\nBody.\n");
    }

    // ---- Adding a class page ----------------------------------------------

    [Fact]
    public void ANewClassPageReallyCanBeTakenBack()
    {
        // AssistWording.ACreatedPageCanBeTakenBack is said to the teacher by
        // add_next_class, word for word. Before the End() it was a promise the
        // tool could not keep: "undo that" answered that nothing had been
        // changed, about a page sitting in the teacher's folder.
        FourClasses();
        var workspace = Open();

        workspace.ApplyAddClasses(workspace.PlanAddNextClass("ICS3U", 1, "", null));

        Assert.True(File.Exists(ClassPath("Unit 2, Day 3")));
        Assert.Single(_history.Entries);

        var undone = _history.Undo();

        Assert.True(undone.Succeeded);
        Assert.Empty(undone.Skipped);
        Assert.False(File.Exists(ClassPath("Unit 2, Day 3")));
    }

    [Fact]
    public void APageTheTeacherHasSinceWrittenInIsLeftAlone()
    {
        // The other half of that same sentence — "as long as you have not
        // written anything in it yet". UndoHistory compares what it wrote
        // against what is there now, so this is the property that makes the
        // promise safe to make.
        FourClasses();
        var workspace = Open();
        workspace.ApplyAddClasses(workspace.PlanAddNextClass("ICS3U", 1, "", null));

        File.AppendAllText(ClassPath("Unit 2, Day 3"), "\nThe lesson, written straight away.\n");
        var undone = _history.Undo();

        Assert.Single(undone.Skipped);
        Assert.True(File.Exists(ClassPath("Unit 2, Day 3")));
        Assert.Contains("written straight away", File.ReadAllText(ClassPath("Unit 2, Day 3")));
    }

    // ---- Making room -------------------------------------------------------

    [Fact]
    public void MakingRoomOffersNoUndoAndSaysTheBackupIsTheWayBack()
    {
        // The mac's rule, mirrored rather than improved on: making room
        // renames later days, re-dates every class after the insertion point
        // and rewrites the links that pointed at the old names. An undo that
        // put some of that back and not the rest is worse than none, so the
        // way back is the backup — and the reply now says so, which it did
        // not while it was quietly recording nothing.
        FourClasses();
        var workspace = Open();

        var result = workspace.ApplyInsertClasses(
            workspace.PlanInsertClasses("ICS3U", 1, unit: 2, atDay: 1, count: 1));

        Assert.Empty(_history.Entries);
        Assert.Contains("will not take this back", result.Message);
        Assert.Contains(Path.GetFileName(result.BackupPath!), result.Message);
    }

    [Fact]
    public async Task MakingRoomNoLongerSwallowsTheNextChangesUndo()
    {
        // THE regression. With Begin and no End, the entry stayed open, so
        // the publish below wrote its files into it and the publish's own
        // Begin was ignored. "Undo that" then said "Earlier, you made room
        // for 1 classes…" and took back the publish AND the room-making's
        // files under that description.
        FourClasses();
        var workspace = Open();
        workspace.ApplyInsertClasses(workspace.PlanInsertClasses("ICS3U", 1, unit: 2, atDay: 1, count: 1));

        await workspace.Apply(workspace.PlanPublish("ICS3U", 1, new[] { "Unit 1, Day 1" },
            includeLinked: false, publishes: false), preview: false);

        var entry = Assert.Single(_history.Entries);
        Assert.Contains("published “Unit 1, Day 1”", entry.Description);
        Assert.Equal(new[] { ClassPath("Unit 1, Day 1") }, entry.Files.Keys.ToArray());

        var undone = _history.Undo();

        Assert.True(undone.Succeeded);
        Assert.Contains("published “Unit 1, Day 1”", undone.Description);
        // The room-making stands: Unit 2's classes are still renamed and the
        // new page is still there.
        Assert.True(File.Exists(ClassPath("Unit 2, Day 3")));
        Assert.True(File.Exists(ClassPath("Unit 2, Day 1")));
    }
}
