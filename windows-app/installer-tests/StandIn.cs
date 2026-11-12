// A stand-in for node.exe, python.exe, Plantoir.exe and the rest, installed by
// the harness installer (#700) so a test can run "a preview serve", "a build"
// or "work that never ends" FROM the harness's own install folder, the way
// the real ones run from {app}\runtime. Built by run-harness.ps1 with the .NET
// Framework's csc.exe (always present on Windows 10 and 11), so it needs no
// SDK and is a few KB.
//
//   --seconds N       exit after N seconds (default: run until ended)
//   --hold PATH       keep PATH open without delete sharing, the way a running
//                     interpreter holds python311.dll: [InstallDelete] cannot
//                     remove it while this runs
//   --child EXE ...   start EXE with the remaining arguments and wait for it,
//                     then exit (build_site.py's subprocess.run of node)
//   --linger-ms N     (before --child) stay N ms after the child has gone
// Any other argument is ignored, so a command line can carry the real shapes
// (`bootstrap-cli.mjs build --serve --port 8081`). Every start is recorded in
// %TEMP%\plantoir-installer-harness\started.txt, OUTSIDE the install folder.
using System;
using System.Diagnostics;
using System.IO;
using System.Text;
using System.Threading;

static class StandIn
{
    static int Main(string[] args)
    {
        try
        {
            string record = Path.Combine(Path.GetTempPath(), "plantoir-installer-harness");
            Directory.CreateDirectory(record);
            File.AppendAllText(Path.Combine(record, "started.txt"),
                DateTime.UtcNow.ToString("o") + "\t" + Process.GetCurrentProcess().Id + "\t" + Environment.CommandLine + Environment.NewLine);
        }
        catch (Exception) { }

        int seconds = -1;
        int lingerMs = 0;
        FileStream held = null;
        for (int i = 0; i < args.Length; i++)
        {
            if (args[i] == "--stand-down-if-installing" && i + 1 < args.Length)
            {
                // What ScheduledRun does since #700's third review: an
                // installer's installing.<pid> marker means stand down and
                // EXIT AT ONCE, so this image is not held while it is replaced.
                string folder = args[++i];
                bool installing = Directory.Exists(folder) && Directory.GetFiles(folder, "installing.*").Length > 0;
                try
                {
                    File.AppendAllText(Path.Combine(Path.GetTempPath(), "plantoir-installer-harness", "started.txt"),
                        (installing ? "STOODDOWN" : "RAN") + "\t" + Process.GetCurrentProcess().MainModule.FileName + Environment.NewLine);
                }
                catch (Exception) { }
                return 0;
            }
            // What it did before (the must-fail): WAIT while the marker is there.
            if (args[i] == "--wait-while-installing" && i + 1 < args.Length)
            {
                // A scheduled run's wait, in miniature: while the installer's
                // installing.<pid> marker is in the state folder, wait.
                string folder = args[++i];
                var clock = Stopwatch.StartNew();
                bool saw = false;
                while (Directory.Exists(folder) && Directory.GetFiles(folder, "installing.*").Length > 0 && clock.Elapsed.TotalSeconds < 60)
                {
                    saw = true;
                    Thread.Sleep(200);
                }
                try
                {
                    File.AppendAllText(Path.Combine(Path.GetTempPath(), "plantoir-installer-harness", "started.txt"),
                        "WAITED\t" + (long)clock.Elapsed.TotalMilliseconds + "\tSAW\t" + saw + Environment.NewLine);
                }
                catch (Exception) { }
                return 0;
            }
            if (args[i] == "--seconds" && i + 1 < args.Length) { seconds = int.Parse(args[++i]); }
            else if (args[i] == "--linger-ms" && i + 1 < args.Length) { lingerMs = int.Parse(args[++i]); }
            else if (args[i] == "--hold" && i + 1 < args.Length)
            {
                held = new FileStream(args[++i], FileMode.Open, FileAccess.Read, FileShare.Read);
            }
            else if (args[i] == "--child" && i + 1 < args.Length)
            {
                string exe = args[i + 1];
                var rest = new StringBuilder();
                for (int j = i + 2; j < args.Length; j++)
                {
                    if (rest.Length > 0) rest.Append(' ');
                    rest.Append(args[j].Contains(" ") ? "\"" + args[j] + "\"" : args[j]);
                }
                var child = Process.Start(new ProcessStartInfo(exe, rest.ToString()) { UseShellExecute = false });
                child.WaitForExit();
                // A real build_site.py outlives its ended server briefly (0.3 s
                // on the real installer, 2026-11-12); --linger-ms makes that so.
                if (lingerMs > 0) Thread.Sleep(lingerMs);
                GC.KeepAlive(held);
                return 3;   // like subprocess.run(check=True) when its child was ended
            }
        }
        if (seconds < 0) Thread.Sleep(Timeout.Infinite);
        Thread.Sleep(seconds * 1000);
        GC.KeepAlive(held);
        return 0;
    }
}
