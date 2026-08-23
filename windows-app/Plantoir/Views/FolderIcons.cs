using System;
using System.Collections.Generic;
using System.Threading.Tasks;
using Microsoft.UI.Xaml.Media.Imaging;
using Windows.Storage;
using Windows.Storage.FileProperties;

namespace Plantoir.Views;

/// <summary>
/// Real shell icons for the working-folder path bar's crumbs
/// (contracts/shared-rules.json -> workingFolderPathBar.icons). Uses the
/// same Shell thumbnail API Explorer itself draws from, so a synced or
/// pinned folder's overlay badge shows too, not a generic folder glyph.
/// Cached by path: a dozen crumbs would otherwise re-hit the shell on every
/// path-bar refresh.
/// </summary>
public static class FolderIcons
{
    private static readonly Dictionary<string, BitmapImage?> Cache =
        new(StringComparer.OrdinalIgnoreCase);

    /// <summary>The folder's shell icon, or null if it can't be loaded — the
    /// caller falls back to showing the crumb's name alone rather than a
    /// broken image. Optional decoration, per the contract note that says
    /// so explicitly.</summary>
    public static async Task<BitmapImage?> ForPathAsync(string path)
    {
        if (Cache.TryGetValue(path, out var cached)) return cached;

        BitmapImage? result = null;
        try
        {
            var folder = await StorageFolder.GetFolderFromPathAsync(path);
            using var thumbnail = await folder.GetThumbnailAsync(
                ThumbnailMode.SingleItem, 32, ThumbnailOptions.UseCurrentScale);
            if (thumbnail is not null)
            {
                var image = new BitmapImage();
                await image.SetSourceAsync(thumbnail);
                result = image;
            }
        }
        catch { /* icon is optional — see ForPathAsync's doc comment */ }

        Cache[path] = result;
        return result;
    }
}
