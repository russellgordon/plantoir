using System;
using System.IO;
using System.Runtime.InteropServices;
using System.Threading;
using Microsoft.UI.Dispatching;
using Microsoft.UI.Xaml;
using WinRT;

namespace Plantoir;

public static class Program
{
    [DllImport("kernel32.dll", SetLastError = true, CharSet = CharSet.Unicode)]
    [return: MarshalAs(UnmanagedType.Bool)]
    private static extern bool SetDllDirectory(string lpPathName);

    [STAThread]
    public static void Main(string[] args)
    {
        // BEFORE the first log line, because that line resolves where it
        // goes the moment it is written. `--state-dir` is read here as well as
        // in OnLaunched: Main logs four times per launch, so a redirect that
        // waited for OnLaunched would already have written to the teacher's
        // own startup log. Setting it twice is harmless - the same value.
        for (int i = 0; i < args.Length - 1; i++)
            if (args[i] == "--state-dir") { Plantoir.Core.Models.AppDataRoot.RedirectTo(args[i + 1]); break; }

        App.LogDiagnostic($"Program.Main starting with {args.Length} args");
        try
        {
            string baseDir = AppContext.BaseDirectory;
            SetDllDirectory(baseDir);
            Environment.CurrentDirectory = baseDir;

            string webView2Dir = Plantoir.Core.Models.AppDataRoot.Combine("WebView2");
            Environment.SetEnvironmentVariable("WEBVIEW2_USER_DATA_FOLDER", webView2Dir);

            ComWrappersSupport.InitializeComWrappers();
            App.LogDiagnostic("Program.Main: ComWrappers initialized");

            Application.Start((p) =>
            {
                App.LogDiagnostic("Application.Start callback invoked");
                var context = new DispatcherQueueSynchronizationContext(DispatcherQueue.GetForCurrentThread());
                SynchronizationContext.SetSynchronizationContext(context);
                new App();
                App.LogDiagnostic("new App() instantiated");
            });
            App.LogDiagnostic("Application.Start returned");
        }
        catch (Exception ex)
        {
            App.LogDiagnostic($"Program.Main EXCEPTION: {ex}");
        }
    }
}
