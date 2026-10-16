using System.Text.Json.Nodes;
using Plantoir.Core.Models;

namespace Plantoir.Tests;

/// <summary>
/// <c>contracts/shared-rules.json</c> → <c>sidebarDeleteKey</c> (#491 items 5–6,
/// the mac's #457): the Delete key runs the menu item the row names, under that
/// item's own enablement. The − button follows the same rule for removal only,
/// and its enablement is pinned against every <c>subjectMenus</c> case whose row
/// is a course or a section — so a reference SECTION (whose cases withhold
/// removeSection, <c>interface.whatIsWithheld</c>) greys it, which before #491
/// removed the whole course instead.
/// </summary>
public class SidebarDeleteKeyContractTests
{
    private static JsonNode Rule => ContractLoader.LoadJson("shared-rules.json")["sidebarDeleteKey"]!;

    private static SubjectMenuRules.Row RowNamed(string name) =>
        Enum.GetValues<SubjectMenuRules.Row>().Single(row => SubjectMenuRules.ContractName(row) == name);

    [Fact]
    public void EveryRowRunsTheItemTheContractNames()
    {
        var cases = Rule["cases"]!.AsArray().Select(c => c!).ToList();
        Assert.Equal(6, cases.Count);
        foreach (var c in cases)
        {
            var row = RowNamed(c["row"]!.ToString());
            string? expected = c["item"]?.ToString();
            var actual = SidebarDeleteKey.ItemFor(row);
            Assert.Equal(expected, actual is { } item ? SubjectMenuRules.ContractName(item) : null);
        }
        // Every row kind is a case: nothing here the contract does not decide.
        Assert.Equal(Enum.GetValues<SubjectMenuRules.Row>().Select(SubjectMenuRules.ContractName).OrderBy(n => n),
                     cases.Select(c => c["row"]!.ToString()).OrderBy(n => n));
    }

    [Fact]
    public void WhatWasRejected_IsWrittenDown() =>
        Assert.NotEmpty(Rule["rejected"]!.AsArray());

    /// <summary>The − button is enabled exactly when the menu's removal item is, on every course and section case.</summary>
    [Fact]
    public void TheMinusButton_FollowsTheMenusRemoval()
    {
        int checkedCases = 0;
        foreach (var c in SubjectMenusContractTests.Rule["cases"]!.AsArray().Select(c => c!))
        {
            var situation = SubjectMenusContractTests.Situation(c["situation"]!.AsObject());
            if (situation.Row is not (SubjectMenuRules.Row.Course or SubjectMenuRules.Row.Section)) continue;
            string item = situation.Row == SubjectMenuRules.Row.Course ? "removeCourse" : "removeSection";
            bool expected = c["enabled"]!.AsArray().Any(n => n!.ToString() == item);
            Assert.True(expected == SidebarDeleteKey.MinusButtonIsEnabled(situation), $"{c["why"]}: − should be {(expected ? "enabled" : "greyed")}");
            checkedCases++;
        }
        Assert.True(checkedCases >= 10, $"only {checkedCases} course and section cases");
    }

    [Theory]
    [InlineData(SubjectMenuRules.Row.Backup)]
    [InlineData(SubjectMenuRules.Row.Archived)]
    [InlineData(SubjectMenuRules.Row.AllBackups)]
    [InlineData(SubjectMenuRules.Row.None)]
    public void TheMinusButton_NeverDeletes(SubjectMenuRules.Row row)
    {
        Assert.Null(SidebarDeleteKey.MinusButtonItem(row));
        Assert.False(SidebarDeleteKey.MinusButtonIsEnabled(new SubjectMenuRules.Situation { HasFolder = true, Row = row }));
    }

    [Fact]
    public void RowOf_ReadsTheSelection()
    {
        Assert.Equal(SubjectMenuRules.Row.Course, SidebarDeleteKey.RowOf(new SidebarSelection.CourseItem("ICS3U"), false));
        Assert.Equal(SubjectMenuRules.Row.Section, SidebarDeleteKey.RowOf(new SidebarSelection.SectionItem("ICS3U", 2), false));
        Assert.Equal(SubjectMenuRules.Row.Backup, SidebarDeleteKey.RowOf(new SidebarSelection.BackupEntry("b"), false));
        Assert.Equal(SubjectMenuRules.Row.Archived, SidebarDeleteKey.RowOf(new SidebarSelection.ArchivedEntry("a"), false));
        Assert.Equal(SubjectMenuRules.Row.AllBackups, SidebarDeleteKey.RowOf(null, true));
        Assert.Equal(SubjectMenuRules.Row.None, SidebarDeleteKey.RowOf(null, false));
    }
}
