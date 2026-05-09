using System.Text.Json;
using System.Text.Json.Serialization;

namespace McController.Server.Config;

/// <summary>
/// JSON-backed config persistence. Loads on startup; saves on demand
/// (debounced from the UI to avoid high-frequency disk writes).
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
            return JsonSerializer.Deserialize<ServerConfig>(json, s_options) ?? new ServerConfig();
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
}
