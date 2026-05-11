using System;
using System.IO;
using System.Text.Json;

namespace McController.App.Services;

/// <summary>
/// User-tunable visual prefs for the main window:
/// - master switch for transparency (Acrylic backdrop on/off)
/// - opacity of the tint over the sidebar + title-bar area
/// - opacity of the tint over the content area
///
/// Persisted as JSON in %APPDATA%\McController\appearance.json, separate
/// from the controller config so a layout / tuning change doesn't
/// inadvertently touch visual prefs. Exposes a <see cref="Changed"/> event
/// so the settings page can push live updates to the main window.
/// </summary>
public static class AppearancePreferences
{
    public sealed class Settings
    {
        /// <summary>Master switch. When false the window paints fully solid.</summary>
        public bool TransparencyEnabled { get; set; } = true;

        /// <summary>0..1. Tint over the sidebar + title bar area; 0 = pure acrylic.</summary>
        public double ChromeOpacity { get; set; } = 0.0;

        /// <summary>0..1. Tint over the content area; mute wallpaper bleed-through.</summary>
        public double ContentOpacity { get; set; } = 0.35;
    }

    private static readonly object _lock = new();
    private static Settings _current = Load();

    /// <summary>Fired on the calling thread whenever <see cref="Update"/> mutates the prefs.</summary>
    public static event Action<Settings>? Changed;

    public static Settings Current
    {
        get { lock (_lock) return Clone(_current); }
    }

    public static void Update(bool transparencyEnabled, double chromeOpacity, double contentOpacity)
    {
        Settings snapshot;
        lock (_lock)
        {
            _current = new Settings
            {
                TransparencyEnabled = transparencyEnabled,
                ChromeOpacity = Math.Clamp(chromeOpacity, 0.0, 1.0),
                ContentOpacity = Math.Clamp(contentOpacity, 0.0, 1.0),
            };
            Save(_current);
            snapshot = Clone(_current);
        }
        Changed?.Invoke(snapshot);
    }

    private static string Path =>
        System.IO.Path.Combine(
            Environment.GetFolderPath(Environment.SpecialFolder.ApplicationData),
            "McController", "appearance.json");

    private static Settings Load()
    {
        try
        {
            if (File.Exists(Path))
            {
                var json = File.ReadAllText(Path);
                var s = JsonSerializer.Deserialize<Settings>(json);
                if (s != null) return s;
            }
        }
        catch { }
        return new Settings();
    }

    private static void Save(Settings s)
    {
        try
        {
            var dir = System.IO.Path.GetDirectoryName(Path);
            if (!string.IsNullOrEmpty(dir)) Directory.CreateDirectory(dir);
            File.WriteAllText(Path,
                JsonSerializer.Serialize(s, new JsonSerializerOptions { WriteIndented = true }));
        }
        catch { /* best-effort */ }
    }

    private static Settings Clone(Settings s) => new()
    {
        TransparencyEnabled = s.TransparencyEnabled,
        ChromeOpacity = s.ChromeOpacity,
        ContentOpacity = s.ContentOpacity,
    };
}
