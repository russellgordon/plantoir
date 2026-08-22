using System;
using System.Collections.Generic;
using System.IO;

namespace Plantoir.Core.Models;

/// <summary>
/// What deploy.ps1 (or deploy.sh) is asked to do for one section, at one
/// destination.
///
/// One place decides this, because several now ask: the Deploy button, the
/// assistant, and a scheduled deploy task. Building the arguments separately
/// in each would let a scheduled Cloudflare deploy quietly go to Netlify —
/// the failure would appear once, overnight, on a live class site.
///
/// A course can publish to more than one destination now (redundancy against
/// one host having a bad day) — see
/// <see cref="CourseConfiguration.AllDeployDestinations"/>. The functions
/// here that take a single <c>destination</c> are the ones a multi-destination
/// deploy calls once per leg; the ones that take a whole
/// <c>CourseConfiguration</c> are thin wrappers over those, kept so every
/// existing caller and existing test — all written against "this course's
/// ONE destination" — keeps working unchanged, reading <c>DeployTarget</c> as
/// that one destination. Mirrors the mac's `DeployCommand.swift`.
/// </summary>
public static class DeployCommand
{
    /// <summary>The launcher in the teacher's working folder.</summary>
    public const string ScriptName = "deploy.ps1";

    /// <summary>
    /// The arguments for one section's deploy, to one destination.
    ///
    /// Netlify passes no target flag at all: it is deploy's default, and every
    /// course written before Cloudflare existed relies on that.
    /// </summary>
    public static IReadOnlyList<string> Arguments(
        string courseCode,
        int sectionNumber,
        CourseConfiguration.DeployDestination destination,
        string cloudflareAccountID = "")
    {
        var args = new List<string> { courseCode, sectionNumber.ToString() };
        if (destination.Type == "local_folder")
        {
            args.Add("--to-folder");
            args.Add(destination.Path);
            return args;
        }

        if (destination.Type == "cloudflare_pages")
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

    /// <summary>The arguments for one section's deploy, to this course's PRIMARY destination only.</summary>
    public static IReadOnlyList<string> Arguments(
        string courseCode,
        int sectionNumber,
        CourseConfiguration configuration,
        string cloudflareAccountID = "") =>
        Arguments(courseCode, sectionNumber,
            new CourseConfiguration.DeployDestination(configuration.DeployTarget, configuration.DeployFolderPath),
            cloudflareAccountID);

    /// <summary>Where a destination deploys to, in the teacher's words.</summary>
    public static string DestinationDescription(CourseConfiguration.DeployDestination destination)
    {
        if (destination.Type == "local_folder")
            return destination.Path;
        if (destination.Type == "cloudflare_pages")
            return "Cloudflare Pages";
        return "Netlify";
    }

    /// <summary>Where this course's PRIMARY destination deploys to, in the teacher's words.</summary>
    public static string DestinationDescription(CourseConfiguration configuration) =>
        DestinationDescription(new CourseConfiguration.DeployDestination(configuration.DeployTarget, configuration.DeployFolderPath));

    /// <summary>
    /// The marker file the deployer writes the first time a section goes out
    /// to a given destination TYPE, or null for a destination that keeps
    /// none. Keyed purely by destination TYPE (never by whether that type
    /// happens to be primary or additional) — an additional Cloudflare
    /// target reuses the identical marker path a primary Cloudflare target
    /// would.
    /// </summary>
    public static string? FirstDeployMarkerPath(int sectionNumber, Course course, string destinationType)
    {
        if (destinationType == "local_folder")
            return null;

        string folderName = destinationType == "cloudflare_pages" ? ".cloudflare_sites" : ".netlify_sites";
        return Path.Combine(course.DirectoryPath, folderName, $"section{sectionNumber}.json");
    }

    /// <summary>The marker file for this course's PRIMARY destination.</summary>
    public static string? FirstDeployMarkerPath(int sectionNumber, Course course) =>
        FirstDeployMarkerPath(sectionNumber, course, course.Configuration.DeployTarget);

    /// <summary>
    /// True when this section has been deployed to the given destination TYPE
    /// at least once, so a deploy to it asks the teacher nothing.
    /// </summary>
    public static bool HasDeployedBefore(int sectionNumber, Course course, string destinationType)
    {
        string? marker = FirstDeployMarkerPath(sectionNumber, course, destinationType);
        if (marker is null) return true;
        return File.Exists(marker);
    }

    /// <summary>True when this section has been deployed to its PRIMARY destination at least once.</summary>
    public static bool HasDeployedBefore(int sectionNumber, Course course) =>
        HasDeployedBefore(sectionNumber, course, course.Configuration.DeployTarget);
}
