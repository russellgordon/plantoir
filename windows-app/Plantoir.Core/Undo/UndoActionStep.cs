using System.Text;
using System.Text.Json.Nodes;
using Plantoir.Core.Scripting;

namespace Plantoir.Core.Undo;

/// <summary>Who makes a step and what it is called: the step's <c>madeBy</c> and its action key (the mac's <c>UndoStepMaker</c>).</summary>
internal sealed record UndoStepMaker(string MadeBy, string ActionKey)
{
    /// <summary>The same maker, for another action.</summary>
    internal UndoStepMaker Making(string actionKey) => this with { ActionKey = actionKey };
}

/// <summary>
/// One member of a JSON file a step changes (#899 W8-11; the mac's
/// <c>(keyPath, before, after)</c> of <c>JournaledStep.editJSON</c>): null
/// before or after is the member absent.
/// </summary>
internal sealed record UndoMemberChange(IReadOnlyList<string> KeyPath, UndoJson? Before, UndoJson? After)
{
    /// <summary>The member as its <c>editJSON</c> op, at <paramref name="relativePath"/> inside the working folder.</summary>
    internal JsonObject Op(string relativePath)
    {
        var keyPath = new JsonArray();
        foreach (string part in KeyPath) keyPath.Add(part);
        var op = new JsonObject { ["kind"] = UndoOp.EditJson, ["path"] = relativePath, ["keyPath"] = keyPath };
        if (Before is not null) op["before"] = JsonNode.Parse(Before.Spelled()!);
        if (After is not null) op["after"] = JsonNode.Parse(After.Spelled()!);
        return op;
    }
}

/// <summary>
/// A daily action's step that the door refused (#899 W7a; the mac's
/// <c>JournaledStepError.refused</c>): NOTHING of it was written. An
/// <see cref="IOException"/>, so a caller that said "Nothing was changed: …"
/// for a failed first write says the same sentence now.
/// </summary>
internal sealed class UndoStepRefusedException(UndoRefusal refusal, string message) : IOException(message)
{
    internal UndoRefusal Refusal { get; } = refusal;
}

/// <summary>
/// A daily action's step refused PART WAY (the mac's
/// <c>JournaledStepError.leftPartWay</c>): a file could not be put back after
/// the step was refused, so it holds the new content while what it held
/// before is kept beside it under each name in <see cref="KeptOriginals"/>.
/// Never said as "Nothing was changed"; its message names where each page's
/// earlier content is kept (<c>undo.wording.keptBesideIt</c>).
/// </summary>
internal sealed class UndoStepLeftPartWayException(UndoRefusal refusal, IReadOnlyList<string> keptOriginals, string message)
    : IOException(message)
{
    internal UndoRefusal Refusal { get; } = refusal;
    internal IReadOnlyList<string> KeptOriginals { get; } = keptOriginals;
}

/// <summary>
/// ONE action's writes, gathered and then made through the door as ONE step
/// (#899 W7a; the mac's <c>JournaledStep</c>, U3a). The action plans every
/// file it will write here instead of writing it (<see cref="Write"/>); it
/// reads through this too (<see cref="ReadText"/>), so a page it wrote a
/// moment ago reads as it will be. <see cref="Make"/> then hands the whole
/// step to <see cref="UndoDoor.Perform(UndoStepDraft)"/>, which writes it
/// down first and stages every file beside its target and swaps them in
/// together: all of them or none (<c>undo.rule.stagedThenSwapped</c>).
///
/// <para><b>Shadow.</b> While the switch is off the files are written exactly
/// as planned whether or not the list could take the step (a list that
/// cannot leaves one trail line, "undo could not record a step"), and nothing
/// is offered back.</para>
///
/// <para><b>A file a step cannot name</b> (no working folder above the course,
/// a link leading outside it, a target that is a link): in shadow the files
/// are staged and swapped in together WITHOUT the list, with one trail line;
/// live, the step is refused before anything changes. A target that is a
/// folder, or a file that cannot be read when first planned, refuses the
/// action before anything is written.</para>
///
/// <para><b>Plan time.</b> Each file's before is what it held when FIRST
/// planned, never a second read at <see cref="Make"/>: a file another
/// program changed in between refuses the step instead of being written
/// over (the U3a review's trap).</para>
///
/// <para><b>The front page</b> is a <c>recompute</c> op
/// (<see cref="KeepsTheFrontPageTrue"/>), re-derived ONCE after the step by
/// the door (or here, when the door made no step), never planned as a file
/// of the step (W6's note: one write of it, not two).</para>
/// </summary>
internal sealed class UndoActionStep
{
    // ---- Stored properties ---------------------------------------------------------

    private readonly UndoStepMaker _maker;
    private readonly string? _root;
    private readonly string? _course;
    private readonly long? _section;
    private readonly string _holds;
    private readonly UndoDoor _door;
    private readonly UndoMode _mode;
    private readonly Action<UndoTrailLine>? _trail;
    private readonly IUndoMaintainers _maintainers;
    private readonly UndoSeams? _plainSeams;

    /// <summary>Each planned file's full path, in the order first planned.</summary>
    private readonly List<string> _order = [];
    private readonly Dictionary<string, byte[]?> _before = new(StringComparer.OrdinalIgnoreCase);
    private readonly Dictionary<string, byte[]?> _after = new(StringComparer.OrdinalIgnoreCase);
    private readonly Dictionary<string, string> _shownAs = new(StringComparer.OrdinalIgnoreCase);
    private readonly List<(string FullPath, long Section)> _frontPages = [];
    /// <summary>Planned files today's in-memory undo does not keep (a record beside the pages).</summary>
    private readonly HashSet<string> _notForToday = new(StringComparer.OrdinalIgnoreCase);
    /// <summary>Planned files the step removed at some point (a rename's old name), whatever it writes there after.</summary>
    private readonly HashSet<string> _removedOnce = new(StringComparer.OrdinalIgnoreCase);
    /// <summary>A JSON file planned member by member (<see cref="EditJson"/>): its members, by the file's full path.</summary>
    private readonly Dictionary<string, IReadOnlyList<UndoMemberChange>> _members = new(StringComparer.OrdinalIgnoreCase);
    /// <summary>Each folder the step makes whole (<see cref="MakeTree"/>), in the order planned.</summary>
    private readonly List<(string FullPath, UndoTreeListing Listing, Dictionary<string, byte[]> Contents)> _trees = [];

    // ---- Initializer ---------------------------------------------------------------

    /// <param name="workingFolder">The folder holding <c>courses\</c>, or null when the course is not inside one.</param>
    /// <param name="undo">The list, mode and trail: this process's by default (<see cref="UndoForThisProcess.Current"/>), a test's own in a test.</param>
    /// <param name="door">A test's door over <paramref name="undo"/> (seams); the list's own by default.</param>
    internal UndoActionStep(UndoStepMaker maker, string? workingFolder, string? course, long? section, string holds = "section",
                            UndoForThisProcess? undo = null, UndoDoor? door = null, UndoSeams? plainSeams = null)
    {
        UndoForThisProcess list = undo ?? UndoForThisProcess.Current;
        _maker = maker;
        _root = workingFolder is null ? null : Path.GetFullPath(workingFolder);
        _course = course;
        _section = section;
        _holds = holds;
        _door = door ?? list.Door();
        _mode = list.Mode;
        _trail = list.Trail;
        _maintainers = list.Maintainers;
        _plainSeams = plainSeams;
    }

    // ---- Computed properties ---------------------------------------------------------

    /// <summary>The front pages this step keeps true, as their full paths.</summary>
    internal IReadOnlyList<string> FrontPages
    {
        get
        {
            var pages = new List<string>();
            foreach ((string full, _) in _frontPages) pages.Add(full);
            return pages;
        }
    }

    /// <summary>Whether anything is planned that differs from what its file held.</summary>
    internal bool ChangesAnything
    {
        get
        {
            if (_trees.Count > 0) return true;
            foreach (string path in _order)
            {
                if (!Same(_before[path], _after[path])) return true;
            }
            return false;
        }
    }

    /// <summary>Each planned file that changes, with the text it held and holds (for today's in-memory undo, <c>UndoHistory</c>).</summary>
    internal IReadOnlyList<(string FullPath, string? Before, string? After, byte[]? BeforeBytes)> ChangedFiles
    {
        get
        {
            var changed = new List<(string, string?, string?, byte[]?)>();
            foreach (string path in _order)
            {
                if (Same(_before[path], _after[path])) continue;
                changed.Add((_shownAs[path], TextOf(_before[path]), TextOf(_after[path]), _before[path]));
            }
            return changed;
        }
    }

    // ---- Functions -------------------------------------------------------------------

    /// <summary>Plans <paramref name="text"/> as the file's content, written as <c>File.WriteAllText</c> writes it (UTF-8, no byte-order mark).</summary>
    /// <param name="todaysUndoKeepsIt">False for a file beside the pages that today's in-memory undo (<c>UndoHistory</c>) never kept, such as <c>later-classes-kept.json</c>: it is in the step, and Undo Last Change leaves it.</param>
    internal void Write(string fullPath, string text, bool todaysUndoKeepsIt = true)
    {
        Plan(fullPath, new UTF8Encoding(false).GetBytes(text));
        if (!todaysUndoKeepsIt) _notForToday.Add(Path.GetFullPath(fullPath));
    }

    /// <summary>Plans <paramref name="bytes"/> as the file's content, exactly as given.</summary>
    internal void WriteBytes(string fullPath, byte[] bytes) => Plan(fullPath, bytes);

    /// <summary>
    /// Plans a JSON file's change as one <c>editJSON</c> per member (#899 W8-11;
    /// the mac's <c>JournaledStep.editJSON</c>, U4a): <paramref name="read"/>
    /// is the bytes the caller's plan was built from, read when planned and
    /// never again at <see cref="Make"/> (the U3a trap), and the step's before
    /// for the file; <paramref name="after"/> the bytes the members leave it
    /// holding, which the caller worked out with the member rule. Made, each
    /// member is moved in the file as it is THEN, so a member another window
    /// changed meanwhile is kept, and one of this step's own changed meanwhile
    /// refuses the step (<c>changedSince</c>). A file already planned in this
    /// step is planned whole instead.
    /// </summary>
    internal void EditJson(string fullPath, byte[] read, IReadOnlyList<UndoMemberChange> members, byte[] after)
    {
        string key = Path.GetFullPath(fullPath);
        if (_before.ContainsKey(key))
        {
            Plan(fullPath, after);
            return;
        }
        if (Directory.Exists(key)) throw new IOException($"“{Path.GetFileName(key)}” is a folder, so it could not be written.");
        _before[key] = read;
        _order.Add(key);
        _shownAs[key] = fullPath;
        _after[key] = after;
        if (members.Count > 0) _members[key] = members;
    }

    /// <summary>
    /// Plans the file's removal (the mac's <c>remove</c>): the step leaves it
    /// absent, read as absent through the step from now on. A rename is a
    /// <see cref="Write"/> of the new name and a remove of the old one, so a
    /// later write of the old name in the same step (a chain of renames, or a
    /// new page put where a renamed one stood) is ONE change of that file
    /// (#899 W7b2-1, Make Room for Classes).
    /// </summary>
    internal void Remove(string fullPath) => Plan(fullPath, null);

    /// <summary>
    /// Plans a folder made whole at <paramref name="fullPath"/>, where nothing
    /// is yet, as ONE <c>createTree</c> (#899 W8-13; the mac's
    /// <c>JournaledStep.makeTree</c>, U4a): <paramref name="folders"/> the
    /// folders inside it and <paramref name="files"/> every file inside it by
    /// its path in the folder (<c>/</c>-separated), with its bytes. Made, the
    /// door is given the listing and every listed file's content as blobs, so
    /// the folder can always be made again.
    /// </summary>
    internal void MakeTree(string fullPath, IReadOnlyList<string> folders, IReadOnlyDictionary<string, byte[]> files)
    {
        var paths = new List<string>();
        foreach (string path in files.Keys) paths.Add(path);
        paths.Sort((first, second) => Encoding.UTF8.GetBytes(first).AsSpan().SequenceCompareTo(Encoding.UTF8.GetBytes(second)));
        var listed = new List<(string Path, string Sha)>();
        var contents = new Dictionary<string, byte[]>(StringComparer.Ordinal);
        foreach (string path in paths)
        {
            listed.Add((path, UndoCheck.Sha(files[path])));
            contents[path] = files[path];
        }
        _trees.Add((Path.GetFullPath(fullPath), new UndoTreeListing(new List<string>(folders), listed), contents));
    }

    /// <summary>Each planned folder's <c>createTree</c> op and the blobs it needs (its listing, then every listed file's bytes), or null when one cannot be named in a step.</summary>
    private List<(JsonObject Op, List<byte[]> Blobs)>? RecordableTrees()
    {
        var result = new List<(JsonObject, List<byte[]>)>();
        foreach ((string full, UndoTreeListing listing, Dictionary<string, byte[]> contents) in _trees)
        {
            if (RelativeOf(full) is not { } relative || !UndoPlaces.StaysInside(_root!, relative)) return null;
            var names = new JsonArray(listing.Sha);
            var blobs = new List<byte[]> { listing.Bytes };
            var seen = new HashSet<string>(StringComparer.Ordinal) { listing.Sha };
            foreach ((string path, string sha) in listing.Files)
            {
                if (seen.Add(sha)) names.Add(sha);
                blobs.Add(contents[path]);
            }
            result.Add((new JsonObject { ["kind"] = UndoOp.CreateTree, ["path"] = relative, ["listingSha"] = listing.Sha, ["blobs"] = names }, blobs));
        }
        return result;
    }

    /// <summary>Every planned file the step leaves with content, as its full path, in the order first planned.</summary>
    internal IReadOnlyList<string> PlannedWithContent
    {
        get
        {
            var present = new List<string>();
            foreach (string path in _order)
            {
                if (_after[path] is not null) present.Add(_shownAs[path]);
            }
            return present;
        }
    }

    /// <summary>Whether today's in-memory undo is told of this planned file.</summary>
    internal bool TodaysUndoKeeps(string fullPath) => !_notForToday.Contains(Path.GetFullPath(fullPath));

    /// <summary>The file's text as the step will leave it, or null when it is (or will be) absent.</summary>
    internal string? ReadTextIfAny(string fullPath)
    {
        string key = Path.GetFullPath(fullPath);
        if (_after.TryGetValue(key, out byte[]? planned)) return TextOf(planned);
        return File.Exists(fullPath) ? File.ReadAllText(fullPath) : null;
    }

    /// <summary>Whether the file is there as the step will leave it: planned with content, else on the disk (the mac's <c>fileExists</c>).</summary>
    internal bool Exists(string fullPath)
    {
        string key = Path.GetFullPath(fullPath);
        if (_after.TryGetValue(key, out byte[]? planned)) return planned is not null;
        return File.Exists(fullPath);
    }

    /// <summary>The file's text as the step will leave it: what is planned, else the disk's.</summary>
    internal string ReadText(string fullPath)
    {
        string key = Path.GetFullPath(fullPath);
        if (_after.TryGetValue(key, out byte[]? planned))
            return planned is null ? throw new FileNotFoundException("A file this change removes.", fullPath) : TextOf(planned)!;
        return File.ReadAllText(fullPath);
    }

    /// <summary>The section's front page is kept true by its rule after the step (<c>recompute</c>, <c>sectionFrontPage</c>).</summary>
    internal void KeepsTheFrontPageTrue(long section, string fullPath)
    {
        // Once per page, as the mac's: an action that plans one class after
        // another names the same front page each time (review 1, LOW).
        var page = (Path.GetFullPath(fullPath), section);
        if (!_frontPages.Contains(page)) _frontPages.Add(page);
    }

    private void Plan(string fullPath, byte[]? after)
    {
        string key = Path.GetFullPath(fullPath);
        if (!_before.ContainsKey(key))
        {
            // Read NOW, at plan time: the step's before is what the plan was
            // built from. A file that cannot be read stops the action here,
            // before anything is written (it threw at this read before W7a too).
            if (Directory.Exists(key)) throw new IOException($"“{Path.GetFileName(key)}” is a folder, so it could not be written.");
            _before[key] = File.Exists(key) ? File.ReadAllBytes(key) : null;
            _order.Add(key);
            _shownAs[key] = fullPath;
        }
        _after[key] = after;
        if (after is null) _removedOnce.Add(key);
        // Planned again as a whole file: no longer member by member.
        _members.Remove(key);
    }

    /// <summary>
    /// Makes the step: once, all or none. Throws <see cref="UndoStepRefusedException"/>
    /// when nothing was written and <see cref="UndoStepLeftPartWayException"/>
    /// when a file could not be put back.
    /// </summary>
    internal void Make()
    {
        if (!ChangesAnything)
        {
            RederiveTheFrontPages();
            return;
        }
        if (RecordableChanges() is not { } changes || (_trees.Count > 0 && RecordableTrees() is null))
        {
            if (_mode == UndoMode.Live)
            {
                CouldNotRecord("a file it writes cannot be named in a step", UndoUnrecordedChange.NothingWasChanged);
                throw new UndoStepRefusedException(new UndoRefusal(UndoRefusalKind.NotReadable),
                    "a file it writes cannot be named in a step");
            }
            WritePlainly();
            return;
        }
        var recomputes = new List<JsonObject>();
        foreach ((string full, long section) in _frontPages)
        {
            recomputes.Add(new JsonObject
            {
                ["kind"] = UndoOp.Recompute, ["maintainer"] = UndoOp.SectionFrontPage,
                ["path"] = RelativeOf(full)!, ["section"] = section,
            });
        }
        if (_members.Count > 0 || _trees.Count > 0)
        {
            MakeAsOps(changes, recomputes);
            return;
        }
        var draft = new UndoStepDraft
        {
            ActionKey = _maker.ActionKey,
            ActionArguments = new Dictionary<string, string>(StringComparer.Ordinal) { ["pageCount"] = changes.Count.ToString(System.Globalization.CultureInfo.InvariantCulture) },
            MadeBy = _maker.MadeBy,
            WorkingFolder = _root!,
            Course = _course,
            Section = _section,
            Class = "A",
            Holds = _holds,
            Changes = changes,
            Recomputes = recomputes,
        };
        HashSet<string> keptBefore = KeptOriginalsNow();
        UndoOutcome outcome;
        try { outcome = _door.Perform(draft); }
        catch (Exception error) when (_mode == UndoMode.Shadow && error is not (IOException or UnauthorizedAccessException))
        {
            // Shadow: nothing the list does may stop the action (rule.shadow).
            // The door handles every failure it knows, and nothing after its
            // swap throws (its re-derivations are caught there: review 1,
            // MEDIUM 4); an unforeseen one is thrown before its swap and
            // changed nothing, so the step is made plainly with its line.
            CouldNotRecord("the list could not be written", UndoUnrecordedChange.WentAhead, after: WritePlainlyQuietly);
            return;
        }
        Answer(outcome, keptBefore);
    }

    /// <summary>
    /// A step holding a JSON file planned member by member (#899 W8-11; the
    /// mac's <c>makeAsOps</c>): its files in the order planned, a member-planned
    /// file as its <c>editJSON</c> ops (no blob) and every other file by the
    /// door's own rule, then its recomputes, through the door that takes every
    /// kind (<see cref="UndoDoor.Perform(UndoOpsDraft)"/>), which plans them
    /// forward from the disk as it is at the make. In shadow, a list that
    /// cannot take the step leaves one trail line and the files are written
    /// as planned, all or none, unrecorded (the mac's <c>makeWithoutARecord</c>).
    /// </summary>
    private void MakeAsOps(List<UndoFileChange> changes, List<JsonObject> recomputes)
    {
        var ops = new JsonArray();
        var blobs = new List<byte[]>();
        int index = 0;
        foreach (string path in _order)
        {
            if (Same(_before[path], _after[path])) continue;
            UndoFileChange change = changes[index++];
            if (_members.TryGetValue(path, out IReadOnlyList<UndoMemberChange>? members))
            {
                foreach (UndoMemberChange member in members) ops.Add(member.Op(change.RelativePath));
                continue;
            }
            foreach (JsonNode? op in UndoLineOps.ForAFile(change.RelativePath, change.Before, change.After))
            {
                ops.Add(op!.DeepClone());
                if ((string?)op["kind"] != UndoOp.WriteFile) continue;
                if (change.Before is { } before) blobs.Add(before);
                if (change.After is { } after) blobs.Add(after);
            }
        }
        // Each folder made whole after the files, as the mac's makeAsOps
        // orders them, counted in pageCount as the mac counts it (W8-13).
        foreach ((JsonObject treeOp, List<byte[]> treeBlobs) in RecordableTrees()!)
        {
            ops.Add(treeOp);
            blobs.AddRange(treeBlobs);
        }
        foreach (JsonObject recompute in recomputes) ops.Add(recompute);
        var draft = new UndoOpsDraft
        {
            ActionKey = _maker.ActionKey,
            ActionArguments = new Dictionary<string, string>(StringComparer.Ordinal) { ["pageCount"] = (changes.Count + _trees.Count).ToString(System.Globalization.CultureInfo.InvariantCulture) },
            MadeBy = _maker.MadeBy,
            WorkingFolder = _root!,
            Course = _course,
            Section = _section,
            Class = "A",
            Holds = _holds,
            Ops = ops,
            Blobs = blobs,
        };
        HashSet<string> keptBefore = KeptOriginalsNow();
        UndoOutcome outcome;
        try { outcome = _door.Perform(draft); }
        catch (Exception error) when (_mode == UndoMode.Shadow && error is not (IOException or UnauthorizedAccessException))
        {
            // As in Make: an unforeseen failure of the list changed nothing.
            CouldNotRecord("the list could not be written", UndoUnrecordedChange.WentAhead, after: WritePlainlyQuietly);
            return;
        }
        // The door that takes every kind refuses, in either mode, a step the
        // list cannot take; in shadow the action still goes ahead (the mac's
        // makeAsOps), live it is refused before anything changes.
        if (outcome.Kind == UndoOutcomeKind.CouldNotRecordTheStep)
        {
            if (_mode == UndoMode.Live)
                throw new UndoStepRefusedException(new UndoRefusal(UndoRefusalKind.CouldNotWrite), "the list of changes could not be written");
            CouldNotRecord("the list could not take the step", UndoUnrecordedChange.WentAhead, after: WritePlainlyQuietly);
            return;
        }
        Answer(outcome, keptBefore);
    }

    /// <summary>What the door's outcome means for the action: nothing more to do, or the refusal it throws.</summary>
    private void Answer(UndoOutcome outcome, HashSet<string> keptBefore)
    {
        switch (outcome.Kind)
        {
            case UndoOutcomeKind.Applied or UndoOutcomeKind.AppliedWithoutARecord:
                return;
            case UndoOutcomeKind.ChangedNothing:
                RederiveTheFrontPages();
                return;
            case UndoOutcomeKind.Refused when outcome.LeftPartWay:
                throw LeftPartWay(outcome.Refusal!, keptBefore);
            case UndoOutcomeKind.Refused:
                throw new UndoStepRefusedException(outcome.Refusal!, Reason(outcome.Refusal!));
            case UndoOutcomeKind.StoppedByATest:
                // A kill point of a test or the harness, which may fall after
                // the swap: never said in the "Nothing was changed" family
                // (review 1, LOW).
                throw new InvalidOperationException("The step was stopped by a test.");
            case UndoOutcomeKind.AnotherChangeIsUnderWay:
                throw new UndoStepRefusedException(new UndoRefusal(UndoRefusalKind.FileIsInUse), "another change to this folder is under way");
            default:
                throw new UndoStepRefusedException(new UndoRefusal(UndoRefusalKind.CouldNotWrite), "the list of changes could not be written");
        }
    }

    /// <summary>
    /// Every planned file as a change the step can name, or null when one
    /// cannot be: no working folder, a path that leads outside it through a
    /// link, a target that is itself a link.
    /// </summary>
    private List<UndoFileChange>? RecordableChanges()
    {
        if (_root is null || !Directory.Exists(Path.Combine(_root, "courses"))) return null;
        var changes = new List<UndoFileChange>();
        foreach (string path in _order)
        {
            if (Same(_before[path], _after[path])) continue;
            if (RelativeOf(path) is not { } relative || !UndoPlaces.StaysInside(_root, relative)) return null;
            if (UndoLinks.Look(path) is UndoLinks.What.Link or UndoLinks.What.CannotLook) return null;
            changes.Add(new UndoFileChange(relative, _before[path], _after[path]));
        }
        foreach ((string full, _) in _frontPages)
        {
            if (RelativeOf(full) is not { } relative || !UndoPlaces.StaysInside(_root, relative)) return null;
        }
        return changes;
    }

    /// <summary>
    /// A step that cannot be named, made in shadow WITHOUT the list: staged
    /// and swapped in together, all or none (the mac's <c>writePlainly</c>),
    /// with one trail line saying what became of it.
    /// </summary>
    private void WritePlainly() =>
        CouldNotRecord("a file it writes cannot be named in a step", UndoUnrecordedChange.WentAhead, after: WritePlainlyQuietly);

    private void WritePlainlyQuietly()
    {
        var targets = new List<UndoSwapTarget>();
        foreach (string path in _order)
        {
            if (Same(_before[path], _after[path])) continue;
            // A link is written through, as File.WriteAllText wrote it: the
            // swap goes in at the file it leads to. A link the step REMOVES
            // (a rename of a linked page, #899 W7b2-1) is the link itself, as
            // File.Delete removed it, and so is a page written where it stood
            // (the next rename in the chain), as Save wrote a plain file
            // there once the link was gone: the file it leads to is never
            // touched.
            string place = _removedOnce.Contains(path) ? path : PlaceWritten(path);
            // Named by its full path: no working folder is there to name it
            // inside, and the refusal's sentence checks the page it names.
            targets.Add(new UndoSwapTarget(place, place, _before[path], _after[path]));
        }
        foreach ((string full, UndoTreeListing listing, Dictionary<string, byte[]> contents) in _trees)
            targets.Add(new UndoSwapTarget(full, full, null, null) { Change = new UndoSwapChange.MakeTree(listing, contents) });
        HashSet<string> keptBefore = KeptOriginalsNow();
        switch (UndoSwap.Swap(targets, UndoSwap.PlainLabel(), null, _plainSeams))
        {
            case UndoSwapResult.Refused { LeftPartWay: true } partWay:
                throw LeftPartWay(partWay.Refusal, keptBefore);
            case UndoSwapResult.Refused refused:
                throw new UndoStepRefusedException(refused.Refusal, Reason(refused.Refusal));
            case UndoSwapResult.StoppedByATest:
                throw new UndoStepRefusedException(new UndoRefusal(UndoRefusalKind.CouldNotWrite), "stopped by a test");
        }
        RederiveTheFrontPages();
    }

    /// <summary>The trail line, written once what became of the change is known (the mac's <c>UndoTrailHook.couldNotRecord</c>).</summary>
    private void CouldNotRecord(string why, UndoUnrecordedChange change, Action? after = null)
    {
        if (after is not null)
        {
            try { after(); }
            catch (UndoStepLeftPartWayException)
            {
                CouldNotRecord(why, UndoUnrecordedChange.StoppedPartWay);
                throw;
            }
            catch
            {
                CouldNotRecord(why, UndoUnrecordedChange.NothingWasChanged);
                throw;
            }
        }
        _trail?.Invoke(new UndoTrailLine(ActivityTrail.Event.UndoCouldNotRecordAStep, _course, _section,
                                         UndoTrail.CouldNotRecordWords(_maker.ActionKey, why, change)));
    }

    private void RederiveTheFrontPages()
    {
        if (_root is null) return;
        foreach ((string full, long section) in _frontPages)
        {
            if (RelativeOf(full) is not { } relative) continue;
            var op = UndoLineOps.Read(new JsonObject
            {
                ["kind"] = UndoOp.Recompute, ["maintainer"] = UndoOp.SectionFrontPage, ["path"] = relative, ["section"] = section,
            });
            // After the files are in: never a failure of the action (review 1, MEDIUM 4).
            try { _maintainers.Rederive(op, _root); }
            catch (Exception) { }
        }
    }

    /// <summary>The refusal as a teacher reads it after "Nothing was changed: ".</summary>
    private string Reason(UndoRefusal refusal)
    {
        string file = refusal.Path is { } path ? "“" + Path.GetFileName(path.Replace('/', Path.DirectorySeparatorChar)) + "”" : "a page";
        // A page marked read-only refuses its rename: said as a permission,
        // which is what it is, never as a full disk.
        string? refusedPage = refusal.Path is not { } named ? null
            : Path.IsPathRooted(named) ? named
            : _root is not null ? UndoDoor.FullPath(_root, named) : null;
        if (refusal.Kind == UndoRefusalKind.CouldNotWrite && refusedPage is not null
            && File.Exists(refusedPage) && File.GetAttributes(refusedPage).HasFlag(FileAttributes.ReadOnly))
            return "Plantoir doesn’t have permission to change one of them.";
        return refusal.Kind switch
        {
            UndoRefusalKind.ChangedSince => $"{file} was changed by another program while it was being saved.",
            UndoRefusalKind.FileIsInUse => $"{file} is in use by another program.",
            UndoRefusalKind.CannotTellNow => $"{file} could not be read just now.",
            // Room and permission are one refusal (couldNotWrite): the
            // sentence names both, so a folder denied by its permissions is
            // never told only that the disk may be full (review 1, LOW).
            UndoRefusalKind.CouldNotWrite when refusal.EveryKeptNameTaken =>
                $"nothing could be written beside {file}: every name Plantoir keeps an earlier copy of it under is already taken there.",
            UndoRefusalKind.CouldNotWrite => $"nothing could be written beside {file} (the disk may be full, or Plantoir may not have permission to write there).",
            _ => $"{file} could not be saved.",
        };
    }

    private UndoStepLeftPartWayException LeftPartWay(UndoRefusal refusal, HashSet<string> keptBefore)
    {
        var kept = new List<string>();
        foreach (string name in KeptOriginalsNow())
        {
            if (keptBefore.Contains(name)) continue;
            kept.Add(name);
            UndoSwap.HideAKeptFileLeft(name);
        }
        var said = new StringBuilder(Reason(refusal));
        foreach (string name in kept)
            said.Append(' ').Append(KeptSentence("“" + (UndoSwap.PlaceOfStagedName(Path.GetFileName(name)) ?? Path.GetFileName(name)) + "”", Path.GetFileName(name)));
        return new UndoStepLeftPartWayException(refusal, kept, said.ToString());
    }

    /// <summary>
    /// One kept original, said after a step refused part way:
    /// <c>shared-rules.json</c> → <c>undo.wording.keptBesideIt</c> (pinned by
    /// <c>UndoActionStepTests</c>). <paramref name="place"/> is already quoted.
    /// </summary>
    internal static string KeptSentence(string place, string kept) =>
        $"What {place} held before is kept beside it as the hidden file “{kept}”.";

    /// <summary>Where the plain write puts a planned file: the file a link leads to, or the planned path itself.</summary>
    private static string PlaceWritten(string path)
    {
        try
        {
            return UndoLinks.Look(path) == UndoLinks.What.Link && File.ResolveLinkTarget(path, returnFinalTarget: true) is { } final
                ? final.FullName : path;
        }
        catch (Exception error) when (error is IOException or UnauthorizedAccessException) { return path; }
    }

    /// <summary>
    /// Every kept original (<c>.&lt;name&gt;.plantoir-undo-…-orig</c>) beside a
    /// planned file now, and beside the file a planned link leads to, where
    /// the plain write keeps it (W7a part two, review 1, LOW 5).
    /// </summary>
    private HashSet<string> KeptOriginalsNow()
    {
        var found = new HashSet<string>(StringComparer.OrdinalIgnoreCase);
        var places = new List<string>();
        foreach (string planned in _order)
        {
            places.Add(planned);
            string written = PlaceWritten(planned);
            if (!string.Equals(written, planned, StringComparison.OrdinalIgnoreCase)) places.Add(written);
        }
        foreach (string path in places)
        {
            string? folder = Path.GetDirectoryName(path);
            if (folder is null || !Directory.Exists(folder)) continue;
            string prefix = "." + Path.GetFileName(path) + ".plantoir-undo-";
            try
            {
                foreach (string entry in Directory.EnumerateFiles(folder, prefix + "*"))
                {
                    if (entry.EndsWith("-orig", StringComparison.Ordinal)) found.Add(entry);
                }
            }
            catch (Exception error) when (error is IOException or UnauthorizedAccessException) { }
        }
        return found;
    }

    private string? RelativeOf(string fullPath)
    {
        if (_root is null) return null;
        string relative = Path.GetRelativePath(_root, fullPath);
        if (relative.StartsWith("..", StringComparison.Ordinal) || Path.IsPathRooted(relative)) return null;
        return relative.Replace('\\', '/');
    }

    private static bool Same(byte[]? left, byte[]? right) =>
        left is null ? right is null : right is not null && left.AsSpan().SequenceEqual(right);

    /// <summary>
    /// The text as <c>File.ReadAllText</c> reads it, a byte-order mark
    /// (UTF-8, UTF-16, UTF-32) detected and dropped, as <c>Save</c> read the
    /// before it gave today's undo (review 1, MEDIUM 3).
    /// </summary>
    private static string? TextOf(byte[]? bytes)
    {
        if (bytes is null) return null;
        using var reader = new StreamReader(new MemoryStream(bytes), new UTF8Encoding(false), detectEncodingFromByteOrderMarks: true);
        return reader.ReadToEnd();
    }
}
