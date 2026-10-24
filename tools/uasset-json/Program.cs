using Newtonsoft.Json.Linq;
using UAssetAPI;
using UAssetAPI.UnrealTypes;
using UAssetAPI.Unversioned;

// uasset-json: legacy .uasset/.uexp <-> UAssetAPI JSON, with the game's mappings (unversioned properties).
//   uasset-json tojson   <in.uasset> <out.json>                     [--usmap <Mappings.usmap>]
//   uasset-json fromjson <in.json> <out.uasset>                     [--usmap <Mappings.usmap>]
//   uasset-json bestiary <legacyRoot> <outRoot> [--layout <path>]   [--usmap <Mappings.usmap>]
// "bestiary" adds the FFR Bestiary rows to the two game tables extracted under <legacyRoot> (retoc to-legacy) and
// writes them under <outRoot> at the same paths, ready for retoc to-zen. Used by the installer on the player's own
// game files, so the release never ships game assets.
static class Program
{
    static readonly string ROOT = Path.GetFullPath(Path.Combine(AppContext.BaseDirectory, "..", "..", "..", "..", ".."));

    const string MENU_TABLE = "FFRS/Content/UI/MainMenu/Data/DT_MainMenuScene";
    const string TAG_TABLE = "FFRS/Plugins/DebugMenuWidget/Content/Data/GameplayTag/DM_DT_GameplayTag_Option";
    const string SCENE_TAG = "UI.MainMenu.Scene.Bestiary";     // must match runtime/FFRBestiary/Scripts/game.lua
    const string DEFAULT_LAYOUT = "/Game/UI/MainMenu/Help/Widget/WBP_HelpLayout.WBP_HelpLayout_C";

    static int Main(string[] argv)
    {
        var args = argv.ToList();
        string Opt(string name, string fallback)
        {
            int i = args.IndexOf(name);
            if (i < 0 || i + 1 >= args.Count) return fallback;
            var v = args[i + 1]; args.RemoveRange(i, 2); return v;
        }
        var map = new Usmap(Opt("--usmap", Path.Combine(ROOT, "extracted", "Mappings.usmap")));
        var layout = Opt("--layout", DEFAULT_LAYOUT);
        if (args.Count != 3) { Console.Error.WriteLine("usage: uasset-json tojson|fromjson|bestiary <in> <out> [--usmap f] [--layout p]"); return 2; }

        switch (args[0])
        {
            case "tojson":
                File.WriteAllText(args[2], new UAsset(args[1], EngineVersion.VER_UE5_6, map).SerializeJson(true));
                Console.WriteLine($"wrote {args[2]}");
                return 0;
            case "fromjson":
                Write(UAsset.DeserializeJson(File.ReadAllText(args[1])), map, args[2]);
                return 0;
            case "bestiary":
                Edit(args[1], args[2], MENU_TABLE, map, d => AddMenuRow(d, layout));
                Edit(args[1], args[2], TAG_TABLE, map, d => AddTagRow(d, SCENE_TAG));
                return 0;
        }
        Console.Error.WriteLine("unknown command"); return 2;
    }

    static void Write(UAsset asset, Usmap map, string path)
    {
        asset.Mappings = map;
        Directory.CreateDirectory(Path.GetDirectoryName(Path.GetFullPath(path))!);
        asset.Write(path);
        Console.WriteLine($"wrote {path}");
    }

    static void Edit(string inRoot, string outRoot, string rel, Usmap map, Action<JObject> change)
    {
        var asset = new UAsset(Path.Combine(inRoot, rel + ".uasset"), EngineVersion.VER_UE5_6, map);
        var doc = JObject.Parse(asset.SerializeJson(false));
        change(doc);
        Write(UAsset.DeserializeJson(doc.ToString()), map, Path.Combine(outRoot, rel + ".uasset"));
    }

    static JArray Rows(JObject d) => (JArray)d["Exports"]!.First(e => e["Table"] != null)["Table"]!["Data"]!;
    static JObject Prop(JToken parent, string name) => (JObject)parent["Value"]!.First(p => (string?)p["Name"] == name);
    static string Tag(JToken row) => (string)Prop(Prop(row, "SceneTag"), "TagName")["Value"]!;

    // New names must sit inside the first NamesReferencedFromExportDataCount entries: retoc drops the names after
    // that block (they are only used by the import table) when it converts to the game's zen format.
    static void AddNames(JObject d, params string[] names)
    {
        var map = (JArray)d["NameMap"]!;
        foreach (var n in names)
        {
            if (map.Any(x => (string?)x == n)) continue;
            int at = (int)d["NamesReferencedFromExportDataCount"]!;
            map.Insert(at, n);
            d["NamesReferencedFromExportDataCount"] = at + 1;
        }
    }

    static void LiteralText(JObject p, string key, string text)
    {
        p["HistoryType"] = "Base"; p["TableId"] = null; p["Namespace"] = "FFRBestiary"; p["Value"] = key;
        p["CultureInvariantString"] = text;
    }

    // DT_MainMenuScene: a "Bestiary" row (copy of the Quests row) with our tag, names, screen and no open hotkey,
    // inserted before System. The menu's entry list itself is extended at runtime by the Lua mod.
    static void AddMenuRow(JObject d, string layout)
    {
        var table = Rows(d);
        if (table.Any(r => (string?)r["Name"] == "Bestiary")) throw new Exception("Bestiary row already there");
        var row = (JObject)table.First(r => Tag(r) == "UI.MainMenu.Scene.Journal").DeepClone();
        row["Name"] = "Bestiary";
        Prop(Prop(row, "SceneTag"), "TagName")["Value"] = SCENE_TAG;
        LiteralText(Prop(row, "SceneTitle"), "SceneTitle", "Bestiary");
        LiteralText(Prop(row, "EntryName"), "EntryName", "Bestiary");
        Prop(row, "OpenInputActionName")["Value"] = "None";
        var dot = layout.LastIndexOf('.');
        var path = (JObject)Prop(Prop(row, "LayoutData"), "LayoutWidget")["Value"]!["AssetPath"]!;
        path["PackageName"] = layout[..dot]; path["AssetName"] = layout[(dot + 1)..];
        int system = table.ToList().FindIndex(r => Tag(r) == "UI.MainMenu.Scene.System");
        table.Insert(system < 0 ? table.Count : system, row);
        AddNames(d, "None", "Bestiary", SCENE_TAG, "FFRBestiary", "SceneTitle", "EntryName", layout[..dot], layout[(dot + 1)..]);
        Console.WriteLine("menu rows: " + string.Join(", ", table.Select(r => Tag(r))));
    }

    // DM_DT_GameplayTag_Option (in DefaultGameplayTags.ini's GameplayTagTableList): registers our tag.
    static void AddTagRow(JObject d, string tag)
    {
        var table = Rows(d);
        var name = tag.Replace('.', '_');
        if (table.Any(r => (string?)r["Name"] == name)) throw new Exception("tag row already there");
        var row = (JObject)table[0].DeepClone();
        row["Name"] = name;
        Prop(row, "Tag")["Value"] = tag;
        table.Add(row);
        AddNames(d, name, tag);
        Console.WriteLine("tag rows: " + string.Join(", ", table.Select(r => (string?)r["Name"])));
    }
}
