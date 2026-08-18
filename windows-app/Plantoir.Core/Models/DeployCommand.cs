using System;
using System.Collections.Generic;
using System.IO;

namespace Plantoir.Core.Models;

/// <summary>
/// What deploy.ps1 (or deploy.sh) is asked to do for one section.
///
/// One place decides this, because two now ask: the Deploy button, and the
/// scheduled deploy task. Building the arguments separately in each would let
/// a scheduled Cloudflare deploy quietly go to Netlify.
/// </summary>
public static class DeployCommand
{
    /// <summary>The launcher in the teacher's working folder.</summary>
    public const string ScriptName = "deploy.ps1";

    /// <summary>
    /// The arguments for one section's deploy.
    ///
    /// Netlify passes no target flag at all: it is deploy's default, and every
    /// course written before Cloudflare existed relies on that.
    /// </summary>
    public static IReadOnlyList<string> Arguments(
        string courseCode,
        int sectionNumber,
        CourseConfiguration configuration,
        string cloudflareAccountID = "")
    {
        var args = new List<string> { courseCode, sectionNumber.ToString() };
        if (configuration.DeploysToLocalFolder)
        {
            args.Add("--to-folder");
            args.Add(configuration.DeployFolderPath);
            return args;
        }

        if (configuration.DeploysToCloudflare)
        {
            args.Add("--target");
            args.Add("cloudflare");

            string identifier = cloudflareAccountID.Trim();
            if (!string.IsNullOrEmpty(identifier))
            {
                args.Add("--account");
                args.Add(identifier);
            }
        }

        return args;
    }

    /// <summary>Where this course and section deploys, in the teacher's words.</summary>
    public static string DestinationDescription(CourseConfiguration configuration)
    {
        if (configuration.DeploysToLocalFolder)
            return configuration.DeployFolderPath;
        if (configuration.DeploysToCloudflare)
            return "Cloudflare Pages";
        return "Netlify";
    }

    /// <summary>
    /// The marker file the deployer writes the first time a section goes out,
    /// or null for a destination that keeps none.
    /// </summary>
    public static string? FirstDeployMarkerPath(int sectionNumber, Course course)
    {
        if (course.Configuration.DeploysToLocalFolder)
            return null;

        string folderName = course.Configuration.DeploysToCloudflare ? ".cloudflare_sites" : ".netlify_sites";
        return Path.Combine(course.DirectoryPath, folderName, $"section{sectionNumber}.json");
    }

    /// <summary>
    /// True when this section has been deployed to its current destination
    /// at least once, so a deploy of it asks the teacher nothing.
    /// </summary>
    public static bool HasDeployedBefore(int sectionNumber, Course course)
    {
        string? marker = FirstDeployMarkerPath(sectionNumber, course);
        if (marker is null) return true;
        return File.Exists(marker);
    }
}
