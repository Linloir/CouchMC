using System;
using H.NotifyIcon;
using Microsoft.UI.Xaml;

namespace McController.App;

/// <summary>
/// WinUI 3 entry point. Owns the singleton <see cref="Services.ServerHost"/>
/// and <see cref="Services.TrayService"/> for the lifetime of the app.
/// The main window's close button hides to tray instead of exiting; the
/// real shutdown path is the tray menu's 退出服务 item, which calls
/// <see cref="ExitApp"/>.
/// </summary>
public partial class App : Application
{
    public static Services.ServerHost Host { get; private set; } = null!;
    public static Window MainAppWindow { get; private set; } = null!;
    public static Services.TrayService Tray { get; private set; } = null!;

    private bool _exiting;

    public App()
    {
        InitializeComponent();

        UnhandledException += (_, args) =>
        {
            // Surface to debug + log so silent page-construction errors
            // don't vanish (mirrors the WPF version's error.log behavior).
            System.Diagnostics.Debug.WriteLine($"[App] Unhandled: {args.Exception}");
            try
            {
                System.IO.File.AppendAllText("mc-controller-errors.log",
                    $"[{DateTime.Now:O}] {args.Exception}\n\n");
            }
            catch { }
            args.Handled = true;
        };
    }

    protected override void OnLaunched(LaunchActivatedEventArgs args)
    {
        // CLI flags reach Main; this OnLaunched only runs for normal launch.
        Host = new Services.ServerHost();
        Host.Start();

        MainAppWindow = new MainWindow();

        // Hide-to-tray instead of exit when the close button is pressed.
        // The server keeps running so a phone session isn't disrupted just
        // because the user dismissed the panel. AppWindow.Closing.Cancel
        // suppresses the destroy; WindowExtensions.Hide() drops the window
        // out of the taskbar so the tray icon is the only visible surface.
        MainAppWindow.AppWindow.Closing += (sender, ev) =>
        {
            if (_exiting) return;
            ev.Cancel = true;
            MainAppWindow.Hide(enableEfficiencyMode: true);
        };
        MainAppWindow.Closed += (_, _) =>
        {
            // Only reached when ExitApp() actually destroys the window.
            try { Host.Dispose(); } catch { }
            try { Tray.Dispose(); } catch { }
        };

        Tray = new Services.TrayService(ShowWindow, ExitApp);
        Tray.Initialize();

        MainAppWindow.Activate();
    }

    private void ShowWindow()
    {
        if (MainAppWindow is null) return;
        MainAppWindow.Show();
        // Pull to foreground in case it was already shown but hidden behind
        // other apps.
        try
        {
            MainAppWindow.Activate();
            var hwnd = WinRT.Interop.WindowNative.GetWindowHandle(MainAppWindow);
            SetForegroundWindow(hwnd);
        }
        catch { }
    }

    private void ExitApp()
    {
        _exiting = true;
        try { MainAppWindow?.Close(); }
        catch { }
        Exit();
    }

    [System.Runtime.InteropServices.DllImport("user32.dll")]
    private static extern bool SetForegroundWindow(IntPtr hWnd);
}

/// <summary>
/// Program entry point for unpackaged WinUI 3. The Application.Start
/// callback must construct the App on the dispatcher thread and not
/// return until shutdown.
/// </summary>
public static class Program
{
    [STAThread]
    public static void Main(string[] args)
    {
        if (args.Length > 0 && string.Equals(args[0], "--selftest", StringComparison.OrdinalIgnoreCase))
        {
            Core.Diag.SelfTest.Run();
            return;
        }

        if (args.Length > 0 && string.Equals(args[0], "--generate-icon", StringComparison.OrdinalIgnoreCase))
        {
            var outPath = args.Length > 1
                ? args[1]
                : System.IO.Path.Combine(AppContext.BaseDirectory, "..", "..", "..", "Assets", "app.ico");
            outPath = System.IO.Path.GetFullPath(outPath);
            IconBaker.BakeGrassBlockToIco(outPath);
            Console.WriteLine($"Icon baked to {outPath}");
            return;
        }

        Microsoft.UI.Xaml.Application.Start(p =>
        {
            var ctx = new Microsoft.UI.Dispatching.DispatcherQueueSynchronizationContext(
                Microsoft.UI.Dispatching.DispatcherQueue.GetForCurrentThread());
            System.Threading.SynchronizationContext.SetSynchronizationContext(ctx);
            _ = new App();
        });
    }
}
