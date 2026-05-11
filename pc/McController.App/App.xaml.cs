using System;
using System.Windows;
using System.Windows.Threading;

namespace McController.App;

public partial class App : Application
{
    public static Services.ServerHost Host { get; private set; } = null!;

    protected override void OnStartup(StartupEventArgs e)
    {
        if (e.Args.Length > 0 && string.Equals(e.Args[0], "--selftest", StringComparison.OrdinalIgnoreCase))
        {
            Core.Diag.SelfTest.Run();
            Shutdown();
            return;
        }

        Host = new Services.ServerHost();
        Host.Start();

        DispatcherUnhandledException += (_, args) =>
        {
            System.Diagnostics.Debug.WriteLine($"[App] Unhandled: {args.Exception}");
            args.Handled = true;
        };

        base.OnStartup(e);
    }

    protected override void OnExit(ExitEventArgs e)
    {
        try { Host?.Dispose(); } catch { }
        base.OnExit(e);
    }
}
