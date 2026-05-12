using System;
using System.Collections.Generic;
using System.Collections.ObjectModel;
using System.Globalization;
using Microsoft.UI.Xaml;
using Microsoft.UI.Xaml.Controls;
using Microsoft.UI.Xaml.Input;
using Windows.System;
using Windows.UI.Core;
using McController.App.Services;
using McController.App.Util;
using McController.Core.Config;

namespace McController.App.Views;

/// <summary>
/// Per-action key binding editor. Two sections:
///   - Movement (the four joystick directions, read by JoystickToWasdMapper)
///   - Action buttons (every ButtonId from the wire protocol, read by
///     ButtonRouter via ServerConfig.Bindings)
///
/// Each row shows the current binding ("W", "Space", …) and an Edit
/// button that opens a capture dialog. The dialog listens for the next
/// key the user presses and stores its scancode + readable hex string.
/// Mouse-button actions (LMB / RMB) offer a "Mouse left / right / middle"
/// picker instead, because there's no way to "press" a mouse button into
/// the dialog without bypassing all the OS click handling.
///
/// Changes mutate ServerConfig in place — mapper + router read the latest
/// values on every input packet, so binding edits take effect immediately
/// without a profile reload. The host saves the config when the page
/// unloads.
/// </summary>
public sealed partial class KeyBindingsPage : Page
{
    private readonly ServerHost _host = App.Host;

    /// <summary>Backing list for the action ItemsControl. ObservableCollection so refresh re-renders.</summary>
    private readonly ObservableCollection<ActionRow> _actions = new();

    public KeyBindingsPage()
    {
        InitializeComponent();
        ActionList.ItemsSource = _actions;
        Loaded += OnLoaded;
        Unloaded += (_, _) => { try { _host.SaveConfig(); } catch { } };
    }

    private void OnLoaded(object sender, RoutedEventArgs e)
    {
        RenderMovement();
        RenderActions();
    }

    // ===== Movement rows =====

    private void RenderMovement()
    {
        var m = _host.Config.Movement_Keys;
        ValForward.Text = ScancodeNames.LabelForHex(m.Forward);
        ValBack.Text    = ScancodeNames.LabelForHex(m.Back);
        ValLeft.Text    = ScancodeNames.LabelForHex(m.Left);
        ValRight.Text   = ScancodeNames.LabelForHex(m.Right);
    }

    private async void OnEditClicked(object sender, RoutedEventArgs e)
    {
        if (sender is not Button btn || btn.Tag is not string slot) return;
        var (titleZh, currentHex) = slot switch
        {
            "forward" => ("前进", _host.Config.Movement_Keys.Forward),
            "back"    => ("后退", _host.Config.Movement_Keys.Back),
            "left"    => ("左移", _host.Config.Movement_Keys.Left),
            "right"   => ("右移", _host.Config.Movement_Keys.Right),
            _ => (slot, "")
        };
        var hex = await CaptureKey($"为「{titleZh}」录入新的按键", currentHex, allowMouse: false);
        if (hex is null) return;
        switch (slot)
        {
            case "forward": _host.Config.Movement_Keys.Forward = hex; break;
            case "back":    _host.Config.Movement_Keys.Back    = hex; break;
            case "left":    _host.Config.Movement_Keys.Left    = hex; break;
            case "right":   _host.Config.Movement_Keys.Right   = hex; break;
        }
        RenderMovement();
        try { _host.SaveConfig(); } catch { }
    }

    // ===== Action rows (ButtonId-based bindings) =====

    private void RenderActions()
    {
        _actions.Clear();
        foreach (var spec in ActionRow.AllSpecs)
        {
            _actions.Add(new ActionRow(spec, _host.Config.Bindings));
        }
    }

    private async void OnActionEditClicked(object sender, RoutedEventArgs e)
    {
        if (sender is not Button btn || btn.Tag is not string buttonIdHex) return;
        var spec = ActionRow.AllSpecs.Find(s => s.ButtonIdHex == buttonIdHex);
        if (spec is null) return;

        if (!_host.Config.Bindings.TryGetValue(buttonIdHex, out var binding))
        {
            binding = new ButtonBinding();
            _host.Config.Bindings[buttonIdHex] = binding;
        }

        var (newBinding, cancelled) = await CaptureBinding(
            title: $"为「{spec.Label}」录入新的按键",
            current: binding,
            allowMouse: spec.AllowMouse);
        if (cancelled || newBinding is null) return;

        _host.Config.Bindings[buttonIdHex] = newBinding;
        RenderActions();
        try { _host.SaveConfig(); } catch { }
    }

    // ===== Capture dialogs =====

    /// <summary>
    /// Shows a dialog that listens for a key-down and returns the captured
    /// scancode as a "0x??" hex string. Returns null on cancel.
    /// </summary>
    private async System.Threading.Tasks.Task<string?> CaptureKey(string title, string currentHex, bool allowMouse)
    {
        // For movement keys we only need the scancode (not the type-switch UI
        // that CaptureBinding gives for LMB/RMB). Reuse CaptureBinding under
        // the hood with allowMouse=false so the user can't pick a mouse
        // option.
        var (b, cancelled) = await CaptureBinding(title, new ButtonBinding
        {
            Type = "key",
            Scancode = currentHex,
        }, allowMouse: allowMouse);
        if (cancelled || b is null || b.Type != "key" || b.Scancode is null) return null;
        return b.Scancode;
    }

    /// <summary>
    /// Shared key-capture dialog. The text "请按下要绑定的按键..." is shown,
    /// the dialog handles KeyDown to capture a scancode, and (if allowMouse)
    /// offers three radio buttons to bind a mouse button instead.
    /// </summary>
    private async System.Threading.Tasks.Task<(ButtonBinding?, bool cancelled)> CaptureBinding(
        string title,
        ButtonBinding current,
        bool allowMouse)
    {
        var captured = current;   // copy via local field on the builder below

        var dialog = new ContentDialog
        {
            XamlRoot = this.XamlRoot,
            Title = title,
            CloseButtonText = "取消",
            PrimaryButtonText = "保存",
            DefaultButton = ContentDialogButton.Primary,
        };

        var capturedText = new TextBlock
        {
            FontFamily = new Microsoft.UI.Xaml.Media.FontFamily("Consolas"),
            FontSize = 18,
            Margin = new Thickness(0, 8, 0, 12),
        };
        void RefreshCapturedText()
        {
            capturedText.Text = captured.Type == "mouse"
                ? $"鼠标 {captured.Button ?? "left"} 键"
                : $"键盘 {ScancodeNames.LabelForHex(captured.Scancode)}";
        }
        RefreshCapturedText();

        var hint = new TextBlock
        {
            Text = allowMouse
                ? "请按下要绑定的键盘按键，或在下方选择鼠标按键。"
                : "请按下要绑定的键盘按键。",
            Opacity = 0.7,
            TextWrapping = TextWrapping.Wrap,
        };

        var stack = new StackPanel { Spacing = 4 };
        stack.Children.Add(hint);
        stack.Children.Add(capturedText);

        if (allowMouse)
        {
            var mousePanel = new StackPanel
            {
                Orientation = Orientation.Horizontal,
                Spacing = 8,
            };
            void AddMouseChoice(string buttonValue, string label)
            {
                var rb = new RadioButton
                {
                    Content = label,
                    GroupName = "mouse",
                    IsChecked = captured.Type == "mouse" && captured.Button == buttonValue,
                };
                rb.Checked += (_, _) =>
                {
                    captured = new ButtonBinding { Type = "mouse", Button = buttonValue };
                    RefreshCapturedText();
                };
                mousePanel.Children.Add(rb);
            }
            AddMouseChoice("left", "左键");
            AddMouseChoice("right", "右键");
            AddMouseChoice("middle", "中键");
            stack.Children.Add(mousePanel);
        }

        dialog.Content = stack;

        // Key capture. PreviewKeyDown via AddHandler so we still see keys
        // the focused button is about to eat. ScanCode comes through
        // KeyStatus on the routed args.
        var keyHandler = new KeyEventHandler((s, args) =>
        {
            // Ignore raw modifier-only presses so the user can preview the
            // dialog with Shift held (rare but possible). The scancode for
            // a pure modifier is still useful for binding, though, so we
            // accept it once Enter / a non-modifier eventually arrives.
            var sc = (ushort)args.KeyStatus.ScanCode;
            if (sc == 0) return;
            // Ignore the Enter / Space / Esc keys that the dialog buttons
            // need so the user can still confirm / cancel with the keyboard.
            if (args.Key == VirtualKey.Enter || args.Key == VirtualKey.Escape) return;
            captured = new ButtonBinding
            {
                Type = "key",
                Scancode = ScancodeNames.FormatHex(sc),
            };
            RefreshCapturedText();
            args.Handled = true;
        });
        dialog.AddHandler(KeyDownEvent, keyHandler, handledEventsToo: true);

        var result = await dialog.ShowAsync();
        dialog.RemoveHandler(KeyDownEvent, keyHandler);

        if (result != ContentDialogResult.Primary) return (null, true);
        return (captured, false);
    }
}

/// <summary>
/// One row in the action-buttons ItemsControl. Built once at page-load
/// time from <see cref="AllSpecs"/>; the binding value is recomputed
/// from <see cref="ServerConfig.Bindings"/> whenever the list is refreshed.
/// </summary>
public sealed class ActionRow
{
    public string ButtonIdHex { get; }
    public string Label { get; }
    public string HelpText { get; }
    public string Glyph { get; }
    public bool AllowMouse { get; }
    public string ValueText { get; }

    public ActionRow(Spec spec, IDictionary<string, ButtonBinding> bindings)
    {
        ButtonIdHex = spec.ButtonIdHex;
        Label = spec.Label;
        HelpText = spec.HelpText;
        Glyph = spec.Glyph;
        AllowMouse = spec.AllowMouse;
        ValueText = FormatBinding(bindings.TryGetValue(spec.ButtonIdHex, out var b) ? b : null);
    }

    private static string FormatBinding(ButtonBinding? b)
    {
        if (b is null) return "—";
        if (b.Type == "mouse")
        {
            return (b.Button ?? "left") switch
            {
                "left"   => "鼠标左键",
                "right"  => "鼠标右键",
                "middle" => "鼠标中键",
                _        => $"鼠标 {b.Button}",
            };
        }
        return ScancodeNames.LabelForHex(b.Scancode);
    }

    public sealed record Spec(
        string ButtonIdHex,
        string Label,
        string HelpText,
        string Glyph,
        bool AllowMouse);

    public static readonly List<Spec> AllSpecs = new()
    {
        new("0x01", "左键 (LMB)",     "手机端 LMB 按钮 / 触控板单击触发",     "", true),
        new("0x02", "右键 (RMB)",     "手机端 RMB 按钮 / 触控板双击触发",     "", true),
        new("0x10", "跳跃",           "默认 Space",                              "", false),
        new("0x11", "潜行",           "默认 Left Shift",                         "", false),
        new("0x12", "疾跑",           "默认 Left Ctrl",                          "", false),
        new("0x20", "物品栏",         "默认 E",                                  "", false),
        new("0x21", "丢弃物品",       "默认 Q;由 hotbar 长按触发",               "", false),
        new("0x22", "副手交换",       "默认 F",                                  "", false),
        new("0x30", "Esc / 暂停",     "默认 Esc",                                "", false),
        new("0x40", "热键栏 1",       "默认 1",                                  "", false),
        new("0x41", "热键栏 2",       "默认 2",                                  "", false),
        new("0x42", "热键栏 3",       "默认 3",                                  "", false),
        new("0x43", "热键栏 4",       "默认 4",                                  "", false),
        new("0x44", "热键栏 5",       "默认 5",                                  "", false),
        new("0x45", "热键栏 6",       "默认 6",                                  "", false),
        new("0x46", "热键栏 7",       "默认 7",                                  "", false),
        new("0x47", "热键栏 8",       "默认 8",                                  "", false),
        new("0x48", "热键栏 9",       "默认 9",                                  "", false),
    };
}
