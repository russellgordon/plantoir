using Plantoir.Core.Models;
using Plantoir.Core.Scripting;

// #911: runs the REAL one-section restore and stops at one point so a test can
// kill this process there. At the point it writes one line, "REACHED <point>",
// to standard output and then waits on standard input; the test waits for
// that line (an event, never a sleep) and kills the process tree.
//
// Arguments: <courses folder> <backup zip> <course code> <section> <stop at> <trail file> [route] [hold]
//   <stop at>: unpack:<n> (after the n-th entry of the backup is unpacked)
//              | staged | setAside | move:<k> (after the k-th move of the swap)
//              | back:<j> (after the j-th move of the way back, which [hold] starts)
//   [route]: assistant (the default, CourseRestorer.RestoreSection) | menu
//            (CourseRestorer.RestoreSectionFromTheMenu, Restore from Backup…'s
//            "Restore Section N", #911 step 3)
//   [hold]: a file, by its path inside the course folder, this process opens
//           without delete sharing before the restore, so the swap's move of
//           the folder holding it fails for real and the way back begins.
string coursesDirectory = args[0];
string backupPath = args[1];
string courseCode = args[2];
int section = int.Parse(args[3], System.Globalization.CultureInfo.InvariantCulture);
string stopAt = args[4];
ActivityTrail.SetCustomLogPathForTesting(args[5]);
string route = args.Length > 6 ? args[6] : "assistant";
FileStream? held = args.Length > 7
    ? new FileStream(Path.Combine(coursesDirectory, courseCode, args[7]), FileMode.Open, FileAccess.Read, FileShare.Read)
    : null;

void Stop(string point)
{
    Console.Out.WriteLine("REACHED " + point);
    Console.Out.Flush();
    Console.In.ReadLine();
}

int moves = 0, movesBack = 0;
bool wayBack = false;
var hooks = new CourseRestorer.SectionSwapHooks
{
    Move = (source, destination) =>
    {
        try { CourseRestorer.MoveEntry(source, destination); }
        catch { wayBack = true; throw; }       // a real refusal: every move after it is the way back
        if (wayBack)
        {
            movesBack++;
            if (stopAt == "back:" + movesBack) Stop(stopAt);
        }
        else
        {
            moves++;
            if (stopAt == "move:" + moves) Stop(stopAt);
        }
    },
    Reached = point =>
    {
        string name = point == CourseRestorer.SwapPoint.Staged ? "staged" : "setAside";
        if (stopAt == name) Stop(name);
    },
    UnpackedAnEntry = count =>
    {
        if (stopAt == "unpack:" + count) Stop(stopAt);
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
held?.Dispose();
