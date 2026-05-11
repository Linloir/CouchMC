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
        // Default to Settings on first launch — Discovery is empty until a
        // phone shows up, but Settings has interesting things immediately.
        Nav.Navigate(typeof(Views.SettingsPage));
    }
}
