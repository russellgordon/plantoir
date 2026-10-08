using System.Text.Json.Nodes;
using Plantoir.Core.Assist;
using Plantoir.Core.Scripting;

namespace Plantoir.Tests;

/// <summary>
/// The one notification a scheduled run sends (#448): the contract's
/// <c>scheduledPublishStopped.notification.announcing</c> cases, and every
/// ending of a REAL run through <see cref="ScheduledRunAnnouncement.RunAndAnnounce"/>
/// — whose one-shot clearing deletes the job file before the notification is
/// posted, which is exactly what silenced every scheduled deploy until #448.
/// A stand-in takes the posts; the system's toasts are never reached.
/// </summary>
[Collection(SharedActivityState.Name)]
public class ScheduledRunAnnouncementTests : IDisposable
{
    private readonly string _root = Directory.CreateTempSubdirectory("plantoir-announce").FullName;
    private readonly FakeScheduler _scheduler;
    private readonly string _trail;
    private string Outcomes => Path.Combine(_root, "outcomes");

    public ScheduledRunAnnouncementTests()
    {
        _scheduler = new FakeScheduler(_root);
        _trail = Path.Combine(_root, "activity.txt");
        ActivityTrail.SetCustomLogPathForTesting(_trail);
    }

    public void Dispose()
    {
        _scheduler.Dispose();
        ActivityTrail.SetCustomLogPathForTesting(TestTrailRedirect.ScratchTrailPath);
        try { Directory.Delete(_root, recursive: true); } catch { }
    }

    /// <summary>Records what it was asked; keeps what is on show by tag, so a post replaces.</summary>
    private sealed class FakeToasts : ScheduledRunAnnouncement.IPoster
    {
        public ScheduledRunAnnouncement.Permission Permission { get; set; } = ScheduledRunAnnouncement.Permission.Allowed;
        public bool PostFails { get; set; }
        public bool PostThrows { get; set; }
        public List<(string Tag, string Launch, string Sentence)> Posts { get; } = new();
        public Dictionary<string, string> OnShow { get; } = new();

        public bool Post(string tag, string launchArgument, string sentence)
        {
            if (PostThrows) throw new InvalidOperationException("the notification platform is not there");
            if (PostFails) return false;
            Posts.Add((tag, launchArgument, sentence));
            OnShow[tag] = sentence;
            return true;
        }

        public bool WithdrawThrows { get; set; }
        public List<string> Withdrawn { get; } = new();

        public void Withdraw(string tag)
        {
            if (WithdrawThrows) throw new InvalidOperationException("Notification Center did not answer");
            Withdrawn.Add(tag);
            OnShow.Remove(tag);
        }
    }

    private string[] TrailLines() => File.Exists(_trail) ? File.ReadAllLines(_trail) : [];

    private string[] NotificationLines() => TrailLines().Where(line =>
        line.Contains(ScheduledRunAnnouncement.ToldLine) || line.Contains(ScheduledRunAnnouncement.TurnedOffLine)
        || line.Contains(ScheduledRunAnnouncement.CouldNotBeSentLine)).ToArray();

    private string Folder()
    {
        string folder = FakeScheduler.WorkingFolderWith(_root, "work", "ICS3U",
            """{ "course_code": "ICS3U", "section_numbers": [1], "deploy_target": "netlify" }""");
        Directory.CreateDirectory(Path.Combine(folder, "courses", "ICS3U", ".netlify_sites"));
        File.WriteAllText(Path.Combine(folder, "courses", "ICS3U", ".netlify_sites", "section1.json"), "{}");
        return folder;
    }

    private ScheduledRun.World World(DateTimeOffset now, Func<string, int> wrapper) => new()
    {
        Now = () => now,
        Sleep = _ => { },
        CloudflareAccountID = () => "",
        RunWrapper = wrapper,
        OutcomeDirectory = Outcomes,
    };

    /// <summary>The section's own sentence for the record that is there, which must be of this kind.</summary>
    private string Expected(string folder, ScheduledPublishOutcome.Kind kind)
    {
        var record = ScheduledPublishOutcome.ReadFrom(Outcomes, "ICS3U", 1, folder)!;
        Assert.Equal(kind, record.Outcome);
        return ScheduledPublishOutcome.Sentence("ICS3U", 1, record);
    }

    // ---- The contract's announcing cases --------------------------------------

    [Fact]
    public void TheContractsAnnouncingCases()
    {
        var notification = ContractLoader.LoadJson("shared-rules.json")["scheduledPublishStopped"]!["notification"]!;
        var kindKeys = ((JsonObject)ContractLoader.LoadJson("shared-rules.json")["scheduledPublishStopped"]!["kinds"]!)
            .Select(pair => pair.Key).ToList();
        var kinds = Enum.GetValues<ScheduledPublishOutcome.Kind>()
            .ToDictionary(ScheduledPublishOutcome.ContractKey);
        Assert.Equal(kindKeys.OrderBy(k => k), kinds.Keys.OrderBy(k => k));   // every kind the contract names, and no other

        int played = 0;
        foreach (var c in notification["announcing"]!["cases"]!.AsArray())
        {
            if (c!["onlyWhereThereIsAPrompt"]?.GetValue<bool>() == true) continue;   // Windows toasts ask no question
            string name = c["name"]!.ToString();
            var permission = c["permission"]!.ToString() switch
            {
                "allowed" => ScheduledRunAnnouncement.Permission.Allowed,
                "notAllowed" => ScheduledRunAnnouncement.Permission.NotAllowed,
                var other => throw new InvalidOperationException($"{name}: permission {other} has no Windows meaning"),
            };
            var records = c["record"]!.ToString() == "everyKind"
                ? kinds.Values.Select(k => (ScheduledPublishOutcome.Kind?)k).ToList()
                : [null];

            foreach (var kind in records)
            {
                string folder = Path.Combine(_root, $"case-{played++}");
                Directory.CreateDirectory(folder);
                if (kind is { } k)
                    ScheduledPublishOutcome.Record(Outcomes, "ICS4U", 1, k, "Netlify", folder);
                var toasts = new FakeToasts { Permission = permission, PostFails = c["postFails"]!.GetValue<bool>() };
                int linesBefore = TrailLines().Length;

                ScheduledRunAnnouncement.Announce(new ScheduledPublishToast.Target("ICS4U", 1, folder), toasts, Outcomes);

                bool posts = c["posts"]!.GetValue<bool>();
                Assert.True(posts == (toasts.Posts.Count == 1), $"{name} ({kind}): posted {toasts.Posts.Count}");
                if (posts)
                    Assert.Equal(ScheduledPublishOutcome.Sentence("ICS4U", 1,
                        ScheduledPublishOutcome.ReadFrom(Outcomes, "ICS4U", 1, folder)!), toasts.Posts[0].Sentence);
                var added = TrailLines().Skip(linesBefore).ToList();
                if (c["trailSays"] is { } says)
                {
                    Assert.True(added.Count == 1, $"{name} ({kind}): {added.Count} trail lines");
                    Assert.EndsWith($" · ICS4U/1 · {says}", added[0]);
                }
                else Assert.Empty(added);
            }
        }
        Assert.True(played >= 3 * kinds.Count, $"only {played} plays");
    }

    // ---- A real run: the one-shot clearing goes first (#448) ------------------

    [Fact]
    public void ARunThatClearedItsOwnJobStillTellsTheTeacher()
    {
        string folder = Folder();
        var now = DateTimeOffset.Now;
        string name = _scheduler.AddNew(folder, "ICS3U", 1, now, "Netlify");
        string jobPath = TaskScheduling.JobPath(name);
        var toasts = new FakeToasts();

        var ending = ScheduledRunAnnouncement.RunAndAnnounce(jobPath, toasts, World(now, _ =>
        {
            ScheduledPublishOutcome.Record(Outcomes, "ICS3U", 1, ScheduledPublishOutcome.Kind.Succeeded, "Netlify", folder);
            return 0;
        }));

        Assert.Equal(ScheduledRun.Ending.Deployed, ending);
        Assert.False(File.Exists(jobPath), "the run did not clear its own job, so this test proves nothing");
        Assert.DoesNotContain(name, _scheduler.Tasks.Keys);
        var post = Assert.Single(toasts.Posts);
        Assert.Equal(Expected(folder, ScheduledPublishOutcome.Kind.Succeeded), post.Sentence);
        Assert.Equal(new ScheduledPublishToast.Target("ICS3U", 1, folder), ScheduledPublishToast.Parse(post.Launch));
        Assert.Equal(ScheduledRunAnnouncement.TagFor(new("ICS3U", 1, folder)), post.Tag);
        Assert.EndsWith($" · ICS3U/1 · {ScheduledRunAnnouncement.ToldLine}", Assert.Single(NotificationLines()));
    }

    [Theory]
    [InlineData(ScheduledPublishOutcome.Kind.Succeeded)]
    [InlineData(ScheduledPublishOutcome.Kind.DidNotFinish)]
    [InlineData(ScheduledPublishOutcome.Kind.NeededAnAnswer)]
    [InlineData(ScheduledPublishOutcome.Kind.BuildNeededAnAnswer)]
    [InlineData(ScheduledPublishOutcome.Kind.BuildDidNotFinish)]
    public void EveryWayADeployEndsIsAnnouncedOnce(ScheduledPublishOutcome.Kind kind)
    {
        string folder = Folder();
        var now = DateTimeOffset.Now;
        string name = _scheduler.AddNew(folder, "ICS3U", 1, now, "Netlify");
        var toasts = new FakeToasts();

        ScheduledRunAnnouncement.RunAndAnnounce(TaskScheduling.JobPath(name), toasts, World(now, _ =>
        {
            ScheduledPublishOutcome.Record(Outcomes, "ICS3U", 1, kind, "Netlify", folder);
            return kind == ScheduledPublishOutcome.Kind.Succeeded ? 0 : 1;
        }));

        Assert.Equal(Expected(folder, kind), Assert.Single(toasts.Posts).Sentence);
        Assert.Single(NotificationLines());
    }

    [Fact]
    public void AStandDownIsAnnouncedAfterItsJobIsCleared()
    {
        string folder = Folder();
        var now = DateTimeOffset.Now;
        string name = _scheduler.AddNew(folder, "ICS3U", 1, now.AddDays(-8), "Netlify");   // past its window
        var toasts = new FakeToasts();

        var ending = ScheduledRunAnnouncement.RunAndAnnounce(TaskScheduling.JobPath(name), toasts, World(now, _ => 0));

        Assert.Equal(ScheduledRun.Ending.StoodDown, ending);
        Assert.False(File.Exists(TaskScheduling.JobPath(name)));
        Assert.Equal(Expected(folder, ScheduledPublishOutcome.Kind.TooLateToRun), Assert.Single(toasts.Posts).Sentence);
    }

    [Fact]
    public void ACouldNotRunAsSetNowIsAnnounced()
    {
        string folder = FakeScheduler.WorkingFolderWith(_root, "cf", "ICS3U",
            """{ "course_code": "ICS3U", "section_numbers": [1], "deploy_target": "cloudflare_pages" }""");
        var now = DateTimeOffset.Now;
        string name = _scheduler.AddNew(folder, "ICS3U", 1, now, "Netlify");
        var toasts = new FakeToasts();

        var ending = ScheduledRunAnnouncement.RunAndAnnounce(TaskScheduling.JobPath(name), toasts, World(now, _ => 0));

        Assert.Equal(ScheduledRun.Ending.StoodDown, ending);
        Assert.Equal(ScheduledPublishOutcome.Sentence("ICS3U", 1, ScheduledPublishOutcome.ReadFrom(Outcomes, "ICS3U", 1, folder)!),
                     Assert.Single(toasts.Posts).Sentence);
    }

    [Fact]
    public void ADeploySetAgainWhileTheRunWorksIsAnnouncedAsThisRunsNewsAndKeepsTheNewTask()
    {
        string folder = Folder();
        var now = DateTimeOffset.Now;
        string name = _scheduler.AddNew(folder, "ICS3U", 1, now, "Netlify");
        var toasts = new FakeToasts();

        ScheduledRunAnnouncement.RunAndAnnounce(TaskScheduling.JobPath(name), toasts, World(now, _ =>
        {
            ScheduledPublishOutcome.Record(Outcomes, "ICS3U", 1, ScheduledPublishOutcome.Kind.Succeeded, "Netlify", folder);
            _scheduler.AddNew(folder, "ICS3U", 1, now.AddDays(1), "Netlify");   // set again, same name
            return 0;
        }));

        Assert.Contains(name, _scheduler.Tasks.Keys);                // "not mine any more": left alone
        Assert.True(File.Exists(TaskScheduling.JobPath(name)));
        Assert.Equal(Expected(folder, ScheduledPublishOutcome.Kind.Succeeded), Assert.Single(toasts.Posts).Sentence);
        Assert.Single(NotificationLines());
    }

    [Fact]
    public void ARunThatNoLongerStandsAnnouncesNothingNotEvenAnOlderRecord()
    {
        string folder = Folder();
        var now = DateTimeOffset.Now;
        string name = _scheduler.AddNew(folder, "ICS3U", 1, now, "Netlify");
        ScheduledPublishOutcome.Record(Outcomes, "ICS3U", 1, ScheduledPublishOutcome.Kind.DidNotFinish, "Netlify", folder);
        _scheduler.Tasks.Remove(name);   // cancelled meanwhile
        var toasts = new FakeToasts();

        var ending = ScheduledRunAnnouncement.RunAndAnnounce(TaskScheduling.JobPath(name), toasts, World(now, _ => 0));

        Assert.Equal(ScheduledRun.Ending.NoLongerStands, ending);
        Assert.Empty(toasts.Posts);
        Assert.Empty(NotificationLines());
    }

    [Fact]
    public void AWrapperThatWroteNothingDoesNotReplayLastWeeksRecord()
    {
        string folder = Folder();
        var now = DateTimeOffset.Now;
        string name = _scheduler.AddNew(folder, "ICS3U", 1, now, "Netlify");
        ScheduledPublishOutcome.Record(Outcomes, "ICS3U", 1, ScheduledPublishOutcome.Kind.Succeeded, "Netlify", folder);
        string record = Directory.GetFiles(Outcomes).Single();
        File.SetLastWriteTime(record, DateTime.Now.AddDays(-7));
        var toasts = new FakeToasts();

        Assert.Equal(ScheduledRun.Ending.Deployed,
            ScheduledRunAnnouncement.RunAndAnnounce(TaskScheduling.JobPath(name), toasts, World(now, _ => 1)));

        Assert.Empty(toasts.Posts);
        Assert.Empty(NotificationLines());
    }

    [Fact]
    public void APostThatThrowsSaysSoOnTheTrailAndTheRunStillEnds()
    {
        string folder = Folder();
        var now = DateTimeOffset.Now;
        string name = _scheduler.AddNew(folder, "ICS3U", 1, now, "Netlify");
        var toasts = new FakeToasts { PostThrows = true };
        var said = new List<string>();

        var ending = ScheduledRunAnnouncement.RunAndAnnounce(TaskScheduling.JobPath(name), toasts, World(now, _ =>
        {
            ScheduledPublishOutcome.Record(Outcomes, "ICS3U", 1, ScheduledPublishOutcome.Kind.Succeeded, "Netlify", folder);
            return 0;
        }), diagnostic: said.Add);

        Assert.Equal(ScheduledRun.Ending.Deployed, ending);
        Assert.EndsWith($" · ICS3U/1 · {ScheduledRunAnnouncement.CouldNotBeSentLine}", Assert.Single(NotificationLines()));
        Assert.Contains(said, line => line.Contains("the notification platform is not there"));
    }

    // ---- What stays on show: notification.onShow (#464) ---------------------

    /// <summary>
    /// Every <c>notification.onShow</c> case, played through the real post
    /// (<see cref="ScheduledRunAnnouncement.Announce"/>, after writing a record of
    /// the step's kind) and the real dismissal
    /// (<see cref="ScheduledRunAnnouncement.TeacherDismissed"/>), against a
    /// stand-in that keeps what is on show by tag. Until #464 Windows ran none of
    /// them, and the dismiss case could not have passed: nothing withdrew.
    /// </summary>
    [Fact]
    public void TheContractsOnShowCases()
    {
        var kinds = Enum.GetValues<ScheduledPublishOutcome.Kind>().ToDictionary(ScheduledPublishOutcome.ContractKey);
        var cases = ContractLoader.LoadJson("shared-rules.json")["scheduledPublishStopped"]!["notification"]!["onShow"]!["cases"]!.AsArray();
        Assert.NotEmpty(cases);
        int played = 0;
        foreach (var c in cases)
        {
            string name = c!["name"]!.ToString();
            string folder = Path.Combine(_root, $"onshow-{played++}");
            Directory.CreateDirectory(folder);
            var toasts = new FakeToasts();
            // Which section and kind each tag on show stands for.
            var meaning = new Dictionary<string, (string Course, int Section, string Kind)>();

            foreach (var step in c["steps"]!.AsArray())
            {
                if (step!["post"] is JsonObject post)
                {
                    var target = new ScheduledPublishToast.Target(post["course"]!.ToString(), post["section"]!.GetValue<int>(), folder);
                    string kind = post["kind"]!.ToString();
                    Assert.True(kinds.ContainsKey(kind), $"{name}: kind {kind} has no Windows record");
                    ScheduledPublishOutcome.Record(Outcomes, target.CourseCode, target.Section, kinds[kind], "Netlify", folder);
                    Assert.Equal(ScheduledRunAnnouncement.Said.Told, ScheduledRunAnnouncement.Announce(target, toasts, Outcomes));
                    meaning[ScheduledRunAnnouncement.TagFor(target)] = (target.CourseCode, target.Section, kind);
                }
                else if (step["dismiss"] is JsonObject dismiss)
                {
                    var target = new ScheduledPublishToast.Target(dismiss["course"]!.ToString(), dismiss["section"]!.GetValue<int>(), folder);
                    ScheduledRunAnnouncement.TeacherDismissed(target, toasts, Outcomes);
                    Assert.Null(ScheduledPublishOutcome.ReadFrom(Outcomes, target.CourseCode, target.Section, folder));
                }
                else throw new InvalidOperationException($"{name}: a step that is neither post nor dismiss");
            }

            var expected = c["stillShown"]!.AsArray()
                .Select(s => $"{s!["course"]}/{s["section"]}/{s["kind"]}").OrderBy(x => x).ToList();
            var shown = toasts.OnShow.Keys.Select(tag => meaning[tag])
                .Select(m => $"{m.Course}/{m.Section}/{m.Kind}").OrderBy(x => x).ToList();
            Assert.True(expected.SequenceEqual(shown), $"{name}: on show [{string.Join(", ", shown)}], expected [{string.Join(", ", expected)}]");
            // What is on show carries the sentence of the kind it stands for.
            foreach (var (tag, sentence) in toasts.OnShow)
            {
                var m = meaning[tag];
                var record = ScheduledPublishOutcome.ReadFrom(Outcomes, m.Course, m.Section, folder)!;
                Assert.Equal(ScheduledPublishOutcome.Sentence(m.Course, m.Section, record), sentence);
            }
        }
        Assert.Equal(cases.Count, played);
    }

    [Fact]
    public void ADismissalWhoseWithdrawalFailsStillClearsTheRecordAndSaysWhy()
    {
        string folder = Path.Combine(_root, "withdraw-fails");
        Directory.CreateDirectory(folder);
        var target = new ScheduledPublishToast.Target("ICS4U", 1, folder);
        ScheduledPublishOutcome.Record(Outcomes, "ICS4U", 1, ScheduledPublishOutcome.Kind.DidNotFinish, "Netlify", folder);
        var said = new List<string>();
        var linesBefore = TrailLines().Length;

        ScheduledRunAnnouncement.TeacherDismissed(target, new FakeToasts { WithdrawThrows = true }, Outcomes, said.Add);

        Assert.Null(ScheduledPublishOutcome.ReadFrom(Outcomes, "ICS4U", 1, folder));
        Assert.Contains(said, line => line.Contains("Notification Center did not answer"));
        Assert.Equal(linesBefore, TrailLines().Length);   // the withdrawal writes no trail line, as on the mac
    }

    [Fact]
    public void TheWithdrawalNamesTheTagThePostUsed()
    {
        string folder = Path.Combine(_root, "same-tag");
        Directory.CreateDirectory(folder);
        var target = new ScheduledPublishToast.Target("ICS4U", 1, folder);
        ScheduledPublishOutcome.Record(Outcomes, "ICS4U", 1, ScheduledPublishOutcome.Kind.Succeeded, "Netlify", folder);
        var toasts = new FakeToasts();
        ScheduledRunAnnouncement.Announce(target, toasts, Outcomes);
        ScheduledRunAnnouncement.TeacherDismissed(target, toasts, Outcomes);
        Assert.Equal(Assert.Single(toasts.Posts).Tag, Assert.Single(toasts.Withdrawn));
    }

    /// <summary>
    /// The band's Dismiss goes through <see cref="ScheduledRunAnnouncement.TeacherDismissed"/>,
    /// and the system's poster removes by the same group it posts under. Source-read,
    /// because the test project cannot reference the WinUI app: a later edit that
    /// put the bare record deletion back would leave the toast up and pass every
    /// other test.
    /// </summary>
    [Fact]
    public void TheBandsDismissWithdrawsTheNotification()
    {
        string app = Path.Combine(ContractLoader.RepositoryRoot, "windows-app", "Plantoir");
        string view = File.ReadAllText(Path.Combine(app, "Views", "SectionDetailView.xaml.cs"));
        Assert.Contains("ScheduledRunAnnouncement.TeacherDismissed(", view);
        Assert.DoesNotContain("ScheduledPublishOutcome.Dismiss(", view);
        string notifier = File.ReadAllText(Path.Combine(app, "Services", "ScheduledPublishNotifier.cs"));
        Assert.Contains("Group = ScheduledRunAnnouncement.ToastGroup,", notifier);
        Assert.Contains("RemoveByTagAndGroupAsync(tag, ScheduledRunAnnouncement.ToastGroup)", notifier);
        // One registration per process, shared by the app and the poster.
        Assert.Equal(1, System.Text.RegularExpressions.Regex.Matches(notifier, @"AppNotificationManager\.Default\.Register\(\)").Count);
    }

    [Fact]
    public void TheseLinesAreTheContractsWords()
    {
        var cases = ContractLoader.LoadJson("shared-rules.json")["scheduledPublishStopped"]!["notification"]!["announcing"]!["cases"]!
            .AsArray().Select(c => c!["trailSays"]?.ToString()).OfType<string>().ToList();
        Assert.Contains(ScheduledRunAnnouncement.ToldLine, cases);
        Assert.Contains(ScheduledRunAnnouncement.TurnedOffLine, cases);
        Assert.Contains(ScheduledRunAnnouncement.CouldNotBeSentLine, cases);
    }
}
