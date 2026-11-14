using System.Text.Json.Nodes;

namespace Plantoir.Tests;

/// <summary>
/// Builds the scratch courses of <c>contracts/app-rules.json →
/// buildFreshness.reuseTheLastBuild.cases</c> on THIS machine, for
/// <see cref="ReuseTheLastBuildTests"/>: a port of
/// <c>scripts/freshness_cases.py</c>, step for step, following the contract's
/// <c>casesShape</c>. Every step is made on the real clock with a pause
/// between, because a folder's time and a file's creation time cannot be set:
/// only the order things happen in gives them.
///
/// <para><b>Links are JUNCTIONS here</b> (<see cref="ReferenceFixtures.Junction"/>):
/// a symbolic link needs Developer Mode, which this PC and most teachers' do
/// not have, and a junction is what a teacher on Windows can actually make.
/// So the hidden <c>.merged_output</c> link and a linked course folder are
/// both junctions, which is also why the two <c>courseFolderIsALink</c> cases
/// run here when the Python suite has to skip them.</para>
/// </summary>
internal static class FreshnessCases
{
    /// <summary>50 ms: Windows stamps a file from a clock that moves in ticks
    /// of up to 15.6 ms, so this is three ticks (the #768 review's L4, and
    /// freshness_cases.PAUSE_SECONDS on nt).</summary>
    public const int PauseMilliseconds = 50;

    public const string CourseCode = "C";

    /// <summary>The stamp the builder writes for a case's default `stamp: this`.</summary>
    public const string ThisToolchain = "files-this-toolchain";

    public static JsonNode Contract =>
        ContractLoader.LoadJson("app-rules.json")["buildFreshness"]!["reuseTheLastBuild"]!;

    public static JsonObject Case(string name) =>
        Contract["cases"]!.AsArray().Select(c => c!.AsObject()).Single(c => c["name"]!.GetValue<string>() == name);

    public static bool IsAKnownLimitHere(JsonObject @case) =>
        @case["knownLimitOn"] is JsonArray platforms && platforms.Any(p => p!.GetValue<string>() == "windows");

    /// <summary>(expect, because) for a reader, <c>inTheApps</c> taken when it does not read the stamp.</summary>
    public static (string Expect, string? Because) Expected(JsonObject @case, bool readsTheStamp)
    {
        JsonNode source = !readsTheStamp && @case["inTheApps"] is { } apps ? apps : @case;
        return (source["expect"]!.GetValue<string>(), source["because"]?.GetValue<string>());
    }

    public static string PreviewPage()
    {
        var signature = ContractLoader.LoadJson("app-rules.json")["buildFreshness"]!["previewBuild"]!["signature"]!;
        return "<html><body>" + signature["asQuartzWritesIt"]!.GetValue<string>() + "</body></html>\n";
    }

    public sealed record Built(string Course, string Section, string Root);

    private static void Pause() => Thread.Sleep(PauseMilliseconds);

    private static void Write(string path, string text)
    {
        Directory.CreateDirectory(Path.GetDirectoryName(path)!);
        File.WriteAllText(path, text);
    }

    private static string Under(string course, string relative) =>
        relative == "." ? course : Path.Combine(course, relative.Replace('/', '\\'));

    private static IEnumerable<JsonObject> Changes(JsonObject @case, string when) =>
        (@case["changes"] as JsonArray ?? new JsonArray())
            .Select(c => c!.AsObject())
            .Where(c => c["when"]!.GetValue<string>() == when);

    /// <summary>What a `replaceKeepingItsOldTime` left, so the runner can say WHY it builds.</summary>
    public sealed class Notes
    {
        public string? ReplacedFile { get; set; }
    }

    public static void Apply(string course, JsonObject change, Notes? notes = null)
    {
        string what = change["do"]!.GetValue<string>();
        string path = Under(course, change["path"]!.GetValue<string>());
        switch (what)
        {
            case "edit":
                // In place, as an editor that saves over the file does here.
                File.AppendAllText(path, "\nedited\n");
                break;
            case "delete":
                if (Directory.Exists(path)) Directory.Delete(path, recursive: true);
                else File.Delete(path);
                break;
            case "rename":
            {
                string target = Under(course, change["to"]!.GetValue<string>());
                Directory.CreateDirectory(Path.GetDirectoryName(target)!);
                if (Directory.Exists(path)) Directory.Move(path, target);
                else File.Move(path, target);
                break;
            }
            case "replaceKeepingItsOldTime":
            {
                DateTime old = File.GetLastWriteTimeUtc(path);
                string beside = path + ".incoming";
                Write(beside, "a new copy\n");
                File.SetLastWriteTimeUtc(beside, old);
                File.Move(beside, path, overwrite: true);
                if (notes is not null) notes.ReplacedFile = path;
                break;
            }
            case "overwriteKeepingItsOldTime":
            {
                DateTime old = File.GetLastWriteTimeUtc(path);
                File.WriteAllText(path, "written over where it stands\n");
                File.SetLastWriteTimeUtc(path, old);
                break;
            }
            case "pointTheLinkAtAnOlderCopy":
            {
                // The course folder is a junction; point it at the copy made
                // before the build: a new junction under a temporary name,
                // the old one removed (the LINK only), the new one renamed
                // into its place. ln -sfn renames over in one step; Windows
                // cannot rename onto an existing folder, so this is two.
                string kept = new DirectoryInfo(course).ResolveLinkTarget(returnFinalTarget: true)!.FullName;
                string older = Path.Combine(Path.GetDirectoryName(kept)!, "older-" + Path.GetFileName(kept));
                string relinking = course + ".relinking";
                ReferenceFixtures.Junction(relinking, older);
                Directory.Delete(course);   // a junction: removes the link, never what it leads to
                if (!Directory.Exists(kept)) throw new InvalidOperationException("removing the junction removed the course it led to");
                Directory.Move(relinking, course);
                break;
            }
            case "createKeepingAnOldTime":
            {
                Write(path, "restored from a backup\n");
                DateTime aYearAgo = DateTime.UtcNow.AddDays(-365);
                File.SetLastWriteTimeUtc(path, aYearAgo);
                File.SetLastAccessTimeUtc(path, aYearAgo);
                break;
            }
            default:
                throw new InvalidOperationException("no such change in the contract: " + what);
        }
    }

    /// <summary>Makes the case under <paramref name="root"/>, in the contract's order.</summary>
    public static Built Build(string root, JsonObject @case, Notes? notes = null)
    {
        string workingFolder = Path.Combine(root, "work");
        if (@case["workingFolderUnderAHiddenFolder"]?.GetValue<bool>() == true)
            workingFolder = Path.Combine(root, ".kept-out-of-sight", "work");
        string course = Path.Combine(workingFolder, "courses", CourseCode);
        bool linked = @case["courseFolderIsALink"]?.GetValue<bool>() == true;
        string older = Path.Combine(root, "kept-elsewhere", "older-" + CourseCode);
        if (linked)
        {
            string kept = Path.Combine(root, "kept-elsewhere", CourseCode);
            Directory.CreateDirectory(kept);
            Directory.CreateDirectory(Path.GetDirectoryName(course)!);
            ReferenceFixtures.Junction(course, kept);
            Directory.CreateDirectory(older);
        }
        else
        {
            Directory.CreateDirectory(course);
        }

        // The built sites live outside the course, behind a hidden link, as
        // the launchers keep them (shared-rules.json -> buildOutputLocation).
        string builds = Path.Combine(root, "builds", CourseCode);
        Directory.CreateDirectory(builds);
        ReferenceFixtures.Junction(Path.Combine(course, ".merged_output"), builds);
        string section = Path.Combine(builds, "section1");

        var files = (@case["course"] as JsonArray ?? Contract["theCourse"]!.AsArray())
            .Select(f => f!.GetValue<string>()).ToList();
        foreach (string relative in files) Write(Under(course, relative), relative + "\n");
        if (linked)
        {
            foreach (string relative in files) Write(Under(older, relative), relative + ", an older copy\n");
            ReferenceFixtures.Junction(Path.Combine(older, ".merged_output"), builds);
        }
        Pause();
        foreach (var change in Changes(@case, "beforeTheBuildStarted")) Apply(course, change, notes);
        Pause();

        if ((@case["site"]?.GetValue<string>() ?? "built") == "notBuilt") return new Built(course, section, root);

        string publicDir = Path.Combine(section, "public");
        Directory.CreateDirectory(publicDir);
        string frontPage = Path.Combine(publicDir, "index.html");
        string marker = Path.Combine(section, ".build-started");
        string order = @case["startedMarker"]?.GetValue<string>() ?? "beforeTheSite";
        string page = @case["previewClient"]?.GetValue<bool>() == true ? PreviewPage() : "<html><body>Welcome</body></html>\n";

        if (order == "beforeTheSite")
        {
            var atTheStart = Changes(@case, "atTheBuildStart").ToList();
            foreach (var change in atTheStart) Apply(course, change, notes);
            Write(marker, "This build started when this file was made.\n");
            foreach (var change in atTheStart)
                File.SetLastWriteTimeUtc(marker, File.GetLastWriteTimeUtc(Under(course, change["path"]!.GetValue<string>())));
            Pause();
            foreach (var change in Changes(@case, "whileItBuilt")) Apply(course, change, notes);
            Pause();
            Write(frontPage, page);
        }
        else if (order == "afterTheSite")
        {
            Write(frontPage, page);
            Pause();
            foreach (var change in Changes(@case, "whileItBuilt")) Apply(course, change, notes);
            Pause();
            Write(marker, "This build started when this file was made.\n");
        }
        else
        {
            foreach (var change in Changes(@case, "whileItBuilt")) Apply(course, change, notes);
            Pause();
            Write(frontPage, page);
        }

        string stamp = @case["stamp"]?.GetValue<string>() ?? "this";
        if (stamp == "this") Write(Path.Combine(section, ".built-with-toolchain"), ThisToolchain + "\n");
        else if (stamp == "another") Write(Path.Combine(section, ".built-with-toolchain"), "files-another-toolchain\n");

        if (@case["datedLaterThanNow"]?.GetValue<bool>() == true)
        {
            foreach (string dated in new[] { marker, frontPage })
                if (File.Exists(dated)) File.SetLastWriteTimeUtc(dated, File.GetLastWriteTimeUtc(dated).AddHours(1));
        }
        Pause();
        foreach (var change in Changes(@case, "afterTheBuild")) Apply(course, change, notes);
        return new Built(course, section, root);
    }

    /// <summary>The time a course is compared with: the earlier of the marker and the front page.</summary>
    public static DateTime Reference(string section)
    {
        DateTime front = File.GetLastWriteTimeUtc(Path.Combine(section, "public", "index.html"));
        string marker = Path.Combine(section, ".build-started");
        if (!File.Exists(marker)) return front;
        DateTime started = File.GetLastWriteTimeUtc(marker);
        return started < front ? started : front;
    }
}
