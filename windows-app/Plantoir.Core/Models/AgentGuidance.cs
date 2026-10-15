using System.ComponentModel;
using System.Security.Cryptography;
using System.Text;
using Newtonsoft.Json;

namespace Plantoir.Core.Models;

/// <summary>
/// Guidance for an assistant started at a working folder (#496 here; the
/// mac's #454, <c>AgentGuidance.swift</c>, ported line for line): the skills
/// under <c>.claude\skills\</c> and <c>.agents\skills\</c>, and a MANAGED
/// SECTION in <c>AGENTS.md</c> and <c>CLAUDE.md</c> at the working folder's
/// root that names them.
/// </summary>
/// <remarks>
/// <para>The rule for the two root files, which are often the teacher's own
/// (<c>shared-rules.json</c> → <c>printablePages.agentGuidance.rootFileCases</c>):
/// no file → write it, holding only Plantoir's section; Plantoir's markers
/// present → replace what is between them, nothing else; no markers → ASK
/// first, then append below the teacher's own text. A Not Now is remembered
/// for that file until the section's words change or the file goes; a file
/// is never appended to without a yes.</para>
///
/// <para>Written AFTER the toolchain copy, on its own outcome
/// (<see cref="ToolchainReadiness"/>): a failure here is logged, recorded on
/// the trail and shown as a quiet notice, and NEVER holds Preview, Deploy or
/// New Course back (the mac's implementation review S1).</para>
///
/// <para><b>Windows departures, each for a reason.</b> (1) The notice's
/// reason: .NET's IO messages carry the full path ("Access to the path
/// 'C:\Users\…' is denied."), so the notice says the SYSTEM's sentence for
/// the error code instead (<see cref="SystemReason"/>) — only for a
/// FACILITY_WIN32 code, because <c>Win32Exception</c> on any other gives
/// "Unknown error (0x…)" (plan review M6). (2) Every write is ATOMIC, a
/// temporary file moved over the old one, as the mac's <c>.atomic</c> is
/// (M7): this pass runs on its own task, which the quit path does not wait
/// for. (3) A file whose only difference from the current section is its
/// line endings is UNCHANGED: an editor that saves CRLF would otherwise have
/// the section rewritten on every launch (M7). (4) Files are read with a
/// STRICT UTF-8 decoder, so a file saved in another encoding cannot be read
/// — and is refused, never written over (addCases "cannot be read again").</para>
/// </remarks>
public static class AgentGuidance
{
    /// <summary>What to do with one root file.</summary>
    public enum RootFileKind { Write, Replace, Unchanged, Ask, Leave }

    /// <summary>What to do with one root file, and the text to write for Write and Replace.</summary>
    public sealed record RootFileAction(RootFileKind Kind, string? Text = null);

    /// <summary>A file waiting for the teacher's answer.</summary>
    public sealed record PendingAppend(string FileName, string FilePath, string Body)
    {
        /// <summary>What would be added, markers included, as the dialog shows it.</summary>
        public string Section => Block(Body);
    }

    /// <summary>What one pass did.</summary>
    public sealed class Outcome
    {
        public int Changed { get; set; }
        /// <summary>One line per file that could not be written: "place: reason".</summary>
        public List<string> Failures { get; } = [];
        /// <summary>The first failure's reason alone, for the notice a teacher reads (no path).</summary>
        public string? FirstReason { get; private set; }
        /// <summary>The teacher's own files, waiting for a yes.</summary>
        public List<PendingAppend> Pending { get; } = [];

        /// <summary>One failure: where (from the working folder down, forward slashes), and why.</summary>
        public void Note(string place, string reason)
        {
            Failures.Add(place + ": " + reason);
            FirstReason ??= WithoutFinalStop(reason);
        }
    }

    /// <summary>The two lines around Plantoir's section (contract: sectionStart, sectionEnd).</summary>
    public const string SectionStart =
        "<!-- BEGIN PLANTOIR: Plantoir writes and replaces everything between this line and END PLANTOIR. Your own text goes above or below. -->";
    public const string SectionEnd = "<!-- END PLANTOIR -->";

    /// <summary>The root files, in the order they are asked about.</summary>
    public static readonly IReadOnlyList<string> RootFiles = ["AGENTS.md", "CLAUDE.md"];

    /// <summary>Where each skill goes, from the working folder down.</summary>
    public static readonly IReadOnlyList<string> SkillHomes = [".claude", ".agents"];

    /// <summary>Said when the system gives no sentence of its own.</summary>
    public const string CouldNotBeWritten = "could not be written";

    private static readonly UTF8Encoding StrictUtf8 = new(encoderShouldEmitUTF8Identifier: false, throwOnInvalidBytes: true);

    // ---- The rule ------------------------------------------------------------

    /// <summary>A sentence without its final full stop, to sit inside brackets.</summary>
    public static string WithoutFinalStop(string text) => text.Trim().TrimEnd('.');

    /// <summary>The section, markers included.</summary>
    public static string Block(string body) => SectionStart + "\n" + body.TrimEnd('\n') + "\n" + SectionEnd;

    /// <summary>A short fingerprint of the section's words, so a Not Now holds only until the words change.</summary>
    public static string Signature(string body) =>
        Convert.ToHexString(SHA256.HashData(Encoding.UTF8.GetBytes(Block(body)))).ToLowerInvariant()[..16];

    /// <summary>What to do with a root file holding <paramref name="existing"/> (null: no file).</summary>
    public static RootFileAction Action(string? existing, string body, string? declinedSignature)
    {
        if (existing is null) return new(RootFileKind.Write, Block(body) + "\n");
        if (ReplacingSection(existing, body) is { } replaced)
        {
            if (replaced == existing || replaced.Replace("\r", "") == existing.Replace("\r", ""))
                return new(RootFileKind.Unchanged);
            return new(RootFileKind.Replace, replaced);
        }
        if (declinedSignature == Signature(body)) return new(RootFileKind.Leave);
        return new(RootFileKind.Ask);
    }

    /// <summary>
    /// The file with Plantoir's section replaced, or null when the file has no
    /// complete section. Anchored on the END line, taking the LAST start line
    /// before it: a stray start line above a real section is the teacher's
    /// text (the mac's fix review; rootFileCases' last case).
    /// </summary>
    public static string? ReplacingSection(string existing, string body)
    {
        int firstStart = existing.IndexOf(SectionStart, StringComparison.Ordinal);
        if (firstStart < 0) return null;
        int end = existing.IndexOf(SectionEnd, firstStart + SectionStart.Length, StringComparison.Ordinal);
        if (end < 0) return null;
        int start = existing.LastIndexOf(SectionStart, end - 1, end, StringComparison.Ordinal);
        if (start < 0) return null;
        return existing[..start] + Block(body) + existing[(end + SectionEnd.Length)..];
    }

    /// <summary>The teacher's file with the section added below their own text, one blank line between.</summary>
    public static string Appended(string existing, string body)
    {
        if (existing.Length == 0) return Block(body) + "\n";
        string joined = existing.EndsWith('\n') ? existing : existing + "\n";
        return joined + "\n" + Block(body) + "\n";
    }

    // ---- The pass --------------------------------------------------------------

    /// <summary>
    /// Writes the skills and settles the root files. <paramref name="declined"/>
    /// answers the stored Not Now signature for a file path, if any;
    /// <paramref name="forgetDeclined"/> is called when a file has gone, so a
    /// new one is written fresh.
    /// </summary>
    public static Outcome Write(string guidanceSource, string workspacePath,
                                Func<string, string?> declined, Action<string> forgetDeclined)
    {
        var outcome = new Outcome();
        string skillsSource = Path.Combine(guidanceSource, "skills");
        IEnumerable<string> skills;
        try { skills = Directory.Exists(skillsSource) ? Directory.EnumerateDirectories(skillsSource).OrderBy(p => p, StringComparer.Ordinal).ToList() : []; }
        catch { skills = []; }
        foreach (string skill in skills)
        {
            string name = Path.GetFileName(skill);
            if (name.StartsWith('.')) continue;
            foreach (string home in SkillHomes)
            {
                // The skill's folder is the app's whole: a true mirror INSIDE
                // it, and nothing else under .claude or .agents is touched.
                var copied = ToolchainMirror.SyncDirectory(skill, Path.Combine(workspacePath, home, "skills", name));
                outcome.Changed += copied.Changed;
                if (copied.Failed > 0)
                {
                    outcome.Note(home + "/skills/" + name,
                        copied.FirstError is { } error ? SystemReason(error) : CouldNotBeWritten);
                }
            }
        }
        foreach (string name in RootFiles)
        {
            string body;
            try { body = File.ReadAllText(Path.Combine(guidanceSource, name), StrictUtf8); }
            catch { continue; }
            string filePath = Path.Combine(workspacePath, name);
            string? existing = null;
            if (File.Exists(filePath))
            {
                try { existing = ReadStrict(filePath); }
                catch { outcome.Note(name, "could not be read"); continue; }
            }
            else
            {
                forgetDeclined(filePath);
            }
            var action = Action(existing, body, declined(filePath));
            switch (action.Kind)
            {
                case RootFileKind.Write:
                case RootFileKind.Replace:
                    try { WriteAtomically(filePath, action.Text!); outcome.Changed++; }
                    catch (Exception error) { outcome.Note(name, SystemReason(error)); }
                    break;
                case RootFileKind.Ask:
                    outcome.Pending.Add(new PendingAppend(name, filePath, body));
                    break;
            }
        }
        return outcome;
    }

    /// <summary>
    /// The teacher said Add: append the section, having read the file again
    /// (it may have changed while the dialog was open). Only a MISSING file
    /// reads as empty; one that is there and can no longer be read is
    /// REFUSED, because writing would replace the teacher's text with the
    /// section alone. Answers null on success, or the reason it failed.
    /// </summary>
    public static string? AppendAfterYes(PendingAppend pending)
    {
        string existing = "";
        if (File.Exists(pending.FilePath))
        {
            try { existing = ReadStrict(pending.FilePath); }
            catch { return "could not be read"; }
        }
        string text = ReplacingSection(existing, pending.Body) ?? Appended(existing, pending.Body);
        try { WriteAtomically(pending.FilePath, text); return null; }
        catch (Exception error) { return SystemReason(error); }
    }

    /// <summary>
    /// The system's own sentence for an IO failure, WITHOUT the path .NET
    /// puts in its message: <c>Win32Exception</c>'s text for a FACILITY_WIN32
    /// code ("Access is denied.", "Cannot create a file when that file already
    /// exists."), and <see cref="CouldNotBeWritten"/> for anything else.
    /// </summary>
    public static string SystemReason(Exception error)
    {
        int code = error.HResult;
        if ((error is IOException or UnauthorizedAccessException) && (code & unchecked((int)0xFFFF0000)) == unchecked((int)0x80070000))
        {
            string said = new Win32Exception(code & 0xFFFF).Message;
            if (!string.IsNullOrWhiteSpace(said) && !said.Contains(":\\", StringComparison.Ordinal)) return said;
        }
        return CouldNotBeWritten;
    }

    private static string ReadStrict(string path) => StrictUtf8.GetString(File.ReadAllBytes(path));

    /// <summary>A temporary file beside the target, moved over it: a crash leaves the old file or the new, never half of one.</summary>
    internal static void WriteAtomically(string path, string text)
    {
        string temporary = path + ".plantoir-" + Guid.NewGuid().ToString("N")[..8] + ".tmp";
        try
        {
            File.WriteAllBytes(temporary, new UTF8Encoding(false).GetBytes(text));
            File.Move(temporary, path, overwrite: true);
        }
        finally
        {
            try { if (File.Exists(temporary)) File.Delete(temporary); } catch { }
        }
    }

    // ---- The trail -------------------------------------------------------------

    /// <summary><c>asked before adding guidance to a file</c>: the file's NAME and the answer.</summary>
    public static string AskedLine(string fileName, bool added) =>
        "asked before adding Plantoir's section to " + fileName + " in the working folder — " + (added ? "added" : "not now");

    /// <summary><c>guidance for assistants could not be written</c>: how many, and the first.</summary>
    public static string CouldNotWriteLine(IReadOnlyList<string> failures)
    {
        string line = "could not write the guidance for assistants into the working folder: " + failures.Count + " problem(s)";
        if (failures.Count > 0) line += " — first: " + failures[0];
        return line;
    }
}

/// <summary>
/// The Not Now answers, file path → the section's signature, kept in the
/// app's own data folder (<c>agent-guidance-declined.json</c>) and deliberately
/// OUT of <see cref="AppSettings"/>, which other code rewrites whole. Paths
/// compare case-insensitively, as NTFS does.
/// </summary>
public static class AgentGuidanceDeclined
{
    private static readonly object Gate = new();

    /// <summary>Where the answers are kept.</summary>
    public static string FilePath => FilePathForTests ?? AppDataRoot.Combine("agent-guidance-declined.json");

    /// <summary>A test's own file, so a test never writes the real one. Null in the app.</summary>
    internal static string? FilePathForTests { get; set; }

    public static string? SignatureFor(string path)
    {
        lock (Gate) return Load().TryGetValue(Normal(path), out var signature) ? signature : null;
    }

    public static void Remember(AgentGuidance.PendingAppend pending)
    {
        lock (Gate)
        {
            var stored = Load();
            stored[Normal(pending.FilePath)] = AgentGuidance.Signature(pending.Body);
            Save(stored);
        }
    }

    public static void Forget(string path)
    {
        lock (Gate)
        {
            var stored = Load();
            if (stored.Remove(Normal(path))) Save(stored);
        }
    }

    private static string Normal(string path)
    {
        try { return Path.GetFullPath(path); } catch { return path; }
    }

    private static Dictionary<string, string> Load()
    {
        try
        {
            if (File.Exists(FilePath)
                && JsonConvert.DeserializeObject<Dictionary<string, string>>(File.ReadAllText(FilePath)) is { } read)
                return new Dictionary<string, string>(read, StringComparer.OrdinalIgnoreCase);
        }
        catch { }
        return new Dictionary<string, string>(StringComparer.OrdinalIgnoreCase);
    }

    private static void Save(Dictionary<string, string> stored)
    {
        try
        {
            Directory.CreateDirectory(Path.GetDirectoryName(FilePath)!);
            AgentGuidance.WriteAtomically(FilePath, JsonConvert.SerializeObject(stored, Formatting.Indented));
        }
        catch { }
    }
}

/// <summary>
/// What a teacher reads about the guidance (<c>printablePages.agentGuidance.words</c>).
/// Rule 1: no machinery words.
/// </summary>
public static class AgentGuidanceWording
{
    public const string ShowWhatIsAdded = "Show what would be added";
    public const string Add = "Add";
    public const string NotNow = "Not Now";
    public const string Dismiss = "Dismiss";
    public const string AskWhat =
        "Plantoir would like to add a short section at the end of it that points them to its guidance for writing pages — for example, how to make a page printable.";
    public const string AskYoursStays = "Your own text stays exactly as it is, above the new section.";

    public static string AskTitle(string file) => "Add a section to " + file + "?";

    public static string AskFound(string file) =>
        "This working folder already has " + file + ", a file that assistants such as Claude Code and Codex read before they start.";

    public static string CouldNotWrite(string reason) =>
        "Plantoir could not put its guidance for assistants into this folder (" + reason + "). Everything else works as usual.";
}
