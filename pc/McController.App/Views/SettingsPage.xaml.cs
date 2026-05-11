using System;
using System.Threading.Tasks;
using Microsoft.UI.Dispatching;
using Microsoft.UI.Xaml;
using Microsoft.UI.Xaml.Controls;
using Microsoft.UI.Xaml.Controls.Primitives;
using Windows.Globalization.NumberFormatting;
using McController.App.Services;
using McController.Core.Config;

namespace McController.App.Views;

/// <summary>
/// Hand-wired settings page (WinUI 3). Each slider's ValueChanged writes
/// back to the active profile inside the live <see cref="ServerConfig"/>,
/// and the curve preview redraws on every camera tweak. POCO config —
/// no INotifyPropertyChanged; the runtime (CameraCurve / JoystickToWasdMapper)
/// reads fields directly on every packet, so live-edit just works.
///
/// Each slider has a sibling <see cref="NumberBox"/> for typed-in values.
/// The two stay synced via the <see cref="_loading"/> re-entrancy guard
/// so editing one doesn't loop-fire the other.
/// </summary>
public sealed partial class SettingsPage : Page
{
    private readonly ServerHost _host = App.Host;
    private readonly ProfileManager _profiles;
    // Start in loading state so handlers fired by XAML coercion of
    // Slider.Value (when Minimum/Maximum are set) early-out cleanly.
    private bool _loading = true;
    private readonly DispatcherQueueTimer _saveStatusTimer;

    public SettingsPage()
    {
        _profiles = new ProfileManager(_host);
        InitializeComponent();

        _saveStatusTimer = DispatcherQueue.CreateTimer();
        _saveStatusTimer.Interval = TimeSpan.FromSeconds(2);
        _saveStatusTimer.IsRepeating = false;
        _saveStatusTimer.Tick += (_, _) => SaveStatus.Text = "";

        ConfigureNumberFormatters();
        Loaded += OnLoaded;
    }

    /// <summary>
    /// Without an explicit NumberFormatter, NumberBox shows machine-precision
    /// doubles like 0.30000000000000004 which overflows the input. Set a
    /// FractionDigits-clamped formatter per box so the displayed text matches
    /// the slider's step granularity.
    /// </summary>
    private void ConfigureNumberFormatters()
    {
        var fmt2 = NewFormatter(2);
        var fmt3 = NewFormatter(3);
        var fmtInt = NewFormatter(0);

        PortBox.NumberFormatter = fmtInt;
        SensitivityNumber.NumberFormatter = fmt2;
        AccelFactorNumber.NumberFormatter = fmt3;
        AccelExpNumber.NumberFormatter = fmt2;
        MaxMulNumber.NumberFormatter = fmt2;
        DeadZoneNumber.NumberFormatter = fmt2;
        EnterNumber.NumberFormatter = fmt2;
        ExitNumber.NumberFormatter = fmt2;
    }

    private static DecimalFormatter NewFormatter(int fractionDigits)
    {
        var f = new DecimalFormatter
        {
            IntegerDigits = 1,
            FractionDigits = fractionDigits,
            IsGrouped = false,
        };
        return f;
    }

    private void OnLoaded(object sender, RoutedEventArgs e)
    {
        _loading = true;
        PortBox.Value = _host.Config.Port;
        ProfileCombo.ItemsSource = _profiles.Profiles;
        ProfileCombo.SelectedItem = _profiles.ActiveProfile;
        RefreshFromProfile(_profiles.ActiveProfile);
        _loading = false;
    }

    private void RefreshFromProfile(ControllerProfile p)
    {
        _loading = true;
        try
        {
            ProfileNameBox.Text = p.Name;

            SensitivitySlider.Value = p.Camera.UserSensitivity;
            SensitivityNumber.Value = p.Camera.UserSensitivity;

            CurveLinear.IsChecked = p.Camera.CurveType == CurveType.Linear;
            CurvePower.IsChecked = p.Camera.CurveType == CurveType.Power;

            AccelFactorSlider.Value = p.Camera.AccelFactor;
            AccelFactorNumber.Value = p.Camera.AccelFactor;
            AccelExpSlider.Value = p.Camera.AccelExp;
            AccelExpNumber.Value = p.Camera.AccelExp;
            MaxMulSlider.Value = p.Camera.MaxAccelMultiplier;
            MaxMulNumber.Value = p.Camera.MaxAccelMultiplier;

            DeadZoneSlider.Value = p.Movement.DeadZone;
            DeadZoneNumber.Value = p.Movement.DeadZone;
            EnterSlider.Value = p.Movement.EnterThreshold;
            EnterNumber.Value = p.Movement.EnterThreshold;
            ExitSlider.Value = p.Movement.ExitThreshold;
            ExitNumber.Value = p.Movement.ExitThreshold;

            CurvePreview.SetCamera(p.Camera);
        }
        finally { _loading = false; }
    }

    private ControllerProfile Active => _profiles.ActiveProfile;

    // ===== Port =====
    private void PortBox_ValueChanged(NumberBox sender, NumberBoxValueChangedEventArgs args)
    {
        if (_loading) return;
        if (!double.IsNaN(args.NewValue) && args.NewValue >= 1024 && args.NewValue <= 65535)
        {
            _host.Config.Port = (int)args.NewValue;
        }
    }

    // ===== Profile select / edit =====
    private void ProfileCombo_SelectionChanged(object sender, SelectionChangedEventArgs e)
    {
        if (_loading) return;
        if (ProfileCombo.SelectedItem is ControllerProfile p)
        {
            _profiles.SetActive(p);
            RefreshFromProfile(p);
        }
    }

    private void ProfileNameBox_TextChanged(object sender, TextChangedEventArgs e)
    {
        if (_loading) return;
        Active.Name = ProfileNameBox.Text;
        _loading = true;
        try
        {
            // Refresh combo display since the bound object's name changed
            // and the ComboBox doesn't observe the field.
            var current = ProfileCombo.SelectedItem;
            ProfileCombo.ItemsSource = null;
            ProfileCombo.ItemsSource = _profiles.Profiles;
            ProfileCombo.SelectedItem = current;
        }
        finally { _loading = false; }
    }

    private void NewProfile_Click(object sender, RoutedEventArgs e)
    {
        var p = _profiles.AddNew("新方案 " + (_profiles.Profiles.Count + 1));
        ProfileCombo.SelectedItem = p;
    }

    private void DuplicateProfile_Click(object sender, RoutedEventArgs e)
    {
        var p = _profiles.Duplicate(Active);
        ProfileCombo.SelectedItem = p;
    }

    private async void DeleteProfile_Click(object sender, RoutedEventArgs e)
    {
        if (_profiles.Profiles.Count <= 1)
        {
            ShowStatus("至少保留一个方案");
            return;
        }
        var ok = await ConfirmAsync($"确定要删除「{Active.Name}」？", "删除配置方案");
        if (!ok) return;
        _profiles.Delete(Active);
        ProfileCombo.SelectedItem = _profiles.ActiveProfile;
        RefreshFromProfile(_profiles.ActiveProfile);
    }

    private async Task<bool> ConfirmAsync(string message, string title)
    {
        var dialog = new ContentDialog
        {
            Title = title,
            Content = message,
            PrimaryButtonText = "确定",
            CloseButtonText = "取消",
            DefaultButton = ContentDialogButton.Close,
            XamlRoot = XamlRoot,
        };
        var result = await dialog.ShowAsync();
        return result == ContentDialogResult.Primary;
    }

    // ===== Sensitivity =====
    private void SensitivitySlider_ValueChanged(object sender, RangeBaseValueChangedEventArgs e)
    {
        if (_loading) return;
        Active.Camera.UserSensitivity = (float)e.NewValue;
        Sync(SensitivityNumber, e.NewValue);
        CurvePreview.SetCamera(Active.Camera);
    }

    private void SensitivityNumber_ValueChanged(NumberBox sender, NumberBoxValueChangedEventArgs args)
    {
        if (_loading || double.IsNaN(args.NewValue)) return;
        Active.Camera.UserSensitivity = (float)args.NewValue;
        Sync(SensitivitySlider, args.NewValue);
        CurvePreview.SetCamera(Active.Camera);
    }

    // ===== Curve type =====
    private void CurveType_Checked(object sender, RoutedEventArgs e)
    {
        if (_loading) return;
        Active.Camera.CurveType = CurvePower.IsChecked == true ? CurveType.Power : CurveType.Linear;
        CurvePreview.SetCamera(Active.Camera);
    }

    // ===== Accel factor =====
    private void AccelFactorSlider_ValueChanged(object sender, RangeBaseValueChangedEventArgs e)
    {
        if (_loading) return;
        Active.Camera.AccelFactor = (float)e.NewValue;
        Sync(AccelFactorNumber, e.NewValue);
        CurvePreview.SetCamera(Active.Camera);
    }

    private void AccelFactorNumber_ValueChanged(NumberBox sender, NumberBoxValueChangedEventArgs args)
    {
        if (_loading || double.IsNaN(args.NewValue)) return;
        Active.Camera.AccelFactor = (float)args.NewValue;
        Sync(AccelFactorSlider, args.NewValue);
        CurvePreview.SetCamera(Active.Camera);
    }

    // ===== Accel exp =====
    private void AccelExpSlider_ValueChanged(object sender, RangeBaseValueChangedEventArgs e)
    {
        if (_loading) return;
        Active.Camera.AccelExp = (float)e.NewValue;
        Sync(AccelExpNumber, e.NewValue);
        CurvePreview.SetCamera(Active.Camera);
    }

    private void AccelExpNumber_ValueChanged(NumberBox sender, NumberBoxValueChangedEventArgs args)
    {
        if (_loading || double.IsNaN(args.NewValue)) return;
        Active.Camera.AccelExp = (float)args.NewValue;
        Sync(AccelExpSlider, args.NewValue);
        CurvePreview.SetCamera(Active.Camera);
    }

    // ===== Max multiplier =====
    private void MaxMulSlider_ValueChanged(object sender, RangeBaseValueChangedEventArgs e)
    {
        if (_loading) return;
        Active.Camera.MaxAccelMultiplier = (float)e.NewValue;
        Sync(MaxMulNumber, e.NewValue);
        CurvePreview.SetCamera(Active.Camera);
    }

    private void MaxMulNumber_ValueChanged(NumberBox sender, NumberBoxValueChangedEventArgs args)
    {
        if (_loading || double.IsNaN(args.NewValue)) return;
        Active.Camera.MaxAccelMultiplier = (float)args.NewValue;
        Sync(MaxMulSlider, args.NewValue);
        CurvePreview.SetCamera(Active.Camera);
    }

    // ===== Movement =====
    private void DeadZoneSlider_ValueChanged(object sender, RangeBaseValueChangedEventArgs e)
    {
        if (_loading) return;
        Active.Movement.DeadZone = (float)e.NewValue;
        Sync(DeadZoneNumber, e.NewValue);
    }

    private void DeadZoneNumber_ValueChanged(NumberBox sender, NumberBoxValueChangedEventArgs args)
    {
        if (_loading || double.IsNaN(args.NewValue)) return;
        Active.Movement.DeadZone = (float)args.NewValue;
        Sync(DeadZoneSlider, args.NewValue);
    }

    private void EnterSlider_ValueChanged(object sender, RangeBaseValueChangedEventArgs e)
    {
        if (_loading) return;
        Active.Movement.EnterThreshold = (float)e.NewValue;
        Sync(EnterNumber, e.NewValue);
    }

    private void EnterNumber_ValueChanged(NumberBox sender, NumberBoxValueChangedEventArgs args)
    {
        if (_loading || double.IsNaN(args.NewValue)) return;
        Active.Movement.EnterThreshold = (float)args.NewValue;
        Sync(EnterSlider, args.NewValue);
    }

    private void ExitSlider_ValueChanged(object sender, RangeBaseValueChangedEventArgs e)
    {
        if (_loading) return;
        Active.Movement.ExitThreshold = (float)e.NewValue;
        Sync(ExitNumber, e.NewValue);
    }

    private void ExitNumber_ValueChanged(NumberBox sender, NumberBoxValueChangedEventArgs args)
    {
        if (_loading || double.IsNaN(args.NewValue)) return;
        Active.Movement.ExitThreshold = (float)args.NewValue;
        Sync(ExitSlider, args.NewValue);
    }

    // ===== Slider <-> NumberBox sync =====
    private void Sync(NumberBox box, double v)
    {
        _loading = true;
        try { box.Value = v; } finally { _loading = false; }
    }

    private void Sync(Slider slider, double v)
    {
        _loading = true;
        try { slider.Value = v; } finally { _loading = false; }
    }

    // ===== Save =====
    private void Save_Click(object sender, RoutedEventArgs e)
    {
        try
        {
            _host.SaveConfig();
            ShowStatus("已保存到 config.json");
        }
        catch (Exception ex)
        {
            ShowStatus("保存失败: " + ex.Message);
        }
    }

    private void ShowStatus(string msg)
    {
        SaveStatus.Text = msg;
        _saveStatusTimer.Stop();
        _saveStatusTimer.Start();
    }
}
