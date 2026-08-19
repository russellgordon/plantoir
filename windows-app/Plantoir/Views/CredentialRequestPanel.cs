using System;
using Microsoft.UI.Xaml;
using Microsoft.UI.Xaml.Controls;
using Plantoir.Core.Scripting;

namespace Plantoir.Views;

/// <summary>
/// Renders a CredentialRequest the way the mac's CredentialRequestSheet
/// does: the explanation, the numbered steps, and — only when the request
/// actually carries one — the page to get the credential from as a link.
/// One builder for every dialog that shows a request, because the copies
/// drifted: the console dialog assumed a link always exists, and
/// `new Uri("")` THROWS — which is how the surname and website-address
/// dialogs (the three linkless requests) never appeared at all.
/// </summary>
internal static class CredentialRequestPanel
{
    public static StackPanel Build(CredentialRequest request)
    {
        var panel = new StackPanel { Spacing = 12, MaxWidth = 480 };
        panel.Children.Add(new TextBlock { Text = request.Explanation, TextWrapping = TextWrapping.Wrap });

        var stepsList = new StackPanel { Spacing = 6, Margin = new Thickness(0, 4, 0, 4) };
        for (int i = 0; i < request.Steps.Count; i++)
        {
            stepsList.Children.Add(new TextBlock
            {
                Text = $"{i + 1}. {request.Steps[i]}",
                TextWrapping = TextWrapping.Wrap
            });
        }
        panel.Children.Add(stepsList);

        // The link is a link, never an automatic browser tab — and only
        // when there is one (mac parity: `if let linkAddress, !linkTitle
        // .isEmpty` in CredentialRequestSheet.swift).
        if (request.LinkAddress.Length > 0 && request.LinkTitle.Length > 0)
        {
            panel.Children.Add(new HyperlinkButton
            {
                Content = request.LinkTitle,
                NavigateUri = new Uri(request.LinkAddress),
                Padding = new Thickness(0)
            });
        }
        return panel;
    }
}
