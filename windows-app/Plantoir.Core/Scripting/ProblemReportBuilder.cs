using System;
using System.Collections.Generic;
using System.IO;
using System.IO.Compression;
using System.Text;
using Plantoir.Core.Models;

namespace Plantoir.Core.Scripting;

public class ProblemReportBuilder
{
    public enum AssistantPrompts
    {
        None,
        Excluded,
        Included,
    }

    public ProblemReportStore Store { get; }

    public const string FolderName = "Plantoir problem report";
    public const string AboutFileName = "what is in this report.txt";
    public const string TrailFileName = "what you were doing.txt";
    public const string SupportEmail = "support@plantoir.app";
    public static readonly Uri SupportMailUri = new("mailto:support@plantoir.app?subject=Plantoir%20problem%20report");
    public const string IncludePromptsLabel = "Include what I typed to the local AI assistant";

    public ProblemReportBuilder(ProblemReportStore? store = null)
    {
        Store = store ?? ProblemReportStore.Standard;
    }

    public static string Stamp(DateTime now) =>
        DateText.Invariant(now, "yyyy-MM-dd 'at' HH.mm.ss");

    public static string StampedFolderName(DateTime now) =>
        $"{FolderName} {Stamp(now)}";

    public static string SuggestedFileName(DateTime now) =>
        $"{StampedFolderName(now)}.zip";

    public static string TaskCountPhrase(int count) =>
        count == 1 ? "the last task Plantoir ran for you" : $"the last {count} tasks Plantoir ran for you";

    public static AssistantPrompts PromptState(bool hasAny, bool including)
    {
        if (!hasAny) return AssistantPrompts.None;
        return including ? AssistantPrompts.Included : AssistantPrompts.Excluded;
    }

    public static string About(int recordCount, AssistantPrompts assistantPrompts, DateTime now)
    {
        var lines = new List<string>
        {
            "What is in this report",
            "======================",
            "",
            $"Made on {DateText.Invariant(now, "yyyy-MM-dd HH:mm:ss zzz")}.",
            "",
            "Everything here is plain text. Open any of it and read it before you",
            "send it — that is what it is for.",
            "",
            $"When you are ready, email this file to {SupportEmail}.",
            "",
            "IN THIS REPORT",
            "  · a list of what you did in Plantoir, in order, with the time of each",
            $"  · {TaskCountPhrase(recordCount)}, and everything",
            "    each one showed on screen while it worked",
            "  · your course codes, section numbers and where your course folders sit",
            "  · the NAMES of your pages — your website builder lists each one as it",
            "    works, so they appear in what it printed",
            "  · which version of Plantoir you are using, and what kind of Windows this is",
        };

        if (assistantPrompts == AssistantPrompts.Included)
        {
            lines.Add("  · what you typed to the local AI assistant, because you asked for it");
            lines.Add("    to be included");
        }

        lines.Add("");
        lines.Add("NOT IN THIS REPORT");
        lines.Add("  · what you have WRITTEN on your pages — only their names appear");
        lines.Add("  · your sign-in details for Netlify or Cloudflare");
        lines.Add("  · your name, your email address, or your account name on this Windows PC");

        if (assistantPrompts == AssistantPrompts.Excluded)
        {
            lines.Add("  · what you typed to the local AI assistant");
        }

        lines.Add("");
        lines.Add("Where something was taken out, it says so in square brackets, like this:");
        lines.Add("  " + LogRedactor.RemovedToken);

        return string.Join("\n", lines) + "\n";
    }

    public bool BuildZip(string destinationZipPath, bool includingAssistantPrompts, DateTime? moment = null)
    {
        DateTime now = moment ?? DateTime.Now;
        var runPaths = Store.RunFilePaths();
        string trail = Store.ActivityText(includingAssistantPrompts);

        if (runPaths.Count == 0 && string.IsNullOrWhiteSpace(trail))
            return false;

        string rootFolderName = StampedFolderName(now);
        var promptState = PromptState(Store.HasAssistantPrompts, includingAssistantPrompts);
        string aboutContent = About(runPaths.Count, promptState, now);

        string? dir = Path.GetDirectoryName(destinationZipPath);
        if (!string.IsNullOrEmpty(dir)) Directory.CreateDirectory(dir);

        if (File.Exists(destinationZipPath)) File.Delete(destinationZipPath);

        using (var zip = ZipFile.Open(destinationZipPath, ZipArchiveMode.Create))
        {
            var aboutEntry = zip.CreateEntry($"{rootFolderName}/{AboutFileName}");
            using (var stream = aboutEntry.Open())
            using (var writer = new StreamWriter(stream, new UTF8Encoding(encoderShouldEmitUTF8Identifier: false)))
            {
                writer.Write(aboutContent);
            }

            if (!string.IsNullOrWhiteSpace(trail))
            {
                var trailEntry = zip.CreateEntry($"{rootFolderName}/{TrailFileName}");
                using (var stream = trailEntry.Open())
                using (var writer = new StreamWriter(stream, new UTF8Encoding(encoderShouldEmitUTF8Identifier: false)))
                {
                    writer.Write(trail);
                }
            }

            foreach (var runPath in runPaths)
            {
                string fileName = Path.GetFileName(runPath);
                zip.CreateEntryFromFile(runPath, $"{rootFolderName}/tasks/{fileName}");
            }
        }

        return true;
    }
}
