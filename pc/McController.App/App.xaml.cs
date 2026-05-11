using System;
using Microsoft.UI.Xaml;

namespace McController.App;

/// <summary>
/// WinUI 3 entry point. Owns the singleton <see cref="Services.ServerHost"/>
/// for the lifetime of the app — the host is created in OnLaunched and
/// disposed when the main window closes.
/// </summary>
public partial class App : Application
{
    public static Services.ServerHost Host { get; private set; } = null!;
    public static Window MainAppWindow { get; private set; } = null!;

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
        MainAppWindow.Closed += (_, _) =>
        {
            try { Host.Dispose(); } catch { }
        };
        MainAppWindow.Activate();
    }
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
