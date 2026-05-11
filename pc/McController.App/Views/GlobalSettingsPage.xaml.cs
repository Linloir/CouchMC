using Microsoft.UI.Xaml;
using Microsoft.UI.Xaml.Controls;
using McController.App.Services;
using McController.App.Util;

namespace McController.App.Views;

public sealed partial class GlobalSettingsPage : Page
{
    private bool _loading = true;

    public GlobalSettingsPage()
    {
        InitializeComponent();
        Loaded += OnLoaded;
        ApplyTranslations();
    }

    private void OnLoaded(object sender, RoutedEventArgs e)
    {
        _loading = true;
        StartupToggle.IsOn = StartupRegistration.IsEnabled();
        _loading = false;
    }

    private void StartupToggle_Toggled(object sender, RoutedEventArgs e)
    {
        if (_loading) return;
        StartupRegistration.SetEnabled(StartupToggle.IsOn);
    }

    private void ApplyTranslations()
    {
        HeaderTitle.Text = L.Get("global.title", HeaderTitle.Text);
        HeaderSubtitle.Text = L.Get("global.subtitle", HeaderSubtitle.Text);
        GeneralHeading.Text = L.Get("global.section.general", GeneralHeading.Text);
        StartupCard.Header = L.Get("global.startup.header", StartupCard.Header?.ToString() ?? "");
        StartupCard.Description = L.Get("global.startup.desc", StartupCard.Description?.ToString() ?? "");
    }
}
