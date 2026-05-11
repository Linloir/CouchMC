using System.Text.Json;
using System.Text.Json.Nodes;
using System.Text.Json.Serialization;

namespace McController.Core.Config;

/// <summary>
/// JSON-backed config persistence. Loads on startup, saves on demand
/// (debounced from the UI to avoid high-frequency disk writes).
///
/// Handles the pre-profile flat config layout (single camera/movement
/// at the root) by wrapping it into a one-element profile list during
/// load.
/// </summary>
public static class ConfigStore
{
    private static readonly JsonSerializerOptions s_options = new()
    {
        WriteIndented = true,
        PropertyNamingPolicy = JsonNamingPolicy.CamelCase,
        Converters = { new JsonStringEnumConverter(JsonNamingPolicy.CamelCase) },
    };

    public static ServerConfig LoadOrDefault(string path)
    {
        try
        {
            if (!File.Exists(path)) return new ServerConfig();
            var json = File.ReadAllText(path);
            var migrated = MigrateIfNeeded(json);
            return JsonSerializer.Deserialize<ServerConfig>(migrated, s_options) ?? new ServerConfig();
        }
        catch (Exception ex)
        {
            Console.Error.WriteLine($"[ConfigStore] failed to load {path}: {ex.Message}. Using defaults.");
            return new ServerConfig();
        }
    }

    public static void Save(string path, ServerConfig config)
    {
        var json = JsonSerializer.Serialize(config, s_options);
        var dir = Path.GetDirectoryName(Path.GetFullPath(path));
        if (!string.IsNullOrEmpty(dir)) Directory.CreateDirectory(dir);
        File.WriteAllText(path, json);
    }

    /// <summary>
    /// Pre-profile configs had <c>camera</c>/<c>movement</c> at the top
    /// level and no <c>profiles</c> array. Wrap them into a single
    /// default profile so the rest of deserialization sees the new shape.
    /// New-shape configs pass through unchanged.
    /// </summary>
    private static string MigrateIfNeeded(string json)
    {
        JsonNode? root;
        try { root = JsonNode.Parse(json); }
        catch { return json; }
        if (root is not JsonObject obj) return json;
        if (obj.ContainsKey("profiles")) return json;
        var camera = obj["camera"];
        var movement = obj["movement"];
        if (camera is null && movement is null) return json;
        var profile = new JsonObject
        {
            ["id"] = "default",
            ["name"] = "默认",
            ["camera"] = camera?.DeepClone() ?? new JsonObject(),
            ["movement"] = movement?.DeepClone() ?? new JsonObject(),
        };
        obj["profiles"] = new JsonArray(profile);
        obj["activeProfileId"] = "default";
        obj.Remove("camera");
        obj.Remove("movement");
        return obj.ToJsonString();
    }
}
