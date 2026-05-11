using System;
using System.Collections.ObjectModel;
using System.Linq;
using McController.Core.Config;

namespace McController.App.Services;

/// <summary>
/// View-side wrapper around the profile list inside <see cref="ServerConfig"/>.
/// Owns the <see cref="ObservableCollection{T}"/> the picker binds to and
/// keeps it in sync with the source-of-truth list on the config object,
/// so server-side code keeps seeing the same <c>cfg.Profiles</c> list it
/// was wired up with at startup.
///
/// Why not just bind the picker to <c>cfg.Profiles</c>? It's a plain
/// <c>List&lt;T&gt;</c> for JSON round-tripping; ObservableCollection's
/// CollectionChanged events make WinUI live-update without extra plumbing.
/// </summary>
public sealed class ProfileManager
{
    private readonly ServerConfig _config;
    private readonly ServerHost _host;

    public ObservableCollection<ControllerProfile> Profiles { get; }

    public event Action? ActiveProfileChanged;

    public ProfileManager(ServerHost host)
    {
        _host = host;
        _config = host.Config;
        Profiles = new ObservableCollection<ControllerProfile>(_config.Profiles);
        Profiles.CollectionChanged += (_, _) => SyncBackToConfig();
    }

    public ControllerProfile ActiveProfile => _config.ActiveProfile;

    public void SetActive(ControllerProfile profile)
    {
        if (!Profiles.Contains(profile)) return;
        if (_config.ActiveProfileId == profile.Id) return;
        _config.ActiveProfileId = profile.Id;
        _host.OnActiveProfileChanged();
        ActiveProfileChanged?.Invoke();
    }

    public ControllerProfile AddNew(string name)
    {
        var profile = new ControllerProfile
        {
            Id = Guid.NewGuid().ToString("N"),
            Name = string.IsNullOrWhiteSpace(name) ? "新方案" : name.Trim(),
        };
        Profiles.Add(profile);
        return profile;
    }

    public ControllerProfile Duplicate(ControllerProfile source)
    {
        var copy = new ControllerProfile
        {
            Id = Guid.NewGuid().ToString("N"),
            Name = source.Name + " 副本",
            Camera = new CameraConfig
            {
                UserSensitivity = source.Camera.UserSensitivity,
                CurveType = source.Camera.CurveType,
                AccelFactor = source.Camera.AccelFactor,
                AccelExp = source.Camera.AccelExp,
                MaxAccelMultiplier = source.Camera.MaxAccelMultiplier,
            },
            Movement = new MovementConfig
            {
                DeadZone = source.Movement.DeadZone,
                EnterThreshold = source.Movement.EnterThreshold,
                ExitThreshold = source.Movement.ExitThreshold,
            },
        };
        Profiles.Add(copy);
        return copy;
    }

    /// <summary>Deletes a profile. Refuses to delete the last one.</summary>
    public bool Delete(ControllerProfile profile)
    {
        if (Profiles.Count <= 1) return false;
        var wasActive = _config.ActiveProfileId == profile.Id;
        Profiles.Remove(profile);
        if (wasActive)
        {
            // Pick a survivor and switch.
            var next = Profiles.First();
            _config.ActiveProfileId = next.Id;
            _host.OnActiveProfileChanged();
            ActiveProfileChanged?.Invoke();
        }
        return true;
    }

    private void SyncBackToConfig()
    {
        _config.Profiles.Clear();
        foreach (var p in Profiles) _config.Profiles.Add(p);
        // Repair active id if it points at a deleted profile.
        if (_config.Profiles.All(p => p.Id != _config.ActiveProfileId) && _config.Profiles.Count > 0)
        {
            _config.ActiveProfileId = _config.Profiles[0].Id;
            _host.OnActiveProfileChanged();
            ActiveProfileChanged?.Invoke();
        }
    }
}
