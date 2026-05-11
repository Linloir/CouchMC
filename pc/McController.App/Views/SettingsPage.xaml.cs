using System;
using System.Globalization;
using System.Windows;
using System.Windows.Controls;
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
/// Profile switching reseeds all sliders from the new active profile via
/// <see cref="RefreshFromProfile"/>. A re-entrancy guard (<see cref="_loading"/>)
/// stops the bulk-set during refresh from firing ValueChanged → write-back.
/// </summary>
public partial class SettingsPage : Page
{
    private readonly ServerHost _host = App.Host;
    private readonly ProfileManager _profiles;
    // Start in loading state — InitializeComponent() parses the XAML and
    // setting Slider.Minimum/Maximum coerces Value, which fires
    // ValueChanged BEFORE the constructor body runs. The handlers all
    // bail out when _loading is true, so this guard keeps the synthetic
    // initial events from crashing on uninitialized state.
    private bool _loading = true;
    private readonly DispatcherTimer _saveStatusTimer;

    public SettingsPage()
    {
        // _profiles must be live before InitializeComponent so that even
        // any handler that ignores the _loading flag still has a real
        // ProfileManager to read from.
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
            SensitivityValue.Text = p.Camera.UserSensitivity.ToString("0.00", CultureInfo.InvariantCulture);

            CurveLinear.IsChecked = p.Camera.CurveType == CurveType.Linear;
            CurvePower.IsChecked = p.Camera.CurveType == CurveType.Power;

            AccelFactorSlider.Value = p.Camera.AccelFactor;
            AccelFactorValue.Text = p.Camera.AccelFactor.ToString("0.0000", CultureInfo.InvariantCulture);

            AccelExpSlider.Value = p.Camera.AccelExp;
            AccelExpValue.Text = p.Camera.AccelExp.ToString("0.00", CultureInfo.InvariantCulture);

            MaxMulSlider.Value = p.Camera.MaxAccelMultiplier;
            MaxMulValue.Text = p.Camera.MaxAccelMultiplier.ToString("0.0", CultureInfo.InvariantCulture);

            DeadZoneSlider.Value = p.Movement.DeadZone;
            DeadZoneValue.Text = p.Movement.DeadZone.ToString("0.00", CultureInfo.InvariantCulture);

            EnterSlider.Value = p.Movement.EnterThreshold;
            EnterValue.Text = p.Movement.EnterThreshold.ToString("0.00", CultureInfo.InvariantCulture);

            ExitSlider.Value = p.Movement.ExitThreshold;
            ExitValue.Text = p.Movement.ExitThreshold.ToString("0.00", CultureInfo.InvariantCulture);

            CurvePreview.SetCamera(p.Camera);
        }
        finally { _loading = false; }
    }

    private ControllerProfile Active => _profiles.ActiveProfile;

    // ===== Port =====
    private void PortBox_ValueChanged(object sender, RoutedEventArgs e)
    {
        if (_loading) return;
        if (PortBox.Value is double v && v >= 1024 && v <= 65535)
        {
            _host.Config.Port = (int)v;
            // Server already bound to the old port — only the next launch picks this up.
            PortStatusText.Text = $"将在下次启动时使用 {(int)v}（当前仍为 {_host.Config.Port}）";
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
        // Refresh the combo display — items don't notify, easiest is to
        // re-bind. Suspend selection-change side effects via _loading.
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
            SaveStatus.Text = "至少保留一个方案";
            _saveStatusTimer.Stop(); _saveStatusTimer.Start();
            return;
        }
        var result = MessageBox.Show($"确定要删除「{Active.Name}」？", "删除配置方案",
                                     MessageBoxButton.OKCancel, MessageBoxImage.Question);
        if (result != MessageBoxResult.OK) return;
        _profiles.Delete(Active);
        ProfileCombo.SelectedItem = _profiles.ActiveProfile;
        RefreshFromProfile(_profiles.ActiveProfile);
    }

    // ===== Sensitivity =====
    private void SensitivitySlider_ValueChanged(object sender, RoutedPropertyChangedEventArgs<double> e)
    {
        if (_loading) return;
        Active.Camera.UserSensitivity = (float)e.NewValue;
        SensitivityValue.Text = e.NewValue.ToString("0.00", CultureInfo.InvariantCulture);
        CurvePreview.SetCamera(Active.Camera);
    }

    // ===== Curve type =====
    private void CurveType_Checked(object sender, RoutedEventArgs e)
    {
        if (_loading) return;
        Active.Camera.CurveType = CurvePower.IsChecked == true ? CurveType.Power : CurveType.Linear;
        CurvePreview.SetCamera(Active.Camera);
    }

    // ===== Accel sliders =====
    private void AccelSlider_ValueChanged(object sender, RoutedPropertyChangedEventArgs<double> e)
    {
        if (_loading) return;
        Active.Camera.AccelFactor = (float)AccelFactorSlider.Value;
        Active.Camera.AccelExp = (float)AccelExpSlider.Value;
        Active.Camera.MaxAccelMultiplier = (float)MaxMulSlider.Value;
        AccelFactorValue.Text = AccelFactorSlider.Value.ToString("0.0000", CultureInfo.InvariantCulture);
        AccelExpValue.Text = AccelExpSlider.Value.ToString("0.00", CultureInfo.InvariantCulture);
        MaxMulValue.Text = MaxMulSlider.Value.ToString("0.0", CultureInfo.InvariantCulture);
        CurvePreview.SetCamera(Active.Camera);
    }

    // ===== Movement sliders =====
    private void MovementSlider_ValueChanged(object sender, RoutedPropertyChangedEventArgs<double> e)
    {
        if (_loading) return;
        Active.Movement.DeadZone = (float)DeadZoneSlider.Value;
        Active.Movement.EnterThreshold = (float)EnterSlider.Value;
        Active.Movement.ExitThreshold = (float)ExitSlider.Value;
        DeadZoneValue.Text = DeadZoneSlider.Value.ToString("0.00", CultureInfo.InvariantCulture);
        EnterValue.Text = EnterSlider.Value.ToString("0.00", CultureInfo.InvariantCulture);
        ExitValue.Text = ExitSlider.Value.ToString("0.00", CultureInfo.InvariantCulture);
    }

    // ===== Save =====
    private void Save_Click(object sender, RoutedEventArgs e)
    {
        try
        {
            _host.SaveConfig();
            SaveStatus.Text = "已保存";
        }
        catch (Exception ex)
        {
            SaveStatus.Text = "保存失败: " + ex.Message;
        }
        _saveStatusTimer.Stop();
        _saveStatusTimer.Start();
    }
}
