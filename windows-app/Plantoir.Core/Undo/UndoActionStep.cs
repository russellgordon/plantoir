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
            foreach (string path in _order)
            {
                if (!Same(_before[path], _after[path])) return true;
            }
            return false;
        }
    }

    /// <summary>Each planned file that changes, with the text it held and holds (for today's in-memory undo, <c>UndoHistory</c>).</summary>
    internal IReadOnlyList<(string FullPath, string? Before, string? After)> ChangedFiles
    {
        get
        {
            var changed = new List<(string, string?, string?)>();
            foreach (string path in _order)
            {
                if (Same(_before[path], _after[path])) continue;
                changed.Add((_shownAs[path], TextOf(_before[path]), TextOf(_after[path])));
            }
            return changed;
        }
    }

    // ---- Functions -------------------------------------------------------------------

    /// <summary>Plans <paramref name="text"/> as the file's content, written as <c>File.WriteAllText</c> writes it (UTF-8, no byte-order mark).</summary>
    internal void Write(string fullPath, string text) => Plan(fullPath, new UTF8Encoding(false).GetBytes(text));

    /// <summary>The file's text as the step will leave it: what is planned, else the disk's.</summary>
    internal string ReadText(string fullPath)
    {
        string key = Path.GetFullPath(fullPath);
        if (_after.TryGetValue(key, out byte[]? planned))
            return planned is null ? throw new FileNotFoundException("A file this change removes.", fullPath) : TextOf(planned)!;
        return File.ReadAllText(fullPath);
    }

    /// <summary>The section's front page is kept true by its rule after the step (<c>recompute</c>, <c>sectionFrontPage</c>).</summary>
    internal void KeepsTheFrontPageTrue(long section, string fullPath) => _frontPages.Add((Path.GetFullPath(fullPath), section));

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
        if (RecordableChanges() is not { } changes)
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
            // The door handles every failure it knows; an unforeseen one,
            // thrown before its swap, changed nothing, so the step is made
            // plainly with its line.
            CouldNotRecord("the list could not be written", UndoUnrecordedChange.WentAhead, after: WritePlainlyQuietly);
            return;
        }
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
            // swap goes in at the file it leads to.
            string place = UndoLinks.Look(path) == UndoLinks.What.Link && File.ResolveLinkTarget(path, returnFinalTarget: true) is { } final
                ? final.FullName : path;
            targets.Add(new UndoSwapTarget(place, Path.GetFileName(path), _before[path], _after[path]));
        }
        HashSet<string> keptBefore = KeptOriginalsNow();
        switch (UndoSwap.Swap(targets, "shadow", null, _plainSeams))
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
            _maintainers.Rederive(op, _root);
        }
    }

    /// <summary>The refusal as a teacher reads it after "Nothing was changed: ".</summary>
    private string Reason(UndoRefusal refusal)
    {
        string file = refusal.Path is { } path ? "“" + Path.GetFileName(path.Replace('/', Path.DirectorySeparatorChar)) + "”" : "a page";
        // A page marked read-only refuses its rename: said as a permission,
        // which is what it is, never as a full disk.
        if (refusal.Kind == UndoRefusalKind.CouldNotWrite && refusal.Path is { } refused && _root is not null
            && File.Exists(UndoDoor.FullPath(_root, refused))
            && File.GetAttributes(UndoDoor.FullPath(_root, refused)).HasFlag(FileAttributes.ReadOnly))
            return "Plantoir doesn’t have permission to change one of them.";
        return refusal.Kind switch
        {
            UndoRefusalKind.ChangedSince => $"{file} was changed by another program while it was being saved.",
            UndoRefusalKind.FileIsInUse => $"{file} is in use by another program.",
            UndoRefusalKind.CannotTellNow => $"{file} could not be read just now.",
            UndoRefusalKind.CouldNotWrite => $"nothing could be written beside {file} (the disk may be full).",
            _ => $"{file} could not be saved.",
        };
    }

    private UndoStepLeftPartWayException LeftPartWay(UndoRefusal refusal, HashSet<string> keptBefore)
    {
        var kept = new List<string>();
        foreach (string name in KeptOriginalsNow())
        {
            if (!keptBefore.Contains(name)) kept.Add(name);
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

    /// <summary>Every kept original (<c>.&lt;name&gt;.plantoir-undo-…-orig</c>) beside a planned file now.</summary>
    private HashSet<string> KeptOriginalsNow()
    {
        var found = new HashSet<string>(StringComparer.OrdinalIgnoreCase);
        foreach (string path in _order)
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

    private static string? TextOf(byte[]? bytes) => bytes is null ? null : new UTF8Encoding(false).GetString(bytes);
}
