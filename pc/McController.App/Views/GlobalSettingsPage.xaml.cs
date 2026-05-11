using System.Globalization;
using Microsoft.UI.Xaml;
using Microsoft.UI.Xaml.Controls;
using Microsoft.UI.Xaml.Controls.Primitives;
using McController.App.Services;
using McController.App.Util;

namespace McController.App.Views;

public sealed partial class GlobalSettingsPage : Page
{
    // Guards the initial Loaded → setter pass so we don't immediately
    // overwrite saved preferences with the freshly-initialized UI state.
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

        var prefs = AppearancePreferences.Current;
        TransparencyToggle.IsOn = prefs.TransparencyEnabled;
        ChromeOpacitySlider.Value  = prefs.ChromeOpacity  * 100.0;
        ContentOpacitySlider.Value = prefs.ContentOpacity * 100.0;
        UpdateOpacityLabel(ChromeOpacityValue,  prefs.ChromeOpacity);
        UpdateOpacityLabel(ContentOpacityValue, prefs.ContentOpacity);
        UpdateSliderEnabledState(prefs.TransparencyEnabled);
        _loading = false;
    }

    private void StartupToggle_Toggled(object sender, RoutedEventArgs e)
    {
        if (_loading) return;
        StartupRegistration.SetEnabled(StartupToggle.IsOn);
    }

    private void TransparencyToggle_Toggled(object sender, RoutedEventArgs e)
    {
        if (_loading) return;
        UpdateSliderEnabledState(TransparencyToggle.IsOn);
        PushAppearance();
    }

    private void ChromeOpacitySlider_ValueChanged(object sender, RangeBaseValueChangedEventArgs e)
    {
        if (_loading) return;
        UpdateOpacityLabel(ChromeOpacityValue, ChromeOpacitySlider.Value / 100.0);
        PushAppearance();
    }

    private void ContentOpacitySlider_ValueChanged(object sender, RangeBaseValueChangedEventArgs e)
    {
        if (_loading) return;
        UpdateOpacityLabel(ContentOpacityValue, ContentOpacitySlider.Value / 100.0);
        PushAppearance();
    }

    private void PushAppearance()
    {
        AppearancePreferences.Update(
            transparencyEnabled: TransparencyToggle.IsOn,
            chromeOpacity:  ChromeOpacitySlider.Value  / 100.0,
            contentOpacity: ContentOpacitySlider.Value / 100.0);
    }

    private void UpdateSliderEnabledState(bool transparencyEnabled)
    {
        // When transparency is off the sliders are forced to 100% by the
        // window; disable them in the UI to make that obvious.
        ChromeOpacitySlider.IsEnabled  = transparencyEnabled;
        ContentOpacitySlider.IsEnabled = transparencyEnabled;
        ChromeOpacityCard.IsEnabled    = transparencyEnabled;
        ContentOpacityCard.IsEnabled   = transparencyEnabled;
    }

    private static void UpdateOpacityLabel(TextBlock target, double opacity)
    {
        var pct = (int)System.Math.Round(opacity * 100.0);
        target.Text = pct.ToString(CultureInfo.InvariantCulture) + "%";
    }

    private void ApplyTranslations()
    {
        HeaderTitle.Text = L.Get("global.title", HeaderTitle.Text);
        HeaderSubtitle.Text = L.Get("global.subtitle", HeaderSubtitle.Text);
        GeneralHeading.Text = L.Get("global.section.general", GeneralHeading.Text);
        StartupCard.Header = L.Get("global.startup.header", StartupCard.Header?.ToString() ?? "");
        StartupCard.Description = L.Get("global.startup.desc", StartupCard.Description?.ToString() ?? "");

        AppearanceHeading.Text = L.Get("global.section.appearance", AppearanceHeading.Text);
        TransparencyCard.Header = L.Get("global.transparency.header", TransparencyCard.Header?.ToString() ?? "");
        TransparencyCard.Description = L.Get("global.transparency.desc", TransparencyCard.Description?.ToString() ?? "");
        ChromeOpacityCard.Header = L.Get("global.chrome.header", ChromeOpacityCard.Header?.ToString() ?? "");
        ChromeOpacityCard.Description = L.Get("global.chrome.desc", ChromeOpacityCard.Description?.ToString() ?? "");
        ContentOpacityCard.Header = L.Get("global.content.header", ContentOpacityCard.Header?.ToString() ?? "");
        ContentOpacityCard.Description = L.Get("global.content.desc", ContentOpacityCard.Description?.ToString() ?? "");
    }
}
