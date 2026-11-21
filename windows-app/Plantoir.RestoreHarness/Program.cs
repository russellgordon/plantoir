using Plantoir.Core.Models;
using Plantoir.Core.Scripting;

// #911: runs the REAL one-section restore of the assistant window's route
// (CourseRestorer.RestoreSection) and stops at one point so a test can kill
// this process there. At the point it writes one line, "REACHED <point>", to
// standard output and then waits on standard input; the test waits for that
// line (an event, never a sleep) and kills the process tree.
//
// Arguments: <courses folder> <backup zip> <course code> <section> <stop at> <trail file> [route]
//   <stop at>: staged | setAside | move:<k> (after the k-th move of the swap)
//   [route]: assistant (the default, CourseRestorer.RestoreSection) | menu
//            (CourseRestorer.RestoreSectionFromTheMenu, Restore from Backup…'s
//            "Restore Section N", #911 step 3)
string coursesDirectory = args[0];
string backupPath = args[1];
string courseCode = args[2];
int section = int.Parse(args[3], System.Globalization.CultureInfo.InvariantCulture);
string stopAt = args[4];
ActivityTrail.SetCustomLogPathForTesting(args[5]);
string route = args.Length > 6 ? args[6] : "assistant";

void Stop(string point)
{
    Console.Out.WriteLine("REACHED " + point);
    Console.Out.Flush();
    Console.In.ReadLine();
}

int moves = 0;
var hooks = new CourseRestorer.SectionSwapHooks
{
    Move = (source, destination) =>
    {
        CourseRestorer.MoveEntry(source, destination);
        moves++;
        if (stopAt == "move:" + moves) Stop(stopAt);
    },
    Reached = point =>
    {
        string name = point == CourseRestorer.SwapPoint.Staged ? "staged" : "setAside";
        if (stopAt == name) Stop(name);
    },
};

var item = BackupItem.From(backupPath, courseCode) ?? throw new InvalidOperationException("not a backup: " + backupPath);
try
{
    if (route == "menu") CourseRestorer.RestoreSectionFromTheMenu(section, item, coursesDirectory, hooks);
    else CourseRestorer.RestoreSection(section, item, coursesDirectory, hooks);
    Console.Out.WriteLine("FINISHED");
}
catch (Exception error)
{
    Console.Out.WriteLine("FAILED " + error.Message);
}
