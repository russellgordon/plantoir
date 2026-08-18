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
        App.LogDiagnostic($"Program.Main starting with {args.Length} args");
        try
        {
            string baseDir = AppContext.BaseDirectory;
            SetDllDirectory(baseDir);
            Environment.CurrentDirectory = baseDir;

            string localAppData = Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.LocalApplicationData), "Plantoir");
            string webView2Dir = Path.Combine(localAppData, "WebView2");
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
