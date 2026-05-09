using McController.Server.Net;

namespace McController.Server.Config;

public sealed class ServerConfig
{
    public int Port { get; set; } = Protocol.DefaultPort;
    public CameraConfig Camera { get; set; } = new();
    public MovementConfig Movement { get; set; } = new();

    /// <summary>
    /// Maps a hex-string ButtonId (e.g. "0x10") to its physical action.
    /// String keys keep JSON readable; runtime resolution to bytes happens
    /// once at startup in <see cref="Input.ButtonRouter"/>.
    /// </summary>
    public Dictionary<string, ButtonBinding> Bindings { get; set; } = DefaultBindings();

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
