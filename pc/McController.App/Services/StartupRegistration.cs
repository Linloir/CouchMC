using System;
using System.IO;
using Microsoft.Win32;

namespace McController.App.Services;

/// <summary>
/// Toggles the app's "run when Windows starts" state via the per-user
/// HKCU\Software\Microsoft\Windows\CurrentVersion\Run registry hive.
///
/// User-scope (not machine-scope) so installation doesn't require admin
/// rights and toggling doesn't either. The value stored is the absolute
/// path to the running .exe — so if the user moves / reinstalls the
/// app, they can re-toggle the setting from the new install to refresh it.
/// </summary>
public static class StartupRegistration
{
    private const string RunKey = @"Software\Microsoft\Windows\CurrentVersion\Run";
    private const string ValueName = "McController";

    public static bool IsEnabled()
    {
        try
        {
            using var key = Registry.CurrentUser.OpenSubKey(RunKey, writable: false);
            if (key is null) return false;
            var v = key.GetValue(ValueName) as string;
            return !string.IsNullOrWhiteSpace(v) && File.Exists(StripQuotes(v));
        }
        catch { return false; }
    }

    public static void SetEnabled(bool enabled)
    {
        try
        {
            using var key = Registry.CurrentUser.CreateSubKey(RunKey, writable: true);
            if (key is null) return;
            if (enabled)
            {
                // Quote the path in case it contains spaces (Program Files etc).
                var exe = Environment.ProcessPath ?? AppContext.BaseDirectory;
                key.SetValue(ValueName, $"\"{exe}\"");
            }
            else
            {
                key.DeleteValue(ValueName, throwOnMissingValue: false);
            }
        }
        catch { /* not fatal; user will see the toggle bounce back on refresh */ }
    }

    private static string StripQuotes(string s) =>
        s.Length >= 2 && s[0] == '"' && s[^1] == '"' ? s[1..^1] : s;
}
