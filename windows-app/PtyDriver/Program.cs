using System.Text;
using System.Text.RegularExpressions;
using Plantoir.Core.Scripting;

// PtyDriver — runs a command under a ConPTY, logs cleaned output, and
// auto-answers prompts from scripted rules. A test harness for the
// launchers, exercising the same ConPtyProcess the app uses.
//
// Usage:
//   PtyDriver --cwd DIR [--log FILE] [--raw-log FILE] [--rule "regex=>reply"]...
//             [--timeout SEC] [--settle MS] -- COMMAND LINE...
//
// TWO logs, and which one a caller wants is not obvious:
//
//   --log      the app's own TranscriptBuilder view - what a teacher would
//              have seen in the console. Readable, and LOSSY BY DESIGN: it
//              drops PLANTOIR_HEALTH: marker lines (TranscriptBuilder.PushLine)
//              and keeps only the last MaximumRetainedLines.
//   --raw-log  every line, nothing dropped and nothing forgotten, with ANSI
//              control sequences stripped so it can be grepped. This is what
//              an automated harness must assert on; verify-deploy.ps1 does.
//
// Added 2026-09-09 with the second half of GitHub issue #123. Before it there
// was only --log, and a harness asserting on it was reading a file that could
// silently stop: an npm build can exceed 4,000 lines, and past that every
// later line was dropped (see the note on lastLoggedLineCount below).
//
// A rule fires when the transcript's last non-empty line matches the regex,
// output has been silent for the settle window, and NEW output has arrived
// since the last reply (the mac app's respondedLength guard). Replies:
// text (sent + Enter), {ENTER}, {RIGHT} (ESC[C), {Q}. Safety valve: 300 replies.

var rules = new List<(Regex Pattern, string Reply)>();
string? cwd = null, logPath = null, rawLogPath = null;
int timeoutSeconds = 3600, settleMs = 1200;
var command = new List<string>();
for (int i = 0; i < args.Length; i++)
{
    switch (args[i])
    {
        case "--raw": break;   // legacy no-op: raw is the only mode
        case "--cwd": cwd = args[++i]; break;
        case "--log": logPath = args[++i]; break;
        case "--raw-log": rawLogPath = args[++i]; break;
        case "--timeout": timeoutSeconds = int.Parse(args[++i]); break;
        case "--settle": settleMs = int.Parse(args[++i]); break;
        case "--rule":
            var parts = args[++i].Split("=>", 2);
            rules.Add((new Regex(parts[0], RegexOptions.IgnoreCase), parts.Length > 1 ? parts[1] : ""));
            break;
        case "--":
            for (int j = i + 1; j < args.Length; j++) command.Add(args[j]);
            i = args.Length;
            break;
    }
}
if (cwd is null || command.Count == 0)
{
    Console.Error.WriteLine("PtyDriver --cwd DIR [--log FILE] [--rule re=>reply]... -- command...");
    return 2;
}

string commandLine = string.Join(" ", command.Select(c => c.Contains(' ') ? $"\"{c}\"" : c));
using var log = logPath is null ? null : new StreamWriter(logPath, append: false, Encoding.UTF8) { AutoFlush = true };
using var rawLog = rawLogPath is null ? null : new StreamWriter(rawLogPath, append: false, Encoding.UTF8) { AutoFlush = true };

// Whatever has arrived since the last newline. The raw log is written a
// COMPLETE LINE AT A TIME rather than chunk by chunk, because stripping ANSI
// escapes from an arbitrary read boundary can cut a sequence in half and leave
// its tail as visible rubbish in the file. A escape sequence does not span a
// newline in any output this drives.
var rawPending = new StringBuilder();
// (char)10 and (char)13 rather than escape sequences, which is not style: a
// backslash-n written here has twice been turned into an actual newline
// inside the quotes by the tooling this file has passed through, and the
// compiler error that follows names a column rather than the cause.
const char Newline = (char)10;
const char CarriageReturn = (char)13;
void WriteRaw(string text)
{
    if (rawLog is null) return;
    rawPending.Append(text);
    while (true)
    {
        string pending = rawPending.ToString();
        int newline = pending.IndexOf(Newline);
        if (newline < 0) break;
        string line = pending[..newline].TrimEnd(CarriageReturn);
        rawLog.WriteLine(TranscriptBuilder.StripControlSequences(line).TrimEnd());
        rawPending.Clear();
        rawPending.Append(pending[(newline + 1)..]);
    }
}
void FlushRaw()
{
    if (rawLog is null || rawPending.Length == 0) return;
    rawLog.WriteLine(TranscriptBuilder.StripControlSequences(rawPending.ToString()).TrimEnd());
    rawPending.Clear();
}

void Note(string s) { Console.WriteLine(s); log?.WriteLine(s); rawLog?.WriteLine(s); }

Note($"# PtyDriver: {commandLine}");
Note($"# cwd: {cwd}");

using var pty = ConPtyProcess.Start(commandLine, cwd);
var transcript = new TranscriptBuilder();
var decoder = Encoding.UTF8.GetDecoder();
var outputLock = new object();
DateTime lastOutputAt = DateTime.UtcNow;
long lastLoggedLineCount = 0;

var reader = new Thread(() =>
{
    var buffer = new byte[8192];
    var chars = new char[8192];
    while (true)
    {
        int n = pty.ReadOutput(buffer);
        if (n <= 0) break;
        int charCount = decoder.GetChars(buffer, 0, n, chars, 0);
        var text = new string(chars, 0, charCount);
        lock (outputLock)
        {
            WriteRaw(text);
            transcript.Append(text);
            lastOutputAt = DateTime.UtcNow;
            DrainTranscriptToLog();
        }
    }
}) { IsBackground = true };
reader.Start();

long respondedVersion = -1;

// The last line we actually replied to, so an IDENTICAL line is not answered
// twice for the same question.
//
// MEASURED, 2026-09-09: a rule replying {ENTER} sends a bare CR, which the
// terminal echoes without producing any new visible text - so the prompt is
// still the last non-empty line. If the child then goes silent (deploy.py does
// exactly this: it accepts the site name and says nothing while POSTing to
// Netlify), the settle window expires with a matching line still showing and
// the reply fires AGAIN. A stub that answers one question and sleeps eight
// seconds got TWO replies.
//
// The noisy log is the least of it. The extra CR sits in the child's input
// buffer and PRE-ANSWERS the next prompt with its default, with no "# prompt:"
// line written for it - so a harness auditing which questions it answered
// cannot see that it accepted one. On deploy.py's name-conflict path that means
// silently taking a fallback web address.
//
// Cleared as soon as the last line CHANGES, so a genuinely repeated prompt
// separated by other output is still answered.
string? repliedTo = null;
int responsesSent = 0;
var deadline = DateTime.UtcNow.AddSeconds(timeoutSeconds);
while (!pty.HasExited)
{
    Thread.Sleep(200);
    if (DateTime.UtcNow > deadline) { Note("# TIMEOUT — killing"); pty.Kill(); break; }
    string lastLine; long version; DateTime silentSince;
    lock (outputLock)
    {
        version = transcript.Version;
        silentSince = lastOutputAt;
        lastLine = transcript.CurrentLine.Trim();
        if (lastLine.Length == 0)
            for (int i = transcript.Lines.Count - 1; i >= 0; i--)
                if (transcript.Lines[i].Trim().Length > 0) { lastLine = transcript.Lines[i].Trim(); break; }
    }
    if (version == respondedVersion) continue;                       // nothing new since last reply
    if (repliedTo is not null && lastLine == repliedTo) continue;    // same question, already answered
    if (repliedTo is not null && lastLine != repliedTo) repliedTo = null;
    if ((DateTime.UtcNow - silentSince).TotalMilliseconds < settleMs) continue;
    foreach (var (pattern, reply) in rules)
    {
        if (!pattern.IsMatch(lastLine)) continue;
        respondedVersion = version;
        repliedTo = lastLine;
        if (++responsesSent > 300) { Note("# SAFETY VALVE — killing"); pty.Kill(); break; }
        Note($"# prompt: {lastLine}");
        Note($"# reply : {reply}");
        byte[] bytes = reply switch
        {
            "{ENTER}" => "\r"u8.ToArray(),
            "{RIGHT}" => "\x1b[C"u8.ToArray(),
            "{Q}" => "q"u8.ToArray(),
            _ => Encoding.UTF8.GetBytes(reply + "\r"),
        };
        pty.WriteInput(bytes);
        break;
    }
}

pty.WaitForExit(15000);
pty.ClosePty();
reader.Join(5000);
lock (outputLock)
{
    DrainTranscriptToLog();
    if (transcript.CurrentLine.Length > 0) log?.WriteLine(transcript.CurrentLine);
    FlushRaw();
}
int exit = pty.ExitCode ?? -1;
Note($"# exit: {exit}");
return exit;

// Copy whatever the transcript has gained into --log.
//
// THE CLAMP IS A BUG FIX, not defensiveness. TranscriptBuilder keeps only its
// last MaximumRetainedLines and drops the front of the list when it goes over
// (TranscriptBuilder.PushLine), while lastLoggedLineCount is an ABSOLUTE index
// into that list. Once trimming began, lastLoggedLineCount was permanently
// >= Lines.Count, this loop never ran again, and --log simply stopped - with
// nothing said, in the middle of a run. An npm build can exceed 4,000 lines,
// so this was reachable by an ordinary publish.
//
// It cannot be fixed by counting differently, because the lines really are
// gone. What it can do is keep writing the ones that arrive AFTER, and say
// once that the file has a hole in it. --raw-log has no such limit and is what
// a harness should read.
void DrainTranscriptToLog()
{
    if (log is null) return;
    if (lastLoggedLineCount > transcript.Lines.Count)
    {
        log.WriteLine($"# NOTE: the console view dropped its oldest lines "
                    + $"({lastLoggedLineCount - transcript.Lines.Count} of them). "
                    + "This log has a hole in it; --raw-log does not.");
        lastLoggedLineCount = transcript.Lines.Count;
    }
    while (lastLoggedLineCount < transcript.Lines.Count)
        log.WriteLine(transcript.Lines[(int)lastLoggedLineCount++]);
}
