using System;
using System.Collections.Generic;
using System.IO;
using System.Linq;
using Plantoir.Core.Assist;

namespace Plantoir.Core.Models;

public static class CourseRenamer
{
    public sealed record Outcome(
        string NewCode,
        IReadOnlyList<int> StoppedScheduledSections,
        IReadOnlyList<int> UnstoppedScheduledSections)
    {
        public bool IsQuiet => StoppedScheduledSections.Count == 0 && UnstoppedScheduledSections.Count == 0;
    }

    public sealed record Notice(string Title, string Message);

    public static Notice? NoticeAfterRenaming(Outcome outcome)
    {
        if (outcome.IsQuiet) return null;

        var sentences = new List<string>();
        if (outcome.StoppedScheduledSections.Count > 0)
        {
            string sections = Listed(outcome.StoppedScheduledSections);
            bool isOne = outcome.StoppedScheduledSections.Count == 1;
            sentences.Add(
                $"{sections} of {outcome.NewCode} {(isOne ? "was" : "were")} set to deploy on " +
                $"{(isOne ? "its" : "their")} own. Renaming turned that off — set " +
                $"{(isOne ? "it" : "them")} again from the section’s menu if you still want " +
                $"{(isOne ? "it" : "them")}.");
        }
        if (outcome.UnstoppedScheduledSections.Count > 0)
        {
            string sections = Listed(outcome.UnstoppedScheduledSections);
            bool isOne = outcome.UnstoppedScheduledSections.Count == 1;
            sentences.Add(
                $"{sections} {(isOne ? "was" : "were")} also set to deploy on " +
                $"{(isOne ? "its" : "their")} own, and Plantoir could not turn that off. " +
                $"{(isOne ? "It" : "They")} may still try to deploy under the old name.");
        }

        string title = outcome.UnstoppedScheduledSections.Count == 0
            ? "Deploying on a schedule was turned off"
            : "A scheduled deploy may still run";
        return new Notice(title, string.Join("\n\n", sentences));
    }

    public static string ObsidianQuestion(int openVaultCount)
    {
        string ending = openVaultCount > 1 ? "open your vaults again" : "open it again";
        return "Renaming moves this course’s folder, and Obsidian would keep showing files that are no longer there.\n\n" +
               $"Plantoir can close Obsidian, rename the course, and {ending}.";
    }

    public static string Listed(IReadOnlyList<int> sectionNumbers)
    {
        if (sectionNumbers.Count == 0) return "Section ";
        if (sectionNumbers.Count == 1) return $"Section {sectionNumbers[0]}";

        var leading = sectionNumbers.Take(sectionNumbers.Count - 1);
        int last = sectionNumbers[^1];
        return $"Sections {string.Join(", ", leading)} and {last}";
    }

    public static Outcome Rename(
        Course course,
        string requestedCode,
        string coursesDirectory,
        IEnumerable<string> existingCodes)
    {
        string newCode = CourseCodeValidator.Normalize(requestedCode);
        if (CourseCodeValidator.Problem(requestedCode, existingCodes, course.Code) is { } problem)
        {
            throw new InvalidOperationException(problem);
        }

        if (string.IsNullOrEmpty(newCode) || newCode == course.Code)
        {
            return new Outcome(course.Code, Array.Empty<int>(), Array.Empty<int>());
        }

        string destinationDir = Path.Combine(coursesDirectory, newCode);
        if (Directory.Exists(destinationDir) || File.Exists(destinationDir))
        {
            throw new InvalidOperationException($"There is already something called {newCode} in this working folder.");
        }

        // Asked of the SCHEDULER, and of this working folder's deploys only
        // (#239, #309): a section removed earlier can have left one behind that
        // the settings no longer list, and another folder's ICS3U is not ours.
        string workingFolder = Path.GetDirectoryName(coursesDirectory.TrimEnd(
            Path.DirectorySeparatorChar, Path.AltDirectorySeparatorChar)) ?? coursesDirectory;
        var scheduled = TaskScheduling.InFolder(workingFolder)
            .Where(task => TaskScheduling.SameCode(task.CourseCode, course.Code))
            .ToList();

        string previousCode = course.Code;
        course.Configuration.SetCourseCode(newCode);
        try
        {
            course.Configuration.Write(course.ConfigFilePath);
        }
        catch (Exception ex)
        {
            course.Configuration.SetCourseCode(previousCode);
            throw new InvalidOperationException($"The course's settings could not be saved: {ex.Message}", ex);
        }

        try
        {
            Directory.Move(course.DirectoryPath, destinationDir);
        }
        catch (Exception ex)
        {
            course.Configuration.SetCourseCode(previousCode);
            try { course.Configuration.Write(course.ConfigFilePath); } catch { }
            throw new InvalidOperationException($"The course's folder could not be renamed: {ex.Message}", ex);
        }

        var stopped = new List<int>();
        var unstopped = new List<int>();
        foreach (var task in scheduled)
        {
            // Cancelled by the name it REALLY has — one set before #309 has
            // the folder-less one, and a rebuilt name would miss it.
            string? cancelError = TaskScheduling.Cancel(task);
            if (cancelError is null)
            {
                if (!stopped.Contains(task.Section)) stopped.Add(task.Section);
                Plantoir.Core.Scripting.ActivityTrail.Note(Plantoir.Core.Scripting.ActivityTrail.Event.ScheduledDeployTurnedOff,
                    $"turned off: the course was renamed to {newCode}", previousCode, task.Section);
            }
            else if (!unstopped.Contains(task.Section))
                unstopped.Add(task.Section);
        }
        stopped.Sort();
        unstopped.Sort();

        return new Outcome(newCode, stopped, unstopped);
    }
}
