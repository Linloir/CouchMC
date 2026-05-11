using System.Text.Json.Serialization;
using McController.Core.Net;

namespace McController.Core.Config;

/// <summary>
/// Root config object. Holds a list of named tuning profiles plus
/// app-wide state (port, button bindings). The "active" profile is
/// the one currently driving the live <see cref="Input.CameraCurve"/>
/// and <see cref="Input.JoystickToWasdMapper"/>; the UI can swap the
/// active profile or edit its values directly.
/// </summary>
public sealed class ServerConfig
{
    public int Port { get; set; } = Protocol.DefaultPort;

    /// <summary>Id of the currently-active profile in <see cref="Profiles"/>.</summary>
    public string ActiveProfileId { get; set; } = "default";

    public List<ControllerProfile> Profiles { get; set; } = new() { new ControllerProfile() };

    /// <summary>
    /// Maps a hex-string ButtonId (e.g. "0x10") to its physical action.
    /// String keys keep JSON readable; runtime resolution to bytes happens
    /// once at startup in <see cref="Input.ButtonRouter"/>.
    /// </summary>
    public Dictionary<string, ButtonBinding> Bindings { get; set; } = DefaultBindings();

    /// <summary>
    /// Returns the active profile, or falls back to the first profile if
    /// <see cref="ActiveProfileId"/> doesn't match anything (recovers from
    /// edits that orphan the active id). Never null at runtime — the
    /// constructor seeds <see cref="Profiles"/> with at least one entry.
    /// </summary>
    [JsonIgnore]
    public ControllerProfile ActiveProfile
    {
        get
        {
            if (Profiles.Count == 0) Profiles.Add(new ControllerProfile());
            return Profiles.FirstOrDefault(p => p.Id == ActiveProfileId) ?? Profiles[0];
        }
    }

    /// <summary>
    /// Live camera config. Delegates to the active profile so existing
    /// consumers (<see cref="Input.CameraCurve"/>) keep working unchanged
    /// across profile switches — they read the field on every input packet.
    /// </summary>
    [JsonIgnore]
    public CameraConfig Camera
    {
        get => ActiveProfile.Camera;
        set => ActiveProfile.Camera = value;
    }

    /// <summary>Live movement config. Same delegation pattern as <see cref="Camera"/>.</summary>
    [JsonIgnore]
    public MovementConfig Movement
    {
        get => ActiveProfile.Movement;
        set => ActiveProfile.Movement = value;
    }

    private static Dictionary<string, ButtonBinding> DefaultBindings() => new()
    {
        ["0x01"] = new() { Type = "mouse", Button = "left" },    // MOUSE_LEFT
        ["0x02"] = new() { Type = "mouse", Button = "right" },   // MOUSE_RIGHT
        ["0x10"] = new() { Type = "key", Scancode = "0x39" },    // JUMP -> Space
        ["0x11"] = new() { Type = "key", Scancode = "0x2A" },    // SNEAK -> LShift
        ["0x12"] = new() { Type = "key", Scancode = "0x1D" },    // SPRINT -> LCtrl
        ["0x20"] = new() { Type = "key", Scancode = "0x12" },    // INVENTORY -> E
        ["0x21"] = new() { Type = "key", Scancode = "0x10" },    // DROP -> Q
        ["0x22"] = new() { Type = "key", Scancode = "0x21" },    // SWAP_HAND -> F
        ["0x30"] = new() { Type = "key", Scancode = "0x01" },    // ESC
        ["0x40"] = new() { Type = "key", Scancode = "0x02" },    // HOTBAR_1
        ["0x41"] = new() { Type = "key", Scancode = "0x03" },
        ["0x42"] = new() { Type = "key", Scancode = "0x04" },
        ["0x43"] = new() { Type = "key", Scancode = "0x05" },
        ["0x44"] = new() { Type = "key", Scancode = "0x06" },
        ["0x45"] = new() { Type = "key", Scancode = "0x07" },
        ["0x46"] = new() { Type = "key", Scancode = "0x08" },
        ["0x47"] = new() { Type = "key", Scancode = "0x09" },
        ["0x48"] = new() { Type = "key", Scancode = "0x0A" },    // HOTBAR_9
    };
}

/// <summary>
/// A single named tuning profile. Camera + movement settings the user
/// can switch between (e.g. "默认" / "瞄准" / "建筑").
/// </summary>
public sealed class ControllerProfile
{
    /// <summary>Stable identifier. Generated once when the profile is created.</summary>
    public string Id { get; set; } = "default";

    public string Name { get; set; } = "默认";

    public CameraConfig Camera { get; set; } = new();
    public MovementConfig Movement { get; set; } = new();
}

public sealed class CameraConfig
{
    /// <summary>User-facing sensitivity multiplier (0.5 .. 3.0). Final scale = curve * this.</summary>
    public float UserSensitivity { get; set; } = 1.5f;

    /// <summary>Developer-tuned curve, hidden from end users in production.</summary>
    public CurveType CurveType { get; set; } = CurveType.Linear;
    public float AccelFactor { get; set; } = 0f;
    public float AccelExp { get; set; } = 1f;
    public float MaxAccelMultiplier { get; set; } = 3f;
}

public sealed class MovementConfig
{
    // Default 0 — most direct response. The mapper uses <= for both
    // dead zone and exit threshold so a v=0 release event always lifts
    // the held key, even with everything at 0.
    public float DeadZone { get; set; } = 0f;
    public float EnterThreshold { get; set; } = 0.30f;
    public float ExitThreshold { get; set; } = 0.20f;
}

public sealed class ButtonBinding
{
    /// <summary>"key" or "mouse"</summary>
    public string Type { get; set; } = "key";

    /// <summary>Hex-string Windows scancode, e.g. "0x39" for Space. Used when Type == "key".</summary>
    public string? Scancode { get; set; }

    /// <summary>"left" / "right" / "middle". Used when Type == "mouse".</summary>
    public string? Button { get; set; }
}

public enum CurveType
{
    Linear,
    Power,
}
