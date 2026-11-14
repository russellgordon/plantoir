using System.Security.Cryptography;
using System.Text;

namespace Plantoir.Core.Undo;

/// <summary>
/// What is at an op's path now, as the check sees it (#899, W1).
///
/// <para><see cref="CannotReadNow"/> is Windows' own case and the reason this
/// type exists rather than a nullable byte array. A page another program holds
/// with no read sharing (<c>FileShare.None</c>), a cloud file that is not
/// available offline, a network share that dropped: the read FAILS, and the
/// page has not been changed by anyone. Reading that failure as "changed since"
/// would make ruling 13 clear the WHOLE list for a file that was merely busy.
/// So it ends the way the contract's <c>fileIsInUse</c> ends
/// (<c>stepCases</c>, <c>rule.clearing</c>: refused, the file named, nothing on
/// the list changed, to be tried again). The contract has no check case for it
/// yet; the proposed cases are the plan review's D1, amended.</para>
/// </summary>
internal abstract record UndoCurrent
{
    private UndoCurrent() { }

    internal sealed record Absent : UndoCurrent;
    internal sealed record Folder : UndoCurrent;
    internal sealed record Bytes(byte[] Content) : UndoCurrent;
    internal sealed record CannotReadNow(int ErrorCode) : UndoCurrent;

    /// <summary>
    /// Reads what is at this path, asking only to READ and sharing everything
    /// (<c>FileShare.ReadWrite | FileShare.Delete</c>), so a check never stands
    /// in the way of the teacher's editor or of another process's swap. It
    /// never asks for write or delete access: a probe that did would call
    /// every page Obsidian has open "cannot read now" (the plan review's M2,
    /// measured: a <c>FileShare.ReadWrite</c> holder does not stop a read).
    /// </summary>
    /// <param name="open">A seam for tests (a cloud or network failure); the real open by default.</param>
    internal static UndoCurrent Read(string fullPath, Func<string, Stream>? open = null)
    {
        if (Directory.Exists(fullPath)) return new Folder();
        try
        {
            using Stream stream = open is null
                ? new FileStream(fullPath, FileMode.Open, FileAccess.Read, FileShare.ReadWrite | FileShare.Delete)
                : open(fullPath);
            using var memory = new MemoryStream();
            stream.CopyTo(memory);
            return new Bytes(memory.ToArray());
        }
        catch (FileNotFoundException) { return new Absent(); }
        catch (DirectoryNotFoundException) { return new Absent(); }
        catch (UnauthorizedAccessException exception)
        {
            // A folder that appeared between the two looks, or an access
            // denial: neither is a change by hand.
            if (Directory.Exists(fullPath)) return new Folder();
            return new CannotReadNow(exception.HResult & 0xFFFF);
        }
        catch (IOException exception)
        {
            // A sharing or lock violation (32, 33), a cloud file not available
            // offline (the 362 to 400 range), a network error: the page is
            // there and has not been read, which is not the same as changed.
            if (!File.Exists(fullPath) && !Directory.Exists(fullPath) && IsNotFound(exception)) return new Absent();
            return new CannotReadNow(exception.HResult & 0xFFFF);
        }
    }

    private static bool IsNotFound(IOException exception) => (exception.HResult & 0xFFFF) is 2 or 3;
}

/// <summary>Where one op's target stands against what the op recorded.</summary>
internal enum UndoOpState
{
    /// <summary>As the step found it (the op's before).</summary>
    Before,
    /// <summary>As the step left it (the op's after).</summary>
    After,
    /// <summary>Neither: changed since, by hand or by something else.</summary>
    Neither,
    /// <summary>It could not be read at the moment (Windows): never "changed since".</summary>
    InUse,
    /// <summary>The op is not one this version can read: never acted on.</summary>
    NotReadable,
}

/// <summary>The contract's verdicts (<c>checkCasesHow</c>), plus the in-use refusal the contract already names.</summary>
internal enum UndoVerdict { CanUndo, AlreadyBack, CanRedo, AlreadyRedone, ChangedSince, NotReadable, FileIsInUse }

/// <summary>
/// "Has what this step changed been changed by hand since?", asked of what is
/// on the disk now and nothing else (#899 piece W1, <c>rule.contentNotTimes</c>).
///
/// <para>Content only, never a time: NTFS keeps an old creation time across a
/// replace within fifteen seconds and a copy keeps its modification time (the
/// Windows director's fact 6 on #899). An <c>editLine</c> entry is compared
/// byte for byte with carriage returns, comments and a byte-order mark kept,
/// after a STRICT UTF-8 decode (a page that is not UTF-8 is changed since for a
/// line op); a whole file by SHA-256 of its bytes. Never
/// <c>File.ReadAllText</c>: it drops a leading byte-order mark and replaces
/// invalid bytes with U+FFFD without a word, and either would make a changed
/// page read as unchanged.</para>
/// </summary>
internal static class UndoCheck
{
    private static readonly UTF8Encoding StrictUtf8 = new(encoderShouldEmitUTF8Identifier: false, throwOnInvalidBytes: true);

    /// <summary>SHA-256 in lower-case hexadecimal, the journal's name for content.</summary>
    internal static string Sha(byte[] content) => Convert.ToHexStringLower(SHA256.HashData(content));

    /// <summary>Strict UTF-8, keeping a byte-order mark as U+FEFF; null when the bytes are not UTF-8.</summary>
    internal static string? DecodeStrictly(byte[] content)
    {
        try { return StrictUtf8.GetString(content); }
        catch (DecoderFallbackException) { return null; }
    }

    internal static UndoOpState StateOf(UndoOp op, UndoCurrent current)
    {
        if (!op.Readable) return UndoOpState.NotReadable;
        if (current is UndoCurrent.CannotReadNow) return UndoOpState.InUse;
        switch (op.Kind)
        {
            case UndoOp.Recompute:
                // No check (opKinds.recompute): re-derived after the other ops, never compared.
                return UndoOpState.After;

            case UndoOp.WriteFile:
            {
                if (current is UndoCurrent.Folder) return UndoOpState.Neither;
                string? sha = current is UndoCurrent.Bytes bytes ? Sha(bytes.Content) : null;
                if (string.Equals(sha, op.BeforeSha, StringComparison.Ordinal)) return UndoOpState.Before;
                if (string.Equals(sha, op.AfterSha, StringComparison.Ordinal)) return UndoOpState.After;
                return UndoOpState.Neither;
            }

            case UndoOp.EditLine:
            {
                // A line op never reads a missing page as already back, and a
                // folder or an undecodable page is changed since.
                if (current is not UndoCurrent.Bytes bytes) return UndoOpState.Neither;
                if (DecodeStrictly(bytes.Content) is not { } text) return UndoOpState.Neither;
                UndoEntries.Reading reading = UndoEntries.ReadingOf(op.Key!, text);
                if (reading.Matches(op.Before)) return UndoOpState.Before;
                if (reading.Matches(op.After)) return UndoOpState.After;
                return UndoOpState.Neither;
            }

            default:
                return UndoOpState.NotReadable;
        }
    }

    internal static UndoVerdict UndoVerdictOf(UndoOpState state) => state switch
    {
        UndoOpState.After => UndoVerdict.CanUndo,
        UndoOpState.Before => UndoVerdict.AlreadyBack,
        UndoOpState.Neither => UndoVerdict.ChangedSince,
        UndoOpState.InUse => UndoVerdict.FileIsInUse,
        _ => UndoVerdict.NotReadable,
    };

    internal static UndoVerdict RedoVerdictOf(UndoOpState state) => state switch
    {
        UndoOpState.Before => UndoVerdict.CanRedo,
        UndoOpState.After => UndoVerdict.AlreadyRedone,
        UndoOpState.Neither => UndoVerdict.ChangedSince,
        UndoOpState.InUse => UndoVerdict.FileIsInUse,
        _ => UndoVerdict.NotReadable,
    };

    // ---- The whole step: all or nothing ----------------------------------

    /// <summary>What checking every op of a step comes to.</summary>
    internal abstract record PlanResult
    {
        private PlanResult() { }

        /// <summary>Every op can be moved: the new content of each file it touches (null: no file).</summary>
        internal sealed record Ready(IReadOnlyDictionary<string, byte[]?> Changes) : PlanResult;

        /// <summary>Something it changed was changed since: the first met is named, with how many others.</summary>
        internal sealed record ChangedSince(string First, int Others) : PlanResult;

        /// <summary>Content it needs is not in the list's store.</summary>
        internal sealed record ContentMissing(string Path) : PlanResult;

        /// <summary>A file could not be read at the moment: refused, the list unchanged.</summary>
        internal sealed record FileIsInUse(string Path) : PlanResult;

        /// <summary>An op this version cannot read: never acted on.</summary>
        internal sealed record NotReadable : PlanResult;
    }

    /// <summary>
    /// Checks EVERY op of a step before anything is written (ruling 4,
    /// <c>rule.stagedThenSwapped</c>), and works out what each file it touches
    /// becomes. Pure: it reads through <paramref name="read"/> and
    /// <paramref name="blob"/> and writes nothing.
    ///
    /// <para>An undo goes through the ops in reverse order, so the last op met
    /// first (<c>stepCases</c>: "an undo checks ops in reverse order"). A
    /// line op that cannot be placed is changed since, and a page found in the
    /// way is reported before content that is missing (U1's F2, which the mac
    /// fixes in U2 and Windows builds from the start). A read that fails at the
    /// moment is reported only when nothing is in the way: a page changed by
    /// hand settles the question whatever else is busy.</para>
    /// </summary>
    /// <param name="read">What is at an op's path now (relative path in, current out).</param>
    /// <param name="blob">A blob's bytes by name, or null when the store does not have it (or its bytes do not hash to its name).</param>
    internal static PlanResult Plan(IReadOnlyList<UndoOp> ops, bool backward,
                                    Func<string, UndoCurrent> read, Func<string, byte[]?> blob)
    {
        foreach (UndoOp op in ops)
        {
            if (!op.Readable) return new PlanResult.NotReadable();
        }

        var ordered = backward ? ops.Reverse().ToList() : ops.ToList();
        var original = new Dictionary<string, UndoCurrent>(StringComparer.Ordinal);
        var working = new Dictionary<string, UndoCurrent>(StringComparer.Ordinal);
        var inTheWay = new List<string>();
        string? missing = null;
        string? inUse = null;

        foreach (UndoOp op in ordered)
        {
            if (op.Kind == UndoOp.Recompute) continue;   // re-derived after, never checked (U2 runs it)
            string path = op.Path!;
            if (!original.ContainsKey(path))
            {
                original[path] = read(path);
                working[path] = original[path];
            }
            UndoOpState state = StateOf(op, working[path]);
            if (state == UndoOpState.InUse) { inUse ??= path; continue; }
            if (state == UndoOpState.Neither)
            {
                if (!inTheWay.Contains(path, StringComparer.Ordinal)) inTheWay.Add(path);
                continue;
            }
            UndoOpState wantedFrom = backward ? UndoOpState.After : UndoOpState.Before;
            if (state != wantedFrom) continue;   // already where this move takes it

            if (op.Kind == UndoOp.WriteFile)
            {
                string? targetSha = backward ? op.BeforeSha : op.AfterSha;
                if (targetSha is null) { working[path] = new UndoCurrent.Absent(); continue; }
                byte[]? content = blob(targetSha);
                if (content is null || !string.Equals(Sha(content), targetSha, StringComparison.Ordinal))
                {
                    missing ??= path;
                    continue;
                }
                working[path] = new UndoCurrent.Bytes(content);
            }
            else
            {
                string text = DecodeStrictly(((UndoCurrent.Bytes)working[path]).Content)!;
                string? source = backward ? op.After : op.Before;
                string? target = backward ? op.Before : op.After;
                if (UndoEntries.Move(op, source, target, text) is not { } moved)
                {
                    if (!inTheWay.Contains(path, StringComparer.Ordinal)) inTheWay.Add(path);
                    continue;
                }
                working[path] = new UndoCurrent.Bytes(StrictUtf8.GetBytes(moved));
            }
        }

        if (inTheWay.Count > 0) return new PlanResult.ChangedSince(inTheWay[0], inTheWay.Count - 1);
        if (missing is not null) return new PlanResult.ContentMissing(missing);
        if (inUse is not null) return new PlanResult.FileIsInUse(inUse);

        var changes = new Dictionary<string, byte[]?>(StringComparer.Ordinal);
        foreach ((string path, UndoCurrent was) in original)
        {
            UndoCurrent now = working[path];
            if (!SameContent(was, now)) changes[path] = now is UndoCurrent.Bytes bytes ? bytes.Content : null;
        }
        return new PlanResult.Ready(changes);
    }

    private static bool SameContent(UndoCurrent a, UndoCurrent b) => (a, b) switch
    {
        (UndoCurrent.Absent, UndoCurrent.Absent) => true,
        (UndoCurrent.Bytes x, UndoCurrent.Bytes y) => x.Content.AsSpan().SequenceEqual(y.Content),
        _ => false,
    };
}
