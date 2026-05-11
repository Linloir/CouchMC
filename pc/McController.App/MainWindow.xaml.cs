using System;
using System.IO;
using System.Runtime.InteropServices;
using Microsoft.UI.Xaml;
using Microsoft.UI.Xaml.Controls;
using Microsoft.UI.Xaml.Input;
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

        // Desktop Acrylic blurs the *live* content behind the window
        // (other apps + wallpaper) rather than wallpaper-only the way
        // MicaBackdrop does. Falls through silently on systems that
        // don't support it (Win10), leaving the standard solid surface.
        try { SystemBackdrop = new DesktopAcrylicBackdrop(); }
        catch { }

        // Click-anywhere-to-defocus. Use AddHandler with handledEventsToo
        // so we still see PointerPressed even when inner inputs handled
        // it; the IsInsideInput check then decides whether to pull focus.
        RootGrid.AddHandler(
            UIElement.PointerPressedEvent,
            new PointerEventHandler(OnRootPointerPressed),
            handledEventsToo: true);

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

    /// <summary>
    /// Pull focus to the invisible FocusSink button when the user clicks
    /// somewhere that isn't a text-input control. Without this, focus
    /// (and the keyboard caret) stays trapped in a NumberBox / TextBox
    /// until the user explicitly tabs out — Win11 Settings dismisses it
    /// the moment you click empty space, this matches that.
    /// </summary>
    private void OnRootPointerPressed(object sender, PointerRoutedEventArgs e)
    {
        if (e.OriginalSource is DependencyObject src && !IsInsideTextInput(src))
        {
            FocusSink.Focus(FocusState.Pointer);
        }
    }

    private static bool IsInsideTextInput(DependencyObject? element)
    {
        while (element != null)
        {
            switch (element)
            {
                case TextBox:
                case NumberBox:
                case PasswordBox:
                case RichEditBox:
                case AutoSuggestBox:
                    return true;
            }
            element = VisualTreeHelper.GetParent(element);
        }
        return false;
    }

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
