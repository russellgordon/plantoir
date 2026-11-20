using Plantoir.Core.Assist;

namespace Plantoir.Core.Undo;

/// <summary>
/// The app's runner for the <c>sectionFrontPage</c> maintainer
/// (<c>undoJournal.opKinds.recompute</c>; the mac's
/// <c>UndoSectionFrontPage</c>): the section's landing page re-derived from
/// the pages as they now stand, by Windows' own front-page rule
/// (<see cref="AssistWorkspace.RederiveTheFrontPage"/>, the rule a publish
/// applies). It writes only when the op names that section's landing page
/// under a course this working folder has, inside the folder through its
/// links; anything else is passed over, writing nothing. Idempotent.
///
/// <para>The composition root (<see cref="UndoForThisProcess"/>) gives every
/// door this runner (W4's review, LOW 5): a draft that carries a recompute is
/// then never refused for want of one, and in shadow the door re-derives the
/// front page itself, as the mac's <c>performAndRederive</c> does.</para>
/// </summary>
internal sealed class UndoSectionFrontPage : IUndoMaintainers
{
    public bool CanRun(string maintainer) => string.Equals(maintainer, UndoOp.SectionFrontPage, StringComparison.Ordinal);

    public void Rederive(UndoOp op, string root) => RederiveThePage(op, root);

    /// <summary>True when the landing page was re-derived (or already right); false when the op names no landing page this rule keeps.</summary>
    internal static bool RederiveThePage(UndoOp op, string root)
    {
        if (op.Path is not { } path || op.Section is not { } section || section < 1 || section > int.MaxValue) return false;
        string[] parts = path.Split('/');
        if (parts.Length < 3 || parts[0] != "courses") return false;
        if (!UndoPlaces.StaysInside(root, path)) return false;
        try
        {
            var workspace = new AssistWorkspace(root, new NoLaunchers());
            return workspace.RederiveTheFrontPage(parts[1], (int)section, UndoDoor.FullPath(root, path));
        }
        catch (Exception error) when (error is AssistRefusal or IOException or UnauthorizedAccessException)
        {
            return false;
        }
    }

    /// <summary>Re-deriving a page never runs a launcher.</summary>
    private sealed class NoLaunchers : ILauncherRunner
    {
        public Task<LaunchOutcome> Run(string launcher, IReadOnlyList<string> arguments, string workingFolder,
                                       IProgress<string>? progress, CancellationToken cancellation) =>
            throw new InvalidOperationException("Re-deriving a front page runs no launcher.");
    }
}
