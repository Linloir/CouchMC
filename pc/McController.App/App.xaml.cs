using System;
using Microsoft.UI.Xaml;

namespace McController.App;

/// <summary>
/// WinUI 3 entry point. Owns the singleton <see cref="Services.ServerHost"/>
/// for the lifetime of the app. The main window's close button hides to
/// tray instead of exiting; the only real shutdown path is the tray
/// menu's 退出服务 item, which the MainWindow code-behind routes back
/// here via <see cref="ExitApplication"/>.
///
/// The TaskbarIcon itself now lives in MainWindow.xaml (not constructed
/// in code) because a programmatically-created MenuFlyout never picks
/// up a XamlRoot and its MenuFlyoutItem.Click events never fire — a
/// well-documented WinUI 3 + H.NotifyIcon trap that caused early
/// "退出服务 doesn't work" reports.
/// </summary>
public partial class App : Application
{
    public static Services.ServerHost Host { get; private set; } = null!;
    public static Window MainAppWindow { get; private set; } = null!;

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
                var dir = System.IO.Path.Combine(
                    Environment.GetFolderPath(Environment.SpecialFolder.LocalApplicationData),
                    "McController");
                System.IO.Directory.CreateDirectory(dir);
                System.IO.File.AppendAllText(
                    System.IO.Path.Combine(dir, "errors.log"),
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

        // Hide-to-tray when the user clicks the window's X. Cancel the
        // close before it propagates; AppWindow.Hide() then drops the
        // window from the taskbar without destroying it. The server
        // listeners and tray icon stay alive — the only path that tears
        // those down is ExitApplication(), triggered by the tray menu's
        // "退出服务" item.
        //
        // Crucially we DON'T subscribe to Window.Closed for cleanup —
        // an earlier version disposed Host there, which killed the
        // listener the moment the window hid. Now all teardown lives in
        // ExitApplication(), so accidental Closed firings can't strand
        // the app with no listener and an orphan tray icon.
        MainAppWindow.AppWindow.Closing += (sender, ev) =>
        {
            if (_exiting) return;
            ev.Cancel = true;
            try { MainAppWindow.AppWindow.Hide(); } catch { }
        };

        MainAppWindow.Activate();
    }

    /// <summary>Brings the main window to the foreground.</summary>
    public void ShowMainWindow()
    {
        if (MainAppWindow is null) return;
        try
        {
            MainAppWindow.AppWindow.Show();
            MainAppWindow.Activate();
            // Pull to the foreground in case Windows decided to keep us
            // behind another window after the show.
            var hwnd = WinRT.Interop.WindowNative.GetWindowHandle(MainAppWindow);
            SetForegroundWindow(hwnd);
        }
        catch { }
    }

    /// <summary>
    /// Tears down the server and forcibly exits the process. Called
    /// from MainWindow's tray-menu click handlers.
    ///
    /// Environment.Exit(0) (= Win32 ExitProcess) is used instead of
    /// the cooperative Application.Exit(). The latter queues a
    /// shutdown signal but won't terminate the process while any
    /// non-background threads or pending dispatcher work survive,
    /// which we can't guarantee from a third-party tray library plus
    /// our own listeners. ExitProcess always wins; we just Dispose
    /// Host first so the TCP/UDP listeners shut down cleanly before
    /// the process drops dead.
    /// </summary>
    public void ExitApplication()
    {
        if (_exiting) return;
        _exiting = true;
        try { Host?.Dispose(); } catch { }
        Environment.Exit(0);
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

        if (args.Length > 0 && string.Equals(args[0], "--generate-android-icon", StringComparison.OrdinalIgnoreCase))
        {
            // Defaults to the Android module's res dir relative to the
            // bin output: ../../../../../android/app/src/main/res.
            var outDir = args.Length > 1
                ? args[1]
                : System.IO.Path.Combine(
                    AppContext.BaseDirectory,
                    "..", "..", "..", "..", "..",
                    "android", "app", "src", "main", "res");
            outDir = System.IO.Path.GetFullPath(outDir);
            IconBaker.BakeGrassBlockToAndroidIcon(outDir);
            Console.WriteLine($"Android adaptive-icon foreground PNGs written under {outDir}");
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
