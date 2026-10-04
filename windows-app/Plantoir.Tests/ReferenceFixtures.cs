using System.Diagnostics;
using System.Security.Cryptography;
using System.Text.Json.Nodes;
using Plantoir.Core.Models;
using Plantoir.Core.Scripting;

namespace Plantoir.Tests;

/// <summary>
/// Trees on disk for the reference-course tests, built from the contract's
/// <c>treeEntries</c> grammar (<c>referenceCourses.obsidianAddOns.treeEntries</c>):
/// a plain string is a file ("something"), except a path ending
/// <c>course_config.json</c>, written as settings naming the folder as its
/// course_code with section_numbers [1]; one ending "/" is an empty folder;
/// {file, text} is a file with that text; {link, to} is a link — a JUNCTION
/// here, since a symlink needs Developer Mode.
/// </summary>
internal static class ReferenceFixtures
{
    public static void Build(string root, JsonArray tree)
    {
        foreach (var node in tree)
        {
            if (node is JsonValue value)
            {
                string relative = value.ToString();
                string path = Path.Combine(root, relative.Replace('/', '\\'));
                if (relative.EndsWith('/')) { Directory.CreateDirectory(path); continue; }
                Directory.CreateDirectory(Path.GetDirectoryName(path)!);
                if (relative.EndsWith("course_config.json"))
                {
                    string folder = Path.GetFileName(Path.GetDirectoryName(path)!)!;
                    File.WriteAllText(path, $"{{\"course_code\": \"{folder}\", \"section_numbers\": [1], \"num_sections\": 1}}");
                }
                else File.WriteAllText(path, "something");
            }
            else if (node!["file"] is { } file)
            {
                string path = Path.Combine(root, file.ToString().Replace('/', '\\'));
                Directory.CreateDirectory(Path.GetDirectoryName(path)!);
                File.WriteAllText(path, node["text"]!.ToString());
            }
            else if (node["link"] is { } link)
            {
                string path = Path.Combine(root, link.ToString().Replace('/', '\\'));
                string target = Path.Combine(root, node["to"]!.ToString().Replace('/', '\\'));
                Directory.CreateDirectory(Path.GetDirectoryName(path)!);
                Directory.CreateDirectory(target);
                Junction(path, target);
            }
        }
    }

    public static void Junction(string link, string target)
    {
        using var process = Process.Start(new ProcessStartInfo("cmd.exe", $"/c mklink /J \"{link}\" \"{target}\"")
        {
            UseShellExecute = false, CreateNoWindow = true, RedirectStandardOutput = true, RedirectStandardError = true,
        })!;
        process.WaitForExit(30_000);
        if (process.ExitCode != 0) throw new InvalidOperationException("could not make a junction at " + link);
    }

    /// <summary>
    /// Removes a test folder safely: every junction FIRST, on its own (never
    /// walked through), then the locks, then the tree.
    /// </summary>
    public static void Remove(string root)
    {
        if (!Directory.Exists(root)) return;
        foreach (string link in Links(root)) { try { Directory.Delete(link); } catch { } }
        ReferenceLock.Clear(root);
        try { Directory.Delete(root, recursive: true); } catch { }
    }

    private static IEnumerable<string> Links(string root)
    {
        var found = new List<string>();
        var pending = new Stack<string>();
        pending.Push(root);
        while (pending.Count > 0)
        {
            string folder = pending.Pop();
            IEnumerable<DirectoryInfo> children;
            try { children = new DirectoryInfo(folder).EnumerateDirectories("*", ReferenceLock.Unfiltered).ToList(); }
            catch { continue; }
            foreach (var child in children)
            {
                if (child.Attributes.HasFlag(FileAttributes.ReparsePoint)) found.Add(child.FullName);
                else pending.Push(child.FullName);
            }
        }
        return found;
    }

    /// <summary>
    /// A MANIFEST of every entry under <paramref name="root"/> — path, size,
    /// last write, SHA-256, attributes and the access rules as SDDL — links
    /// listed and never followed. LastAccessTime is deliberately NOT in it:
    /// NTFS may update it on a read (review L3).
    /// </summary>
    public static SortedDictionary<string, string> Manifest(string root)
    {
        var manifest = new SortedDictionary<string, string>(StringComparer.Ordinal);
        var pending = new Stack<string>();
        pending.Push(root);
        while (pending.Count > 0)
        {
            string folder = pending.Pop();
            foreach (var entry in new DirectoryInfo(folder).EnumerateFileSystemInfos("*", ReferenceLock.Unfiltered))
            {
                string relative = Path.GetRelativePath(root, entry.FullName);
                string sddl = entry is DirectoryInfo d
                    ? d.GetAccessControl().GetSecurityDescriptorSddlForm(System.Security.AccessControl.AccessControlSections.Access)
                    : ((FileInfo)entry).GetAccessControl().GetSecurityDescriptorSddlForm(System.Security.AccessControl.AccessControlSections.Access);
                // A FOLDER's last-write time is left out: measured, NTFS moves it
                // a few milliseconds after the files in it were written, with
                // nothing touching the folder in between. A file's is kept.
                string facts = entry is DirectoryInfo
                    ? $"{entry.Attributes}|{sddl}"
                    : $"{entry.Attributes}|{entry.LastWriteTimeUtc.Ticks}|{sddl}";
                if (entry.Attributes.HasFlag(FileAttributes.ReparsePoint)) { manifest[relative] = "link|" + facts + "|" + entry.LinkTarget; continue; }
                if (entry is FileInfo file)
                {
                    using var stream = new FileStream(file.FullName, FileMode.Open, FileAccess.Read, FileShare.ReadWrite | FileShare.Delete);
                    manifest[relative] = $"file|{file.Length}|{Convert.ToHexString(SHA256.HashData(stream))}|{facts}";
                }
                else
                {
                    manifest[relative] = "folder|" + facts;
                    pending.Push(entry.FullName);
                }
            }
        }
        return manifest;
    }

    /// <summary>Lines of the test trail written since <paramref name="mark"/> (a length taken before the act).</summary>
    public static List<string> TrailSince(long mark)
    {
        string path = ActivityTrail.CurrentLogPath;
        if (!File.Exists(path)) return new List<string>();
        using var stream = new FileStream(path, FileMode.Open, FileAccess.Read, FileShare.ReadWrite | FileShare.Delete);
        if (mark > stream.Length) mark = 0;
        stream.Seek(mark, SeekOrigin.Begin);
        using var reader = new StreamReader(stream);
        return reader.ReadToEnd().Split('\n', StringSplitOptions.RemoveEmptyEntries).Select(line => line.TrimEnd('\r')).ToList();
    }

    public static long TrailMark()
    {
        string path = ActivityTrail.CurrentLogPath;
        return File.Exists(path) ? new FileInfo(path).Length : 0;
    }
}
