using System;
using System.IO;
using H.NotifyIcon;
using Microsoft.UI.Xaml;
using Microsoft.UI.Xaml.Controls;
using Microsoft.UI.Xaml.Media.Imaging;

namespace McController.App.Services;

/// <summary>
/// System-tray icon + context menu. Lives for the lifetime of the app
/// (created in App.OnLaunched, disposed on real exit). Right-click shows
/// "打开面板" / "退出服务"; double-click on the icon shows the main window.
///
/// The window's close button is wired to hide-to-tray rather than exit
/// — the server keeps relaying input even when the panel isn't visible.
/// "退出服务" is the only way to actually shut down.
/// </summary>
public sealed class TrayService : IDisposable
{
    private readonly Action _showWindow;
    private readonly Action _exitApp;
    private TaskbarIcon? _icon;
    private bool _disposed;

    public TrayService(Action showWindow, Action exitApp)
    {
        _showWindow = showWindow;
        _exitApp = exitApp;
    }

    public void Initialize()
    {
        // Resolve the .ico in the deployed output (Assets/app.ico is copied
        // there by csproj <Content>). Falls back to the OS default tray
        // icon if the file is missing for any reason.
        var iconPath = Path.Combine(AppContext.BaseDirectory, "Assets", "app.ico");

        var openItem = new MenuFlyoutItem { Text = "打开面板" };
        openItem.Click += (_, _) => _showWindow();

        var exitItem = new MenuFlyoutItem { Text = "退出服务" };
        exitItem.Click += (_, _) => _exitApp();

        var menu = new MenuFlyout();
        menu.Items.Add(openItem);
        menu.Items.Add(new MenuFlyoutSeparator());
        menu.Items.Add(exitItem);

        _icon = new TaskbarIcon
        {
            ToolTipText = "MC Controller",
            ContextFlyout = menu,
            LeftClickCommand = new RelayCommand(_showWindow),
            DoubleClickCommand = new RelayCommand(_showWindow),
        };
        if (File.Exists(iconPath))
        {
            try
            {
                _icon.IconSource = new BitmapImage(new Uri(iconPath));
            }
            catch { /* fall back to default tray glyph */ }
        }
        _icon.ForceCreate();
    }

    public void Dispose()
    {
        if (_disposed) return;
        _disposed = true;
        try { _icon?.Dispose(); } catch { }
        _icon = null;
    }

    /// <summary>Tiny ICommand for the tray click callbacks.</summary>
    private sealed class RelayCommand : System.Windows.Input.ICommand
    {
        private readonly Action _action;
        public RelayCommand(Action action) { _action = action; }
        public event EventHandler? CanExecuteChanged { add { } remove { } }
        public bool CanExecute(object? parameter) => true;
        public void Execute(object? parameter) => _action();
    }
}
