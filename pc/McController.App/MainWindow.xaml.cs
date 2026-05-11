using System;
using System.IO;
using System.Runtime.InteropServices;
using Microsoft.UI.Xaml;
using Microsoft.UI.Xaml.Controls;
using Microsoft.UI.Xaml.Media;
using Microsoft.UI.Xaml.Media.Animation;
using Windows.Graphics;
using WinRT.Interop;

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
            // AppWindow.Resize takes physical pixels, so multiply by the
            // window's DPI scale to keep the on-screen size consistent on
            // high-DPI displays (otherwise 1280 physical = ~853 logical
            // at 150% scale and the window looks tiny).
            var hwnd = WindowNative.GetWindowHandle(this);
            double scale = GetDpiForWindow(hwnd) / 96.0;
            if (scale <= 0) scale = 1.0;
            AppWindow.Resize(new SizeInt32
            {
                Width = (int)(1400 * scale),
                Height = (int)(900 * scale),
            });
        }
        catch { }
    }

    [DllImport("user32.dll")]
    private static extern uint GetDpiForWindow(IntPtr hwnd);

    private void Nav_Loaded(object sender, RoutedEventArgs e)
    {
        // First-launch landing is Device Discovery — it's where the user
        // pairs their phone, so it's the natural starting point.
        foreach (var item in Nav.MenuItems)
        {
            if (item is NavigationViewItem parent)
            {
                foreach (var child in parent.MenuItems)
                {
                    if (child is NavigationViewItem nvi && (nvi.Tag as string) == "discovery")
                    {
                        Nav.SelectedItem = nvi;
                        break;
                    }
                }
                break;
            }
        }
        ContentFrame.Navigate(
            typeof(Views.DeviceDiscoveryPage),
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
