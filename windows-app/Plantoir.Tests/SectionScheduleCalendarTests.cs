using System;
using System.Collections.Generic;
using System.IO;
using Plantoir.Core.Assist;
using Xunit;

namespace Plantoir.Tests;

public class SectionScheduleCalendarTests
{
    [Fact]
    public void CalendarDayTextExtractsIsoDate()
    {
        Assert.Equal("2026-09-08", SectionScheduleSource.CalendarDayText("20260908T090000Z"));
        Assert.Equal("2026-09-08", SectionScheduleSource.CalendarDayText("20260908"));
        Assert.Equal("short", SectionScheduleSource.CalendarDayText("short"));
    }

    [Fact]
    public void UnfoldedReassemblesWrappedLines()
    {
        string raw = "DTSTART;VALUE=DATE:\r\n 20260908\r\nSUMMARY:First\r\n\t Class\r\n";
        var unfolded = SectionScheduleSource.Unfolded(raw);
        Assert.Equal(2, unfolded.Count);
        Assert.Equal("DTSTART;VALUE=DATE:20260908", unfolded[0]);
        Assert.Equal("SUMMARY:First Class", unfolded[1]);
    }

    [Fact]
    public void ReadFromIcsCalendarExportExtractsDates()
    {
        string ics = @"BEGIN:VCALENDAR
VERSION:2.0
PRODID:-//Test//Calendar//EN
BEGIN:VEVENT
UID:123
DTSTART;VALUE=DATE:20260908
SUMMARY:Class 1
END:VEVENT
BEGIN:VEVENT
UID:456
DTSTART:20260910T143000Z
SUMMARY:Class 2
END:VEVENT
BEGIN:VEVENT
UID:789
DTSTART:
 20260915T090000
SUMMARY:Class 3
END:VEVENT
END:VCALENDAR";

        string temp = Path.GetTempFileName();
        string icsPath = Path.ChangeExtension(temp, ".ics");
        File.Move(temp, icsPath);

        try
        {
            File.WriteAllText(icsPath, ics);
            var outcome = SectionScheduleSource.ReadFromFile(icsPath);
            Assert.IsType<ScheduleOutcome.Dates>(outcome);

            var datesOutcome = (ScheduleOutcome.Dates)outcome;
            Assert.Equal(new[] { "2026-09-08", "2026-09-10", "2026-09-15" }, datesOutcome.Reading.DatesText);
            Assert.Equal(Path.GetFileName(icsPath), datesOutcome.Reading.SuggestedSource);
        }
        finally
        {
            try { File.Delete(icsPath); } catch { }
        }
    }

    [Fact]
    public void ReadFromIcsWithoutDtstartThrowsRefusal()
    {
        string ics = @"BEGIN:VCALENDAR
VERSION:2.0
PRODID:-//Test//Calendar//EN
BEGIN:VEVENT
UID:123
SUMMARY:Empty Event
END:VEVENT
END:VCALENDAR";

        string temp = Path.GetTempFileName();
        string icsPath = Path.ChangeExtension(temp, ".ics");
        File.Move(temp, icsPath);

        try
        {
            File.WriteAllText(icsPath, ics);
            var ex = Assert.Throws<AssistRefusal>(() => SectionScheduleSource.ReadFromFile(icsPath));
            Assert.Contains("No start dates were found", ex.Message);
        }
        finally
        {
            try { File.Delete(icsPath); } catch { }
        }
    }
}
