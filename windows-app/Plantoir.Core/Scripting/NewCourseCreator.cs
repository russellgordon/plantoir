using System;
using System.Threading.Tasks;
using Newtonsoft.Json.Linq;
using Plantoir.Core.Models;

namespace Plantoir.Core.Scripting;

/// <summary>
/// "The wizard with every answer pre-filled": the app writes the teacher's
/// choices to course_config.json first, runs the REAL setup launcher, and
/// presses Return at each prompt — the wizard re-reads the file as its
/// saved defaults, so a plain Return accepts every one. The one exception,
/// the course-code prompt, is answered explicitly.
/// </summary>
public sealed class NewCourseCreator
{
    public ScriptRunner Runner { get; }
    public bool IsCreating { get; private set; }
    public string? PreparationProblem { get; private set; }
    public string? InstalledExampleCode { get; private set; }

    private string _courseCode = "";
    private long _respondedVersion = -1;
    private int _responsesSent;

    public NewCourseCreator(ScriptRunner runner) => Runner = runner;

    public async Task CreateCourse(JObject configuration, string workspacePath)
    {
        PreparationProblem = null;
        if (configuration["course_code"]?.ToString() is not { Length: > 0 } storedCode)
        {
            PreparationProblem = "The course needs a code.";
            return;
        }
        _courseCode = storedCode.ToUpperInvariant();

        // The launcher must exist BEFORE anything is written: writing
        // course_config.json first and then failing to launch left a
        // half-made course that both blocked a retry ("already exists") and
        // stopped the folder counting as empty, so the picker no longer
        // offered to set it up. Found by adversarial testing, 2026-08-19.
        if (!File.Exists(Path.Combine(workspacePath, "setup.ps1")))
        {
            PreparationProblem = "This working folder isn't ready yet. Choose it from the File menu first, then create the course.";
            return;
        }

        try
        {
            string courseDir = Path.Combine(Workspace.CoursesDirectory(workspacePath), _courseCode);
            Directory.CreateDirectory(courseDir);
            CourseConfiguration.FromDictionary(configuration)
                .Write(Path.Combine(courseDir, "course_config.json"));
        }
        catch (Exception error)
        {
            PreparationProblem = $"Could not write the course configuration: {error.Message}";
            return;
        }

        _respondedVersion = -1;
        _responsesSent = 0;
        IsCreating = true;
        Runner.Milestones = TaskMilestones.CourseCreation;
        Runner.Run("setup.ps1", Array.Empty<string>(), workspacePath);
        await PumpAnswers();
        IsCreating = false;
    }

    public async Task InstallExampleCourse(string workspacePath)
    {
        PreparationProblem = null;
        IsCreating = true;
        Runner.Milestones = TaskMilestones.ExampleCourse;
        Runner.Run("setup.ps1", new[] { "--install-example" }, workspacePath);
        await Runner.WaitUntilFinished();
        InstalledExampleCode = OutputParsers.ExampleCourseCode(Runner.Transcript.DisplayText);
        IsCreating = false;
    }

    /// <summary>
    /// Every 400 ms: if NEW output has arrived and its last non-empty line is
    /// prompt-shaped, answer — the course code where asked, a bare Return
    /// everywhere else. The new-output guard is the whole anti-double-answer
    /// mechanism; 300 responses is the runaway valve.
    /// </summary>
    /// <summary>
    /// Wait for output to go quiet before answering, so we only ever act on a
    /// COMPLETE prompt. Without this, a multi-line render whose intermediate
    /// lines happen to end in ':' — the colour-scheme picker prints
    /// "Light Mode:" and "Dark Mode:" before its "Use ← / →" footer — would be
    /// answered mid-render, firing an extra Return into the raw key reader and
    /// desyncing the whole sequence into a deadlock.
    /// </summary>
    private const int SettleMilliseconds = 600;

    private async Task PumpAnswers()
    {
        while (Runner.IsRunning)
        {
            await Task.Delay(200);
            if (_responsesSent > 300) { Runner.Terminate(); break; }
            long version = Runner.Transcript.Version;
            if (version == _respondedVersion) continue;
            // Output is still streaming — let the current prompt finish printing.
            if ((DateTime.UtcNow - Runner.LastOutputAt).TotalMilliseconds < SettleMilliseconds) continue;
            // This version is now settled; mark it handled either way so a
            // non-prompt (a status line between prompts) doesn't busy-loop.
            _respondedVersion = version;
            string lastLine = CurrentPromptLine();
            if (!LooksLikePrompt(lastLine)) continue;
            _responsesSent++;
            Runner.SendLine(lastLine.Contains("Enter the course code") ? _courseCode : "");
        }
    }

    private string CurrentPromptLine()
    {
        string current = Runner.Transcript.CurrentLine.Trim();
        if (current.Length > 0) return current;
        for (int i = Runner.Transcript.Lines.Count - 1; i >= 0; i--)
        {
            string line = Runner.Transcript.Lines[i].Trim();
            if (line.Length > 0) return line;
        }
        return "";
    }

    /// <summary>
    /// Looser than the question heuristic on purpose — matched to the prompt
    /// shapes setup_course.py really prints, including the arrow-key colour
    /// picker (where Return accepts the current scheme).
    ///
    /// The picker footer is matched by CONTAINS, not StartsWith: the Windows
    /// pseudo console sometimes renders it onto the tail of the last swatch
    /// line ("… textHighlight Use ← / → … Enter to select …"), so anchoring at
    /// the start would miss it and the run would deadlock waiting for input
    /// that never comes.
    /// </summary>
    internal static bool LooksLikePrompt(string line) =>
        line.EndsWith(':') || line.EndsWith(": ", StringComparison.Ordinal)
        || line == ">"
        || line.Contains("Enter to select", StringComparison.Ordinal)
        || line.EndsWith('?');
}
