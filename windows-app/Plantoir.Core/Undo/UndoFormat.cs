using System.Text;
using System.Text.Json;

namespace Plantoir.Core.Undo;

/// <summary>The events of <c>undoJournal.events</c>.</summary>
internal enum UndoEvent
{
    Begin, Applied, RolledBack, Interrupted, Undoing, Undone, Redoing, Redone,
    Failed, Dropped, Pruned, Cleared, Note,
}

/// <summary>What a <c>failed</c>, <c>rolledBack</c> or <c>interrupted</c> line ended.</summary>
internal enum UndoPhase { Begin, Undoing, Redoing }

/// <summary>
/// The process a <c>begin</c>, <c>undoing</c> or <c>redoing</c> names, as
/// written. <c>Host</c> is for a person and never compared; <c>Started</c> is
/// the writing platform's own spelling, compared only by that platform.
/// </summary>
internal sealed record UndoProcess(string? Host, long Pid, string? Name, string? Started);

/// <summary>A step's <c>workingFolder</c>: its identifier and the canonical path it had.</summary>
internal sealed record UndoWorkingFolder(string? Id, string? PathAtTheTime);

/// <summary>
/// <c>madeBy</c>, split at its ENDS (<c>stepKeys.madeBy</c>): who is the word
/// before the FIRST colon, the id what follows the LAST, and the client name
/// whatever is between (it may hold colons). An open string: nothing here
/// rejects a value it does not know.
/// </summary>
internal readonly record struct UndoMadeBy(string Who, string? Client, string? Id)
{
    internal static UndoMadeBy Split(string madeBy)
    {
        int first = madeBy.IndexOf(':', StringComparison.Ordinal);
        if (first < 0) return new UndoMadeBy(madeBy, null, null);
        int last = madeBy.LastIndexOf(':');
        string? client = last > first ? madeBy[(first + 1)..last] : null;
        return new UndoMadeBy(madeBy[..first], client, madeBy[(last + 1)..]);
    }
}

/// <summary>
/// One op of a step, as far as this version can read it
/// (<c>undoJournal.opKinds</c>). <see cref="Readable"/> false means the op is
/// KEPT and never acted on: an unknown kind (every reserved kind included), a
/// field of the wrong type, a path that breaks the rules, a
/// <c>recompute</c> whose maintainer is not one this version knows.
/// </summary>
internal sealed record UndoOp
{
    internal required string? Kind { get; init; }
    internal required bool Readable { get; init; }
    internal string? Path { get; init; }

    // editLine
    internal string? Key { get; init; }
    internal string? Before { get; init; }
    internal string? After { get; init; }
    internal string? AfterKey { get; init; }
    internal bool CreatedTheBlock { get; init; }

    // writeFile
    internal string? BeforeSha { get; init; }
    internal string? AfterSha { get; init; }

    // recompute
    internal string? Maintainer { get; init; }
    internal long? Section { get; init; }

    // replaceText (with Before and After): the text either side of the hunk
    internal string? ContextBefore { get; init; }
    internal string? ContextAfter { get; init; }

    // editJSON: the members walked from the top-level object down
    internal IReadOnlyList<string>? KeyPath { get; init; }

    /// <summary><c>editJSON</c> and <c>external</c>: the value before and after, any JSON (null: no such member, or not set; <see cref="UndoJson.Null"/>: JSON's null).</summary>
    internal UndoJson? ValueBefore { get; init; }
    internal UndoJson? ValueAfter { get; init; }

    // move: where the item was and where it went; a file's SHA-256 (never a blob)
    internal string? From { get; init; }
    internal string? To { get; init; }
    internal string? Sha { get; init; }

    /// <summary>A folder's <c>move</c>, <c>createTree</c> and <c>removeTree</c>: the SHA-256 of the folder's listing (<see cref="UndoTreeListing"/>).</summary>
    internal string? ListingSha { get; init; }

    /// <summary><c>external</c>: what outside every working folder it changed (<c>preference:&lt;name&gt;</c>).</summary>
    internal string? Target { get; init; }

    /// <summary>Every blob this op names: <c>blobs</c>, writeFile's two hashes, and a listing's hash.</summary>
    internal IReadOnlyList<string> Blobs { get; init; } = [];

    /// <summary>Every path inside the working folder the op names: its <c>path</c>, or a move's <c>from</c> and <c>to</c>; none for an <c>external</c> op.</summary>
    internal IEnumerable<string> PathsNamed
    {
        get
        {
            if (Path is not null) yield return Path;
            if (From is not null) yield return From;
            if (To is not null) yield return To;
        }
    }

    /// <summary>The name recovery and a refusal use for the op's place: its path, a move's <c>from</c>, or an external op's target.</summary>
    internal string PlaceName => Path ?? From ?? Target ?? Kind ?? "";

    /// <summary>
    /// A move, a tree or an external op: judged and changed AS A WHOLE against
    /// what is there now, on its own, never folded into another op's file
    /// (<c>opKinds.wholeOps</c>).
    /// </summary>
    internal bool IsWhole => Readable && Kind is Move or CreateTree or RemoveTree or External;

    internal const string WriteFile = "writeFile";
    internal const string EditLine = "editLine";
    internal const string Recompute = "recompute";
    internal const string ReplaceText = "replaceText";
    internal const string EditJson = "editJSON";
    internal const string Move = "move";
    internal const string CreateTree = "createTree";
    internal const string RemoveTree = "removeTree";
    internal const string External = "external";

    /// <summary>The kinds this version reads (U1's three and U2's six); every other kind, U5's reserved two included, is one it does not know.</summary>
    internal static readonly IReadOnlySet<string> KindsThisVersionKnows = new HashSet<string>(StringComparer.Ordinal)
    {
        WriteFile, EditLine, Recompute, ReplaceText, EditJson, Move, CreateTree, RemoveTree, External,
    };

    /// <summary>The <c>external</c> families this version reads and writes, by the part before the first colon.</summary>
    internal static readonly IReadOnlySet<string> ExternalFamiliesThisVersionKnows = new HashSet<string>(StringComparer.Ordinal) { "preference" };

    /// <summary>The one maintainer U1 defines (<c>opKinds.recompute</c>).</summary>
    internal const string SectionFrontPage = "sectionFrontPage";

    /// <summary>
    /// Whether two places are the same, or one is a folder holding the other,
    /// compared part by part WITHOUT regard to case (the mac's U2b hard review,
    /// MEDIUM 7): NTFS, like a Mac's volume, takes <c>a.json</c> and
    /// <c>A.json</c> for one place, so a move between them, or two ops naming
    /// them, is a step this version cannot read. That is also why a move that
    /// changes only case is never made as two renames here.
    /// </summary>
    internal static bool PlacesOverlap(string first, string second) =>
        PartInside(first, second) is not null || PartInside(second, first) is not null;

    /// <summary>
    /// Whether <paramref name="edit"/> is an edit (a <c>writeFile</c>, an
    /// <c>editLine</c>, a <c>replaceText</c> or an <c>editJSON</c>) of the item
    /// a <c>move</c> moved, or of a file inside the folder it moved, named at
    /// the NEW place and naming nothing inside the old one (the mac's
    /// <c>UndoOp.moveCarries</c>, U4b; <c>opKinds.wholeOps</c>' one exception;
    /// #899 W8-2). Such an edit is made, and redone, after the move and taken
    /// back before it, and the move is judged as if it were taken back.
    /// Whether it comes AFTER the move in the step is the caller's to check.
    /// "At or inside" is <see cref="PartInside"/>, the one comparison. A
    /// capitalisation-only move (piece 5) and a link's move (piece 6) carry
    /// nothing here yet: the first fails the last test (its two places
    /// overlap), and the second is not readable on Windows.
    /// </summary>
    internal static bool MoveCarries(UndoOp move, UndoOp edit)
    {
        if (move.Kind != Move || !move.Readable || move.From is not { } from || move.To is not { } to || edit.Path is not { } path) return false;
        if (edit.Kind is not (WriteFile or EditLine or ReplaceText or EditJson)) return false;
        if (edit.From is not null || edit.To is not null || edit.Target is not null) return false;
        if (PartInside(to, path) is null) return false;
        return !PlacesOverlap(from, path);
    }

    /// <summary>The place <paramref name="path"/>, named inside a move's <paramref name="to"/>, had before the move: the same path under its <paramref name="from"/> (the mac's <c>placeBeforeTheMove</c>).</summary>
    internal static string PlaceBeforeTheMove(string path, string from, string to) =>
        PartInside(to, path) is not { } inside ? path : inside.Length == 0 ? from : from + "/" + inside;

    /// <summary>
    /// Where a teacher finds the item this op names now, going this way: a
    /// <c>move</c>'s <c>to</c> before it is undone and its <c>from</c> before
    /// it is redone (the mac's <c>placeAsFound</c>, U4b); <see cref="PlaceName"/>
    /// for every other op.
    /// </summary>
    internal string PlaceAsFound(bool backward) =>
        Kind == Move && From is { } from && To is { } to ? (backward ? to : from) : PlaceName;

    /// <summary>
    /// The part of <paramref name="path"/> inside <paramref name="place"/>,
    /// spelled as <paramref name="path"/> spells it: "" when it is the place
    /// itself, null when it is neither the place nor inside it (the mac's
    /// <c>UndoOp.partInside</c>, U4b2-9; #899 W8-2). Compared part by part
    /// (split on <c>/</c>), each part WITHOUT regard to case, as NTFS takes
    /// them: <c>Renamed/a.md</c> is inside <c>renamed</c>, and
    /// <c>Mediahouse/a.md</c> is not inside <c>Media</c>. The ONE comparison
    /// for "at or inside" (W8 COMMON, lesson 6): <see cref="PlacesOverlap"/>,
    /// whether a move carries an edit, and every later use.
    /// </summary>
    internal static string? PartInside(string place, string path)
    {
        string[] placeParts = place.Split('/');
        string[] pathParts = path.Split('/');
        if (pathParts.Length < placeParts.Length) return null;
        for (int index = 0; index < placeParts.Length; index++)
        {
            if (!string.Equals(placeParts[index].ToLowerInvariant(), pathParts[index].ToLowerInvariant(), StringComparison.Ordinal)) return null;
        }
        return string.Join('/', pathParts, placeParts.Length, pathParts.Length - placeParts.Length);
    }
}

/// <summary>
/// A step, as its <c>begin</c> line wrote it (<c>undoJournal.stepKeys</c>).
/// <see cref="Readable"/> false is <c>unknown.unreadableStep</c>: the step moves
/// through the fold like any other, but is never undone, redone or settled,
/// and is a barrier at its seq.
/// </summary>
internal sealed record UndoStep
{
    internal required long Seq { get; init; }
    internal required bool Readable { get; init; }
    internal DateTimeOffset? MadeAt { get; init; }
    internal IReadOnlyList<UndoOp> Ops { get; init; } = [];
    internal UndoWorkingFolder? WorkingFolder { get; init; }
    internal string? Course { get; init; }
    internal long? Section { get; init; }
    internal string? Class { get; init; }
    internal string? Holds { get; init; }
    internal string? MadeBy { get; init; }
    internal string? ActionKey { get; init; }
    internal IReadOnlyDictionary<string, string> ActionArguments { get; init; } =
        new Dictionary<string, string>(StringComparer.Ordinal);

    /// <summary>
    /// The blobs it keeps while it is kept: for a readable step every op's
    /// <see cref="UndoOp.Blobs"/>; for one this version cannot read, every
    /// 64-character lower-case hexadecimal name its begin line's text holds
    /// (<c>unknown.deleting</c>).
    /// </summary>
    internal IReadOnlyList<string> Blobs { get; init; } = [];

    /// <summary>Every path its ops name (a move's two included), for an <c>interrupted</c> line that closes it unsettled and for the tidy of its staged files.</summary>
    internal IEnumerable<string> Paths
    {
        get
        {
            var seen = new HashSet<string>(StringComparer.Ordinal);
            foreach (UndoOp op in Ops)
            {
                foreach (string path in op.PathsNamed)
                {
                    if (seen.Add(path)) yield return path;
                }
            }
        }
    }

    /// <summary>
    /// Every path the tidy of its staged files looks beside: <see cref="Paths"/>,
    /// and each edit a move carries also where it is before the move
    /// (<see cref="UndoOp.PlaceBeforeTheMove"/>), so the step's own files
    /// inside a moved folder are found wherever the folder is now (U4b, M1;
    /// #899 W8-3).
    /// </summary>
    internal IEnumerable<string> PathsToTidy
    {
        get
        {
            var seen = new HashSet<string>(StringComparer.Ordinal);
            foreach (string path in Paths)
            {
                if (seen.Add(path)) yield return path;
            }
            foreach ((string carried, UndoOp move) in UndoCheck.Carriers(Ops))
            {
                string before = UndoOp.PlaceBeforeTheMove(carried, move.From!, move.To!);
                if (seen.Add(before)) yield return before;
            }
        }
    }

    /// <summary>
    /// <c>opKinds.wholeOps</c>: no other op of the step names a whole op's
    /// places (a move's two, a tree's folder or anything inside it) or its
    /// target. A step that breaks it is one this version cannot read: a
    /// barrier, never undone in a guessed order. The one exception: an edit a
    /// move carries (<see cref="UndoOp.MoveCarries"/>), after the move; one
    /// inside the move's <c>from</c>, or before it, is still a barrier.
    /// </summary>
    internal static bool WholeOpsStandAlone(IReadOnlyList<UndoOp> ops)
    {
        for (int index = 0; index < ops.Count; index++)
        {
            UndoOp op = ops[index];
            if (!op.IsWhole) continue;
            for (int other = 0; other < ops.Count; other++)
            {
                if (other == index) continue;
                UndoOp second = ops[other];
                if (op.Target is { } target && string.Equals(second.Target, target, StringComparison.Ordinal)) return false;
                // An edit inside what a move moved, named at its new place
                // and written after it, is the one op that may share a
                // move's place (opKinds.wholeOps' order; #899 W8-2).
                if (other > index && UndoOp.MoveCarries(op, second)) continue;
                foreach (string mine in op.PathsNamed)
                {
                    foreach (string theirs in second.PathsNamed)
                    {
                        if (UndoOp.PlacesOverlap(mine, theirs)) return false;
                    }
                }
            }
        }
        return true;
    }
}

/// <summary>
/// One line of a segment, read leniently. A line this version cannot read is
/// <see cref="Readable"/> false and is KEPT (<c>unknown.unreadableLine</c>):
/// its seq, when it has a whole number for one, counts for the highest seq, it
/// is a barrier at that seq or at its <see cref="Place"/>, and the blob names
/// its text holds are kept.
/// </summary>
internal sealed record UndoLine
{
    internal required bool Readable { get; init; }
    internal long? Seq { get; init; }
    internal UndoEvent Event { get; init; }
    internal UndoPhase? Phase { get; init; }
    internal DateTimeOffset? At { get; init; }
    internal UndoStep? Step { get; init; }
    internal UndoProcess? Process { get; init; }
    internal string? Reason { get; init; }

    /// <summary>For an unreadable line: the blob names its text holds.</summary>
    internal IReadOnlyList<string> BlobNamesInText { get; init; } = [];

    /// <summary>Which segment it is in (its number, from 1) and its place in the whole journal (from 0).</summary>
    internal int Segment { get; init; }
    internal long Place { get; init; }
}

/// <summary>
/// The lenient reader of one journal line (<c>file-formats.json</c> →
/// <c>undoJournal</c>, #899 piece W1).
///
/// <para><b>The rule it is built round: what it cannot read it KEEPS, and never
/// skips.</b> The mac's first reader was typed and threw on a field it did not
/// expect; the line was skipped as if absent, and Undo then took back the step
/// BELOW a newer one. So nothing here throws: a line that is not what this
/// version writes comes back as a line (or a step, or an op) marked
/// unreadable, with whatever could be read of its seq and its blob
/// names.</para>
///
/// <para>Read with <see cref="JsonDocument"/>, never a typed deserialiser.
/// Bytes are decoded as strict UTF-8 (a line that is not is unreadable); a
/// carriage return before the line feed is JSON white space after the object
/// and changes nothing, since readers never compare a line's bytes. A key it
/// does not know is ignored. A key that appears twice in one object is read as
/// unreadable at that level (the line, the step or the op): JSON does not say
/// which of the two is meant, <see cref="JsonDocument"/> would silently keep
/// one, and "when in doubt, keep and do not act" is the contract's rule.</para>
/// </summary>
internal static class UndoFormat
{
    private static readonly UTF8Encoding StrictUtf8 = new(encoderShouldEmitUTF8Identifier: false, throwOnInvalidBytes: true);

    private static readonly JsonDocumentOptions Options = new()
    {
        AllowTrailingCommas = false,
        CommentHandling = JsonCommentHandling.Disallow,
        MaxDepth = 64,
    };

    internal static readonly IReadOnlyDictionary<string, UndoEvent> Events = new Dictionary<string, UndoEvent>(StringComparer.Ordinal)
    {
        ["begin"] = UndoEvent.Begin,
        ["applied"] = UndoEvent.Applied,
        ["rolledBack"] = UndoEvent.RolledBack,
        ["interrupted"] = UndoEvent.Interrupted,
        ["undoing"] = UndoEvent.Undoing,
        ["undone"] = UndoEvent.Undone,
        ["redoing"] = UndoEvent.Redoing,
        ["redone"] = UndoEvent.Redone,
        ["failed"] = UndoEvent.Failed,
        ["dropped"] = UndoEvent.Dropped,
        ["pruned"] = UndoEvent.Pruned,
        ["cleared"] = UndoEvent.Cleared,
        ["note"] = UndoEvent.Note,
    };

    private static readonly IReadOnlyDictionary<string, UndoPhase> Phases = new Dictionary<string, UndoPhase>(StringComparer.Ordinal)
    {
        ["begin"] = UndoPhase.Begin,
        ["undoing"] = UndoPhase.Undoing,
        ["redoing"] = UndoPhase.Redoing,
    };

    /// <summary>The two values of <c>holds</c> this version knows; absent is readable too.</summary>
    internal static readonly IReadOnlySet<string> HoldsKnown = new HashSet<string>(StringComparer.Ordinal) { "section", "course" };

    /// <summary>One line's bytes, without its line feed (a carriage return before it is allowed).</summary>
    internal static UndoLine Parse(ReadOnlySpan<byte> bytes, int segment = 1, long place = 0)
    {
        string text;
        try { text = StrictUtf8.GetString(bytes); }
        catch (DecoderFallbackException)
        {
            return Unreadable(null, BlobNames(Encoding.Latin1.GetString(bytes)), segment, place);
        }
        return Parse(text, segment, place);
    }

    /// <summary>One line's text, without its line feed.</summary>
    internal static UndoLine Parse(string text, int segment = 1, long place = 0)
    {
        JsonDocument document;
        try { document = JsonDocument.Parse(text, Options); }
        catch (JsonException) { return Unreadable(null, BlobNames(text), segment, place); }

        using (document)
        {
            JsonElement root = document.RootElement;
            if (root.ValueKind != JsonValueKind.Object) return Unreadable(null, BlobNames(text), segment, place);

            long? seq = WholeNumber(root, "seq");
            Func<IReadOnlyList<string>> names = () => BlobNames(text);   // scanned only for what cannot be read
            if (HasDuplicateKeys(root)) return Unreadable(seq, names(), segment, place);
            if (!IsTheNumberOne(root)) return Unreadable(seq, names(), segment, place);
            if (!root.TryGetProperty("event", out JsonElement eventElement)
                || eventElement.ValueKind != JsonValueKind.String
                || !Events.TryGetValue(eventElement.GetString()!, out UndoEvent kind))
                return Unreadable(seq, names(), segment, place);

            // Every event needs a whole-number seq. A note too (events.note):
            // without one it is an unreadable line, a barrier at its place.
            if (seq is null) return Unreadable(null, names(), segment, place);

            DateTimeOffset? at = root.TryGetProperty("at", out JsonElement atElement) && atElement.ValueKind == JsonValueKind.String
                ? UndoMoment.Parse(atElement.GetString())
                : null;

            if (kind == UndoEvent.Note)
            {
                // Passed over whatever else it carries: a phase or a reason of
                // any value leaves it a note.
                return new UndoLine { Readable = true, Seq = seq, Event = kind, At = at, Segment = segment, Place = place };
            }

            UndoPhase? phase = null;
            if (kind is UndoEvent.Failed or UndoEvent.RolledBack or UndoEvent.Interrupted)
            {
                if (!root.TryGetProperty("phase", out JsonElement phaseElement)
                    || phaseElement.ValueKind != JsonValueKind.String
                    || !Phases.TryGetValue(phaseElement.GetString()!, out UndoPhase known))
                    return Unreadable(seq, names(), segment, place);
                phase = known;
            }

            UndoStep? step = null;
            if (kind == UndoEvent.Begin)
            {
                if (!root.TryGetProperty("step", out JsonElement stepElement) || stepElement.ValueKind != JsonValueKind.Object)
                    return Unreadable(seq, names(), segment, place);
                if (WholeNumber(stepElement, "seq") is not { } stepSeq || stepSeq != seq.Value)
                    return Unreadable(seq, names(), segment, place);
                step = ReadStep(stepElement, stepSeq, names);
            }

            UndoProcess? process = kind is UndoEvent.Begin or UndoEvent.Undoing or UndoEvent.Redoing
                && root.TryGetProperty("process", out JsonElement processElement)
                ? ReadProcess(processElement)
                : null;

            string? reason = root.TryGetProperty("reason", out JsonElement reasonElement) && reasonElement.ValueKind == JsonValueKind.String
                ? reasonElement.GetString()
                : null;

            return new UndoLine
            {
                Readable = true,
                Seq = seq,
                Event = kind,
                Phase = phase,
                At = at,
                Step = step,
                Process = process,
                Reason = reason,
                Segment = segment,
                Place = place,
            };
        }
    }

    private static UndoLine Unreadable(long? seq, IReadOnlyList<string> names, int segment, long place) =>
        new() { Readable = false, Seq = seq, BlobNamesInText = names, Segment = segment, Place = place };

    // ---- The step and its ops -------------------------------------------

    private static UndoStep ReadStep(JsonElement element, long seq, Func<IReadOnlyList<string>> namesInText)
    {
        bool readable = !HasDuplicateKeys(element);

        DateTimeOffset? madeAt = null;
        if (element.TryGetProperty("madeAt", out JsonElement madeAtElement) && madeAtElement.ValueKind == JsonValueKind.String)
            madeAt = UndoMoment.Parse(madeAtElement.GetString());
        if (madeAt is null) readable = false;   // required, and the limits need it

        var ops = new List<UndoOp>();
        if (element.TryGetProperty("ops", out JsonElement opsElement) && opsElement.ValueKind == JsonValueKind.Array)
        {
            foreach (JsonElement opElement in opsElement.EnumerateArray())
            {
                UndoOp op = ReadOp(opElement);
                if (!op.Readable) readable = false;
                ops.Add(op);
            }
        }
        else
        {
            readable = false;   // required
        }

        UndoWorkingFolder? folder = null;
        if (element.TryGetProperty("workingFolder", out JsonElement folderElement))
        {
            if (folderElement.ValueKind == JsonValueKind.Object && !HasDuplicateKeys(folderElement)
                && OptionalString(folderElement, "id", out string? id) && OptionalString(folderElement, "pathAtTheTime", out string? pathAtTheTime))
                folder = new UndoWorkingFolder(id, pathAtTheTime);
            else
                readable = false;
        }
        // A step with ops that name paths and no working folder cannot say
        // where they are; a step of external ops alone needs none (wholeOps).
        if (folder is null && ops.Any(op => op.PathsNamed.Any())) readable = false;
        if (readable && !UndoStep.WholeOpsStandAlone(ops)) readable = false;

        if (!OptionalString(element, "course", out string? course)) readable = false;
        if (!OptionalWholeNumber(element, "section", out long? section)) readable = false;
        if (!OptionalString(element, "class", out string? klass)) readable = false;     // an open string
        if (!OptionalString(element, "madeBy", out string? madeBy)) readable = false;   // an open string
        if (!OptionalString(element, "holds", out string? holds)) readable = false;
        if (holds is not null && !HoldsKnown.Contains(holds)) readable = false;

        string? actionKey = null;
        var arguments = new Dictionary<string, string>(StringComparer.Ordinal);
        if (element.TryGetProperty("action", out JsonElement actionElement))
        {
            if (actionElement.ValueKind != JsonValueKind.Object || HasDuplicateKeys(actionElement)
                || !OptionalString(actionElement, "key", out actionKey))
            {
                readable = false;
            }
            else if (actionElement.TryGetProperty("arguments", out JsonElement argumentsElement))
            {
                if (argumentsElement.ValueKind != JsonValueKind.Object || HasDuplicateKeys(argumentsElement)) readable = false;
                else
                {
                    foreach (JsonProperty argument in argumentsElement.EnumerateObject())
                    {
                        if (argument.Value.ValueKind == JsonValueKind.String) arguments[argument.Name] = argument.Value.GetString()!;
                        else readable = false;
                    }
                }
            }
        }

        IReadOnlyList<string> blobs;
        if (readable)
        {
            var kept = new List<string>();
            foreach (UndoOp op in ops) kept.AddRange(op.Blobs);
            blobs = kept.Distinct(StringComparer.Ordinal).ToList();
        }
        else
        {
            blobs = namesInText();
        }

        return new UndoStep
        {
            Seq = seq,
            Readable = readable,
            MadeAt = madeAt,
            Ops = ops,
            WorkingFolder = folder,
            Course = course,
            Section = section,
            Class = klass,
            Holds = holds,
            MadeBy = madeBy,
            ActionKey = actionKey,
            ActionArguments = arguments,
            Blobs = blobs,
        };
    }

    /// <summary>
    /// One op. Never throws: anything it cannot read makes the op unreadable.
    /// A key of the wrong type makes a known op unreadable whatever its kind
    /// (the mac's <c>UndoLenient</c>); a kind's own rules are then
    /// <see cref="ShapeIsKnown"/>'s, the mac's <c>UndoOp.shapeIsKnown</c>.
    /// </summary>
    internal static UndoOp ReadOp(JsonElement element)
    {
        if (element.ValueKind != JsonValueKind.Object) return new UndoOp { Kind = null, Readable = false };
        string? kind = element.TryGetProperty("kind", out JsonElement kindElement) && kindElement.ValueKind == JsonValueKind.String
            ? kindElement.GetString()
            : null;
        bool readable = kind is not null && UndoOp.KindsThisVersionKnows.Contains(kind) && !HasDuplicateKeys(element);

        // `blobs` binds every kind, a kind this version does not know included,
        // so a pruner that cannot read the op still keeps what it names.
        var blobs = new List<string>();
        List<string>? listedBlobs = null;
        if (element.TryGetProperty("blobs", out JsonElement blobsElement) && blobsElement.ValueKind != JsonValueKind.Null)
        {
            listedBlobs = [];
            if (blobsElement.ValueKind == JsonValueKind.Array)
            {
                foreach (JsonElement blob in blobsElement.EnumerateArray())
                {
                    if (blob.ValueKind == JsonValueKind.String) { blobs.Add(blob.GetString()!); listedBlobs.Add(blob.GetString()!); }
                    else readable = false;
                }
            }
            else readable = false;
        }

        if (!OptionalString(element, "path", out string? path)) readable = false;

        // editJSON's and external's before and after are ANY JSON, null
        // included (a member holding null is not a member that is absent);
        // every other kind's are strings.
        bool valuesAreJson = kind is UndoOp.EditJson or UndoOp.External;
        string? before = null, after = null;
        UndoJson? valueBefore = null, valueAfter = null;
        if (valuesAreJson)
        {
            if (!OptionalJson(element, "before", out valueBefore)) readable = false;
            if (!OptionalJson(element, "after", out valueAfter)) readable = false;
        }
        else
        {
            if (!OptionalString(element, "before", out before)) readable = false;
            if (!OptionalString(element, "after", out after)) readable = false;
        }
        if (!OptionalString(element, "key", out string? key)) readable = false;
        if (!OptionalString(element, "afterKey", out string? afterKey)) readable = false;
        bool okBeforeSha = OptionalString(element, "beforeSha", out string? beforeSha);
        bool okAfterSha = OptionalString(element, "afterSha", out string? afterSha);
        bool okMaintainer = OptionalString(element, "maintainer", out string? maintainer);
        bool okSection = OptionalWholeNumber(element, "section", out long? section);
        if (!OptionalString(element, "contextBefore", out string? contextBefore)) readable = false;
        if (!OptionalString(element, "contextAfter", out string? contextAfter)) readable = false;
        if (!OptionalString(element, "from", out string? from)) readable = false;
        if (!OptionalString(element, "to", out string? to)) readable = false;
        if (!OptionalString(element, "sha", out string? sha)) readable = false;
        if (!OptionalString(element, "listingSha", out string? listingSha)) readable = false;
        if (!OptionalString(element, "target", out string? target)) readable = false;
        List<string>? keyPath = null;
        if (element.TryGetProperty("keyPath", out JsonElement keyPathElement) && keyPathElement.ValueKind != JsonValueKind.Null)
        {
            if (keyPathElement.ValueKind != JsonValueKind.Array) readable = false;
            else
            {
                keyPath = [];
                foreach (JsonElement part in keyPathElement.EnumerateArray())
                {
                    if (part.ValueKind == JsonValueKind.String) keyPath.Add(part.GetString()!);
                    else readable = false;
                }
            }
        }
        bool created = false;
        bool okCreated = true;
        if (element.TryGetProperty("createdTheBlock", out JsonElement createdElement))
        {
            if (createdElement.ValueKind == JsonValueKind.True) created = true;
            else if (createdElement.ValueKind is JsonValueKind.False or JsonValueKind.Null) created = false;
            else okCreated = false;
        }
        // `element` (an array element of editJSON) and `heldBy` (a removeTree
        // held outside the journal) are later pieces' meanings: an op carrying
        // either is one this version cannot undo by its own rule.
        if (kind == UndoOp.EditJson && element.TryGetProperty("element", out _)) readable = false;
        if (kind == UndoOp.RemoveTree && element.TryGetProperty("heldBy", out _)) readable = false;

        switch (kind)
        {
            case UndoOp.EditLine:
                if (!okCreated || key is null) readable = false;
                if (before is null && after is null) readable = false;   // at least one present
                break;
            case UndoOp.WriteFile:
                if (!okBeforeSha || !okAfterSha) readable = false;
                if (beforeSha is not null && !IsBlobName(beforeSha)) readable = false;
                if (afterSha is not null && !IsBlobName(afterSha)) readable = false;
                if (beforeSha is not null) blobs.Add(beforeSha);
                if (afterSha is not null) blobs.Add(afterSha);
                break;
            case UndoOp.Recompute:
                // A maintainer a reader does not know is a re-derivation it
                // cannot run: never undone with it skipped (opKinds.recompute).
                if (!okMaintainer || !okSection || !string.Equals(maintainer, UndoOp.SectionFrontPage, StringComparison.Ordinal)) readable = false;
                break;
        }
        // A tree's listing is one of its blobs, so the folder can be made
        // again. A folder move's is not: "The moved content is never a blob:
        // the item itself is what moves" (opKinds.move). Named as one, the
        // door's vetting refused every folder move as not readable, as the
        // mac's JournaledWrite.vet did until U4b (#899 W8-2).
        if (listingSha is not null && kind != UndoOp.Move) blobs.Add(listingSha);

        var op = new UndoOp
        {
            Kind = kind,
            Readable = readable,
            Path = path,
            Key = key,
            Before = before,
            After = after,
            AfterKey = afterKey,
            CreatedTheBlock = created,
            BeforeSha = beforeSha,
            AfterSha = afterSha,
            Maintainer = maintainer,
            Section = section,
            ContextBefore = contextBefore,
            ContextAfter = contextAfter,
            KeyPath = keyPath,
            ValueBefore = valueBefore,
            ValueAfter = valueAfter,
            From = from,
            To = to,
            Sha = sha,
            ListingSha = listingSha,
            Target = target,
            Blobs = blobs.Distinct(StringComparer.Ordinal).ToList(),
        };
        return readable && ShapeIsKnown(op, listedBlobs) ? op : op with { Readable = false };
    }

    /// <summary>
    /// Whether an op of a kind this version knows has the shape that kind
    /// needs (the mac's <c>UndoOp.shapeIsKnown</c>): every blob a blob's name,
    /// safe paths, and the fields of its kind.
    /// </summary>
    private static bool ShapeIsKnown(UndoOp op, IReadOnlyList<string>? listedBlobs)
    {
        foreach (string name in op.Blobs)
        {
            if (!IsBlobName(name)) return false;
        }
        if (op.Sha is not null && !IsBlobName(op.Sha)) return false;
        switch (op.Kind)
        {
            case UndoOp.Move:
                // No path: from and to follow path's rules, differ, and neither
                // holds the other; exactly one of a file's sha and a folder's listingSha.
                if (op.Path is not null || op.From is null || op.To is null) return false;
                if (!UndoPath.IsWithinTheRules(op.From) || !UndoPath.IsWithinTheRules(op.To)) return false;
                if (UndoOp.PlacesOverlap(op.From, op.To)) return false;
                return (op.Sha is not null) != (op.ListingSha is not null);
            case UndoOp.External:
            {
                if (op.Path is not null || op.Target is not { } target) return false;
                int colon = target.IndexOf(':', StringComparison.Ordinal);
                if (colon < 0) return false;
                string family = target[..colon];
                if (target.Length == colon + 1 || !UndoOp.ExternalFamiliesThisVersionKnows.Contains(family)) return false;
                return op.ValueBefore is not null || op.ValueAfter is not null;
            }
        }
        if (!UndoPath.IsWithinTheRules(op.Path)) return false;
        switch (op.Kind)
        {
            case UndoOp.ReplaceText:
                // Every part present (an empty string is a part), and the two
                // windows differ, or the hunk could never tell its states apart.
                if (op.Before is null || op.After is null || op.ContextBefore is null || op.ContextAfter is null) return false;
                return !string.Equals(op.ContextBefore + op.Before + op.ContextAfter, op.ContextBefore + op.After + op.ContextAfter, StringComparison.Ordinal);
            case UndoOp.EditJson:
                if (op.KeyPath is not { Count: > 0 }) return false;
                if (op.ValueBefore is null && op.ValueAfter is null) return false;
                return !UndoJson.Same(op.ValueBefore, op.ValueAfter);
            case UndoOp.CreateTree:
            case UndoOp.RemoveTree:
                return op.ListingSha is not null && listedBlobs is not null && listedBlobs.Contains(op.ListingSha, StringComparer.Ordinal);
        }
        return true;
    }

    private static UndoProcess? ReadProcess(JsonElement element)
    {
        if (element.ValueKind != JsonValueKind.Object) return null;
        if (WholeNumber(element, "pid") is not { } pid) return null;
        OptionalString(element, "host", out string? host);
        OptionalString(element, "name", out string? name);
        OptionalString(element, "started", out string? started);
        return new UndoProcess(host, pid, name, started);
    }

    // ---- Small readers ----------------------------------------------------

    private static bool IsTheNumberOne(JsonElement root) =>
        root.TryGetProperty("v", out JsonElement v) && v.ValueKind == JsonValueKind.Number
        && v.TryGetInt64(out long version) && version == 1;

    private static long? WholeNumber(JsonElement element, string name) =>
        element.TryGetProperty(name, out JsonElement value) && value.ValueKind == JsonValueKind.Number
        && value.TryGetInt64(out long number)
            ? number
            : null;

    /// <summary>False only when the key is there with a value that is neither a string nor null.</summary>
    private static bool OptionalString(JsonElement element, string name, out string? value)
    {
        value = null;
        if (!element.TryGetProperty(name, out JsonElement found) || found.ValueKind == JsonValueKind.Null) return true;
        if (found.ValueKind != JsonValueKind.String) return false;
        value = found.GetString();
        return true;
    }

    /// <summary>Any JSON value, null included (absent: null; JSON's null: <see cref="UndoJson.Null"/>). False when it is there and no double can hold a number in it.</summary>
    private static bool OptionalJson(JsonElement element, string name, out UndoJson? value)
    {
        value = null;
        if (!element.TryGetProperty(name, out JsonElement found)) return true;
        value = UndoJson.From(found);
        return value is not null;
    }

    private static bool OptionalWholeNumber(JsonElement element, string name, out long? value)
    {
        value = null;
        if (!element.TryGetProperty(name, out JsonElement found) || found.ValueKind == JsonValueKind.Null) return true;
        if (found.ValueKind != JsonValueKind.Number || !found.TryGetInt64(out long number)) return false;
        value = number;
        return true;
    }

    private static bool HasDuplicateKeys(JsonElement element)
    {
        var seen = new HashSet<string>(StringComparer.Ordinal);
        foreach (JsonProperty property in element.EnumerateObject())
        {
            if (!seen.Add(property.Name)) return true;
        }
        return false;
    }

    /// <summary>A blob's name: exactly 64 lower-case hexadecimal characters.</summary>
    internal static bool IsBlobName(string text)
    {
        if (text.Length != 64) return false;
        foreach (char character in text)
        {
            if (!IsLowerHex(character)) return false;
        }
        return true;
    }

    private static bool IsLowerHex(char character) => character is >= '0' and <= '9' or >= 'a' and <= 'f';

    /// <summary>
    /// Every run of exactly 64 lower-case hexadecimal characters standing alone
    /// in a line's text (<c>unknown.deleting</c>): neither neighbour is a
    /// letter or a digit, so a longer run, or a name inside a word, is not one.
    /// </summary>
    internal static IReadOnlyList<string> BlobNames(string text)
    {
        var found = new List<string>();
        int index = 0;
        while (index < text.Length)
        {
            if (!IsLowerHex(text[index])) { index++; continue; }
            int start = index;
            while (index < text.Length && IsLowerHex(text[index])) index++;
            bool alone = (start == 0 || !char.IsAsciiLetterOrDigit(text[start - 1]))
                && (index == text.Length || !char.IsAsciiLetterOrDigit(text[index]));
            if (index - start == 64 && alone)
            {
                string name = text[start..index];
                if (!found.Contains(name, StringComparer.Ordinal)) found.Add(name);
            }
        }
        return found;
    }
}
