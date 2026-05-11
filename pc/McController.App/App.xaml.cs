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
        // those down is ExitApp(), triggered exclusively by the tray
        // menu's "退出服务" item.
        //
        // Crucially we DON'T subscribe to Window.Closed for cleanup —
        // an earlier version disposed Host + Tray there, which killed
        // both the moment the window hid. Now all teardown lives in
        // ExitApp(), so accidental Closed firings can't strand the app
        // with no listeners and no tray.
        MainAppWindow.AppWindow.Closing += (sender, ev) =>
        {
            if (_exiting) return;
            ev.Cancel = true;
            try { MainAppWindow.AppWindow.Hide(); } catch { }
        };

        Tray = new Services.TrayService(ShowWindow, ExitApp);
        Tray.Initialize();

        MainAppWindow.Activate();
    }

    private void ShowWindow()
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

    private void ExitApp()
    {
        _exiting = true;
        try { Host?.Dispose(); } catch { }
        try { Tray?.Dispose(); } catch { }
        try { MainAppWindow?.Close(); } catch { }
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
