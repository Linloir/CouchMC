using System.Windows;
using Wpf.Ui.Controls;

namespace McController.App;

public partial class MainWindow : FluentWindow
{
    public MainWindow()
    {
        InitializeComponent();
    }

    private void Nav_Loaded(object sender, RoutedEventArgs e)
    {
        // Default to Settings on first launch. Sub-item clicks use
        // TargetPageType auto-nav (the standard WPF-UI pattern), so no
        // manual SelectionChanged handler is needed.
        Nav.Navigate(typeof(Views.SettingsPage));
    }
}
