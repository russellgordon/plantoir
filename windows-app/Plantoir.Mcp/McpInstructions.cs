namespace Plantoir.Mcp;

/// <summary>
/// What an outside assistant (Claude Code, Codex) is told when it connects —
/// the MCP <c>instructions</c> field, which the local router never reads.
/// </summary>
/// <remarks>
/// <para><b>Why this exists (#352, 2026-10-01).</b> Until then this server's
/// tool descriptions carried procedural sentences written for Claude Code:
/// plan first, read it out, wait; look at the preview before deploying; the
/// computer must be awake for a scheduled deploy. #114 decided ONE
/// description per tool, the contract's (<c>assist-cases.json →
/// toolDescriptions</c>), and that procedure does not belong in a description:
/// a small local model reads a description as a routing signal, and the
/// contract's rule sends "procedural instructions meant only for an MCP client"
/// here instead. So when the descriptions converged, every instruction they
/// carried was gathered into this one text rather than dropped. The mac
/// serves its own (<c>AssistMCPServer.instructions</c>); the two are not
/// pinned against each other.</para>
/// <para>Nothing here is enforced by the words: the write tools refuse what
/// they must refuse in code, whatever a client believes.</para>
/// </remarks>
public static class McpInstructions
{
    public const string Text =
        "Plantoir turns a teacher's course notes into a website per class section. These tools act on one working folder.\n\n" +
        "Plan, show, then act. Most tools that change pages have a plan_ twin: call the plan first, show the teacher " +
        "what it said in full, and wait for them to agree before calling the tool that writes. For one that has none " +
        "(roll_over_section, back_up_course), say what it will do and wait for the teacher; undo_last_change takes " +
        "back what this conversation did. Making room part-way " +
        "through a unit (plan_make_room_for_classes) moves and renames more pages than anything else: read the whole " +
        "plan, link count included, because the teacher cannot check that without opening every page.\n\n" +
        "Publishing is not deploying. Publishing a page only decides whether it is built into the section's site and " +
        "rebuilds the teacher's PREVIEW. Deploying (deploy_section) is the one step students see: before it, tell the " +
        "teacher to look the preview over in Plantoir and wait for them to say they have; if they have not, offer to " +
        "wait. A deploy takes several minutes, and so does building a preview.\n\n" +
        "Scheduled deploys. Call plan_scheduled_deploy first and read it out, especially that the computer must be ON " +
        "and AWAKE at that moment, plugged in if it is a laptop, with the lid open: Plantoir does not wake it. Pass the " +
        "class pages the teacher has in mind as `classes` so the plan checks they are actually published. Scheduling " +
        "replaces any deploy already scheduled for that section; cancel_scheduled_deploy calls it off and is safe when " +
        "nothing is scheduled.\n\n" +
        "Dates. Call read_remembered_timetable before asking the teacher for their class dates, and before any tool that " +
        "needs dates. When they tell you when their class meets, call remember_timetable with the WHOLE list every " +
        "time (it replaces what was recorded), dates as YYYY-MM-DD separated by commas or spaces. For " +
        "plan_re_date_classes, give `pages` and `meetings` as matching lists to choose which lesson lands on which " +
        "meeting; leaving both empty spreads them evenly, which is a starting point rather than an answer. Pages can be " +
        "chosen by name, or by date with onOrAfter/before.\n\n" +
        "Reading pages. list_pages takes `matching` to narrow a long list (for example \"Unit 2\"). A page under " +
        "section1/ carries `publish:`; a course-level page carries `publishForSection1:`, `publishForSection2:` and so " +
        "on. Older courses carry `draft:` / `draftSection1:`, which mean the OPPOSITE (`draft: true` is a page students " +
        "cannot see). Report what you find; do not rewrite settings yourself.\n\n" +
        "Taking things back. undo_last_change reverses the most recent change THIS conversation made and can be called " +
        "again to step further back; for anything older, Plantoir's Backups list holds a copy taken before the " +
        "conversation's first change. Undoing pages does not take down a site already deployed: the teacher deploys " +
        "again. make_room_for_classes cannot be undone this way once other classes have moved; its backup is the way " +
        "out. Before editing a course's files directly rather than through these tools, call back_up_course: course " +
        "folders are not in version control.\n\n" +
        "After a batch of publish_pages or unpublish_pages calls made with preview=false, call rebuild_preview once.";
}
