using System;
using System.Collections.Generic;

namespace Plantoir.Core.Models;

/// <summary>
/// Every sentence the Problems tab, its marker and its alert say (#734).
/// </summary>
/// <remarks>
/// <para>Retyped from <c>contracts/shared-rules.json</c> →
/// <c>sectionProblems.words</c> and <c>sectionProblems.kinds</c> (each kind's
/// <c>label</c> and <c>scope</c>), and pinned against them key by key by
/// <c>SectionProblemsContractTests</c> — one constant per word, its name the
/// key with a capital, the arrangement <c>LinksChecklistWording</c> uses. A
/// word with a <c>{placeholder}</c> is kept as its template and filled by
/// <see cref="Fill"/>, in one pass. The ROWS' own words are not here: the
/// shared Python writes them into the record, worded by the folder problem's
/// own makers.</para>
///
/// <para>Close and Not Now are not here either: they are
/// <see cref="SiteHealthRepair.CloseTitle"/>'s, as on every folder-problem
/// dialog.</para>
/// </remarks>
public static class SectionProblemsWording
{
    // ---- The tabs

    public const string TabWebsite = "Website";
    public const string TabProblems = "Problems";

    // ---- The table

    public const string ColumnIncluded = "Include";
    public const string ColumnKind = "Kind";
    public const string ColumnPage = "Page";
    public const string ColumnProblem = "Problem";
    public const string ColumnFirstFound = "First found";
    public const string ColumnLastFound = "Last found";
    public const string WholeSection = "Whole section";
    public const string WholeCourse = "Whole course";
    public const string Intro = "What the last preview or deploy of {course} Section {section} found. A problem leaves this list when a build no longer finds it.";
    public const string FixedInTheSource = "Fixed in the source — preview or deploy this section to update it.";

    // ---- The alert

    public const string AlertTitleOne = "A new problem in {course} Section {section}";
    public const string AlertTitleSeveral = "{count} new problems in {course} Section {section}";
    public const string AlertMessage = "Show opens this section’s Problems tab, which names the page of each problem and what to change.";
    public const string AlertAlsoGoneOne = "One problem found before is gone.";
    public const string AlertAlsoGoneSeveral = "{count} problems found before are gone.";
    public const string Show = "Show";

    // ---- The marker

    public const string MarkerHelp = "The last preview or deploy of this section found problems. Open its Problems tab to see them.";

    // ---- Kinds

    /// <summary><c>sectionProblems.kinds</c> → each kind's <c>label</c>.</summary>
    public static readonly IReadOnlyDictionary<string, string> KindLabels = new Dictionary<string, string>(StringComparer.Ordinal)
    {
        ["curriculumCoverageFoundNothing"] = "Curriculum map",
        ["courseTeachesNothing"] = "Curriculum map",
        ["mediaFolderMissing"] = "Media folder",
        ["sectionIndexMissing"] = "Front page",
        ["handWrittenCoveragePage"] = "Curriculum map",
        ["noGradedFolders"] = "Curriculum map",
        ["pageSettingsUnreadable"] = "Page settings",
        ["linksIntoHiddenPages"] = "Link to a hidden page",
        ["printPdfNotFound"] = "Handout",
        ["figuresCouldNotBeDrawn"] = "Diagram or graph",
        ["swiftCouldNotBePrepared"] = "Swift program",
        ["quizzesNotReady"] = "Self-check question",
        ["runnableCodeShownAsPlainCode"] = "Runnable code",
        ["quizzesReadDifferently"] = "Self-check question",
        ["geogebraSketchesNotReady"] = "GeoGebra sketch",
        ["filesTooLargeForCloudflare"] = "File too large",
    };

    /// <summary><c>sectionProblems.kinds</c> → each kind's <c>scope</c>.</summary>
    public static readonly IReadOnlyDictionary<string, string> KindScopes = new Dictionary<string, string>(StringComparer.Ordinal)
    {
        ["curriculumCoverageFoundNothing"] = "section",
        ["courseTeachesNothing"] = "section",
        ["mediaFolderMissing"] = "course",
        ["sectionIndexMissing"] = "section",
        ["handWrittenCoveragePage"] = "section",
        ["noGradedFolders"] = "section",
        ["pageSettingsUnreadable"] = "page",
        ["linksIntoHiddenPages"] = "page",
        ["printPdfNotFound"] = "page",
        ["figuresCouldNotBeDrawn"] = "page",
        ["swiftCouldNotBePrepared"] = "page",
        ["quizzesNotReady"] = "page",
        ["runnableCodeShownAsPlainCode"] = "page",
        ["quizzesReadDifferently"] = "page",
        ["geogebraSketchesNotReady"] = "page",
        ["filesTooLargeForCloudflare"] = "section",
    };

    /// <summary>
    /// Fills every <c>{name}</c> in ONE pass, so a value that itself holds a
    /// brace — a course name, a TeX error inside a row — is never read as a
    /// placeholder.
    /// </summary>
    public static string Fill(string template, IReadOnlyDictionary<string, string> values)
    {
        var made = new System.Text.StringBuilder();
        int i = 0;
        while (i < template.Length)
        {
            if (template[i] == '{')
            {
                int end = template.IndexOf('}', i + 1);
                if (end > i && values.TryGetValue(template[(i + 1)..end], out var value))
                {
                    made.Append(value);
                    i = end + 1;
                    continue;
                }
            }
            made.Append(template[i]);
            i++;
        }
        return made.ToString();
    }

    /// <summary>A kind's label; a kind this app does not know yet reads as its name rather than as nothing.</summary>
    public static string LabelOfKind(string kind) => KindLabels.TryGetValue(kind, out var label) ? label : kind;

    /// <summary>What the Page column shows for a row.</summary>
    public static string PageColumn(SectionProblemRow row)
    {
        if (row.Page.Length > 0) return row.Page;
        return KindScopes.TryGetValue(row.Kind, out var scope) && scope == "course" ? WholeCourse : WholeSection;
    }

    /// <summary>The words above the table.</summary>
    public static string IntroFor(string course, int section) =>
        Fill(Intro, new Dictionary<string, string> { ["course"] = course, ["section"] = section.ToString() });

    /// <summary>The alert's title for a record's new problems.</summary>
    public static string AlertTitle(int newCount, string course, int section) =>
        newCount == 1
            ? Fill(AlertTitleOne, new Dictionary<string, string> { ["course"] = course, ["section"] = section.ToString() })
            : Fill(AlertTitleSeveral, new Dictionary<string, string>
                { ["count"] = newCount.ToString(), ["course"] = course, ["section"] = section.ToString() });

    /// <summary>
    /// The alert's message, as paragraphs: the new problem's own sentence when
    /// there is exactly one, where Show takes you, and how many went.
    /// </summary>
    public static IReadOnlyList<string> AlertParagraphs(IReadOnlyList<SectionProblemRow> newRows, int goneCount)
    {
        var paragraphs = new List<string>();
        if (newRows.Count == 1 && newRows[0].Sentence.Length > 0) paragraphs.Add(newRows[0].Sentence);
        paragraphs.Add(AlertMessage);
        if (goneCount == 1) paragraphs.Add(AlertAlsoGoneOne);
        else if (goneCount > 1)
            paragraphs.Add(Fill(AlertAlsoGoneSeveral, new Dictionary<string, string> { ["count"] = goneCount.ToString() }));
        return paragraphs;
    }

    /// <summary>
    /// What the Problem column says: the contract's sentence for a row fixed
    /// in the source, else the row's item, else its sentence (a row with no
    /// page has no item).
    /// </summary>
    public static string ProblemColumn(SectionProblemRow row, SectionProblemsRules.RowState state) =>
        state == SectionProblemsRules.RowState.FixedInTheSource ? FixedInTheSource
        : row.Item.Length > 0 ? row.Item
        : row.Sentence;

    /// <summary>The whole of what the folder problem says — the row's tooltip and its help text.</summary>
    public static string Help(SectionProblemRow row) =>
        row.Detail.Length == 0 ? row.Sentence : row.Sentence + "\n\n" + row.Detail;
}
