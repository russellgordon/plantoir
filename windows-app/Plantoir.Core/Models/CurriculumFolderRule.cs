using System;
using System.Collections.Generic;
using System.Linq;

namespace Plantoir.Core.Models;

/// <summary>
/// Which folder the GUI protects as the course's curriculum folder, computed
/// from the config's own <c>shared_folders</c> list.
///
/// <para>The course's configured <c>curriculum_folder</c> wins if it is in the
/// list; otherwise the alphabetically first name containing "curriculum",
/// case-insensitively.</para>
///
/// <para><b>This is the NAME half of <c>build_site.py:_find_curriculum_folder</c>,
/// and deliberately only that half.</b> The build additionally scans the vault
/// and accepts a folder only if it holds a page whose title is an expectation
/// code — a check neither app can make from the config alone. So the GUI may
/// protect a folder the build would skip (one with no expectation pages yet);
/// it never protects a DIFFERENT folder than the build would pick among those
/// it can see. Do not try to replicate the disk check: guessing at it would
/// trade a harmless over-protection for a wrong answer.</para>
///
/// <para>Pinned by <c>contracts/shared-rules.json</c> ->
/// <c>specialNames.curriculumFolderResolution</c>.</para>
/// </summary>
public static class CurriculumFolderRule
{
    private const string Marker = "curriculum";

    /// <summary>
    /// The resolved folder name, or null when the course has none the GUI can
    /// see.
    /// </summary>
    public static string? Resolve(string? configuredName, IEnumerable<string>? sharedFolders)
    {
        var folders = (sharedFolders ?? Enumerable.Empty<string>())
            .Where(f => !string.IsNullOrEmpty(f)).ToList();

        // The configured name wins even when it does not mention the word
        // curriculum at all — that is the whole reason the key exists, for a
        // course whose folder is called "Expectations" and which the scan
        // below would never find.
        if (!string.IsNullOrEmpty(configuredName) &&
            folders.Contains(configuredName!, StringComparer.Ordinal))
            return configuredName;

        return folders
            .Where(f => f.Contains(Marker, StringComparison.OrdinalIgnoreCase))
            .OrderBy(f => f, StringComparer.Ordinal)
            .FirstOrDefault();
    }
}
