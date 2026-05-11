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

        // ApplicationThemeManager wires WPF-UI's dynamic theme resources
        // (TextFillColorPrimaryBrush, CardBackgroundFillColorDefaultBrush,
        // etc.) so the Pages — which use DynamicResource lookups for text
        // and background — pick up the dark palette. Without this call
        // some surfaces fall back to system defaults (black text on dark).
        Wpf.Ui.Appearance.ApplicationThemeManager.Apply(
            Wpf.Ui.Appearance.ApplicationTheme.Dark,
            Wpf.Ui.Controls.WindowBackdropType.Mica);

        Host = new Services.ServerHost();
        Host.Start();

        DispatcherUnhandledException += (_, args) =>
        {
            // Show a dialog AND log to file so silent page-construction
            // failures actually surface. The file is appended next to the
            // running exe and the dialog is best-effort (won't survive if
            // the UI thread itself is dead).
            System.Diagnostics.Debug.WriteLine($"[App] Unhandled: {args.Exception}");
            try
            {
                System.IO.File.AppendAllText("mc-controller-errors.log",
                    $"[{DateTime.Now:O}] {args.Exception}\n\n");
            }
            catch { }
            try
            {
                MessageBox.Show(args.Exception.Message, "MC Controller — 未捕获异常",
                                MessageBoxButton.OK, MessageBoxImage.Error);
            }
            catch { }
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
