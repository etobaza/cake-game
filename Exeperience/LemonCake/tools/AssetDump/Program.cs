using UAssetAPI;
using UAssetAPI.UnrealTypes;
using UAssetAPI.ExportTypes;
using System.Text.Json;
using System.Text.Json.Nodes;

if (args.Length < 3)
{
    Console.Error.WriteLine("Usage: AssetDump <input-directory> <output-directory> <VER_UE4_24> [path-filter]");
    return 2;
}
var root = Path.GetFullPath(args[0]);
var output = Path.GetFullPath(args[1]);
var engine = Enum.Parse<EngineVersion>(args[2]);
Directory.CreateDirectory(output);
var results = new List<object>();
int success = 0, failure = 0;
foreach (var path in Directory.EnumerateFiles(root, "*", SearchOption.AllDirectories).Order())
{
    if (Path.GetExtension(path) is not (".uasset" or ".umap")) continue;
    var relative = Path.GetRelativePath(root, path);
    if (args.Length > 3 && !relative.Contains(args[3], StringComparison.OrdinalIgnoreCase)) continue;
    try
    {
        var asset = new UAsset(path, engine);
        var target = Path.Combine(output, relative + ".json");
        Directory.CreateDirectory(Path.GetDirectoryName(target)!);
        var document = JsonNode.Parse(asset.SerializeJson())!;
        var offsets = new Dictionary<string, object>();
        foreach (var function in asset.Exports.OfType<FunctionExport>())
        {
            uint offset = 0;
            var positions = new List<uint>();
            foreach (var instruction in function.ScriptBytecode ?? [])
            {
                positions.Add(offset);
                offset += instruction.GetSize(asset);
            }
            offsets[function.ObjectName.ToString()] = new { positions, computedSize = offset, declaredSize = function.ScriptBytecodeSize };
        }
        document["ResearchBytecodeOffsets"] = JsonSerializer.SerializeToNode(offsets);
        File.WriteAllText(target, document.ToJsonString());
        var raw = asset.Exports.Count(e => e.GetType().Name == "RawExport");
        results.Add(new { path = relative.Replace('\\', '/'), status = "ok", exports = asset.Exports.Count, rawExports = raw });
        success++;
    }
    catch (Exception ex)
    {
        results.Add(new { path = relative.Replace('\\', '/'), status = "error", error = ex.GetType().Name + ": " + ex.Message });
        failure++;
    }
    if ((success + failure) % 100 == 0) Console.WriteLine($"Parsed {success}; failed {failure}");
}
File.WriteAllText(Path.Combine(output, "parse-report.json"), JsonSerializer.Serialize(results, new JsonSerializerOptions { WriteIndented = true }));
Console.WriteLine($"Done: {success} parsed; {failure} failed. RawExport counts in parse-report.json are partial-parse indicators.");
return failure == 0 ? 0 : 1;
