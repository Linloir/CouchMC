using System.Globalization;
using McController.Server.Config;

namespace McController.Server.Input;

/// <summary>
/// Routes a wire-protocol ButtonId + down state to the correct OS input action,
/// using bindings loaded from config. Bindings are resolved once at construction.
///
/// Tracks currently-held buttons so that <see cref="ReleaseAll"/> on disconnect
/// restores a clean keyboard/mouse state (prevents stuck-key bugs).
/// </summary>
public sealed class ButtonRouter
{
    private readonly IInputInjector _injector;
    private readonly Dictionary<byte, ResolvedBinding> _resolved;
    private readonly HashSet<byte> _down = new();
    private readonly object _lock = new();

    public ButtonRouter(IInputInjector injector, ServerConfig config)
    {
        _injector = injector;
        _resolved = ResolveBindings(config.Bindings);
    }

    public void Handle(byte buttonId, bool down)
    {
        lock (_lock)
        {
            if (!_resolved.TryGetValue(buttonId, out var b)) return;

            if (down) _down.Add(buttonId);
            else _down.Remove(buttonId);

            switch (b.Kind)
            {
                case BindingKind.Key:
                    _injector.Key(b.Scancode, down);
                    break;
                case BindingKind.Mouse:
                    _injector.SetMouseButton(b.MouseButton, down);
                    break;
            }
        }
    }

    public void ReleaseAll()
    {
        lock (_lock)
        {
            foreach (var id in _down)
            {
                if (!_resolved.TryGetValue(id, out var b)) continue;
                switch (b.Kind)
                {
                    case BindingKind.Key:
                        _injector.Key(b.Scancode, false);
                        break;
                    case BindingKind.Mouse:
                        _injector.SetMouseButton(b.MouseButton, false);
                        break;
                }
            }
            _down.Clear();
        }
    }

    private static Dictionary<byte, ResolvedBinding> ResolveBindings(
        IDictionary<string, ButtonBinding> raw)
    {
        var result = new Dictionary<byte, ResolvedBinding>();
        foreach (var (key, b) in raw)
        {
            if (!TryParseHexByte(key, out var id)) continue;

            switch (b.Type.ToLowerInvariant())
            {
                case "key":
                    if (b.Scancode != null && TryParseHexUshort(b.Scancode, out var sc))
                        result[id] = new ResolvedBinding(BindingKind.Key, sc, MouseButton.Left);
                    break;
                case "mouse":
                    var mb = (b.Button ?? "").ToLowerInvariant() switch
                    {
                        "left" => MouseButton.Left,
                        "right" => MouseButton.Right,
                        "middle" => MouseButton.Middle,
                        _ => (MouseButton?)null,
                    };
                    if (mb.HasValue)
                        result[id] = new ResolvedBinding(BindingKind.Mouse, 0, mb.Value);
                    break;
            }
        }
        return result;
    }

    private static bool TryParseHexByte(string s, out byte value)
    {
        if (s.StartsWith("0x", StringComparison.OrdinalIgnoreCase)) s = s[2..];
        return byte.TryParse(s, NumberStyles.HexNumber, CultureInfo.InvariantCulture, out value);
    }

    private static bool TryParseHexUshort(string s, out ushort value)
    {
        if (s.StartsWith("0x", StringComparison.OrdinalIgnoreCase)) s = s[2..];
        return ushort.TryParse(s, NumberStyles.HexNumber, CultureInfo.InvariantCulture, out value);
    }

    private enum BindingKind { Key, Mouse }
    private readonly record struct ResolvedBinding(BindingKind Kind, ushort Scancode, MouseButton MouseButton);
}
