using System.Collections.Generic;

namespace Plantoir.Core.Models;

/// <summary>
/// What a teacher is told about a working folder a cloud service keeps in sync.
///
/// <para>Every sentence here is pinned against
/// <c>contracts/shared-rules.json</c> → <c>cloudSyncedFolders.wording</c> by
/// <c>CloudSyncedFolderTests</c>, so the two apps say the same thing. They name
/// EFFECTS a teacher can recognise — building can be slower, renaming a folder
/// can take a while — and never machinery.</para>
/// </summary>
public static class CloudSyncWording
{
    public static string Headline(string service) =>
        $"This folder is kept in sync with {service}.";

    public static string Summary =>
        "Plantoir works here, but building can be slower and renaming folders can take a while. Your notes stay where they are.";

    public static string NotesStayPut =>
        "Your course notes stay exactly where they are. Plantoir never moves them.";

    public static string OffloadedPagesAreSlow(string service) =>
        $"If {service} has moved some of your pages off this computer to save space, Plantoir has to download each one before it can read it. Renaming a folder reads every page, so it can take a while.";

    public static string SyncingCanInterruptAMove(string service) =>
        $"If {service} is busy copying a file at the moment Plantoir needs to move or rename it, that step can fail. Plantoir checks before it moves anything, and you can try again once syncing has settled.";

    public static string WhatToDo =>
        "To avoid all of this, keep your working folder somewhere that is not synced — a folder inside your home folder, for example. If reaching your notes from other devices matters more, carry on: Plantoir will work, just more slowly at times.";

    public const string UseAnywayButton = "Use This Folder Anyway";
    public const string ChooseDifferentFolderButton = "Choose a Different Folder…";
    public const string DismissNoticeButton = "Got It";
    public const string ShowDetailsButton = "Show Details";
    public const string HideDetailsButton = "Hide Details";

    /// <summary>
    /// The full explanation, in the contract's order.
    ///
    /// <para>Reassurance FIRST: the words "kept in sync" beside a warning read
    /// as "your notes are at risk", and they are not. The choice comes last,
    /// once the reasons have been given.</para>
    ///
    /// <para>Four sentences, not five. A fifth — about build files being copied
    /// into the folder — was RETIRED on both platforms on 2026-09-05, because
    /// neither app builds inside the working folder any more. Do not add it
    /// back; the contract keeps its words under
    /// <c>buildFilesAreCopiedRetired</c> precisely so nobody does.</para>
    /// </summary>
    public static IReadOnlyList<string> Explanation(string service) => new[]
    {
        NotesStayPut,
        OffloadedPagesAreSlow(service),
        SyncingCanInterruptAMove(service),
        WhatToDo,
    };
}
