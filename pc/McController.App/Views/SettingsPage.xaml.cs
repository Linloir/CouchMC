using System;
using System.Globalization;
using System.Windows;
using System.Windows.Controls;
using System.Windows.Input;
using System.Windows.Threading;
using McController.App.Services;
using McController.Core.Config;

namespace McController.App.Views;

/// <summary>
/// Hand-wired settings page: every slider's ValueChanged writes back to the
/// active profile inside the live <see cref="ServerConfig"/>, and the curve
/// preview redraws on every camera tweak. No MVVM binding — the underlying
/// config objects are POCO without INotifyPropertyChanged, and the runtime
/// path (CameraCurve, JoystickToWasdMapper) reads the fields directly on
/// every packet, so live-edit just works.
///
/// Each slider has a sibling <c>ui:NumberBox</c> for typed-in values. The
/// two are kept in sync via the <see cref="_loading"/> guard so editing
/// one doesn't loop-fire the other's ValueChanged.
/// </summary>
public partial class SettingsPage : Page
{
    private readonly ServerHost _host = App.Host;
    private readonly ProfileManager _profiles;
    // Start in loading state — InitializeComponent() parses the XAML and
    // setting Slider.Minimum/Maximum coerces Value, which fires ValueChanged
    // BEFORE the constructor body runs. The handlers all bail when this is
    // true, so the synthetic initial events don't crash on uninitialized
    // state or loop between slider <-> numberbox writes.
    private bool _loading = true;
    private readonly DispatcherTimer _saveStatusTimer;

    public SettingsPage()
    {
        _profiles = new ProfileManager(_host);
        InitializeComponent();

        _saveStatusTimer = new DispatcherTimer { Interval = TimeSpan.FromSeconds(2) };
        _saveStatusTimer.Tick += (_, _) => { SaveStatus.Text = ""; _saveStatusTimer.Stop(); };

        Loaded += OnLoaded;
    }

    private void OnLoaded(object sender, RoutedEventArgs e)
    {
        _loading = true;
        PortBox.Value = _host.Config.Port;
        PortStatusText.Text = $"服务正在监听 {_host.Config.Port}（修改后重启程序生效）";

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

    // ===== Scroll body wheel forwarding =====
    // Sliders + NumberBoxes inside a ScrollViewer eat the mouse wheel by
    // default; forwarding it at the viewer level keeps the page scrollable
    // even when the cursor hovers over a control.
    private void Scroller_PreviewMouseWheel(object sender, MouseWheelEventArgs e)
    {
        if (e.Handled) return;
        var sv = (ScrollViewer)sender;
        sv.ScrollToVerticalOffset(sv.VerticalOffset - e.Delta);
        e.Handled = true;
    }

    // ===== Port =====
    private void PortBox_ValueChanged(object sender, RoutedEventArgs e)
    {
        if (_loading) return;
        if (PortBox.Value is double v && v >= 1024 && v <= 65535)
        {
            _host.Config.Port = (int)v;
            PortStatusText.Text = $"将在下次启动时使用 {(int)v}";
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
            var current = ProfileCombo.SelectedItem;
            ProfileCombo.Items.Refresh();
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

    private void DeleteProfile_Click(object sender, RoutedEventArgs e)
    {
        if (_profiles.Profiles.Count <= 1)
        {
            ShowStatus("至少保留一个方案");
            return;
        }
        var result = MessageBox.Show($"确定要删除「{Active.Name}」？", "删除配置方案",
                                     MessageBoxButton.OKCancel, MessageBoxImage.Question);
        if (result != MessageBoxResult.OK) return;
        _profiles.Delete(Active);
        ProfileCombo.SelectedItem = _profiles.ActiveProfile;
        RefreshFromProfile(_profiles.ActiveProfile);
    }

    // ===== Sensitivity (slider <-> numberbox) =====
    private void SensitivitySlider_ValueChanged(object sender, RoutedPropertyChangedEventArgs<double> e)
    {
        if (_loading) return;
        SetCameraSensitivity(e.NewValue);
        SyncNumberFromSlider(SensitivityNumber, e.NewValue);
    }

    private void SensitivityNumber_ValueChanged(object sender, RoutedEventArgs e)
    {
        if (_loading) return;
        if (SensitivityNumber.Value is double v)
        {
            SetCameraSensitivity(v);
            SyncSliderFromNumber(SensitivitySlider, v);
        }
    }

    private void SetCameraSensitivity(double v)
    {
        Active.Camera.UserSensitivity = (float)v;
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
    private void AccelFactorSlider_ValueChanged(object sender, RoutedPropertyChangedEventArgs<double> e)
    {
        if (_loading) return;
        Active.Camera.AccelFactor = (float)e.NewValue;
        SyncNumberFromSlider(AccelFactorNumber, e.NewValue);
        CurvePreview.SetCamera(Active.Camera);
    }

    private void AccelFactorNumber_ValueChanged(object sender, RoutedEventArgs e)
    {
        if (_loading || AccelFactorNumber.Value is not double v) return;
        Active.Camera.AccelFactor = (float)v;
        SyncSliderFromNumber(AccelFactorSlider, v);
        CurvePreview.SetCamera(Active.Camera);
    }

    // ===== Accel exp =====
    private void AccelExpSlider_ValueChanged(object sender, RoutedPropertyChangedEventArgs<double> e)
    {
        if (_loading) return;
        Active.Camera.AccelExp = (float)e.NewValue;
        SyncNumberFromSlider(AccelExpNumber, e.NewValue);
        CurvePreview.SetCamera(Active.Camera);
    }

    private void AccelExpNumber_ValueChanged(object sender, RoutedEventArgs e)
    {
        if (_loading || AccelExpNumber.Value is not double v) return;
        Active.Camera.AccelExp = (float)v;
        SyncSliderFromNumber(AccelExpSlider, v);
        CurvePreview.SetCamera(Active.Camera);
    }

    // ===== Max multiplier =====
    private void MaxMulSlider_ValueChanged(object sender, RoutedPropertyChangedEventArgs<double> e)
    {
        if (_loading) return;
        Active.Camera.MaxAccelMultiplier = (float)e.NewValue;
        SyncNumberFromSlider(MaxMulNumber, e.NewValue);
        CurvePreview.SetCamera(Active.Camera);
    }

    private void MaxMulNumber_ValueChanged(object sender, RoutedEventArgs e)
    {
        if (_loading || MaxMulNumber.Value is not double v) return;
        Active.Camera.MaxAccelMultiplier = (float)v;
        SyncSliderFromNumber(MaxMulSlider, v);
        CurvePreview.SetCamera(Active.Camera);
    }

    // ===== Movement (dead zone / enter / exit) =====
    private void DeadZoneSlider_ValueChanged(object sender, RoutedPropertyChangedEventArgs<double> e)
    {
        if (_loading) return;
        Active.Movement.DeadZone = (float)e.NewValue;
        SyncNumberFromSlider(DeadZoneNumber, e.NewValue);
    }

    private void DeadZoneNumber_ValueChanged(object sender, RoutedEventArgs e)
    {
        if (_loading || DeadZoneNumber.Value is not double v) return;
        Active.Movement.DeadZone = (float)v;
        SyncSliderFromNumber(DeadZoneSlider, v);
    }

    private void EnterSlider_ValueChanged(object sender, RoutedPropertyChangedEventArgs<double> e)
    {
        if (_loading) return;
        Active.Movement.EnterThreshold = (float)e.NewValue;
        SyncNumberFromSlider(EnterNumber, e.NewValue);
    }

    private void EnterNumber_ValueChanged(object sender, RoutedEventArgs e)
    {
        if (_loading || EnterNumber.Value is not double v) return;
        Active.Movement.EnterThreshold = (float)v;
        SyncSliderFromNumber(EnterSlider, v);
    }

    private void ExitSlider_ValueChanged(object sender, RoutedPropertyChangedEventArgs<double> e)
    {
        if (_loading) return;
        Active.Movement.ExitThreshold = (float)e.NewValue;
        SyncNumberFromSlider(ExitNumber, e.NewValue);
    }

    private void ExitNumber_ValueChanged(object sender, RoutedEventArgs e)
    {
        if (_loading || ExitNumber.Value is not double v) return;
        Active.Movement.ExitThreshold = (float)v;
        SyncSliderFromNumber(ExitSlider, v);
    }

    // ===== Slider <-> NumberBox sync helpers =====
    private void SyncNumberFromSlider(Wpf.Ui.Controls.NumberBox box, double v)
    {
        _loading = true;
        try { box.Value = v; }
        finally { _loading = false; }
    }

    private void SyncSliderFromNumber(Slider slider, double v)
    {
        _loading = true;
        try { slider.Value = v; }
        finally { _loading = false; }
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
