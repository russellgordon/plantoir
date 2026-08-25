using System.Text;
using Newtonsoft.Json;
using Newtonsoft.Json.Linq;

namespace Plantoir.Core.Models;

/// <summary>
/// The in-memory copy of one course's course_config.json.
///
/// Deliberately NOT a typed model: the decoded JSON lives in a mutable
/// JObject and edits happen key by key, so keys written by a newer
/// toolchain version survive a settings round trip untouched. The CLI
/// scripts own the format; this class is a careful guest in their file.
///
/// Written form matches what the toolchain leaves on disk: 2-space indent,
/// keys sorted ascending (ordinal), raw non-ASCII (emoji stay emoji),
/// LF newlines, one trailing newline.
/// </summary>
public sealed class CourseConfiguration
{
    private JObject _values;
    private byte[] _lastSavedData;

    private CourseConfiguration(JObject values, byte[] lastSavedData)
    {
        _values = values;
        _lastSavedData = lastSavedData;
    }

    public static CourseConfiguration Load(string path) => FromBytes(File.ReadAllBytes(path));

    public static CourseConfiguration FromBytes(byte[] data)
    {
        var token = JToken.Parse(Encoding.UTF8.GetString(data));
        if (token is not JObject obj)
            throw new InvalidDataException("course_config.json does not hold a JSON object.");
        return new CourseConfiguration(obj, data);
    }

    public static CourseConfiguration FromDictionary(JObject values)
    {
        var config = new CourseConfiguration(values, Array.Empty<byte>());
        config._lastSavedData = config.SerializedBytes();
        return config;
    }

    // ---- Round-trip contract -------------------------------------------

    public byte[] SerializedBytes()
    {
        var text = new StringWriter { NewLine = "\n" };
        using (var writer = new JsonTextWriter(text)
        {
            Formatting = Formatting.Indented,
            Indentation = 2,
            IndentChar = ' ',
        })
        {
            SortedCopy(_values).WriteTo(writer);
        }
        return Encoding.UTF8.GetBytes(text.ToString() + "\n");
    }

    private static JToken SortedCopy(JToken node) => node switch
    {
        JObject obj => new JObject(obj.Properties()
            .OrderBy(p => p.Name, StringComparer.Ordinal)
            .Select(p => new JProperty(p.Name, SortedCopy(p.Value)))),
        JArray array => new JArray(array.Select(SortedCopy)),
        _ => node.DeepClone(),
    };

    public void Write(string path)
    {
        byte[] data = SerializedBytes();
        string temp = path + ".tmp";
        File.WriteAllBytes(temp, data);
        File.Move(temp, path, overwrite: true);
        _lastSavedData = data;
    }

    /// <summary>The Revert button: put the values back the way the last save left them.</summary>
    public void DiscardChanges()
    {
        if (_lastSavedData.Length == 0) return;
        if (JToken.Parse(Encoding.UTF8.GetString(_lastSavedData)) is JObject obj) _values = obj;
    }

    public bool HasUnsavedChanges
    {
        get
        {
            if (_lastSavedData.Length == 0) return true;
            try
            {
                var saved = JToken.Parse(Encoding.UTF8.GetString(_lastSavedData));
                return !JToken.DeepEquals(SortedCopy(_values), SortedCopy(saved));
            }
            catch { return true; }
        }
    }

    public JObject Values => _values;

    // ---- Flat keys ------------------------------------------------------

    public string CourseCode => StringValue("course_code");

    public void SetCourseCode(string code) => _values["course_code"] = code;

    public string CourseName
    {
        get => StringValue("course_name");
        set => _values["course_name"] = value;
    }

    public string CustomShortName
    {
        get => StringValue("custom_short_name");
        set => _values["custom_short_name"] = value;
    }

    /// <summary>
    /// Where publishes go: "netlify" (the default) or "local_folder" — a
    /// folder on this computer, for teachers who upload to their own web
    /// host themselves (e.g. over SFTP). Course-level: every section of the
    /// course publishes the same way.
    /// </summary>
    public string DeployTarget
    {
        get { var raw = StringValue("deploy_target"); return raw.Length == 0 ? "netlify" : raw; }
        set
        {
            _values["deploy_target"] = value;
            // A destination can never be both primary and additional at
            // once — deploying to the same place twice makes no sense.
            AdditionalDeployTargets = PruningAdditionalTargets(AdditionalDeployTargets, value);
        }
    }

    /// <summary>
    /// One additional (non-primary) destination this course also publishes
    /// to, for redundancy — <see cref="DeployTarget"/> remains the primary.
    /// <c>Type</c> uses the same spellings as <see cref="DeployTarget"/>;
    /// <c>Path</c> is only meaningful when <c>Type</c> is "local_folder".
    /// </summary>
    public readonly record struct AdditionalDeployTarget(string Type, string Path);

    /// <summary>One place this course publishes to — either the primary or one of <see cref="AdditionalDeployTargets"/>.</summary>
    public readonly record struct DeployDestination(string Type, string Path);

    /// <summary>
    /// The three destinations Plantoir knows how to publish to, in the order
    /// they are offered — shared by the primary picker and the
    /// additional-targets list, so "one of each type" has a single place
    /// that defines what a "type" even is. Mirrors the mac's
    /// `CourseConfiguration.knownDeployTargetTypes`.
    /// </summary>
    public static readonly IReadOnlyList<string> KnownDeployTargetTypes =
        new[] { "netlify", "cloudflare_pages", "local_folder" };

    /// <summary>
    /// Removes <paramref name="type"/> from <paramref name="targets"/> if
    /// present — the one place that knows how to keep a primary choice and
    /// an additional-targets list from ever agreeing on the same
    /// destination twice. A plain function rather than an instance method,
    /// so it is usable both by this class's own <see cref="DeployTarget"/>
    /// setter and by a wizard's plain in-memory list, which has no
    /// <see cref="CourseConfiguration"/> to route through until the course
    /// is actually created.
    /// </summary>
    public static List<AdditionalDeployTarget> PruningAdditionalTargets(
        IReadOnlyList<AdditionalDeployTarget> targets, string type) =>
        targets.Where(t => t.Type != type).ToList();

    /// <summary>Types available to add as an ADDITIONAL target for a given primary — every known type except that one.</summary>
    public static List<string> AvailableAdditionalDeployTargetTypes(string primaryType) =>
        KnownDeployTargetTypes.Where(t => t != primaryType).ToList();

    /// <summary>Whether <paramref name="type"/> is present in <paramref name="targets"/>.</summary>
    public static bool HasAdditionalDeployTarget(IReadOnlyList<AdditionalDeployTarget> targets, string type) =>
        targets.Any(t => t.Type == type);

    /// <summary>The stored path for an additional local-folder target, or "" when that type is not configured.</summary>
    public static string AdditionalDeployTargetPath(IReadOnlyList<AdditionalDeployTarget> targets, string type)
    {
        foreach (var target in targets)
            if (target.Type == type) return target.Path;
        return "";
    }

    /// <summary>
    /// Turns an additional target on or off. Turning one off drops it
    /// entirely, including any path it carried — re-enabling it later starts
    /// from a blank path rather than resurrecting the old one, so a stale
    /// folder from months ago can never come back silently.
    /// </summary>
    public static List<AdditionalDeployTarget> SettingAdditionalDeployTarget(
        IReadOnlyList<AdditionalDeployTarget> targets, bool enabled, string type)
    {
        var result = targets.Where(t => t.Type != type).ToList();
        if (enabled) result.Add(new AdditionalDeployTarget(type, ""));
        return result;
    }

    /// <summary>Updates the folder path for an additional local-folder target. A no-op if that type is not currently enabled.</summary>
    public static List<AdditionalDeployTarget> SettingAdditionalDeployTargetPath(
        IReadOnlyList<AdditionalDeployTarget> targets, string path, string type) =>
        targets.Select(t => t.Type == type ? t with { Path = path } : t).ToList();

    /// <summary>
    /// Extra places this course ALSO publishes to, beyond <see cref="DeployTarget"/> —
    /// for redundancy against one host having a bad day, never a replacement
    /// for the primary choice: <see cref="DeployTarget"/> still decides where
    /// the "Live URL" link on a finished deploy points.
    ///
    /// Empty for every course that has not opted in, which is the
    /// overwhelming majority: the key is OMITTED from course_config.json
    /// entirely rather than written as [], so a course nobody has touched
    /// writes the exact same file this app has always written. At most one
    /// entry per known type, and never a type that already IS the primary.
    /// </summary>
    public List<AdditionalDeployTarget> AdditionalDeployTargets
    {
        get
        {
            var result = new List<AdditionalDeployTarget>();
            if (_values["additional_deploy_targets"] is not JArray array) return result;
            foreach (var entry in array)
            {
                if (entry is not JObject obj) continue;
                if (obj["type"] is not JValue { Type: JTokenType.String } typeValue) continue;
                string type = (string)typeValue!;
                if (type.Length == 0) continue;
                string path = obj["path"] is JValue { Type: JTokenType.String } pathValue ? (string)pathValue! : "";
                result.Add(new AdditionalDeployTarget(type, path));
            }
            return result;
        }
        set
        {
            if (value.Count == 0)
            {
                _values.Remove("additional_deploy_targets");
                return;
            }
            var encoded = new JArray();
            foreach (var target in value)
            {
                var entry = new JObject { ["type"] = target.Type };
                if (target.Path.Length > 0) entry["path"] = target.Path;
                encoded.Add(entry);
            }
            _values["additional_deploy_targets"] = encoded;
        }
    }

    /// <summary>
    /// Every destination this course publishes to, in deploy order — the
    /// primary first, then each additional target in the order it was
    /// added. This is the one list a multi-destination deploy walks; the
    /// primary is not special beyond going first, which is only how the
    /// "Live URL" link on a finished deploy is chosen.
    /// </summary>
    public List<DeployDestination> AllDeployDestinations
    {
        get
        {
            var result = new List<DeployDestination> { new(DeployTarget, DeployFolderPath) };
            foreach (var target in AdditionalDeployTargets)
                result.Add(new DeployDestination(target.Type, target.Path));
            return result;
        }
    }

    /// <summary>
    /// The folder local-folder publishes land in; each section gets its own
    /// sectionN subfolder inside it.
    /// </summary>
    public string DeployFolderPath
    {
        get => StringValue("deploy_folder_path");
        set => _values["deploy_folder_path"] = value;
    }

    /// <summary>True when this course publishes to a folder rather than Netlify.</summary>
    public bool DeploysToLocalFolder =>
        DeployTarget == "local_folder" && DeployFolderPath.Trim().Length > 0;

    /// <summary>True when this course publishes to Cloudflare Pages.</summary>
    public bool DeploysToCloudflare => DeployTarget == "cloudflare_pages";

    /// <summary>
    /// What is wrong with a Cloudflare account ID, or null when it looks
    /// usable. A token scoped to Pages cannot list its own account — verified
    /// against a real token — so the teacher supplies it once here, and the
    /// app checks the shape before a publish can fail on it.
    /// </summary>
    public static string? CloudflareAccountProblem(string rawId)
    {
        string id = rawId.Trim();
        if (id.Length == 0) return "Paste your Cloudflare Account ID.";
        if (id.Length != 32 || !id.All(Uri.IsHexDigit))
            return "That doesn’t look like an Account ID — it’s 32 letters and digits.";
        return null;
    }

    /// <summary>
    /// What is wrong with a folder chosen for local-folder publishing, or
    /// null when the folder is usable. Both the settings form and the wizard
    /// check this live — and block saving — so a publish never discovers the
    /// problem after the fact.
    /// </summary>
    public static string? DeployFolderProblem(string rawPath)
    {
        string path = rawPath.Trim();
        if (path.Length == 0) return "Choose the folder this course deploys into.";
        if (File.Exists(path)) return "That’s a file — deploying needs a folder.";
        if (!Directory.Exists(path)) return "That folder doesn’t exist — use Choose… to pick or create one.";
        try
        {
            string probe = Path.Combine(path, ".plantoir-write-probe-" + Guid.NewGuid().ToString("N"));
            File.WriteAllText(probe, "");
            File.Delete(probe);
        }
        catch
        {
            return "That folder can’t be written to — choose a different one.";
        }
        return null;
    }

    public string Locale
    {
        get { var raw = StringValue("locale"); return raw.Length == 0 ? "en-US" : raw; }
        set => _values["locale"] = value;
    }

    public bool ExpandOnFolderClick
    {
        get => BoolValue("expandOnFolderClick", false);
        set => _values["expandOnFolderClick"] = value;
    }

    public bool ShowReadingTime
    {
        get => BoolValue("show_reading_time", false);
        set => _values["show_reading_time"] = value;
    }

    public string FooterHtml
    {
        get => StringValue("footer_html");
        set => _values["footer_html"] = value;
    }

    public List<string> SharedFolders { get => StringList("shared_folders"); set => SetStringList("shared_folders", value); }
    public List<string> SharedFiles { get => StringList("shared_files"); set => SetStringList("shared_files", value); }
    public List<string> PerSectionFolders { get => StringList("per_section_folders"); set => SetStringList("per_section_folders", value); }
    public List<string> PerSectionFiles { get => StringList("per_section_files"); set => SetStringList("per_section_files", value); }
    public List<string> HiddenItems { get => StringList("hidden"); set => SetStringList("hidden", value); }
    public List<string> ExpandableItems { get => StringList("expandable"); set => SetStringList("expandable", value); }

    // ---- Marks and the curriculum folder --------------------------------

    /// <summary>
    /// What this course calls the folder holding one page per curriculum
    /// expectation. Declared by every payload and skeleton manifest and
    /// carried here at creation; empty for a course made from scratch, which
    /// has no manifest to declare anything.
    /// </summary>
    public string CurriculumFolder
    {
        get => StringValue("curriculum_folder");
        set => _values["curriculum_folder"] = value;
    }

    /// <summary>
    /// The folder this app protects as the curriculum folder, or null.
    /// Name-only — see <see cref="CurriculumFolderRule"/>.
    /// </summary>
    public string? ResolvedCurriculumFolder =>
        CurriculumFolderRule.Resolve(CurriculumFolder, SharedFolders);

    /// <summary>
    /// The folders whose contents count for marks, or <b>null</b> when the key
    /// is ABSENT — a course that has never been asked, to which the historical
    /// substring rule still applies.
    ///
    /// <para>An explicit JSON <c>null</c> reads as a CLEARED list rather than
    /// an unset one: the key is present, and the absent case is reserved for a
    /// course nobody has asked. Pinned by <c>gradedFolders</c>'s case "an
    /// explicit null is a CLEARED list, not an unset one", which exists
    /// because the two implementations once agreed by accident and nothing
    /// said which answer was intended.</para>
    /// </summary>
    public List<string>? GradedFolders
    {
        get
        {
            var token = _values["graded_folders"];
            if (token is null) return null;
            var result = new List<string>();
            if (token is JArray array)
                foreach (var element in array)
                    if (element is JValue { Type: JTokenType.String } v) result.Add((string)v!);
            return result;
        }
        set
        {
            if (value is null) _values.Remove("graded_folders");
            else _values["graded_folders"] = new JArray(value);
        }
    }

    /// <summary>
    /// The marks pool as a list that can be edited — materialising the pool a
    /// never-asked course is ALREADY working to, rather than starting from
    /// empty.
    ///
    /// <para>Without this, a teacher's first tick on a legacy course would
    /// silently narrow it from "every folder mentioning tasks" to the one box
    /// they touched, taking the assessed marks off every other one. Called on
    /// the way in to any edit of the pool — a tick, an untick, or a folder
    /// leaving the list.</para>
    /// </summary>
    public List<string> MaterializedGradedFolders() =>
        GradedFolders ?? GradedFolderRule.InferredPool(
            SharedFolders.Concat(PerSectionFolders));

    /// <summary>Whether a page counts for marks in this course.</summary>
    public bool CountsForMarks(string relativePath) =>
        GradedFolderRule.CountsForMarks(GradedFolders, relativePath);

    // ---- Excluded items -------------------------------------------------

    /// <summary>The scope keys inside <c>excluded_items</c>.</summary>
    public const string SharedScope = "shared";
    public const string PerSectionScope = "per_section";

    /// <summary>
    /// How a scope is written on the activity trail. NOT the JSON key: the
    /// contract asks for "per-section" in a teacher-readable line and
    /// <c>per_section</c> in the file, and writing the file's spelling into a
    /// sentence is how machinery leaks in front of a teacher.
    /// </summary>
    public static string ScopeInWords(string scope) =>
        scope == PerSectionScope ? "per-section" : "shared";

    /// <summary>
    /// Names this course has excluded from previews and deploys, by scope.
    ///
    /// <para>An OBJECT keyed by scope rather than a flat list, because the two
    /// scopes are matched by different scans in the build and the same bare
    /// name can legitimately exist in both. The key is ABSENT — never
    /// <c>{}</c> — when nothing is excluded, so a course nobody has touched
    /// writes the same file it always has.</para>
    ///
    /// <para>Matching is EXACT, case included, because
    /// <c>preflight_update_course_config</c> tests membership of a plain
    /// Python set. A case-insensitive answer here would have the app believe a
    /// folder is excluded while the build cheerfully publishes it — the two
    /// must agree or the feature reports a state that is not real.</para>
    /// </summary>
    public List<string> ExcludedItems(string scope)
    {
        var result = new List<string>();
        if (_values["excluded_items"] is JObject map && map[scope] is JArray array)
            foreach (var element in array)
                if (element is JValue { Type: JTokenType.String } v) result.Add((string)v!);
        return result;
    }

    public bool IsExcluded(string scope, string name) =>
        ExcludedItems(scope).Contains(name, StringComparer.Ordinal);

    /// <summary>
    /// Record that a name is excluded. Idempotent.
    ///
    /// <para>The CALLER must also take the name out of its copy list
    /// (<c>shared_folders</c> and friends). Absence from the copy list is the
    /// actual mechanism of exclusion; this key is what stops preflight putting
    /// it back. Preflight does reconcile the two, but only at the next build —
    /// a teacher reading the list in Settings before then would see a folder
    /// they had just removed.</para>
    /// </summary>
    public void Exclude(string scope, string name)
    {
        if (string.IsNullOrEmpty(name)) return;
        var items = ExcludedItems(scope);
        if (items.Contains(name, StringComparer.Ordinal)) return;
        items.Add(name);
        SetExcludedItems(scope, items);
    }

    /// <summary>
    /// Stop excluding a name, and say whether it HAD been excluded.
    ///
    /// <para>The answer is the point. An ordinary new folder is not a
    /// re-inclusion, and a trail line saying it was would be believed — the
    /// caller records "item re-included" only on a true here.</para>
    /// </summary>
    public bool ReInclude(string scope, string name)
    {
        if (string.IsNullOrEmpty(name)) return false;
        var items = ExcludedItems(scope);
        int removed = items.RemoveAll(i => string.Equals(i, name, StringComparison.Ordinal));
        if (removed == 0) return false;
        SetExcludedItems(scope, items);
        return true;
    }

    /// <summary>
    /// Writes one scope's list, dropping the scope when it empties and the
    /// whole key when every scope has. Absent, not empty — see the property
    /// above and <c>contracts/file-formats.json</c>.
    ///
    /// <para>Scopes this app does not know about are PRESERVED: handoff item
    /// 11 promises the object is additive, so a future
    /// <c>"sections": {"4": [...]}</c> has to survive a teacher removing a
    /// folder in a build that has never heard of it. An <c>excluded_items</c>
    /// that is not an object AT ALL is replaced rather than read around —
    /// there is nothing here that could preserve it meaningfully, and this
    /// class is a careful guest in the toolchain's file rather than a
    /// validator of it.</para>
    /// </summary>
    private void SetExcludedItems(string scope, IReadOnlyList<string> items)
    {
        if (_values["excluded_items"] is not JObject map) { map = new JObject(); }

        if (items.Count == 0) map.Remove(scope);
        else map[scope] = new JArray(items);

        if (map.Count == 0) _values.Remove("excluded_items");
        else _values["excluded_items"] = map;
    }

    /// <summary>sharedFolders + sharedFiles + perSectionFolders + perSectionFiles, in that order.</summary>
    public List<string> AllSidebarItems =>
        SharedFolders.Concat(SharedFiles).Concat(PerSectionFolders).Concat(PerSectionFiles).ToList();

    /// <summary>
    /// Whether this course's code names a club rather than a course —
    /// delegates to ClubCodeRule, the shared rule both apps ask
    /// (contracts/course-management.json -> courseCode.clubDetection): the
    /// catalog is asked first and its answer is final, and only a code the
    /// catalog has never heard of falls back to the fourth-character guess.
    /// </summary>
    public bool IsClub(Plantoir.Core.Catalogs.CourseNameCatalog catalog) =>
        ClubCodeRule.IsClub(CourseCode, catalog);

    // ---- Section numbers (matching the mac app's three tiers) -----------

    public List<int> SectionNumbers
    {
        get
        {
            if (_values["section_numbers"] is JArray array)
            {
                // An empty stored list IS the answer (a course whose every
                // section was archived); only an unreadable list falls through.
                var parsed = array
                    .Where(t => t.Type is JTokenType.Integer or JTokenType.Float)
                    .Select(t => (int)t)
                    .OrderBy(n => n)
                    .ToList();
                if (array.Count == 0 || parsed.Count > 0) return parsed;
            }
            int count = IntValue("num_sections", 1);
            return Enumerable.Range(1, Math.Max(count, 1)).ToList();
        }
    }

    /// <summary>Writes BOTH section_numbers and num_sections = count.</summary>
    public void SetSectionNumbers(IReadOnlyList<int> numbers)
    {
        var sorted = numbers.OrderBy(n => n).ToList();
        _values["section_numbers"] = new JArray(sorted);
        _values["num_sections"] = sorted.Count;
    }

    // ---- Per-section nested maps ({key: {"sections": {"sectionN": v}}}) --

    public string Emoji(int section)
    {
        string raw = NestedString("emojis", "sections", SectionKey(section));
        return raw.Length == 0 ? "📚" : raw;
    }

    public void SetEmoji(int section, string emoji) =>
        SetNestedValue("emojis", "sections", SectionKey(section), emoji);

    /// <summary>
    /// The teacher's own domain for ONE DESTINATION of a section's published
    /// site. Keyed by destination TYPE, not just by section, because a course
    /// publishing to more than one destination for redundancy may want a
    /// domain on one and not another — mirrors
    /// `CourseConfiguration.customDomain(forSection:destinationType:)` on the
    /// mac side; see WINDOWS-HANDOFF.md entry 307.
    ///
    /// Reads an OLDER shape too: `custom_domains.sections.sectionN` used to
    /// be a bare string, written before a course could have more than one
    /// destination. That value is treated as belonging to the section's
    /// PRIMARY destination (<see cref="DeployTarget"/>) — the only
    /// destination that existed when it could have been set — and is
    /// invisible to every other destination type.
    /// </summary>
    public string CustomDomain(int section, string destinationType)
    {
        if (_values["custom_domains"] is not JObject outer) return "";
        if (outer["sections"] is not JObject sections) return "";
        var entry = sections[SectionKey(section)];
        if (entry is JObject perDestination)
            return perDestination[destinationType] is JValue { Type: JTokenType.String } v ? (string)v! : "";
        // Old shape: a bare string, meant for whichever destination was
        // primary when it was set — never for any other type.
        if (entry is JValue { Type: JTokenType.String } legacy && destinationType == DeployTarget)
            return (string)legacy!;
        return "";
    }

    /// <summary>Convenience for the primary destination — what a course with a single destination always means.</summary>
    public string CustomDomain(int section) => CustomDomain(section, DeployTarget);

    /// <summary>
    /// Writes ONE destination's domain, never clobbering another
    /// destination's entry. A stray old-shape bare string already on disk
    /// (set before this course had more than one destination) is carried
    /// forward into the new per-destination map, attributed to the PRIMARY
    /// destination, rather than silently discarded the first time any
    /// destination's domain is set here — see WINDOWS-HANDOFF.md entry 307,
    /// which found the mac side losing exactly this data before the map
    /// shape existed. Setting an empty domain removes that destination's own
    /// entry rather than storing an empty string.
    /// </summary>
    public void SetCustomDomain(int section, string destinationType, string domain)
    {
        if (_values["custom_domains"] is not JObject outer) { outer = new JObject(); _values["custom_domains"] = outer; }
        if (outer["sections"] is not JObject sections) { sections = new JObject(); outer["sections"] = sections; }
        string sectionKey = SectionKey(section);

        JObject perDestination;
        if (sections[sectionKey] is JObject existing)
        {
            perDestination = existing;
        }
        else
        {
            perDestination = new JObject();
            if (sections[sectionKey] is JValue { Type: JTokenType.String } legacy && ((string)legacy!).Length > 0)
                perDestination[DeployTarget] = (string)legacy!;
            sections[sectionKey] = perDestination;
        }

        string normalized = NormalizedCustomDomain(domain);
        if (normalized.Length == 0) perDestination.Remove(destinationType);
        else perDestination[destinationType] = normalized;
    }

    /// <summary>Convenience for the primary destination — what a course with a single destination always means.</summary>
    public void SetCustomDomain(int section, string domain) => SetCustomDomain(section, DeployTarget, domain);

    public bool ShowsSectionMarker(int section) =>
        NestedBool("show_section_marker", "sections", SectionKey(section), true);

    public void SetShowsSectionMarker(int section, bool value) =>
        SetNestedValue("show_section_marker", "sections", SectionKey(section), value);

    /// <summary>
    /// Legacy rule: a plain course-wide Bool wins for every section until the
    /// first per-section write replaces it with a map.
    /// </summary>
    public bool ShowsGradeInTitle(int section)
    {
        if (_values["show_grade_in_title"] is JValue { Type: JTokenType.Boolean } legacy)
            return (bool)legacy;
        return NestedBool("show_grade_in_title", "sections", SectionKey(section), true);
    }

    public void SetShowsGradeInTitle(int section, bool value)
    {
        if (_values["show_grade_in_title"] is JValue { Type: JTokenType.Boolean })
            _values["show_grade_in_title"] = new JObject();
        SetNestedValue("show_grade_in_title", "sections", SectionKey(section), value);
    }

    public bool IncludesCurriculumCoverage(int section)
    {
        if (_values["include_curriculum_coverage"] is JValue { Type: JTokenType.Boolean } legacy)
            return (bool)legacy;
        return NestedBool("include_curriculum_coverage", "sections", SectionKey(section), true);
    }

    public void SetIncludesCurriculumCoverage(int section, bool value)
    {
        if (_values["include_curriculum_coverage"] is JValue { Type: JTokenType.Boolean })
            _values["include_curriculum_coverage"] = new JObject();
        SetNestedValue("include_curriculum_coverage", "sections", SectionKey(section), value);
        if (!value)
        {
            SetIncludesCoverageNotes(section, false);
        }
    }

    public bool IncludesCoverageNotes(int section)
    {
        if (!IncludesCurriculumCoverage(section)) return false;
        if (_values["include_coverage_notes"] is JValue { Type: JTokenType.Boolean } legacy)
            return (bool)legacy;
        return NestedBool("include_coverage_notes", "sections", SectionKey(section), true);
    }

    public void SetIncludesCoverageNotes(int section, bool value)
    {
        if (_values["include_coverage_notes"] is JValue { Type: JTokenType.Boolean })
            _values["include_coverage_notes"] = new JObject();
        SetNestedValue("include_coverage_notes", "sections", SectionKey(section), value);
    }

    public bool OverallIncludesCurriculumCoverage =>
        SectionNumbers.All(IncludesCurriculumCoverage);

    public bool OverallIncludesCoverageNotes =>
        SectionNumbers.All(IncludesCoverageNotes);

    public static bool CoverageNotesEnabled(bool coverageEnabled, bool notesEnabled) =>
        coverageEnabled && notesEnabled;

    /// <summary>
    /// The EFFECTIVE value of "include the curriculum coverage map" for a
    /// course being created, given the wizard's switch.
    ///
    /// <para>Deliberately not gated on pre-populating: a course created
    /// WITHOUT example content still gets the map, and the wizard writes
    /// exactly this into `include_curriculum_coverage`. It looks trivial, and
    /// that is the point — the wizard's protection rules and its config writer
    /// ask the same function, so they cannot drift into disagreeing about what
    /// is switched on. A rule that blocks a removal on a value the file will
    /// not carry is the deadlock this exists to prevent.</para>
    /// </summary>
    public static bool CurriculumCoverageEnabled(bool coverageSwitchIsOn) => coverageSwitchIsOn;

    /// <summary>
    /// The EFFECTIVE value of "include curriculum pages", which unlike the
    /// coverage map IS gated on there being example content to take them from
    /// and on the teacher pre-populating with it. Mirrors what
    /// `NewCourseDialog.BuildConfiguration` writes for
    /// `include_curriculum_pages`.
    /// </summary>
    public static bool CurriculumPagesEnabled(bool hasExampleContent, bool prepopulating,
                                              bool contentIncludesCurriculum, bool curriculumSwitchIsOn) =>
        hasExampleContent && prepopulating && contentIncludesCurriculum && curriculumSwitchIsOn;

    /// <summary>color_schemes is FLAT — {"color_schemes": {"sectionN": "id"}}, no "sections" wrapper.</summary>
    public string ColourSchemeId(int section) =>
        _values["color_schemes"] is JObject map && map[SectionKey(section)] is JValue { Type: JTokenType.String } v
            ? (string)v! : "";

    public void SetColourSchemeId(int section, string id)
    {
        if (_values["color_schemes"] is not JObject map)
        {
            map = new JObject();
            _values["color_schemes"] = map;
        }
        map[SectionKey(section)] = id;
    }

    /// <summary>fonts.sections.sectionN → fonts.default → system default.</summary>
    public FontChoice Font(int section)
    {
        if (_values["fonts"] is JObject fonts)
        {
            if (fonts["sections"] is JObject sections && sections[SectionKey(section)] is JObject perSection)
                return FontChoice.FromJson(perSection);
            if (fonts["default"] is JObject fallback)
                return FontChoice.FromJson(fallback);
        }
        return FontChoice.SystemDefault;
    }

    public void SetFont(int section, FontChoice choice)
    {
        if (_values["fonts"] is not JObject fonts) { fonts = new JObject(); _values["fonts"] = fonts; }
        if (fonts["sections"] is not JObject sections) { sections = new JObject(); fonts["sections"] = sections; }
        sections[SectionKey(section)] = choice.ToJson();
    }

    // ---- Rules ----------------------------------------------------------

    /// <summary>Trim → strip a leading https:// then http:// → cut at the first slash.</summary>
    public static string NormalizedCustomDomain(string raw)
    {
        string s = raw.Trim();
        if (s.StartsWith("https://", StringComparison.Ordinal)) s = s["https://".Length..];
        else if (s.StartsWith("http://", StringComparison.Ordinal)) s = s["http://".Length..];
        int slash = s.IndexOf('/');
        if (slash >= 0) s = s[..slash];
        return s;
    }

    /// <summary>
    /// The quiet orange warning: the switch stays literal, but when it is on
    /// and the course name already carries its grade label, say so.
    /// </summary>
    public static string? GradeInTitleWarning(string courseName, string courseCode, bool showsGrade)
    {
        if (!showsGrade) return null;
        string label = SectionAdder.GradeLabel(courseCode);
        if (label.Length == 0 || !courseName.Contains(label, StringComparison.Ordinal)) return null;
        return $"The course name already includes “{label}”, so the site title would repeat it. Edit the name, or turn this off.";
    }

    /// <summary>
    /// The site title as build_site.py's computed_landing_title will compute
    /// it at build time — [Grade X ]Name[, Section N], deliberately literal:
    /// the grade switch alone decides the prefix, the marker switch alone
    /// decides the suffix, and an empty name falls back to the code.
    /// </summary>
    public static string ComputedSiteTitle(string courseName, string courseCode, int sectionNumber,
                                           bool showsGrade, bool showsMarker)
    {
        string code = courseCode.Trim().ToUpperInvariant();
        string name = courseName.Trim();
        if (name.Length == 0) name = code;
        string label = SectionAdder.GradeLabel(code);
        string prefix = showsGrade && label.Length > 0 ? label + " " : "";
        string suffix = showsMarker ? $", Section {sectionNumber}" : "";
        return prefix + name + suffix;
    }

    // ---- Helpers --------------------------------------------------------

    internal static string SectionKey(int section) => "section" + section;

    private string StringValue(string key) =>
        _values[key] is JValue { Type: JTokenType.String } v ? (string)v! : "";

    private bool BoolValue(string key, bool fallback) =>
        _values[key] is JValue { Type: JTokenType.Boolean } v ? (bool)v : fallback;

    private int IntValue(string key, int fallback) =>
        _values[key] is JValue { Type: JTokenType.Integer } v ? (int)v : fallback;

    private List<string> StringList(string key)
    {
        var result = new List<string>();
        if (_values[key] is JArray array)
            foreach (var element in array)
                if (element is JValue { Type: JTokenType.String } v) result.Add((string)v!);
        return result;
    }

    private void SetStringList(string key, IReadOnlyList<string> items) =>
        _values[key] = new JArray(items);

    private string NestedString(string key, string childKey, string entryKey) =>
        _values[key] is JObject outer && outer[childKey] is JObject inner &&
        inner[entryKey] is JValue { Type: JTokenType.String } v ? (string)v! : "";

    private bool NestedBool(string key, string childKey, string entryKey, bool fallback) =>
        _values[key] is JObject outer && outer[childKey] is JObject inner &&
        inner[entryKey] is JValue { Type: JTokenType.Boolean } v ? (bool)v : fallback;

    private void SetNestedValue(string key, string childKey, string entryKey, JToken value)
    {
        if (_values[key] is not JObject outer) { outer = new JObject(); _values[key] = outer; }
        if (outer[childKey] is not JObject inner) { inner = new JObject(); outer[childKey] = inner; }
        inner[entryKey] = value;
    }
}

/// <summary>Header, body, and code font display names for one section.</summary>
public readonly record struct FontChoice(string Header, string Body, string Code)
{
    public static FontChoice SystemDefault { get; } = new("Helvetica, Arial", "Helvetica, Arial", "IBM Plex Mono");

    public static FontChoice FromJson(JObject obj) => new(
        Field(obj, "header", SystemDefault.Header),
        Field(obj, "body", SystemDefault.Body),
        Field(obj, "code", SystemDefault.Code));

    private static string Field(JObject obj, string key, string fallback) =>
        obj[key] is JValue { Type: JTokenType.String } v ? (string)v! : fallback;

    public JObject ToJson() => new()
    {
        ["header"] = Header,
        ["body"] = Body,
        ["code"] = Code,
    };
}
