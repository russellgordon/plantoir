namespace Plantoir.Core.Models;

/// <summary>
/// Help ▸ Plantoir Help (#491, the mac's #457 item 4): the support page on
/// plantoir.app, opened in the teacher's browser. The mac's Help item said
/// "Help isn't available for Plantoir" until then; Windows had no item at all.
/// </summary>
public static class PlantoirHelp
{
    /// <summary>The page the item opens — the mac's address.</summary>
    public const string SupportPage = "https://plantoir.app/support/";

    /// <summary>The trail line (<c>activityTrail.mustRecord</c> → "opened Plantoir Help").</summary>
    public const string TrailLine = "Help ▸ Plantoir Help — opened the support page in the browser";
}
