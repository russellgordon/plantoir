using System;
using System.Diagnostics;
using System.IO;
using Plantoir.Core.Models;

namespace Plantoir.Services;

/// <summary>
/// Opens a web address in the teacher's own browser — except in a redirected
/// run (<c>--state-dir</c>, the UI tests), where the address is appended to
/// <c>links-opened.txt</c> in the run's state folder instead, so a test can
/// read what WOULD have opened and never puts a browser in front of the
/// person at the desk. The same arrangement as <c>DialogGate.Holds</c>'
/// measurement files.
/// </summary>
public static class ExternalLinks
{
    /// <summary>Where a redirected run writes the addresses it did not open, one per line.</summary>
    public const string OpenedFileName = "links-opened.txt";

    /// <summary>Opens <paramref name="address"/>; true when it was handed over (or recorded, in a redirected run).</summary>
    public static bool Open(Uri address)
    {
        try
        {
            if (AppDataRoot.IsRedirected)
            {
                File.AppendAllText(AppDataRoot.Combine(OpenedFileName), address.AbsoluteUri + Environment.NewLine);
                return true;
            }
            Process.Start(new ProcessStartInfo(address.AbsoluteUri) { UseShellExecute = true });
            return true;
        }
        catch (Exception ex)
        {
            App.LogDiagnostic($"could not open {address.AbsoluteUri}: {ex.Message}");
            return false;
        }
    }
}
