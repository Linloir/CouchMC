using System;
using System.IO;
using Microsoft.UI.Xaml;
using Microsoft.UI.Xaml.Controls;
using Microsoft.UI.Xaml.Media;
using Microsoft.UI.Xaml.Media.Animation;
using Windows.Graphics;

namespace McController.App;

public sealed partial class MainWindow : Window
{
    public MainWindow()
    {
        InitializeComponent();
        Title = "MC Controller";

        ExtendsContentIntoTitleBar = true;
        SetTitleBar(AppTitleBar);

        // App icon for the taskbar / Alt-Tab list. AppContext.BaseDirectory
        // resolves to the exe directory at runtime; Assets/app.ico is copied
        // there by the csproj's <Content> declaration.
        try
        {
            AppWindow.SetIcon(Path.Combine(AppContext.BaseDirectory, "Assets", "app.ico"));
        }
        catch { /* fall back to default icon */ }

        // Mica backdrop — Win11+ requirement; silently fails on Win10 and we
        // fall back to the standard solid surface, which still looks fine.
        try
        {
            SystemBackdrop = new MicaBackdrop
            {
                Kind = Microsoft.UI.Composition.SystemBackdrops.MicaKind.Base,
            };
        }
        catch { }

        try
        {
            AppWindow.Resize(new SizeInt32 { Width = 1100, Height = 720 });
        }
        catch { }
    }

    private void Nav_Loaded(object sender, RoutedEventArgs e)
    {
        // First-launch landing is Settings (Discovery is empty until a phone
        // connects). Use SlideNavigationTransitionInfo for the Win11-style
        // page slide.
        foreach (var item in Nav.MenuItems)
        {
            if (item is NavigationViewItem parent)
            {
                foreach (var child in parent.MenuItems)
                {
                    if (child is NavigationViewItem nvi && (nvi.Tag as string) == "settings")
                    {
                        Nav.SelectedItem = nvi;
                        break;
                    }
                }
                break;
            }
        }
        ContentFrame.Navigate(
            typeof(Views.SettingsPage),
            null,
            new SlideNavigationTransitionInfo { Effect = SlideNavigationTransitionEffect.FromRight });
    }

    private void Nav_SelectionChanged(NavigationView sender, NavigationViewSelectionChangedEventArgs args)
    {
        if (args.SelectedItem is not NavigationViewItem item) return;
        Type? target = (item.Tag as string) switch
        {
            "discovery" => typeof(Views.DeviceDiscoveryPage),
            "settings" => typeof(Views.SettingsPage),
            _ => null,
        };
        if (target is null) return;
        if (ContentFrame.CurrentSourcePageType == target) return;
        ContentFrame.Navigate(
            target,
            null,
            new SlideNavigationTransitionInfo { Effect = SlideNavigationTransitionEffect.FromBottom });
    }
}
