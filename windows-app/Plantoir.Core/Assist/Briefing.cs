namespace Plantoir.Core.Assist;

/// <summary>
/// The short explanation of what "publish" means here, given once per section
/// and then remembered.
///
/// Two words do a lot of work in this app and mean different things:
///
/// * **Publish / unpublish** is about a page's <c>publish</c> flag — whether
///   the page is built into the site, and so whether it appears in the
///   teacher's own preview. It says nothing about who can edit it.
/// * **Deploy** is putting the built site where students can reach it. The
///   assistant CAN do it, on request and never otherwise, and says so —
///   claiming it never deploys would be a promise the tools do not keep,
///   which is worse than the jargon this exists to explain.
///
/// A teacher who has not been told that will reasonably hear "I've published
/// tomorrow's class" as "students can see it now" — and act, or fail to act,
/// on that. So the assistant says it plainly the first time it works on a
/// section, and not again in the same conversation: a tool that re-explains
/// itself every few turns is one a teacher learns to skim.
///
/// Kept per SECTION rather than per course because that is the unit a teacher
/// works in, and because a teacher who takes on a second section months later
/// has usually forgotten.
///
/// **Who remembers, and for how long, is not here.** That is
/// <c>AssistWorkspace.NoteExplainedThisConversation</c>, and it is per
/// CONVERSATION. This class used to write a marker file per working folder,
/// which outlived the reason for it once a fixed phrasing let a TEACHER call
/// the tool; the reasoning is recorded on that method. This one holds only
/// the words.
/// </summary>
public static class Briefing
{
    /// <summary>
    /// The words themselves, in the app's voice: short, concrete, and about
    /// what the teacher will see rather than about how any of it works.
    ///
    /// An earlier wording said unpublished pages "stay in your folder and stay
    /// yours to edit", which is true and still manages to mislead: it implies
    /// the opposite of published pages, as though publishing a page hands it
    /// over. It does not. Every page in the course stays the teacher's to edit,
    /// always, and the flag decides one thing only — whether the page is built
    /// into the site. So publishing is described by where it shows up (the
    /// preview) rather than by who may touch it.
    /// </summary>
    public static string Words(string courseCode, int sectionNumber, string destination) =>
        $"Before we start on {courseCode} Section {sectionNumber}, two words I’ll use:\n\n" +
        "**Publish** and **unpublish** decide whether a page is built into your site. " +
        "A published page shows up in your preview; an unpublished one is left out of the build. " +
        "Either way it stays in your folder and stays yours to edit — publishing a page doesn’t " +
        "put it beyond your reach, and it doesn’t show it to anybody yet.\n\n" +
        $"**Deploying** is sending the built site to {destination}, and it is the only thing students " +
        "ever see. I can do that, but only if you ask me to — and I'll want you to look at the preview " +
        "first, because deploying is the step students notice. You can always do it yourself instead: " +
        "the button is there in Plantoir.\n\n" +
        "So: I publish pages and rebuild your preview, and I never deploy without being asked. " +
        "Nothing reaches students until you say so.";
}
