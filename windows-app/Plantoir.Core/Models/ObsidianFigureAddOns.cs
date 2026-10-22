using System.Security.Cryptography;
using System.Text;
using System.Text.Json;

namespace Plantoir.Core.Models;

/// <summary>One file of an add-on as Plantoir carries it, pinned by size and SHA-256.</summary>
public sealed record CarriedFile(string Name, long Bytes, string Sha256);

/// <summary>
/// One Obsidian add-on Plantoir carries for a figure fence (#581, the mac's
/// #495): which fence it draws, and the exact files. The pins are the
/// contract's (<c>obsidianAddOnsForFigures.addOns</c>), held equal by
/// <c>ObsidianFigureAddOnsTests</c>.
/// </summary>
public sealed record ObsidianFigureAddOn(string Kind, string Id, string Name, string Version, IReadOnlyList<CarriedFile> Files);

/// <summary>
/// Obsidian's add-ons for diagrams and graphs (#581; the mac's
/// <c>ObsidianFigureAddOns.swift</c>, #495): which ones a course needs, and
/// adding them to the course on the teacher's one yes.
/// </summary>
/// <remarks>
/// <para><b>Why Plantoir writes files at all.</b> Obsidian loads an add-on from
/// <c>.obsidian/plugins/&lt;id&gt;/</c> when its id is in
/// <c>.obsidian/community-plugins.json</c>; nothing checks a signature. What it
/// will NOT do is run one unasked: the first time a course with add-ons opens,
/// Obsidian asks whether the teacher trusts its author, and Plantoir never
/// answers that for them (<c>rejected</c> in the contract).</para>
/// <para><b>What is written, in an order a crash at any point recovers from</b>
/// (<see cref="Install"/>): refuse a linked <c>.obsidian</c> or
/// <c>.obsidian/plugins</c>; re-hash the carried files; seed the course
/// defaults if <c>.obsidian</c> is absent and refuse unless <c>app.json</c> is
/// there; read the list (anything but an array of strings writes NOTHING);
/// decide each add-on (<c>vaultCases</c>); write the list, THEN each add-on as
/// <c>&lt;id&gt;.plantoir-partial</c> with the <c>.plantoir</c> marker, renamed
/// into place, <c>manifest.json</c> last.</para>
/// <para><b>Never while the course is open in Obsidian</b> — the callers'
/// rule (<see cref="ObsidianOpenRoute"/>), not this file's.</para>
/// <para><b>Windows' own two things.</b> A "link" is a reparse point with a
/// <see cref="FileSystemInfo.LinkTarget"/> — a junction or a symbolic link —
/// so a OneDrive placeholder folder, which is a reparse point too, is neither
/// refused nor skipped. And every rename, replace and delete is retried for a
/// moment (<see cref="Retrying"/>): right after a 7.8 MB write, Defender, the
/// indexer or OneDrive can hold the file or folder open, and a refusal that
/// clears in 200 ms is not a reason to fail a pass (#581 plan review, M5).</para>
/// </remarks>
public static class ObsidianFigureAddOns
{
    /// <summary>What one pass did for one add-on — the contract's <c>vaultCases.outcomeNames</c>.</summary>
    public enum OutcomeKind
    {
        Added, AlreadyThere, AlreadyThereSwitchedOff, LeftAloneTheirs, LeftAloneOtherVersion, LeftAloneUnreadable,
        RefusedListUnreadable, RefusedLink, RefusedCarriedCopy, RefusedSettingsNotSeeded, CouldNotWrite,
    }

    /// <summary>An outcome, with the version found (the two left-alone kinds that know one) or the system's reason (<c>CouldNotWrite</c>).</summary>
    public sealed record Outcome(OutcomeKind Kind, string? Version = null, string? Reason = null)
    {
        /// <summary>The contract's name for it.</summary>
        public string ContractName => char.ToLowerInvariant(Kind.ToString()[0]) + Kind.ToString()[1..];

        /// <summary>The whole pass was refused before any add-on was looked at.</summary>
        public bool IsARefusal => Kind is OutcomeKind.RefusedListUnreadable or OutcomeKind.RefusedLink
            or OutcomeKind.RefusedCarriedCopy or OutcomeKind.RefusedSettingsNotSeeded;
    }

    /// <summary>One add-on and what the pass did with it.</summary>
    public sealed record Result(ObsidianFigureAddOn AddOn, Outcome Outcome);

    /// <summary>What the list becomes when ids are added (<c>listCases</c>): write <see cref="Text"/>, leave it, or never overwrite it.</summary>
    public sealed record ListAfter(ListAfterKind Kind, string? Text = null);

    public enum ListAfterKind { Write, Unchanged, Refused }

    /// <summary>The add-ons, in the contract's order (<c>ObsidianFigureAddOnsTests.ThePinsAreTheContracts</c>).</summary>
    public static readonly IReadOnlyList<ObsidianFigureAddOn> Pinned = new[]
    {
        new ObsidianFigureAddOn("tikz", "obsidian-tikzjax", "TikZJax", "0.5.2", new[]
        {
            new CarriedFile("main.js", 7_861_284, "cbae1ad4362d44173e56ba512f01e65de1f7cc69a4bf4733bc5711a2de101f41"),
            new CarriedFile("manifest.json", 261, "09fbbb05aeffc32bc65365d8526fc2222ee971417dcd4afddeb989498a5e1de1"),
            new CarriedFile("styles.css", 4_791_190, "d9a7f741ec8fdcbe5e0145152c799238cee8df5a14ddc7dc9feb3bb835ce068d"),
            new CarriedFile("LICENSE.md", 1_068, "f2cb60614f038ec0db9a04546c05cc72d6c68a2cdb39bce0a853b692a5739291"),
        }),
        new ObsidianFigureAddOn("functionplot", "obsidian-functionplot", "Functionplot", "1.2.1", new[]
        {
            new CarriedFile("main.js", 220_867, "8b490af5fd3015e15237dbaadbb98fcdf823a42086029527381e48c5080be43f"),
            new CarriedFile("manifest.json", 287, "991ffea318c2483c4dd3eef2fdec47479d05dea8d04993becc2f74c186318195"),
            new CarriedFile("LICENSE", 1_072, "6e1b8deb29dc68d12c965b32600d1fe6089cee56dbb3b8662361296bcb221eed"),
        }),
    };

    /// <summary>The marker inside an add-on's folder that says Plantoir put it there (<c>sidecar.name</c>).</summary>
    public const string MarkerName = ".plantoir";

    /// <summary>The folder an add-on is written into before it is renamed into place (<c>sidecar.partialSuffix</c>).</summary>
    public const string PartialSuffix = ".plantoir-partial";

    /// <summary>Obsidian's list of the add-ons it switches on.</summary>
    public const string ListName = "community-plugins.json";

    /// <summary>Where the app carries the add-ons: <c>obsidian-addons\&lt;id&gt;\&lt;file&gt;</c> beside Plantoir.exe.</summary>
    public const string CarriedFolderName = "obsidian-addons";

    private static readonly object PassesLock = new();
    private static int _passesRunning;
    private static int _mostPassesSeen;

    /// <summary>The most passes ever seen running at once — read by a test, which proves passes never overlap.</summary>
    public static int MostPassesAtOnce { get { lock (PassesLock) return _mostPassesSeen; } }

    public static void ForgetMostPassesAtOnce() { lock (PassesLock) _mostPassesSeen = 0; }

    /// <summary>The marker's bytes for a version: the same bytes every pass (<c>sidecar.text</c>).</summary>
    public static string MarkerText(string version) => "{\"addedBy\":\"Plantoir\",\"version\":\"" + version + "\"}";

    /// <summary>The add-ons whose fence kind is among <paramref name="kinds"/>, in pinned order.</summary>
    public static List<ObsidianFigureAddOn> AddOnsForKinds(ICollection<string> kinds, IReadOnlyList<ObsidianFigureAddOn>? among = null) =>
        (among ?? Pinned).Where(addOn => kinds.Contains(addOn.Kind)).ToList();

    // ---- Which add-ons a course needs (whichPages) --------------------------

    /// <summary>
    /// The figure kinds the course's pages use, among <paramref name="kinds"/>:
    /// every <c>.md</c> file under the course — drafts and shared pages too,
    /// the vault is the whole course — except inside a folder whose name starts
    /// with a dot, through a link (never followed, so never a loop), or a page
    /// the cloud has not downloaded (<paramref name="isEvicted"/>, so the scan
    /// never forces a download). A byte test first; it stops once every kind
    /// is found. A page is decoded as Python's utf-8 reader with
    /// <c>errors="replace"</c> decodes it, its byte-order mark kept.
    /// </summary>
    public static ISet<string> KindsUsed(string coursePath, IReadOnlySet<string> kinds, Func<string, bool>? isEvicted = null)
    {
        isEvicted ??= PageIsEvicted;
        var found = new HashSet<string>(StringComparer.Ordinal);
        var folders = new Stack<string>();
        folders.Push(coursePath);
        while (folders.Count > 0 && found.Count < kinds.Count)
        {
            string folder = folders.Pop();
            IEnumerable<FileSystemInfo> entries;
            try { entries = new DirectoryInfo(folder).EnumerateFileSystemInfos("*", Unfiltered).OrderBy(e => e.Name, StringComparer.Ordinal).ToList(); }
            catch { continue; }
            foreach (var entry in entries)
            {
                if (found.Count == kinds.Count) break;
                if (entry.Name.StartsWith('.')) continue;
                if (entry.Attributes.HasFlag(FileAttributes.ReparsePoint) && entry.LinkTarget is not null) continue;
                if (entry is DirectoryInfo) { folders.Push(entry.FullName); continue; }
                if (!entry.Name.EndsWith(".md", StringComparison.OrdinalIgnoreCase)) continue;
                if (isEvicted(entry.FullName)) continue;
                byte[] data;
                try { data = File.ReadAllBytes(entry.FullName); }
                catch { continue; }
                var stillToFind = kinds.Where(kind => !found.Contains(kind)
                    && data.AsSpan().IndexOf(Encoding.ASCII.GetBytes(kind)) >= 0).ToHashSet(StringComparer.Ordinal);
                if (stillToFind.Count == 0) continue;
                foreach (string kind in FigureFenceScan.Kinds(Encoding.UTF8.GetString(data), stillToFind)) found.Add(kind);
            }
        }
        return found;
    }

    /// <summary>
    /// Whether Windows holds only a placeholder for the page (OneDrive Files
    /// On-Demand): reading it would download it. The mac's <c>SF_DATALESS</c>;
    /// here <c>FILE_ATTRIBUTE_RECALL_ON_DATA_ACCESS</c> (0x400000),
    /// <c>FILE_ATTRIBUTE_RECALL_ON_OPEN</c> (0x40000) or <c>Offline</c>.
    /// </summary>
    public static bool PageIsEvicted(string path)
    {
        try
        {
            int attributes = (int)File.GetAttributes(path);
            return (attributes & (0x400000 | 0x40000 | (int)FileAttributes.Offline)) != 0;
        }
        catch { return false; }
    }

    /// <summary>Which add-ons the course needs, and which of those a pass would ADD. Pure file work — run it off the UI thread.</summary>
    public static (List<ObsidianFigureAddOn> Needed, List<ObsidianFigureAddOn> WouldAdd) Scan(string coursePath)
    {
        var kinds = Pinned.Select(addOn => addOn.Kind).ToHashSet(StringComparer.Ordinal);
        var needed = AddOnsForKinds(KindsUsed(coursePath, kinds));
        return (needed, WouldAdd(needed, coursePath));
    }

    // ---- The list (listCases) -----------------------------------------------

    /// <summary>Reads <c>community-plugins.json</c>: null data (no file) is no ids; anything but a JSON array of strings is null (unreadable).</summary>
    public static List<string>? ReadList(byte[]? data)
    {
        if (data is null) return new List<string>();
        try
        {
            using var document = JsonDocument.Parse(data);
            if (document.RootElement.ValueKind != JsonValueKind.Array) return null;
            var ids = new List<string>();
            foreach (var element in document.RootElement.EnumerateArray())
            {
                if (element.ValueKind != JsonValueKind.String) return null;
                ids.Add(element.GetString()!);
            }
            return ids;
        }
        catch { return null; }
    }

    /// <summary>The list with <paramref name="adding"/> appended: every id kept in its order, none twice.</summary>
    public static List<string> IdsAdding(IReadOnlyList<string> existing, IEnumerable<string> adding)
    {
        var result = existing.ToList();
        foreach (string id in adding) if (!result.Contains(id)) result.Add(id);
        return result;
    }

    /// <summary>
    /// The list as Obsidian writes it: <c>JSON.stringify(ids, undefined, 2)</c>,
    /// no newline at the end (1.13.7's <c>writeConfigJson</c>). Written by hand,
    /// with <c>\n</c> and JSON.stringify's own escaping — a general serializer
    /// escapes non-ASCII, <c>+</c>, <c>&lt;</c>, <c>&gt;</c>, <c>&amp;</c> or
    /// <c>'</c>, and then a second pass would change bytes Obsidian wrote.
    /// </summary>
    public static string ListText(IReadOnlyList<string> ids)
    {
        if (ids.Count == 0) return "[]";
        return "[\n" + string.Join(",\n", ids.Select(id => "  " + JsonStringify(id))) + "\n]";
    }

    /// <summary>JSON.stringify of one string: <c>"</c>, <c>\</c> and control characters escaped (lowercase hex), lone surrogates as <c>\uXXXX</c>, everything else as it is.</summary>
    public static string JsonStringify(string value)
    {
        var text = new StringBuilder("\"");
        for (int i = 0; i < value.Length; i++)
        {
            char c = value[i];
            switch (c)
            {
                case '"': text.Append("\\\""); break;
                case '\\': text.Append("\\\\"); break;
                case '\b': text.Append("\\b"); break;
                case '\f': text.Append("\\f"); break;
                case '\n': text.Append("\\n"); break;
                case '\r': text.Append("\\r"); break;
                case '\t': text.Append("\\t"); break;
                default:
                    if (c < 0x20) text.Append("\\u").Append(((int)c).ToString("x4"));
                    else if (char.IsHighSurrogate(c) && i + 1 < value.Length && char.IsLowSurrogate(value[i + 1])) { text.Append(c).Append(value[i + 1]); i++; }
                    else if (char.IsSurrogate(c)) text.Append("\\u").Append(((int)c).ToString("x4"));
                    else text.Append(c);
                    break;
            }
        }
        return text.Append('"').ToString();
    }

    /// <summary>The list after adding <paramref name="adding"/> to what <paramref name="listData"/> holds (null: no file yet).</summary>
    public static ListAfter ListAfterAdding(IReadOnlyList<string> adding, byte[]? listData)
    {
        var listed = ReadList(listData);
        if (listed is null) return new ListAfter(ListAfterKind.Refused);
        var newList = IdsAdding(listed, adding);
        if (newList.SequenceEqual(listed) && listData is not null) return new ListAfter(ListAfterKind.Unchanged);
        return new ListAfter(ListAfterKind.Write, ListText(newList));
    }

    // ---- Deciding and installing (vaultCases) -------------------------------

    /// <summary>The add-ons a pass would add, without writing — what decides whether there is anything to offer. A refused pass would add nothing.</summary>
    public static List<ObsidianFigureAddOn> WouldAdd(IReadOnlyList<ObsidianFigureAddOn> addOns, string coursePath)
    {
        string settings = Path.Combine(coursePath, ObsidianAddOns.SettingsFolderName);
        string plugins = Path.Combine(settings, "plugins");
        if (KindOf(settings) == EntryKind.Link || KindOf(plugins) == EntryKind.Link) return new();
        var listed = ReadList(ReadListData(Path.Combine(settings, ListName)));
        if (listed is null) return new();
        return addOns.Where(addOn => Decide(addOn, plugins, listed) is null).ToList();
    }

    /// <summary>
    /// Adds the add-ons a course needs. Pure file work, run only through
    /// <see cref="ObsidianFigureAddOnsQueue"/>, so two passes never overlap.
    /// <paramref name="carriedPath"/> holds <c>&lt;id&gt;\&lt;file&gt;</c>;
    /// <paramref name="defaultsPath"/> is the toolchain's
    /// <c>support\obsidian_defaults\.obsidian</c>.
    /// </summary>
    public static List<Result> Install(IReadOnlyList<ObsidianFigureAddOn> addOns, string coursePath, string? carriedPath, string? defaultsPath)
    {
        if (addOns.Count == 0) return new();
        lock (PassesLock) { _passesRunning++; if (_passesRunning > _mostPassesSeen) _mostPassesSeen = _passesRunning; }
        try { return InstallWhileCounted(addOns, coursePath, carriedPath, defaultsPath); }
        finally { lock (PassesLock) _passesRunning--; }
    }

    private static List<Result> InstallWhileCounted(IReadOnlyList<ObsidianFigureAddOn> addOns, string coursePath, string? carriedPath, string? defaultsPath)
    {
        string settings = Path.Combine(coursePath, ObsidianAddOns.SettingsFolderName);
        string plugins = Path.Combine(settings, "plugins");

        // 1. Links are never followed.
        if (KindOf(settings) == EntryKind.Link || KindOf(plugins) == EntryKind.Link) return Every(addOns, OutcomeKind.RefusedLink);

        // 2. The carried copy, re-hashed before anything is written.
        if (carriedPath is null || !CarriedCopyMatches(addOns, carriedPath)) return Every(addOns, OutcomeKind.RefusedCarriedCopy);

        // 3. The course's defaults first, or nothing.
        if (KindOf(settings) == EntryKind.None && defaultsPath is not null && Directory.Exists(defaultsPath))
        {
            try { CopyTree(defaultsPath, settings); } catch { }
        }
        if (KindOf(Path.Combine(settings, "app.json")) != EntryKind.File) return Every(addOns, OutcomeKind.RefusedSettingsNotSeeded);

        // 4. The list.
        string listPath = Path.Combine(settings, ListName);
        byte[]? listData = ReadListData(listPath);
        var listed = ReadList(listData);
        if (listed is null) return Every(addOns, OutcomeKind.RefusedListUnreadable);

        // 5. Each add-on. A partial folder left by an earlier pass is ours by
        // name and is never anything but a leftover: it goes first.
        var results = new List<Result>();
        var adding = new List<ObsidianFigureAddOn>();
        foreach (var addOn in addOns)
        {
            string partial = Path.Combine(plugins, addOn.Id + PartialSuffix);
            if (KindOf(partial) != EntryKind.None) { try { Retrying(() => Remove(partial)); } catch { } }
            if (Decide(addOn, plugins, listed) is { } kept) results.Add(new Result(addOn, kept));
            else adding.Add(addOn);
        }
        if (adding.Count == 0) return InPinnedOrder(results);

        // 6. The list, then the files.
        var after = ListAfterAdding(adding.Select(addOn => addOn.Id).ToList(), listData);
        if (after.Kind == ListAfterKind.Write)
        {
            try { WriteAtomically(listPath, Encoding.UTF8.GetBytes(after.Text!)); }
            catch (Exception error)
            {
                results.AddRange(adding.Select(addOn => new Result(addOn, new Outcome(OutcomeKind.CouldNotWrite, Reason: error.Message))));
                return InPinnedOrder(results);
            }
        }
        foreach (var addOn in adding) results.Add(new Result(addOn, Write(addOn, plugins, Path.Combine(carriedPath, addOn.Id))));
        return InPinnedOrder(results);
    }

    /// <summary>Whether every file of these add-ons is carried, the size and SHA-256 its pin says.</summary>
    public static bool CarriedCopyMatches(IReadOnlyList<ObsidianFigureAddOn> addOns, string carriedPath)
    {
        foreach (var addOn in addOns)
            foreach (var file in addOn.Files)
            {
                byte[] data;
                try { data = File.ReadAllBytes(Path.Combine(carriedPath, addOn.Id, file.Name)); }
                catch { return false; }
                if (data.Length != file.Bytes) return false;
                if (Sha256(data) != file.Sha256) return false;
            }
        return true;
    }

    /// <summary>Lowercase hex SHA-256.</summary>
    public static string Sha256(byte[] data) => Convert.ToHexString(SHA256.HashData(data)).ToLowerInvariant();

    /// <summary>
    /// The folders under <c>plugins</c> that carry Plantoir's marker, sorted —
    /// partial copies included. One attribute read of the marker per folder;
    /// never follows a link, never opens anything.
    /// </summary>
    public static List<string> PlantoirAddOnFolders(string pluginsPath)
    {
        var names = new List<string>();
        IEnumerable<FileSystemInfo> entries;
        try { entries = new DirectoryInfo(pluginsPath).EnumerateFileSystemInfos("*", Unfiltered).ToList(); }
        catch { return names; }
        foreach (var entry in entries)
        {
            if (entry.Name.StartsWith('.')) continue;
            if (KindOf(entry.FullName) != EntryKind.Directory) continue;
            if (KindOf(Path.Combine(entry.FullName, MarkerName)) == EntryKind.File) names.Add(entry.Name);
        }
        names.Sort(StringComparer.Ordinal);
        return names;
    }

    // ---- What kind of thing is at a path ------------------------------------

    public enum EntryKind { None, File, Directory, Link }

    internal static readonly EnumerationOptions Unfiltered = new()
    {
        AttributesToSkip = 0, IgnoreInaccessible = false, RecurseSubdirectories = false, ReturnSpecialDirectories = false,
    };

    /// <summary>What is at a path, without following a link: a junction or a symbolic link is <c>Link</c>; a cloud placeholder is what it stands for.</summary>
    public static EntryKind KindOf(string path)
    {
        FileAttributes attributes;
        try { attributes = File.GetAttributes(path); }
        catch { return EntryKind.None; }
        bool folder = attributes.HasFlag(FileAttributes.Directory);
        if (attributes.HasFlag(FileAttributes.ReparsePoint))
        {
            try
            {
                FileSystemInfo info = folder ? new DirectoryInfo(path) : new FileInfo(path);
                if (info.LinkTarget is not null) return EntryKind.Link;
            }
            catch { return EntryKind.Link; }
        }
        return folder ? EntryKind.Directory : EntryKind.File;
    }

    // ---- Private helpers ----------------------------------------------------

    /// <summary>The vault-state table for one add-on: null means add it; otherwise what the pass leaves.</summary>
    private static Outcome? Decide(ObsidianFigureAddOn addOn, string plugins, IReadOnlyList<string> listed)
    {
        string folder = Path.Combine(plugins, addOn.Id);
        var kind = KindOf(folder);
        if (kind == EntryKind.None) return null;
        if (kind != EntryKind.Directory) return new Outcome(OutcomeKind.LeftAloneUnreadable);
        bool hasMarker = KindOf(Path.Combine(folder, MarkerName)) == EntryKind.File;
        string? version = ManifestVersion(folder);
        if (version is null) return hasMarker ? null : new Outcome(OutcomeKind.LeftAloneUnreadable);
        if (!hasMarker) return new Outcome(OutcomeKind.LeftAloneTheirs, version);
        if (version != addOn.Version) return new Outcome(OutcomeKind.LeftAloneOtherVersion, version);
        return new Outcome(listed.Contains(addOn.Id) ? OutcomeKind.AlreadyThere : OutcomeKind.AlreadyThereSwitchedOff);
    }

    private static string? ManifestVersion(string folder)
    {
        string manifest = Path.Combine(folder, "manifest.json");
        if (KindOf(manifest) != EntryKind.File) return null;
        try
        {
            using var document = JsonDocument.Parse(File.ReadAllBytes(manifest));
            if (document.RootElement.ValueKind != JsonValueKind.Object) return null;
            return document.RootElement.TryGetProperty("version", out var version) && version.ValueKind == JsonValueKind.String
                ? version.GetString() : null;
        }
        catch { return null; }
    }

    /// <summary>The list's bytes, or null when there is no file; a file that cannot be read reads as empty, which is unreadable.</summary>
    private static byte[]? ReadListData(string listPath)
    {
        if (KindOf(listPath) == EntryKind.None) return null;
        try { return File.ReadAllBytes(listPath); }
        catch { return Array.Empty<byte>(); }
    }

    /// <summary>Writes one add-on: partial folder, marker, rename, manifest last.</summary>
    private static Outcome Write(ObsidianFigureAddOn addOn, string plugins, string source)
    {
        string folder = Path.Combine(plugins, addOn.Id);
        string partial = Path.Combine(plugins, addOn.Id + PartialSuffix);
        try
        {
            Directory.CreateDirectory(plugins);
            // Only reached for Plantoir's own unfinished copy (Decide).
            if (KindOf(folder) != EntryKind.None) Retrying(() => Remove(folder));
            Directory.CreateDirectory(partial);
            foreach (var file in addOn.Files.Where(file => file.Name != "manifest.json"))
                File.Copy(Path.Combine(source, file.Name), Path.Combine(partial, file.Name));
            File.WriteAllBytes(Path.Combine(partial, MarkerName), Encoding.UTF8.GetBytes(MarkerText(addOn.Version)));
            Retrying(() => Directory.Move(partial, folder));
            WriteAtomically(Path.Combine(folder, "manifest.json"), File.ReadAllBytes(Path.Combine(source, "manifest.json")));
            return new Outcome(OutcomeKind.Added);
        }
        catch (Exception error)
        {
            try { if (KindOf(partial) != EntryKind.None) Remove(partial); } catch { }
            return new Outcome(OutcomeKind.CouldNotWrite, Reason: error.Message);
        }
    }

    /// <summary>A temporary file beside the target, then a replace — the list and the manifest are never half-written.</summary>
    private static void WriteAtomically(string path, byte[] bytes)
    {
        string temporary = path + ".plantoir-" + Guid.NewGuid().ToString("N")[..8];
        try
        {
            File.WriteAllBytes(temporary, bytes);
            Retrying(() => File.Move(temporary, path, overwrite: true));
        }
        finally
        {
            try { if (File.Exists(temporary)) File.Delete(temporary); } catch { }
        }
    }

    private static void Remove(string path)
    {
        if (Directory.Exists(path)) Directory.Delete(path, recursive: true);
        else File.Delete(path);
    }

    /// <summary>
    /// A rename, replace or delete, tried again for about 0.75 s when the
    /// disk says the thing is in use or refused — a scanner holding a file it
    /// has just seen written. Anything still refused after that is the
    /// pass's failure (couldNotWrite), with the system's reason.
    /// </summary>
    internal static void Retrying(Action action)
    {
        int[] pauses = { 50, 100, 200, 400 };
        for (int attempt = 0; ; attempt++)
        {
            try { action(); return; }
            catch (Exception error) when ((error is IOException or UnauthorizedAccessException) && attempt < pauses.Length)
            {
                Thread.Sleep(pauses[attempt]);
            }
        }
    }

    private static void CopyTree(string source, string destination)
    {
        Directory.CreateDirectory(destination);
        foreach (string file in Directory.EnumerateFiles(source, "*", SearchOption.AllDirectories))
        {
            string target = Path.Combine(destination, Path.GetRelativePath(source, file));
            Directory.CreateDirectory(Path.GetDirectoryName(target)!);
            File.Copy(file, target, overwrite: true);
        }
    }

    private static List<Result> Every(IReadOnlyList<ObsidianFigureAddOn> addOns, OutcomeKind kind) =>
        addOns.Select(addOn => new Result(addOn, new Outcome(kind))).ToList();

    /// <summary>Results in the pinned order, so a trail line reads the same way every time.</summary>
    private static List<Result> InPinnedOrder(List<Result> results)
    {
        var ordered = Pinned.SelectMany(pin => results.Where(result => result.AddOn.Id == pin.Id)).ToList();
        ordered.AddRange(results.Where(result => Pinned.All(pin => pin.Id != result.AddOn.Id)));
        return ordered;
    }
}

/// <summary>
/// The one place installs run, so two passes never overlap (#581 item 5, the
/// mac's actor): Open in Obsidian and a finished preview can ask at once, and
/// the second pass's "remove a leftover partial folder" would otherwise delete
/// the first pass's folder while it is being written. One gate for every
/// course's pass, which costs nothing at this size.
/// </summary>
public static class ObsidianFigureAddOnsQueue
{
    private static readonly SemaphoreSlim Gate = new(1, 1);

    public static async Task<List<ObsidianFigureAddOns.Result>> InstallAsync(
        IReadOnlyList<ObsidianFigureAddOn> addOns, string coursePath, string? carriedPath, string? defaultsPath)
    {
        await Gate.WaitAsync().ConfigureAwait(false);
        try { return await Task.Run(() => ObsidianFigureAddOns.Install(addOns, coursePath, carriedPath, defaultsPath)).ConfigureAwait(false); }
        finally { Gate.Release(); }
    }
}
