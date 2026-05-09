using System.Drawing;
using System.Windows.Forms;
using McController.Server.Config;
using McController.Server.Diag;

namespace McController.Server.Tuner;

/// <summary>
/// Single-window tuning panel. Slider edits go straight into the live
/// <see cref="ServerConfig"/> instance; the running server reads those
/// fields on every input packet, so changes take effect immediately.
///
/// "Save" persists the in-memory config to disk. "Reload" loads disk back
/// over the live config. "Reset" replaces the live config with defaults.
/// </summary>
public sealed class TuningForm : Form
{
    private readonly ServerConfig _cfg;
    private readonly ConnectionStats _stats;
    private readonly string _configPath;

    private readonly System.Windows.Forms.Timer _refreshTimer;
    private long _lastJ, _lastL, _lastB;
    private DateTime _lastSampleTime;

    // Status row labels
    private Label _lblConn = null!;
    private Label _lblMode = null!;
    private Label _lblRtt = null!;
    private Label _lblPkts = null!;
    private Label _lblDropped = null!;

    // Camera (User)
    private TrackBar _trkSensitivity = null!;
    private Label _lblSensitivityVal = null!;

    // Camera (Dev)
    private RadioButton _rbCurveLinear = null!;
    private RadioButton _rbCurvePower = null!;
    private TrackBar _trkAccelFactor = null!;
    private Label _lblAccelFactorVal = null!;
    private TrackBar _trkAccelExp = null!;
    private Label _lblAccelExpVal = null!;
    private TrackBar _trkMaxMul = null!;
    private Label _lblMaxMulVal = null!;

    // Movement
    private TrackBar _trkDeadZone = null!;
    private Label _lblDeadZoneVal = null!;
    private TrackBar _trkEnter = null!;
    private Label _lblEnterVal = null!;
    private TrackBar _trkExit = null!;
    private Label _lblExitVal = null!;

    public TuningForm(ServerConfig cfg, ConnectionStats stats, string configPath)
    {
        _cfg = cfg;
        _stats = stats;
        _configPath = configPath;

        Text = "MC Controller — Server (Step 3)";
        ClientSize = new Size(460, 700);
        FormBorderStyle = FormBorderStyle.FixedSingle;
        MaximizeBox = false;
        StartPosition = FormStartPosition.CenterScreen;
        Font = new Font("Segoe UI", 9f);

        BuildUi();
        RefreshSlidersFromConfig();
        UpdateStatusLabels();

        _refreshTimer = new System.Windows.Forms.Timer { Interval = 100 };
        _refreshTimer.Tick += (_, _) => RefreshStatusTick();
        _lastSampleTime = DateTime.UtcNow;
    }

    protected override void OnShown(EventArgs e)
    {
        base.OnShown(e);
        _refreshTimer.Start();
    }

    protected override void OnFormClosed(FormClosedEventArgs e)
    {
        _refreshTimer.Stop();
        _refreshTimer.Dispose();
        base.OnFormClosed(e);
    }

    // ===== UI construction =====

    private void BuildUi()
    {
        int y = 10;

        var grpStatus = BuildStatusGroup(y, out _lblConn, out _lblMode, out _lblRtt, out _lblPkts, out _lblDropped);
        Controls.Add(grpStatus);
        y += grpStatus.Height + 8;

        var grpUser = BuildCameraUserGroup(y);
        Controls.Add(grpUser);
        y += grpUser.Height + 8;

        var grpDev = BuildCameraDevGroup(y);
        Controls.Add(grpDev);
        y += grpDev.Height + 8;

        var grpMove = BuildMovementGroup(y);
        Controls.Add(grpMove);
        y += grpMove.Height + 8;

        BuildButtonRow(y);
    }

    private GroupBox BuildStatusGroup(int top, out Label conn, out Label mode, out Label rtt, out Label pkts, out Label dropped)
    {
        var g = new GroupBox { Text = "Status", Top = top, Left = 10, Width = 440, Height = 125 };
        conn = new Label { Top = 22, Left = 10, Width = 410, Height = 18, Text = "● Disconnected", ForeColor = Color.Gray };
        mode = new Label { Top = 42, Left = 10, Width = 410, Height = 18, Text = "Mode: —" };
        rtt = new Label { Top = 62, Left = 10, Width = 410, Height = 18, Text = "RTT: — (Android-side; this UI shows server-side stats)" };
        pkts = new Label { Top = 82, Left = 10, Width = 410, Height = 18, Text = "Pkts/s: J=0  L=0  B=0" };
        dropped = new Label { Top = 102, Left = 10, Width = 410, Height = 18, Text = "UDP dropped: 0" };
        g.Controls.Add(conn); g.Controls.Add(mode); g.Controls.Add(rtt); g.Controls.Add(pkts); g.Controls.Add(dropped);
        return g;
    }

    private GroupBox BuildCameraUserGroup(int top)
    {
        var g = new GroupBox { Text = "Look (User)", Top = top, Left = 10, Width = 440, Height = 70 };
        (_trkSensitivity, _lblSensitivityVal) = AddSliderRow(
            g, top: 22, name: "Sensitivity",
            min: 10, max: 300, initial: (int)(_cfg.Camera.UserSensitivity * 100f),
            formatter: v => (v / 100f).ToString("F2"),
            onChange: v => _cfg.Camera.UserSensitivity = v / 100f);
        return g;
    }

    private GroupBox BuildCameraDevGroup(int top)
    {
        var g = new GroupBox { Text = "Look (Dev — internal curve)", Top = top, Left = 10, Width = 440, Height = 195 };

        _rbCurveLinear = new RadioButton { Text = "Linear", Top = 22, Left = 15, Width = 80, Checked = _cfg.Camera.CurveType == CurveType.Linear };
        _rbCurvePower = new RadioButton { Text = "Power", Top = 22, Left = 100, Width = 80, Checked = _cfg.Camera.CurveType == CurveType.Power };
        _rbCurveLinear.CheckedChanged += (_, _) => { if (_rbCurveLinear.Checked) _cfg.Camera.CurveType = CurveType.Linear; };
        _rbCurvePower.CheckedChanged += (_, _) => { if (_rbCurvePower.Checked) _cfg.Camera.CurveType = CurveType.Power; };
        g.Controls.Add(_rbCurveLinear);
        g.Controls.Add(_rbCurvePower);

        (_trkAccelFactor, _lblAccelFactorVal) = AddSliderRow(
            g, top: 60, name: "Accel Factor",
            min: 0, max: 100, initial: (int)(_cfg.Camera.AccelFactor * 100f),
            formatter: v => (v / 100f).ToString("F2"),
            onChange: v => _cfg.Camera.AccelFactor = v / 100f);

        (_trkAccelExp, _lblAccelExpVal) = AddSliderRow(
            g, top: 100, name: "Accel Exp",
            min: 50, max: 250, initial: (int)(_cfg.Camera.AccelExp * 100f),
            formatter: v => (v / 100f).ToString("F2"),
            onChange: v => _cfg.Camera.AccelExp = v / 100f);

        (_trkMaxMul, _lblMaxMulVal) = AddSliderRow(
            g, top: 140, name: "Max Mult",
            min: 10, max: 50, initial: (int)(_cfg.Camera.MaxAccelMultiplier * 10f),
            formatter: v => (v / 10f).ToString("F1"),
            onChange: v => _cfg.Camera.MaxAccelMultiplier = v / 10f);

        return g;
    }

    private GroupBox BuildMovementGroup(int top)
    {
        var g = new GroupBox { Text = "Movement", Top = top, Left = 10, Width = 440, Height = 155 };

        (_trkDeadZone, _lblDeadZoneVal) = AddSliderRow(
            g, top: 22, name: "Dead Zone",
            min: 0, max: 50, initial: (int)(_cfg.Movement.DeadZone * 100f),
            formatter: v => (v / 100f).ToString("F2"),
            onChange: v => _cfg.Movement.DeadZone = v / 100f);

        (_trkEnter, _lblEnterVal) = AddSliderRow(
            g, top: 62, name: "Enter Threshold",
            min: 10, max: 70, initial: (int)(_cfg.Movement.EnterThreshold * 100f),
            formatter: v => (v / 100f).ToString("F2"),
            onChange: v => _cfg.Movement.EnterThreshold = v / 100f);

        (_trkExit, _lblExitVal) = AddSliderRow(
            g, top: 102, name: "Exit Threshold",
            min: 0, max: 60, initial: (int)(_cfg.Movement.ExitThreshold * 100f),
            formatter: v => (v / 100f).ToString("F2"),
            onChange: v => _cfg.Movement.ExitThreshold = v / 100f);

        return g;
    }

    private void BuildButtonRow(int top)
    {
        var btnSave = new Button { Text = "Save", Top = top, Left = 10, Width = 120, Height = 32 };
        btnSave.Click += (_, _) =>
        {
            try
            {
                ConfigStore.Save(_configPath, _cfg);
                btnSave.Text = "Saved ✓";
                var t = new System.Windows.Forms.Timer { Interval = 1200 };
                t.Tick += (_, _) => { btnSave.Text = "Save"; t.Stop(); t.Dispose(); };
                t.Start();
            }
            catch (Exception ex)
            {
                MessageBox.Show($"Failed to save: {ex.Message}", "Save error", MessageBoxButtons.OK, MessageBoxIcon.Error);
            }
        };

        var btnReload = new Button { Text = "Reload", Top = top, Left = 140, Width = 120, Height = 32 };
        btnReload.Click += (_, _) =>
        {
            try
            {
                var loaded = ConfigStore.LoadOrDefault(_configPath);
                CopyFieldsFrom(loaded);
                RefreshSlidersFromConfig();
            }
            catch (Exception ex)
            {
                MessageBox.Show($"Failed to load: {ex.Message}", "Reload error", MessageBoxButtons.OK, MessageBoxIcon.Error);
            }
        };

        var btnReset = new Button { Text = "Reset Defaults", Top = top, Left = 270, Width = 180, Height = 32 };
        btnReset.Click += (_, _) =>
        {
            CopyFieldsFrom(new ServerConfig());
            RefreshSlidersFromConfig();
        };

        Controls.Add(btnSave);
        Controls.Add(btnReload);
        Controls.Add(btnReset);
    }

    private static (TrackBar trk, Label lblValue) AddSliderRow(
        GroupBox parent, int top, string name,
        int min, int max, int initial,
        Func<int, string> formatter,
        Action<int> onChange)
    {
        var lblName = new Label
        {
            Text = name,
            Top = top + 4,
            Left = 10,
            Width = 110,
            Height = 22,
            TextAlign = ContentAlignment.MiddleLeft,
        };
        var trk = new TrackBar
        {
            Top = top - 4,
            Left = 125,
            Width = 240,
            Minimum = min,
            Maximum = max,
            Value = Math.Clamp(initial, min, max),
            TickStyle = TickStyle.None,
        };
        var lblValue = new Label
        {
            Text = formatter(trk.Value),
            Top = top + 4,
            Left = 370,
            Width = 60,
            Height = 22,
            TextAlign = ContentAlignment.MiddleLeft,
        };
        trk.ValueChanged += (_, _) =>
        {
            onChange(trk.Value);
            lblValue.Text = formatter(trk.Value);
        };
        parent.Controls.Add(lblName);
        parent.Controls.Add(trk);
        parent.Controls.Add(lblValue);
        return (trk, lblValue);
    }

    // ===== State sync =====

    private void RefreshSlidersFromConfig()
    {
        _trkSensitivity.Value = Math.Clamp((int)(_cfg.Camera.UserSensitivity * 100f), _trkSensitivity.Minimum, _trkSensitivity.Maximum);
        _lblSensitivityVal.Text = _cfg.Camera.UserSensitivity.ToString("F2");

        _rbCurveLinear.Checked = _cfg.Camera.CurveType == CurveType.Linear;
        _rbCurvePower.Checked = _cfg.Camera.CurveType == CurveType.Power;

        _trkAccelFactor.Value = Math.Clamp((int)(_cfg.Camera.AccelFactor * 100f), _trkAccelFactor.Minimum, _trkAccelFactor.Maximum);
        _lblAccelFactorVal.Text = _cfg.Camera.AccelFactor.ToString("F2");

        _trkAccelExp.Value = Math.Clamp((int)(_cfg.Camera.AccelExp * 100f), _trkAccelExp.Minimum, _trkAccelExp.Maximum);
        _lblAccelExpVal.Text = _cfg.Camera.AccelExp.ToString("F2");

        _trkMaxMul.Value = Math.Clamp((int)(_cfg.Camera.MaxAccelMultiplier * 10f), _trkMaxMul.Minimum, _trkMaxMul.Maximum);
        _lblMaxMulVal.Text = _cfg.Camera.MaxAccelMultiplier.ToString("F1");

        _trkDeadZone.Value = Math.Clamp((int)(_cfg.Movement.DeadZone * 100f), _trkDeadZone.Minimum, _trkDeadZone.Maximum);
        _lblDeadZoneVal.Text = _cfg.Movement.DeadZone.ToString("F2");

        _trkEnter.Value = Math.Clamp((int)(_cfg.Movement.EnterThreshold * 100f), _trkEnter.Minimum, _trkEnter.Maximum);
        _lblEnterVal.Text = _cfg.Movement.EnterThreshold.ToString("F2");

        _trkExit.Value = Math.Clamp((int)(_cfg.Movement.ExitThreshold * 100f), _trkExit.Minimum, _trkExit.Maximum);
        _lblExitVal.Text = _cfg.Movement.ExitThreshold.ToString("F2");
    }

    private void CopyFieldsFrom(ServerConfig src)
    {
        _cfg.Port = src.Port;
        _cfg.Camera.UserSensitivity = src.Camera.UserSensitivity;
        _cfg.Camera.CurveType = src.Camera.CurveType;
        _cfg.Camera.AccelFactor = src.Camera.AccelFactor;
        _cfg.Camera.AccelExp = src.Camera.AccelExp;
        _cfg.Camera.MaxAccelMultiplier = src.Camera.MaxAccelMultiplier;
        _cfg.Movement.DeadZone = src.Movement.DeadZone;
        _cfg.Movement.EnterThreshold = src.Movement.EnterThreshold;
        _cfg.Movement.ExitThreshold = src.Movement.ExitThreshold;
        // Bindings: not hot-reloaded — ButtonRouter caches resolved bindings at startup.
    }

    private void UpdateStatusLabels()
    {
        if (_stats.Connected)
        {
            _lblConn.Text = $"● Connected   {_stats.ClientEndpoint}";
            _lblConn.ForeColor = Color.Green;
        }
        else
        {
            _lblConn.Text = "● Disconnected";
            _lblConn.ForeColor = Color.Gray;
        }
        _lblMode.Text = $"Mode: {_stats.Mode ?? "—"}";
        _lblDropped.Text = $"UDP dropped: {_stats.UdpDropped}";
    }

    private void RefreshStatusTick()
    {
        UpdateStatusLabels();

        var now = DateTime.UtcNow;
        var elapsed = (now - _lastSampleTime).TotalSeconds;
        if (elapsed < 0.05) return;  // sub-50ms tick — skip

        var j = _stats.JoystickCount;
        var l = _stats.LookCount;
        var b = _stats.ButtonCount;

        var dj = (j - _lastJ) / elapsed;
        var dl = (l - _lastL) / elapsed;
        var db = (b - _lastB) / elapsed;

        _lblPkts.Text = $"Pkts/s: J={dj,5:F0}  L={dl,5:F0}  B={db,5:F0}";

        _lastJ = j; _lastL = l; _lastB = b;
        _lastSampleTime = now;
    }
}
