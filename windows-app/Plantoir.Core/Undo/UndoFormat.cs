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

    /// <summary>Every blob this op names: <c>blobs</c>, and writeFile's two hashes.</summary>
    internal IReadOnlyList<string> Blobs { get; init; } = [];

    internal const string WriteFile = "writeFile";
    internal const string EditLine = "editLine";
    internal const string Recompute = "recompute";

    /// <summary>The one maintainer U1 defines (<c>opKinds.recompute</c>).</summary>
    internal const string SectionFrontPage = "sectionFrontPage";
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

    /// <summary>Every path its ops name, for an <c>interrupted</c> line that closes it unsettled.</summary>
    internal IEnumerable<string> Paths
    {
        get
        {
            var seen = new HashSet<string>(StringComparer.Ordinal);
            foreach (UndoOp op in Ops)
            {
                if (op.Path is { } path && seen.Add(path)) yield return path;
            }
        }
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
        // A step with ops that have paths and no working folder cannot say where they are.
        if (folder is null && ops.Any(op => op.Path is not null)) readable = false;

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

    /// <summary>One op. Never throws: anything it cannot read makes the op unreadable.</summary>
    internal static UndoOp ReadOp(JsonElement element)
    {
        if (element.ValueKind != JsonValueKind.Object) return new UndoOp { Kind = null, Readable = false };
        string? kind = element.TryGetProperty("kind", out JsonElement kindElement) && kindElement.ValueKind == JsonValueKind.String
            ? kindElement.GetString()
            : null;
        bool readable = kind is UndoOp.WriteFile or UndoOp.EditLine or UndoOp.Recompute && !HasDuplicateKeys(element);

        // `blobs` binds every kind, a kind this version does not know included,
        // so a pruner that cannot read the op still keeps what it names.
        var blobs = new List<string>();
        if (element.TryGetProperty("blobs", out JsonElement blobsElement))
        {
            if (blobsElement.ValueKind == JsonValueKind.Array)
            {
                foreach (JsonElement blob in blobsElement.EnumerateArray())
                {
                    if (blob.ValueKind == JsonValueKind.String) blobs.Add(blob.GetString()!);
                    else readable = false;
                }
            }
            else readable = false;
        }

        if (!OptionalString(element, "path", out string? path)) readable = false;
        if (kind is UndoOp.WriteFile or UndoOp.EditLine or UndoOp.Recompute && !UndoPath.IsWithinTheRules(path)) readable = false;

        bool okBefore = OptionalString(element, "before", out string? before);
        bool okAfter = OptionalString(element, "after", out string? after);
        bool okKey = OptionalString(element, "key", out string? key);
        bool okAfterKey = OptionalString(element, "afterKey", out string? afterKey);
        bool okBeforeSha = OptionalString(element, "beforeSha", out string? beforeSha);
        bool okAfterSha = OptionalString(element, "afterSha", out string? afterSha);
        bool okMaintainer = OptionalString(element, "maintainer", out string? maintainer);
        bool okSection = OptionalWholeNumber(element, "section", out long? section);
        bool created = false;
        bool okCreated = true;
        if (element.TryGetProperty("createdTheBlock", out JsonElement createdElement))
        {
            if (createdElement.ValueKind == JsonValueKind.True) created = true;
            else if (createdElement.ValueKind is JsonValueKind.False or JsonValueKind.Null) created = false;
            else okCreated = false;
        }

        // A field of the wrong type makes a known op unreadable whatever its kind
        // (the reference model, readable_op, checks these four for every kind).
        if (!okBefore || !okAfter || !okKey || !okAfterKey) readable = false;

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

        return new UndoOp
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
            Blobs = blobs.Distinct(StringComparer.Ordinal).ToList(),
        };
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
