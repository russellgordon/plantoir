namespace Plantoir.Core.Assist;

/// <summary>
/// What this session changed, so a teacher who published the wrong class can
/// say "undo that" and get exactly that back.
///
/// A whole-course backup is taken before every write and is the durable safety
/// net, but it is a sledgehammer: restoring it puts the entire course back,
/// losing anything else done since. The common mistake is small and recent —
/// the wrong class, in a rush, thirty seconds ago — and it deserves a small
/// and recent fix.
///
/// Deliberately **in memory and session-scoped**. It lives as long as the
/// server process, which lives as long as the teacher's conversation, and goes
/// when that does. Nothing accumulates on disk, nothing has to be pruned, and
/// there is no second store of course content to fall out of step with the
/// files. For anything older than the conversation, the backups are the
/// answer, and they are what the undo tool points at once its own history runs
/// out.
///
/// Every entry stores what each file held BEFORE and what this session wrote
/// AFTER. The "after" is the important half: on undo, a file whose contents no
/// longer match what we wrote has been changed by someone else — Obsidian, the
/// teacher, another session — and putting our old copy back would destroy
/// their work. Those are reported and skipped rather than overwritten.
/// </summary>
public sealed class UndoHistory
{
    /// <summary>One operation, and the files it touched.</summary>
    public sealed record Entry(string Description, DateTime When, IReadOnlyDictionary<string, FileState> Files);

    /// <summary>What a file held before and after. Null means it did not exist.</summary>
    public readonly record struct FileState(string? Before, string? After);

    private readonly List<Entry> _entries = new();
    private Dictionary<string, FileState>? _open;
    private string _description = "";

    /// <summary>How many operations back a teacher can go before the backups take over.</summary>
    private const int MostRemembered = 20;

    public IReadOnlyList<Entry> Entries => _entries;

    /// <summary>
    /// Start recording an operation. Nested calls are ignored — the outermost
    /// wins — and the return says which this call was.
    /// </summary>
    /// <returns>
    /// True when this call actually opened the entry, false when one was
    /// already open. <see cref="Recording"/> uses it so that an inner scope
    /// cannot end or abandon an outer operation's entry.
    /// </returns>
    public bool Begin(string description)
    {
        if (_open is not null) return false;
        _open = new Dictionary<string, FileState>(StringComparer.OrdinalIgnoreCase);
        _description = description;
        return true;
    }

    /// <summary>
    /// Begin an operation whose entry cannot be left open, whatever happens.
    ///
    /// <para><b>Why a scope rather than a Begin/End pair.</b> Three tools
    /// called <see cref="Begin"/> and never <see cref="End"/>, and five more
    /// closed theirs only on the path where nothing threw — and the failure is
    /// silent in both directions. Nothing is recorded, so "undo that" tells a
    /// teacher nothing has been changed; and the entry stays OPEN, so the NEXT
    /// operation's files are swallowed into it and committed under the earlier
    /// description. A teacher who made room, published a class and asked to
    /// undo was told they had made room, and had the publish taken back with
    /// it.</para>
    ///
    /// <para>So the pairing is no longer something to remember:
    /// <c>using var recording = UndoHistory.Record(_undo, "…");</c> at the top,
    /// <c>recording.Done();</c> where the operation has finished. Anything that
    /// leaves without reaching <c>Done</c> — a throw, or a return added years
    /// later by somebody who never read this — abandons instead, which is the
    /// safe default rather than the lossy one. See
    /// <c>documentation/10-local-ai-assistant.md</c> for WHY abandoning is
    /// right when an operation threw partway, and what was rejected.</para>
    /// </summary>
    /// <param name="history">May be null: an MCP server with no history simply records nothing.</param>
    public static Recording Record(UndoHistory? history, string description) => new(history, description);

    /// <summary>One operation's recording, ended or abandoned by leaving its scope.</summary>
    public sealed class Recording : IDisposable
    {
        private readonly UndoHistory? _history;
        private readonly bool _owns;
        private bool _settled;

        internal Recording(UndoHistory? history, string description)
        {
            _history = history;
            _owns = history is not null && history.Begin(description);
        }

        /// <summary>The operation finished. Commit what it touched.</summary>
        public void Done()
        {
            if (_settled || !_owns) return;
            _settled = true;
            _history!.End();
        }

        /// <summary>
        /// Left without finishing, so nothing is remembered. A nested scope
        /// does nothing at all here: the outermost call owns the entry.
        /// </summary>
        public void Dispose()
        {
            if (_settled || !_owns) return;
            _settled = true;
            _history!.Abandon();
        }
    }

    /// <summary>
    /// Note a file about to be written. Called before the write, so the
    /// "before" is genuinely what was there.
    /// </summary>
    public void Touch(string path, string? before)
    {
        if (_open is null) return;
        // Only the FIRST before matters: if one operation writes a file twice,
        // undoing it should reach back past both writes.
        if (!_open.ContainsKey(path)) _open[path] = new FileState(before, null);
    }

    /// <summary>Note what was actually written, so a later change by someone else is detectable.</summary>
    public void Wrote(string path, string? after)
    {
        if (_open is null || !_open.TryGetValue(path, out var state)) return;
        _open[path] = state with { After = after };
    }

    /// <summary>Finish recording. An operation that changed nothing is not remembered.</summary>
    public void End()
    {
        if (_open is null) return;
        var touched = _open.Where(f => f.Value.Before != f.Value.After)
            .ToDictionary(f => f.Key, f => f.Value, StringComparer.OrdinalIgnoreCase);
        if (touched.Count > 0)
        {
            _entries.Add(new Entry(_description, DateTime.Now, touched));
            while (_entries.Count > MostRemembered) _entries.RemoveAt(0);
        }
        _open = null;
    }

    /// <summary>
    /// Remember an entry exactly as given, for the contract's undo rows
    /// (<c>undoFiles</c>): <see cref="End"/> drops a file whose BEFORE equals
    /// its AFTER, and one row is exactly that file.
    /// </summary>
    internal void Remember(Entry entry) => _entries.Add(entry);

    /// <summary>Abandon recording, for an operation that threw partway.</summary>
    public void Abandon() => _open = null;

    /// <summary>
    /// Put the most recent operation back. Each file gets ONE verdict
    /// (<see cref="UndoVerdict.Of"/>, #564 / mac #555): already back (nothing
    /// written, not counted, does not hold the entry), put back, or left alone
    /// because somebody else has changed it since — our copy of it is stale
    /// and writing it would destroy whatever they did. The entry comes off the
    /// list once nothing is left alone.
    /// </summary>
    public UndoResult Undo()
    {
        if (_entries.Count == 0)
            return new UndoResult(false, "This conversation hasn’t changed anything yet.",
                Array.Empty<string>(), Array.Empty<string>(), Array.Empty<string>());

        var entry = _entries[^1];
        var restored = new List<string>();
        var alreadyBack = new List<string>();
        var skipped = new List<string>();

        foreach (var (path, state) in entry.Files)
        {
            switch (UndoVerdict.Of(path, state))
            {
                case UndoVerdict.Kind.AlreadyBack:
                    alreadyBack.Add(path);
                    continue;
                case UndoVerdict.Kind.LeftAlone:
                    skipped.Add(path);
                    continue;
            }
            try
            {
                if (state.Before is null) File.Delete(path);
                else File.WriteAllText(path, state.Before);
                restored.Add(path);
            }
            // A write that fails is left alone, as the mac's is: the file
            // still holds what the change left, so the entry must stay.
            catch { skipped.Add(path); }
        }

        // Only forget the operation once nothing is left holding it. A
        // half-undone change stays on the list so the teacher can try again
        // after sorting out whatever is holding the other files — and the
        // files an earlier press put back no longer count against it (#564).
        bool cameOff = skipped.Count == 0;
        if (cameOff) _entries.RemoveAt(_entries.Count - 1);

        // Succeeded is the mac's `!restored.isEmpty || entryCameOff`: something
        // was written back, or the change is off the list (every file back).
        return new UndoResult(restored.Count > 0 || cameOff, entry.Description, restored, skipped, alreadyBack);
    }
}

/// <summary>
/// What an undo does with one saved file (#564, the mac's
/// <c>AssistUndoVerdict</c>, #555; the rows are <c>contracts/assist-cases.json</c>
/// → <c>undoFiles.files</c>). ONE rule, asked by <see cref="UndoHistory.Undo"/>
/// and by the start-of-year undo sheet before the teacher agrees, so the sheet
/// can never list a page differently from how the undo treats it.
/// </summary>
public static class UndoVerdict
{
    public enum Kind
    {
        /// <summary>The disk holds what the change left: write BEFORE back (or remove the file when BEFORE is null).</summary>
        PutBack,

        /// <summary>
        /// The disk already holds BEFORE — an earlier press, or the teacher,
        /// put it back. Nothing is written, it is not counted as put back, and
        /// it does not hold the change on the list. Until #564 it read as
        /// "edited since", so a change taken back in part never came off.
        /// </summary>
        AlreadyBack,

        /// <summary>Anything else: the teacher has changed it since, and newer work is never thrown away.</summary>
        LeftAlone,
    }

    /// <summary>
    /// Which of the three this file is, read off the disk now. BEFORE is
    /// compared first, so a row the change left as it found it (all absent,
    /// or BEFORE equal to AFTER) is already back rather than a removal that
    /// fails and holds the change for ever.
    /// </summary>
    public static Kind Of(string path, UndoHistory.FileState state) =>
        Holds(path, state.Before) ? Kind.AlreadyBack
        : Holds(path, state.After) ? Kind.PutBack
        : Kind.LeftAlone;

    /// <summary>
    /// Whether the disk holds this copy. Null means NOTHING is at the path —
    /// not "could not be read as text": a folder, or a file that is not UTF-8,
    /// matches neither copy (the contract's <c>currentKind</c> rows). Text
    /// means a readable UTF-8 file with exactly this text, ONE leading byte-
    /// order mark dropped first, because the saved copies came from
    /// <c>File.ReadAllText</c>, which drops it (the mac's
    /// <c>String(contentsOf:encoding:)</c> drops it too).
    /// </summary>
    internal static bool Holds(string path, string? expected)
    {
        bool isFile = File.Exists(path);
        if (expected is null) return !isFile && !Directory.Exists(path);
        if (!isFile) return false;
        return ReadStrictly(path) is { } now && now == expected;
    }

    private static readonly System.Text.UTF8Encoding Strict = new(encoderShouldEmitUTF8Identifier: false, throwOnInvalidBytes: true);

    /// <summary>The file's text, or null when it cannot be read or is not UTF-8.</summary>
    internal static string? ReadStrictly(string path)
    {
        try
        {
            byte[] bytes = File.ReadAllBytes(path);
            int start = bytes.Length >= 3 && bytes[0] == 0xEF && bytes[1] == 0xBB && bytes[2] == 0xBF ? 3 : 0;
            return Strict.GetString(bytes, start, bytes.Length - start);
        }
        catch { return null; }
    }
}

/// <summary>Which sentence answers an undo (#564): the names are <c>assist-wording.json</c> keys.</summary>
public enum UndoAnswer { NothingToUndo, Undid, UndidPartly, CouldNotUndo }

/// <summary>How an undo went: what was written back, what was left alone, and what was already back.</summary>
public sealed record UndoResult(
    bool Succeeded, string Description, IReadOnlyList<string> Restored, IReadOnlyList<string> Skipped,
    IReadOnlyList<string> AlreadyBack)
{
    /// <summary>
    /// Every file back → undid (even when this press wrote nothing, its files
    /// all already back); written and left → undidPartly; nothing written and
    /// something left → couldNotUndo; no files at all → nothingToUndo.
    /// </summary>
    public UndoAnswer Answer =>
        Restored.Count == 0 && Skipped.Count == 0 && AlreadyBack.Count == 0 ? UndoAnswer.NothingToUndo
        : Skipped.Count == 0 ? UndoAnswer.Undid
        : Restored.Count == 0 ? UndoAnswer.CouldNotUndo
        : UndoAnswer.UndidPartly;
}
