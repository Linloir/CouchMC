using System;
using System.IO;
using System.Runtime.InteropServices;
using System.Windows.Input;
using Microsoft.UI.Xaml;
using Microsoft.UI.Xaml.Controls;
using Microsoft.UI.Xaml.Input;
using Microsoft.UI.Xaml.Media;
using Microsoft.UI.Xaml.Media.Animation;
using Microsoft.UI.Xaml.Media.Imaging;
using Windows.Graphics;
using Windows.UI;
using WinRT.Interop;
using McController.App.Services;

namespace McController.App;

public sealed partial class MainWindow : Window
{
    // Tint brushes layered over the SystemBackdrop:
    //   _chromeBrush  → title bar (AppTitleBar) + sidebar pane background
    //   _contentBrush → content frame area
    // Both have their Opacity driven by AppearancePreferences so the user
    // can dial bleed-through to taste from the global settings page. The
    // brushes are reused for the lifetime of the window — changing Opacity
    // on the same instance triggers a redraw without rebuilding the tree.
    //
    // _windowBgBrush is a third "underlay" applied to RootGrid that's
    // only opaque when transparency is OFF. Its job is to cover the
    // window's default-black where the chrome/content brushes have a gap
    // (NavigationView splitter, the strip below the title bar, page
    // transition slivers, etc). With acrylic on, this brush sits at
    // opacity 0 and the live backdrop fills those gaps instead.
    private readonly SolidColorBrush _chromeBrush;
    private readonly SolidColorBrush _contentBrush;
    private readonly SolidColorBrush _windowBgBrush;

    /// <summary>
    /// Bound to <c>TaskbarIcon.LeftClickCommand</c> / <c>DoubleClickCommand</c>
    /// in MainWindow.xaml. Defined here rather than in TrayService because
    /// x:Bind needs the binding source visible on the page class.
    /// </summary>
    public ICommand ShowWindowCommand { get; }

    public MainWindow()
    {
        ShowWindowCommand = new RelayCommand(() =>
            (Application.Current as App)?.ShowMainWindow());

        InitializeComponent();
        Title = Util.L.Get("app.title", "MC Controller");

        // Tray strings + icon are runtime values; XAML defaults cover the
        // first paint, this pass applies the user's locale + the path-
        // resolved app.ico.
        TrayIcon.ToolTipText = Util.L.Get("app.tooltip", TrayIcon.ToolTipText ?? "MC Controller");
        TrayOpenItem.Text    = Util.L.Get("tray.open",   TrayOpenItem.Text);
        TrayExitItem.Text    = Util.L.Get("tray.exit",   TrayExitItem.Text);
        try
        {
            var iconPath = Path.Combine(AppContext.BaseDirectory, "Assets", "app.ico");
            if (File.Exists(iconPath))
                TrayIcon.IconSource = new BitmapImage(new Uri(iconPath));
        }
        catch { /* fall back to library default tray glyph */ }

        NavRoot.Content        = Util.L.Get("nav.root",        NavRoot.Content?.ToString() ?? "");
        NavDiscovery.Content   = Util.L.Get("nav.discovery",   NavDiscovery.Content?.ToString() ?? "");
        NavKeyBindings.Content = Util.L.Get("nav.keybindings", NavKeyBindings.Content?.ToString() ?? "");
        NavSettings.Content    = Util.L.Get("nav.settings",    NavSettings.Content?.ToString() ?? "");
        NavGlobal.Content      = Util.L.Get("nav.global",      NavGlobal.Content?.ToString() ?? "");
        NavAbout.Content       = Util.L.Get("nav.about",       NavAbout.Content?.ToString() ?? "");

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

        // Theme-aware tint color. Dark/light pick mirrors the WinUI
        // SolidBackgroundFillColorBase values; we use a single snapshot
        // taken at window construction (theme-switch at runtime is rare
        // for this app and a relaunch is acceptable).
        var tintColor = Application.Current.RequestedTheme == ApplicationTheme.Dark
            ? Color.FromArgb(0xFF, 0x20, 0x20, 0x20)
            : Color.FromArgb(0xFF, 0xF3, 0xF3, 0xF3);
        _chromeBrush   = new SolidColorBrush(tintColor) { Opacity = 0.0 };
        _contentBrush  = new SolidColorBrush(tintColor) { Opacity = 0.35 };
        _windowBgBrush = new SolidColorBrush(tintColor) { Opacity = 0.0 };

        // Override the NavigationView pane + content tint resources with
        // our managed brushes, and paint the title bar with the same
        // chrome brush so the title bar / sidebar form a single visual
        // band. Setting these before NavigationView's template applies
        // means the first paint already uses them.
        Nav.Resources["NavigationViewExpandedPaneBackground"] = _chromeBrush;
        Nav.Resources["NavigationViewContentBackground"]      = _contentBrush;
        AppTitleBar.Background = _chromeBrush;
        RootGrid.Background    = _windowBgBrush;

        ApplyAppearance(AppearancePreferences.Current);
        AppearancePreferences.Changed += OnAppearanceChanged;
        Closed += (_, _) => AppearancePreferences.Changed -= OnAppearanceChanged;

        // Click-anywhere-to-defocus. Tapped (rather than PointerPressed)
        // fires AFTER the inner controls have processed the click, so
        // NumberBox / TextBox have already finished any focus dance of
        // their own — calling Focus on our sink at this point reliably
        // wins. AddHandler with handledEventsToo means we still see the
        // event even if the inner control marked it handled. The Focus
        // call is also dispatched to the next tick to ensure it lands
        // after the gesture machine has fully unwound.
        RootGrid.AddHandler(
            UIElement.TappedEvent,
            new TappedEventHandler(OnRootTapped),
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

    private void OnAppearanceChanged(AppearancePreferences.Settings s)
    {
        // Changed fires on whichever thread called Update(); marshal to UI.
        DispatcherQueue.TryEnqueue(() => ApplyAppearance(s));
    }

    private void ApplyAppearance(AppearancePreferences.Settings s)
    {
        if (s.TransparencyEnabled)
        {
            // Acrylic active: the brush opacities act as tints over the
            // live-blurred wallpaper, both adjustable from settings. The
            // RootGrid underlay sits at 0 so it doesn't double-tint the
            // chrome / content layers that paint on top of it.
            if (SystemBackdrop is not DesktopAcrylicBackdrop)
            {
                try { SystemBackdrop = new DesktopAcrylicBackdrop(); }
                catch { }
            }
            _chromeBrush.Opacity   = s.ChromeOpacity;
            _contentBrush.Opacity  = s.ContentOpacity;
            _windowBgBrush.Opacity = 0.0;
        }
        else
        {
            // Solid mode: drop the backdrop entirely. The chrome / content
            // brushes go opaque so the visible areas paint with a flat
            // theme color, and the RootGrid underlay also goes opaque so
            // the gaps between NavigationView regions (where the brushes
            // don't reach) don't fall through to the window's default
            // black.
            SystemBackdrop = null;
            _chromeBrush.Opacity   = 1.0;
            _contentBrush.Opacity  = 1.0;
            _windowBgBrush.Opacity = 1.0;
        }
    }

    private void TrayOpenItem_Click(object sender, RoutedEventArgs e)
    {
        (Application.Current as App)?.ShowMainWindow();
    }

    private void TrayExitItem_Click(object sender, RoutedEventArgs e)
    {
        (Application.Current as App)?.ExitApplication();
    }

    [DllImport("user32.dll")]
    private static extern uint GetDpiForWindow(IntPtr hwnd);

    /// <summary>Minimal ICommand used for the tray icon's LeftClick / DoubleClick.</summary>
    private sealed class RelayCommand : ICommand
    {
        private readonly Action _action;
        public RelayCommand(Action action) { _action = action; }
        public event EventHandler? CanExecuteChanged { add { } remove { } }
        public bool CanExecute(object? parameter) => true;
        public void Execute(object? parameter) => _action();
    }

    /// <summary>
    /// Pull focus to the invisible FocusSink button when the user clicks
    /// somewhere that isn't a text-input control. Without this, focus
    /// (and the keyboard caret) stays trapped in a NumberBox / TextBox
    /// until the user explicitly tabs out — Win11 Settings dismisses it
    /// the moment you click empty space, this matches that.
    /// </summary>
    private void OnRootTapped(object sender, TappedRoutedEventArgs e)
    {
        if (e.OriginalSource is DependencyObject src && !IsInsideTextInput(src))
        {
            // Defer to next tick. If we Focus() synchronously inside the
            // Tapped handler, NumberBox's own pointer-released logic
            // (which re-grabs focus to its inner TextBox in some cases)
            // can win over ours; dispatching guarantees we land last.
            DispatcherQueue.TryEnqueue(() => FocusSink.Focus(FocusState.Pointer));
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
            "discovery"   => typeof(Views.DeviceDiscoveryPage),
            "keybindings" => typeof(Views.KeyBindingsPage),
            "settings"    => typeof(Views.SettingsPage),
            "global"      => typeof(Views.GlobalSettingsPage),
            "about"       => typeof(Views.AboutPage),
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
