using Xunit.Abstractions;

namespace Plantoir.UiTests;

/// <summary>
/// End to end, ruling U2 (5): a section set to publish to a folder on this
/// PC, Deploy pressed in the window, and the PUBLISHED FOLDER read back — the
/// front page and a visible page are in it, a page hidden from the section is
/// not in it anywhere (not as a page, not in the search index).
/// </summary>
/// <remarks>
/// Runs the real build and the real <c>deploy.ps1 --to-folder</c>. The
/// destination is a folder beside the temporary working folder, deleted with
/// the run; the build in the real builds root is deleted by
/// <see cref="DrivenApp.Dispose"/>. Netlify and Cloudflare are not driven from
/// the window (ruling U2): <c>verify-deploy.ps1</c> owns those.
/// </remarks>
[Collection("drives the real app")]
public class PublishToFolderUiTests
{
    private const string Code = "UIPUB4";
    private static readonly TimeSpan LongEnoughToPublish = TimeSpan.FromMinutes(15);

    private readonly ITestOutputHelper _output;
    public PublishToFolderUiTests(ITestOutputHelper output) => _output = output;

    [UiFact]
    public void DeployingToAFolderPublishesWhatStudentsMaySeeAndNothingElse()
    {
        string front = EndToEnd.Marker("Front"), visible = EndToEnd.Marker("Visible"), hidden = EndToEnd.Marker("Hidden");
        string? published = null;
        using var app = new DrivenApp(courses =>
        {
            published = Path.Combine(Path.GetDirectoryName(Path.GetDirectoryName(courses)!)!, "published");
            Directory.CreateDirectory(published);
            string dir = EndToEnd.WriteCourse(courses, Code, "Publishing End to End", new[] { "Concepts" },
                EndToEnd.PublishesTo(published), frontPage: $"---\ntitle: {Code}\n---\n# Welcome\n\n{front}\n");
            EndToEnd.WritePage(Path.Combine(dir, "Concepts", "Circuits.md"), "title: Circuits", $"Visible to students: {visible}");
            EndToEnd.WritePage(Path.Combine(dir, "Concepts", "Answer Key.md"), "title: Answer Key\npublishForSection1: false",
                               $"Held back: {hidden}");
        });

        app.SelectSection(Code, 1);
        var pressed = DateTime.Now;
        EndToEnd.DeployAndWait(app, LongEnoughToPublish);
        _output.WriteLine($"deployed to a folder in {(DateTime.Now - pressed).TotalSeconds:0} s");

        string site = Path.Combine(published!, "section1");
        Assert.True(File.Exists(Path.Combine(site, "index.html")), $"nothing was published at {site}");
        Assert.NotEmpty(EndToEnd.FilesContaining(site, front));
        Assert.NotEmpty(EndToEnd.FilesContaining(site, visible));
        var leaked = EndToEnd.FilesContaining(site, hidden);
        Assert.True(leaked.Count == 0, "a page hidden from section 1 was published: " + string.Join(", ", leaked));

        // The same answer in the build the publish was made from.
        string built = Path.Combine(app.RealBuildsRoot, Code, "section1", "public");
        Assert.NotEmpty(EndToEnd.FilesContaining(built, visible));
        Assert.Empty(EndToEnd.FilesContaining(built, hidden));
    }
}
