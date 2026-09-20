using System.ComponentModel;
using Microsoft.UI.Xaml.Media;
using Plantoir.Core.Models;

namespace Plantoir.Views;

/// <summary>
/// One crumb in the working-folder path bar. Wraps the platform-agnostic
/// <see cref="FolderCrumb"/> with the one thing that can't live in
/// Plantoir.Core: a WinUI image source for the folder's real shell icon
/// (contracts/shared-rules.json -> workingFolderPathBar.icons — "not
/// decoration: a teacher recognises their Desktop or a synced folder by its
/// icon before reading the word"). The icon loads asynchronously after the
/// bar is populated, so it starts null and notifies when it arrives.
/// </summary>
public sealed class PathBarCrumb(FolderCrumb crumb) : INotifyPropertyChanged
{
    public string Path { get; } = crumb.Path;
    public string DisplayName { get; } = crumb.DisplayName;

    /// <summary>Same reason FolderCrumb overrides this: the overflow
    /// dropdown and narrator fall back to ToString() independently of the
    /// item template, and the default would print the type name.</summary>
    public override string ToString() => DisplayName;

    public event PropertyChangedEventHandler? PropertyChanged;

    private ImageSource? _icon;

    /// <summary>Null until the shell icon has loaded (or failed to) — the
    /// crumb shows its name alone until then, never a broken image.</summary>
    public ImageSource? Icon
    {
        get => _icon;
        set
        {
            if (ReferenceEquals(_icon, value)) return;
            _icon = value;
            PropertyChanged?.Invoke(this, new PropertyChangedEventArgs(nameof(Icon)));
        }
    }
}
