using System;
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
        // phone connects, but Settings has interesting things immediately.
        Nav.Navigate(typeof(Views.SettingsPage));
    }

    /// <summary>
    /// Manual nav handler. NavigationViewItem.TargetPageType auto-nav was
    /// failing silently when the target page threw during construction, so
    /// we route by Tag here — combined with the global unhandled-exception
    /// dialog in <see cref="App"/>, any constructor error now surfaces.
    /// </summary>
    private void Nav_SelectionChanged(NavigationView sender, RoutedEventArgs args)
    {
        if (sender.SelectedItem is not NavigationViewItem item) return;
        var tag = item.Tag as string;
        Type? target = tag switch
        {
            "discovery" => typeof(Views.DeviceDiscoveryPage),
            "settings" => typeof(Views.SettingsPage),
            _ => null,
        };
        if (target is not null) Nav.Navigate(target);
    }
}
