using System.Text;
using CUE4Parse.Compression;
using CUE4Parse.Encryption.Aes;
using CUE4Parse.FileProvider;
using CUE4Parse.MappingsProvider.Usmap;
using CUE4Parse.UE4.Objects.Core.Misc;
using CUE4Parse.UE4.Versions;
using Newtonsoft.Json;

// ffr-dump: read FFR's IoStore containers (from the modding copy) with CUE4Parse. Recon only.
//   ffr-dump list <substring>              list matching package paths
//   ffr-dump json <objectPath> <out.json>  one object (DataTable, StringTable, ...) as JSON
//   ffr-dump tree <pathPrefix> <outDir>    every package under a prefix as JSON (all exports)
//   ffr-dump find <pathPrefix> <ext> <typeRegex> <out.jsonl>  exports whose class matches, one JSON line each
//   ffr-dump names <pathPrefix> <nameRegex>   packages whose name map has a matching FName
//   ffr-dump raw <filePath> <out>          one file's bytes (ini, locres, ...)
//   ffr-dump locres <culture> <out.json>   FFRS Game.locres for a culture (e.g. en) as JSON
static class Program
{
    const string PAKS = @"C:\Games\FFR-mod\FFRS\Content\Paks";
    static readonly string ROOT = Path.GetFullPath(Path.Combine(AppContext.BaseDirectory, "..", "..", "..", "..", ".."));

    static int Main(string[] args)
    {
        Console.OutputEncoding = Encoding.UTF8;
        if (args.Length < 2) { Console.Error.WriteLine("usage: ffr-dump list|json|tree|locres ..."); return 2; }
        var oodleDir = Path.Combine(ROOT, "tools", "oodle"); Directory.CreateDirectory(oodleDir);
        string? oodle = Path.Combine(oodleDir, OodleHelper.OODLE_NAME_CURRENT);
        if (!File.Exists(oodle)) OodleHelper.DownloadOodleDll(ref oodle);
        OodleHelper.Initialize(oodle!);

        var provider = new DefaultFileProvider(Environment.GetEnvironmentVariable("FFR_PAKS") ?? PAKS,
            SearchOption.TopDirectoryOnly, new VersionContainer(EGame.GAME_UE5_6));
        provider.MappingsContainer = new FileUsmapTypeMappingsProvider(Path.Combine(ROOT, "extracted", "Mappings.usmap"));
        provider.Initialize();
        provider.SubmitKey(new FGuid(), new FAesKey("0x0000000000000000000000000000000000000000000000000000000000000000"));
        provider.ReadScriptData = Environment.GetEnvironmentVariable("FFR_SCRIPT") == "1";   // Blueprint bytecode in exports
        provider.PostMount();
        Console.Error.WriteLine($"mounted files: {provider.Files.Count}");

        switch (args[0])
        {
            case "list":
                foreach (var f in provider.Files.Keys.Where(k => k.Contains(args[1], StringComparison.OrdinalIgnoreCase)).OrderBy(k => k))
                    Console.WriteLine(f);
                return 0;
            case "json":
            {
                var obj = provider.LoadPackageObject(args[1]);
                Write(args[2], obj);
                return 0;
            }
            case "tree":
            {
                int ok = 0, bad = 0;
                foreach (var f in provider.Files.Keys.Where(k => k.StartsWith(args[1], StringComparison.OrdinalIgnoreCase)
                                                              && k.EndsWith(".uasset")).OrderBy(k => k))
                {
                    var outPath = Path.Combine(args[2], Path.ChangeExtension(f.Substring(args[1].Length).TrimStart('/'), ".json"));
                    try { Write(outPath, provider.LoadPackage(f).GetExports()); ok++; }
                    catch (Exception e) { bad++; Console.Error.WriteLine($"FAIL {f}: {e.Message}"); }
                }
                Console.Error.WriteLine($"tree: {ok} ok, {bad} failed");
                return bad == 0 ? 0 : 1;
            }
            case "find":
            {
                var rx = new System.Text.RegularExpressions.Regex(args[3]);
                using var w = new StreamWriter(args[4], false, new UTF8Encoding(false));
                int pk = 0, hits = 0, bad = 0;
                foreach (var f in provider.Files.Keys.Where(k => k.StartsWith(args[1], StringComparison.OrdinalIgnoreCase)
                                                              && k.EndsWith(args[2])).OrderBy(k => k))
                {
                    pk++;
                    try
                    {
                        foreach (var e in provider.LoadPackage(f).GetExports())
                        {
                            if (!rx.IsMatch(e.ExportType)) continue;
                            hits++;
                            w.WriteLine(JsonConvert.SerializeObject(new { package = f, name = e.Name, type = e.ExportType, obj = e }));
                        }
                    }
                    catch (Exception ex) { bad++; Console.Error.WriteLine($"FAIL {f}: {ex.Message}"); }
                }
                Console.Error.WriteLine($"find: {pk} packages, {hits} exports, {bad} failed");
                return 0;
            }
            case "names":
            {
                var rx = new System.Text.RegularExpressions.Regex(args[2]);
                foreach (var f in provider.Files.Keys.Where(k => k.StartsWith(args[1], StringComparison.OrdinalIgnoreCase)
                                                              && (k.EndsWith(".uasset") || k.EndsWith(".umap"))).OrderBy(k => k))
                {
                    try
                    {
                        var hits = provider.LoadPackage(f).NameMap.Select(n => n.Name).Where(n => n != null && rx.IsMatch(n)).ToList();
                        if (hits.Count > 0) Console.WriteLine(f + "	" + string.Join(",", hits));
                    }
                    catch (Exception ex) { Console.Error.WriteLine($"FAIL {f}: {ex.Message}"); }
                }
                return 0;
            }
            case "objects":                                       // objects <list of object paths> <outDir>: json each
                foreach (var p in File.ReadAllLines(args[1]).Where(l => l.Trim().Length > 0))
                {
                    var outPath = Path.Combine(args[2], p.TrimStart('/').Split('.')[0] + ".json");
                    try { Write(outPath, provider.LoadPackageObject(p)); }
                    catch (Exception ex) { Console.Error.WriteLine($"FAIL {p}: {ex.Message}"); }
                }
                return 0;
            case "raw":
                Directory.CreateDirectory(Path.GetDirectoryName(Path.GetFullPath(args[2]))!);
                File.WriteAllBytes(args[2], provider.SaveAsset(args[1]));
                return 0;
            case "locres":
            {
                var path = provider.Files.Keys.First(k => k.Equals($"FFRS/Content/Localization/Game/{args[1]}/Game.locres", StringComparison.OrdinalIgnoreCase));
                Write(args[2], new CUE4Parse.UE4.Localization.FTextLocalizationResource(provider.CreateReader(path)));
                return 0;
            }
        }
        Console.Error.WriteLine("unknown command"); return 2;
    }

    static void Write(string path, object obj)
    {
        Directory.CreateDirectory(Path.GetDirectoryName(Path.GetFullPath(path))!);
        File.WriteAllText(path, JsonConvert.SerializeObject(obj, Formatting.Indented), new UTF8Encoding(false));
    }
}
