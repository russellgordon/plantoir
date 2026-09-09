using System.Text.Json;
using Plantoir.Core.Assist;
using Plantoir.Core.Models;

namespace Plantoir.Tests;

/// <summary>
/// <c>contracts/file-formats.json</c> — the files both apps WRITE and the
/// Python then reads.
///
/// <para>A format is the one kind of rule where drift cannot be argued about:
/// a course made on one machine is opened on the other, and a key one app does
/// not write is a question the Python answers with its own default while the
/// teacher is never asked. Three of these lists were read by nobody on this
/// side (contracts/README.md) and one of them, <c>wizardAnswerKeys</c>,
/// describes item 25 exactly.</para>
/// </summary>
public sealed class FileFormatContractTests : IDisposable
{
    private readonly string _folder = Path.Combine(Path.GetTempPath(),
        "plantoir-formats-" + Guid.NewGuid().ToString("N"));

    public void Dispose()
    {
        try { Directory.Delete(_folder, recursive: true); } catch { }
    }

    private static string RepoRoot
    {
        get
        {
            var dir = new DirectoryInfo(AppContext.BaseDirectory);
            for (int i = 0; i < 8 && dir is not null; i++, dir = dir.Parent)
            {
                if (File.Exists(Path.Combine(dir.FullName, "Dockerfile")))
                    return dir.FullName;
            }
            throw new DirectoryNotFoundException("Could not find repository root containing Dockerfile.");
        }
    }

    // ---- The three answers the wizard has to write down -------------------

    /// <summary>
    /// Every source line of the interface project, for the tests that can only
    /// ask "does the app contain this".
    ///
    /// <para>The wizard lives in <c>windows-app/Plantoir/</c>, which
    /// <c>Plantoir.Tests.csproj</c> does not reference — it references
    /// <c>Plantoir.Core</c> and <c>Plantoir.Mcp</c> only. Reading the source is
    /// the same shape <see cref="TaskMilestoneLauncherMarkerTests"/> uses for
    /// the <c>.ps1</c> launchers and <see cref="ToolchainContractTests"/> for
    /// the Dockerfile: coarse, but it answers the one question that matters
    /// here, and it fails when the answer changes.</para>
    /// </summary>
    private static string InterfaceSource()
    {
        string project = Path.Combine(RepoRoot, "windows-app", "Plantoir");
        var text = new System.Text.StringBuilder();
        foreach (string file in Directory.EnumerateFiles(project, "*.cs", SearchOption.AllDirectories))
        {
            if (file.Contains($"{Path.DirectorySeparatorChar}obj{Path.DirectorySeparatorChar}")) continue;
            if (file.Contains($"{Path.DirectorySeparatorChar}bin{Path.DirectorySeparatorChar}")) continue;
            text.Append(File.ReadAllText(file));
        }
        return text.ToString();
    }

    /// <summary>
    /// The wizard writes every answer the contract says it asks for.
    ///
    /// <para><c>setup_course.py</c> reads each of these as the DEFAULT for a
    /// question it would otherwise ask, so an app that omits one does not
    /// merely skip a step: the Python takes its own answer and the teacher
    /// never learns there was a choice.</para>
    /// </summary>
    [Fact]
    public void TheWizardWritesEveryAnswerTheContractSaysItAsksFor()
    {
        // Empty since 2026-09-07, when the wizard began asking the skeleton
        // question (contracts/README.md). It held "use_skeleton" for three
        // weeks — named HERE rather than read from the contract's
        // knownDivergence note, because a note cannot fail a test run and a
        // name beside a skipped test shows in every run's skip count. Kept so
        // the next knowingly absent key has somewhere to be named.
        var knowinglyAbsent = new HashSet<string>(StringComparer.Ordinal);

        var doc = ContractLoader.LoadJson("file-formats.json");
        var keys = doc["courseConfigKeys"]!["wizardAnswerKeys"]!["keys"]!.AsArray();
        Assert.NotEmpty(keys);

        string source = InterfaceSource();
        foreach (var entry in keys)
        {
            string key = entry!["key"]!.ToString();
            if (knowinglyAbsent.Contains(key)) continue;

            // The dictionary-entry shape, not bare containment: `SkeletonCatalog`
            // is already in this app and "referenced only from a comment"
            // (item 25), which is exactly how a source search goes green for a
            // question nobody asks.
            Assert.True(source.Contains($"[\"{key}\"]", StringComparison.Ordinal),
                $"The wizard writes no \"{key}\" into course_config.json. setup_course.py will " +
                "take its own default for it and the teacher is never asked — which is not a " +
                "missing feature a teacher can report, because nothing on screen says the " +
                "question existed.");
        }
    }

    /// <summary>
    /// contracts/README.md's acceptance test, skipped from 2026-09-06
    /// until the wizard asked the skeleton question on 2026-09-07.
    ///
    /// <para>Around 1,900 course codes have a skeleton and no ready-made
    /// payload, so this is the question most teachers actually meet. Both
    /// apps ask it and write <c>hasSkeleton(code) &amp;&amp; teacherSaidYes</c>.
    /// For three weeks this side wrote nothing, so <c>setup_course.py</c>'s
    /// own default of TRUE decided — the right answer, arrived at without
    /// asking, which was still not the same product.</para>
    /// </summary>
    [Fact]
    public void TheWizardWritesUseSkeleton()
    {
        Assert.Contains("[\"use_skeleton\"]", InterfaceSource(), StringComparison.Ordinal);
    }

    // ---- Where a section's first publish leaves its mark ------------------

    /// <summary>
    /// How each app knows whether a section has EVER been published to where
    /// it is going NOW — which is what makes a 6:30 AM deploy safe or a
    /// failure nobody is awake for.
    ///
    /// <para>The paths were retyped by hand in two test files. Driving them
    /// from the contract means a destination the mac adds arrives here as a
    /// named failure rather than as a silent hole.</para>
    /// </summary>
    [Fact]
    public void TheFirstPublishMarkerIsWhereTheContractSaysForEveryDestination()
    {
        var doc = ContractLoader.LoadJson("file-formats.json");
        var paths = doc["firstDeployMarkers"]!["paths"]!.AsArray();
        Assert.NotEmpty(paths);

        // The contract names destinations in a teacher's words; the config
        // spells them its own way. A destination the mac adds fails here on
        // the lookup, naming it.
        var configSpelling = new Dictionary<string, string>(StringComparer.Ordinal)
        {
            ["Netlify"] = "netlify",
            ["Cloudflare Pages"] = "cloudflare_pages",
            ["a folder on this computer"] = "local_folder",
        };

        string courseFolder = Path.Combine(_folder, "courses", "ICS3U");
        Directory.CreateDirectory(courseFolder);
        File.WriteAllText(Path.Combine(_folder, "preview.ps1"), "# marker");
        File.WriteAllText(Path.Combine(_folder, "deploy.ps1"), "# marker");
        File.WriteAllText(Path.Combine(courseFolder, "course_config.json"),
            """
            {
              "course_code": "ICS3U",
              "course_name": "Computer Science",
              "deploy_target": "netlify",
              "num_sections": 1,
              "section_numbers": [1]
            }
            """);
        var course = new AssistWorkspace(_folder, new FakeLauncher()).Course("ICS3U");
        Assert.NotNull(course);

        foreach (var entry in paths)
        {
            string destination = entry!["destination"]!.ToString();
            Assert.True(configSpelling.TryGetValue(destination, out string? type),
                $"contracts/file-formats.json names a publishing destination this app has no " +
                $"spelling for: \"{destination}\". Add it, or say here why this platform has none.");

            string? actual = DeployCommand.FirstDeployMarkerPath(1, course!, type!);

            if (entry["path"] is null)
            {
                Assert.True(actual is null,
                    $"\"{destination}\" keeps no marker — it asks the teacher nothing, so it counts " +
                    $"as always-published — but this app looked for one at {actual}.");
                continue;
            }

            string expected = entry["path"]!.ToString()
                .Replace("courses/<CODE>", courseFolder.Replace('\\', '/'), StringComparison.Ordinal)
                .Replace("<N>", "1", StringComparison.Ordinal);

            Assert.Equal(expected, actual!.Replace('\\', '/'));
        }
    }

    // ---- The dates a section actually meets -------------------------------

    /// <summary>
    /// The remembered timetable is at the path the contract names and carries
    /// the fields it names, because the OTHER app reads this file.
    ///
    /// <para>It lives inside the course folder deliberately, so it travels
    /// with a backup, an archive and a restore.</para>
    /// </summary>
    [Fact]
    public void TheRememberedTimetableIsWhereTheContractSaysAndCarriesItsFields()
    {
        var doc = ContractLoader.LoadJson("file-formats.json");
        var section = doc["sectionTimetable"]!;

        Directory.CreateDirectory(Path.Combine(_folder, "courses", "ICS3U"));
        Assert.True(TimetableMemory.Write(_folder, "ICS3U", 2,
            new[] { new DateOnly(2026, 9, 10), new DateOnly(2026, 9, 8) },
            "timetable.xlsx, block H", new DateOnly(2026, 8, 14)));

        string expected = Path.GetFullPath(Path.Combine(_folder,
            section["path"]!.ToString().Replace("<CODE>", "ICS3U").Replace("<N>", "2")));
        Assert.True(File.Exists(expected),
            $"The contract says a section's timetable is kept at {section["path"]}, and nothing " +
            "was written there. Both apps read this file, so a path only one of them uses is a " +
            "timetable the other cannot find.");

        var written = JsonDocument.Parse(File.ReadAllText(expected)).RootElement;
        foreach (var field in section["fields"]!.AsArray())
        {
            string name = field!["field"]!.ToString();
            Assert.True(written.TryGetProperty(name, out var value),
                $"The timetable file carries no \"{name}\". The contract says it must, and the " +
                "other app reads it.");

            switch (name)
            {
                case "dates":
                    Assert.Equal(JsonValueKind.Array, value.ValueKind);
                    // Plain dates, earliest first — not a recurrence rule, because
                    // no rule survives a school year's holidays and PA days.
                    Assert.Equal(new[] { "2026-09-08", "2026-09-10" },
                        value.EnumerateArray().Select(d => d.GetString()).ToArray());
                    break;
                case "source":
                    Assert.Equal("timetable.xlsx, block H", value.GetString());
                    break;
                case "recorded":
                    Assert.Equal("2026-08-14", value.GetString());
                    break;
                case "section":
                    // Presence is not enough: `section: 0` would satisfy a
                    // TryGetProperty and tell the other app nothing.
                    Assert.Equal(2, value.GetInt32());
                    break;
            }
        }

        // "Read back as 'not recorded' when absent rather than blank" — the
        // contract's reason for the source field being there at all.
        File.WriteAllText(expected, """{"section": 2, "dates": ["2026-09-08"]}""");
        Assert.Equal("not recorded", TimetableMemory.Read(_folder, "ICS3U", 2)!.Source);
    }

    // ---- What may be done to a teacher's own frontmatter ------------------

    /// <summary>
    /// The rules for editing the line that decides whether students see a
    /// page. Every one of them is about restraint: the frontmatter is the
    /// teacher's, and they will see the diff in Obsidian.
    ///
    /// <para>Keyed by the contract's own rule sentences and checked for
    /// completeness at the end, so a rule the mac ADDS fails here by name
    /// rather than sitting unread — which is the failure contracts/README.md item
    /// 29 exists to end.</para>
    /// </summary>
    [Fact]
    public void TheRulesForWritingAPagesVisibilityAreFollowed()
    {
        var doc = ContractLoader.LoadJson("file-formats.json");
        var unanswered = new HashSet<string>(StringComparer.Ordinal);
        foreach (var rule in doc["pageVisibility"]!["writingRules"]!.AsArray())
            unanswered.Add(rule!["rule"]!.ToString());
        Assert.NotEmpty(unanswered);

        void Answered(string rule)
        {
            Assert.True(unanswered.Remove(rule),
                $"No rule in the contract reads \"{rule}\" any more — it has been renamed or " +
                "removed on the mac and this test is answering a question nobody asked.");
        }

        // The first rule was this app's own behaviour before it was the
        // contract's: until 2026-09-07 the contract said the opposite (keep
        // the old key, inverted), this test held that rule in a
        // "knowinglyNotFollowed" set removed by NAME, and the migration test
        // sat skipped as a named divergence. The set is kept, EMPTY, so the
        // next knowing divergence has somewhere to be named rather than a
        // comment — and so that a contract rule this app does not follow
        // fails here by name instead of being quietly marked answered.
        var knowinglyNotFollowed = new HashSet<string>(StringComparer.Ordinal);

        // A page in the old spelling is migrated: the new key on the old
        // key's line, the legacy key gone. The full set of cases, including
        // the deliberate exception to rule 4, is TheOldSpellingIsMigratedToTheNewKey.
        var (migrated, migration) = PageFrontmatter.SetDraft(
            "---\ntitle: Day one\ndraftSection1: true\n---\nBody.\n", "publishForSection1", draft: false);
        Assert.True(migration.Changed);
        Assert.Equal("---\ntitle: Day one\npublishForSection1: true\n---\nBody.\n", migrated);
        Answered("A page written in the old spelling is MIGRATED to the new key, and the legacy key removed, the first time something edits its visibility");

        // Edit the LINE, never round-trip the YAML.
        string withComment =
            "---\ntitle: Day one   # the teacher's own note\npublishForSection1: false\ntags: [unit1]\n---\nBody.\n";
        var (edited, edit) = PageFrontmatter.SetDraft(withComment, "publishForSection1", draft: false);
        Assert.True(edit.Changed);
        Assert.Contains("# the teacher's own note", edited, StringComparison.Ordinal);
        Assert.Contains("tags: [unit1]", edited, StringComparison.Ordinal);
        Assert.Equal(
            new[] { "title", "publishForSection1", "tags" },
            edited.Split('\n').Where(line => line.Contains(':') && !line.StartsWith("---"))
                  .Select(line => line[..line.IndexOf(':')].Trim()).ToArray());
        Answered("Edit the LINE, never round-trip the YAML");

        // A page with no frontmatter at all gets a block of its own.
        var (given, gaveOne) = PageFrontmatter.SetDraft("# Just a heading\n", "publish", draft: true);
        Assert.True(gaveOne.Changed);
        Assert.StartsWith("---", given, StringComparison.Ordinal);
        Assert.Contains("publish: false", given, StringComparison.Ordinal);
        Assert.EndsWith("# Just a heading\n", given, StringComparison.Ordinal);
        Answered("A page with no frontmatter at all gets a block of its own");

        // Writing the value it already has changes nothing — because a no-op
        // write still moves the modification time, and the next build then
        // believes the content changed.
        string already = "---\npublish: true\n---\nBody.\n";
        var (untouched, noEdit) = PageFrontmatter.SetDraft(already, "publish", draft: false);
        Assert.False(noEdit.Changed);
        Assert.Equal(already, untouched);
        Answered("Writing the value it already has changes nothing");

        foreach (string rule in knowinglyNotFollowed)
        {
            Assert.True(unanswered.Remove(rule),
                $"\"{rule}\" is recorded here as a rule this app knowingly does not follow, and the " +
                "contract no longer contains it — or a test above has just answered it. Either way " +
                "the divergence is over: delete it from knowinglyNotFollowed and assert the " +
                "rule above.");
        }

        Assert.True(unanswered.Count == 0,
            "contracts/file-formats.json names rules for writing a page's visibility that no test " +
            "here answers: " + string.Join("; ", unanswered.OrderBy(r => r, StringComparer.Ordinal)) +
            ". A rule added on the mac is a rule this app is not following yet.");
    }

    /// <summary>
    /// <c>pageVisibility.writingRules[0]</c>, as decided 2026-09-07: a page
    /// in the old spelling is MIGRATED — the new key on the old key's line,
    /// the legacy key gone — and a page carrying both loses the legacy one.
    /// Until that day this test asserted the opposite and was skipped as a
    /// named divergence (the contract and the mac kept the old key inverted;
    /// this app migrated). The contract moved to this app's behaviour, so
    /// the mac's suite fails on it until the mac adopts it — a request, not
    /// damage (issue #107).
    ///
    /// <para>The last assertion is the one genuine design question: a legacy
    /// page whose value is already right IS rewritten, once, to migrate the
    /// key, as the contract's own exception to rule 4 says. The case is
    /// reachable only inside a batch that is changing other pages, so the
    /// build that follows was happening anyway.</para>
    /// </summary>
    [Fact]
    public void TheOldSpellingIsMigratedToTheNewKey()
    {
        // The per-section spelling, on a course-level page: same line, new key.
        string shared = "---\ntitle: Day one\ndraftSection1: true\n---\nBody.\n";
        var (writtenShared, sharedEdit) = PageFrontmatter.SetDraft(shared, "publishForSection1", draft: false);
        Assert.Equal("---\ntitle: Day one\npublishForSection1: true\n---\nBody.\n", writtenShared);
        Assert.True(sharedEdit.Changed);

        // And the plain one, on a page inside a section's own folder.
        string local = "---\ntitle: Day one\ndraft: true\n---\nBody.\n";
        var (writtenLocal, _) = PageFrontmatter.SetDraft(local, "publish", draft: false);
        Assert.Equal("---\ntitle: Day one\npublish: true\n---\nBody.\n", writtenLocal);

        // Both spellings on one page: the legacy line goes.
        string both = "---\npublishForSection1: false\ndraftSection1: true\n---\nBody.\n";
        var (writtenBoth, _) = PageFrontmatter.SetDraft(both, "publishForSection1", draft: false);
        Assert.Equal("---\npublishForSection1: true\n---\nBody.\n", writtenBoth);

        // Already right, still legacy: migrated once, on purpose (rule 4's one exception).
        string alreadyRight = "---\ndraftSection1: false\n---\nBody.\n";
        var (migrated, edit) = PageFrontmatter.SetDraft(alreadyRight, "publishForSection1", draft: false);
        Assert.True(edit.Changed);
        Assert.Equal("---\npublishForSection1: true\n---\nBody.\n", migrated);

        // And once migrated, rule 4 holds: the same value again touches nothing.
        var (untouched, again) = PageFrontmatter.SetDraft(migrated, "publishForSection1", draft: false);
        Assert.False(again.Changed);
        Assert.Equal(migrated, untouched);
    }
}
