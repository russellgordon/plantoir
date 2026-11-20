using System.Security.Cryptography;
using System.Text;
using System.Text.Json.Nodes;
using System.Text.RegularExpressions;
using Xunit;
using Xunit.Abstractions;

namespace Plantoir.Tests;

/// <summary>
/// #965: on a clean Windows (no Visual C++ redistributable) the runtime's
/// native Node modules must still load. Two of them, lightningcss and the
/// Typst compiler, import <c>VCRUNTIME140.dll</c>, and the first preview on
/// a clean machine stopped with <c>ERR_DLOPEN_FAILED</c>, because the only
/// copy was in <c>runtime\python</c>, which is not on PATH. The runtime now
/// carries that file beside <c>runtime\node\node.exe</c> and beside each of
/// those two modules (Russell's rulings, 2026-11-14 and 2026-11-19), taken
/// by <c>fetch-runtime.ps1</c> out of Microsoft's own Visual C++
/// Redistributable without running it (#1010; until then from the Python
/// zip). Node
/// loads a <c>.node</c> file with <c>LOAD_WITH_ALTERED_SEARCH_PATH</c>, so
/// Windows looks for its libraries in the MODULE's folder, then System32,
/// and node.exe's folder only through PATH: the copy beside the module is
/// the one that counts here.
/// <c>contracts/toolchain.json</c> → <c>windowsNodeVcRuntime</c> holds the
/// file, its hash, the list of Windows' own libraries and the reasons;
/// <c>documentation/12-windows-app.md</c> → "The Visual C++ runtime beside
/// node.exe".
/// </summary>
/// <remarks>
/// Loading each module with a PATH that holds no copy is not a test the
/// development PC can run (its System32 has the redistributable), so the
/// honest form, as the issue says, is a check on the runtime's FILES: every
/// library each <c>.node</c> imports must sit beside it (where Windows looks
/// first, with or without PATH), or be on the contract's named list of
/// libraries every Windows carries. A copy beside <c>node.exe</c> alone does
/// not count for a module. That fails on a PC that has the redistributable just as
/// it does on one that does not.
/// </remarks>
public sealed class NativeModuleImportsTests
{
    private readonly ITestOutputHelper _output;

    public NativeModuleImportsTests(ITestOutputHelper output) => _output = output;

    private static string RepoRoot => ContractLoader.RepositoryRoot;

    private static JsonNode Entry =>
        ContractLoader.LoadJson("toolchain.json")["windowsNodeVcRuntime"]
        ?? throw new InvalidOperationException("contracts/toolchain.json has no windowsNodeVcRuntime.");

    private static JsonNode CarriedFile => Entry["files"]!.AsArray().Single()!;

    private static IReadOnlyList<string> ModuleFolders =>
        Entry["besideModules"]!.AsArray().Select(n => n!.ToString()).ToList();

    private static IReadOnlyList<string> SystemLibraries =>
        Entry["windowsSystemLibraries"]!.AsArray().Select(n => n!.ToString().ToLowerInvariant()).ToList();

    private static bool IsSystemLibrary(string name)
    {
        string lower = name.ToLowerInvariant();
        foreach (string entry in SystemLibraries)
        {
            if (entry.EndsWith("*", StringComparison.Ordinal))
            {
                if (lower.StartsWith(entry[..^1], StringComparison.Ordinal)) return true;
            }
            else if (lower == entry) return true;
        }
        return false;
    }

    // MARK: - The contract, the recipe and the build

    [Fact]
    public void TheSystemListNamesNoVisualCppRuntimeLibrary()
    {
        string[] redistributable = { "vcruntime140.dll", "vcruntime140_1.dll", "vcruntime140_threads.dll", "msvcp140.dll",
                                     "msvcp140_1.dll", "msvcp140_2.dll", "concrt140.dll", "vccorlib140.dll", "ucrtbased.dll" };
        foreach (string name in redistributable)
            Assert.False(IsSystemLibrary(name),
                $"contracts/toolchain.json -> windowsNodeVcRuntime -> windowsSystemLibraries matches {name}, which the Visual C++ redistributable installs, not Windows: a clean PC lacks it (#965).");
        foreach (string entry in SystemLibraries)
            Assert.False(entry.StartsWith("vc", StringComparison.Ordinal) || entry.StartsWith("msvc", StringComparison.Ordinal) || entry == "*",
                $"windowsSystemLibraries entry '{entry}' would cover the Visual C++ runtime.");
    }

    [Fact]
    public void TheRecipeCarriesTheContractsVersionAndHash()
    {
        string recipe = File.ReadAllText(Path.Combine(RepoRoot, "windows-app", "Vendor", "fetch-runtime.ps1"));
        string version = CarriedFile["fileVersion"]!.ToString();
        string sha = CarriedFile["sha256"]!.ToString();
        string bytes = CarriedFile["bytes"]!.ToString();
        Assert.True(HasStatement(recipe, $"$NodeVcRuntimeVersion = \"{version}\""), $"fetch-runtime.ps1 does not set $NodeVcRuntimeVersion = \"{version}\".");
        Assert.True(HasStatement(recipe, $"$NodeVcRuntimeSha256  = \"{sha}\""), $"fetch-runtime.ps1 does not set $NodeVcRuntimeSha256 to the contract's {sha}.");
        Assert.True(HasStatement(recipe, $"$NodeVcRuntimeLength  = {bytes}"), $"fetch-runtime.ps1 does not set $NodeVcRuntimeLength = {bytes}.");
        Assert.True(HasStatement(recipe, "Install-NodeVcRuntime $vcRuntimeSource $nodeDir $Runtime"),
            "fetch-runtime.ps1 never runs Install-NodeVcRuntime $vcRuntimeSource $nodeDir $Runtime: the runtime would carry no Visual C++ runtime beside node.exe (#965).");
        Assert.True(HasStatement(recipe, "$fields.nodeVcRuntime = $NodeVcRuntimeVersion"),
            "fetch-runtime.ps1 never records nodeVcRuntime in the manifest, so the build's guard cannot see it.");
    }

    /// <summary>
    /// #1010 (Russell's ruling of 2026-11-19 on #1006): the copy comes from
    /// Microsoft's own Visual C++ Redistributable, pinned by the contract's
    /// SHA-256, size, version and the places inside it, and never from the
    /// Python zip. Every call that places the file is fed by
    /// <c>Get-MicrosoftVcRuntime</c>, and its cache sits outside
    /// <c>runtime\</c>, which the installer packs whole.
    /// </summary>
    [Fact]
    public void TheRecipeTakesTheFileFromMicrosoftsRedistributable()
    {
        string recipe = File.ReadAllText(Path.Combine(RepoRoot, "windows-app", "Vendor", "fetch-runtime.ps1"));
        JsonNode bundle = Entry["redistributable"]
            ?? throw new InvalidOperationException("contracts/toolchain.json -> windowsNodeVcRuntime has no redistributable.");
        string[] expected =
        {
            $"$VcRedistVersion   = \"{bundle["version"]}\"",
            $"$VcRedistUrl       = \"{bundle["url"]}\"",
            $"$VcRedistPermalink = \"{bundle["permalink"]}\"",
            $"$VcRedistSha256    = \"{bundle["sha256"]}\"",
            $"$VcRedistLength    = {bundle["bytes"]}",
            $"$VcRedistContainerOffset = {bundle["containerOffset"]}",
            $"$VcRedistContainerLength = {bundle["containerBytes"]}",
            $"$VcRedistPayload         = \"{bundle["payload"]}\"",
            $"$VcRedistPayloadLength   = {bundle["payloadBytes"]}",
            $"$VcRedistMember          = \"{bundle["member"]}\"",
        };
        foreach (string statement in expected)
            Assert.True(HasStatement(recipe, statement), $"fetch-runtime.ps1 does not set {statement} (contracts/toolchain.json -> windowsNodeVcRuntime -> redistributable).");

        Assert.StartsWith("https://download.visualstudio.microsoft.com/", bundle["url"]!.ToString(), StringComparison.Ordinal);
        Assert.StartsWith("https://aka.ms/", bundle["permalink"]!.ToString(), StringComparison.Ordinal);

        int placements = 0;
        int fetches = 0;
        foreach (string line in recipe.Split('\n'))
        {
            string trimmed = line.Trim();
            if (trimmed.StartsWith("Install-NodeVcRuntime ", StringComparison.Ordinal))
            {
                placements += 1;
                Assert.Equal("Install-NodeVcRuntime $vcRuntimeSource $nodeDir $Runtime", trimmed);
            }
            if (trimmed == "$vcRuntimeSource = Get-MicrosoftVcRuntime $VcRuntimeCache $Temp") fetches += 1;
        }
        Assert.Equal(2, placements);
        Assert.Equal(placements, fetches);
        Assert.False(recipe.Contains("Install-NodeVcRuntime $pyDir", StringComparison.Ordinal),
            "fetch-runtime.ps1 still places the copy from runtime\\python (the Python zip), which #1010 replaced with Microsoft's redistributable.");
        Assert.True(HasStatement(recipe, "$VcRuntimeCache = Join-Path $VendorDir \"vc-runtime\""),
            "fetch-runtime.ps1's cache of the checked file must be windows-app\\Vendor\\vc-runtime, outside runtime\\ (which the installer packs whole).");
    }

    /// <summary>
    /// The recipe places the copy in the contract's module folders, exactly
    /// those, and records the contract's layout in the manifest (Russell's
    /// ruling of 2026-11-19 on #965).
    /// </summary>
    [Fact]
    public void TheRecipePlacesTheCopyBesideTheContractsModules()
    {
        string recipe = File.ReadAllText(Path.Combine(RepoRoot, "windows-app", "Vendor", "fetch-runtime.ps1"));
        string layout = Entry["layout"]!.ToString();
        Assert.True(HasStatement(recipe, $"$NodeVcRuntimeLayout  = \"{layout}\""), $"fetch-runtime.ps1 does not set $NodeVcRuntimeLayout to the contract's \"{layout}\".");
        Assert.True(HasStatement(recipe, "$fields.nodeVcRuntimeLayout = $NodeVcRuntimeLayout"),
            "fetch-runtime.ps1 never records nodeVcRuntimeLayout in the manifest, so the build's guard cannot tell a runtime with the node.exe copy alone.");
        Assert.Equal("node", Entry["besideNode"]!.ToString());

        Assert.Equal(ModuleFolders, ListedModuleFolders(recipe));
        Assert.True(ModuleFolders.Count >= 2, "windowsNodeVcRuntime -> besideModules names fewer than the two modules that import vcruntime140.dll (lightningcss, the Typst compiler).");

        // The function takes the runtime as a parameter (#1006): it never
        // reads the script's own $Runtime, so it can be lifted and run alone.
        int begin = recipe.IndexOf("# BEGIN Install-NodeVcRuntime", StringComparison.Ordinal);
        int finish = recipe.IndexOf("# END Install-NodeVcRuntime", StringComparison.Ordinal);
        Assert.True(begin >= 0 && finish > begin, "fetch-runtime.ps1 has no Install-NodeVcRuntime between its markers.");
        string function = recipe[begin..finish];
        Assert.Contains("function Install-NodeVcRuntime([string]$From, [string]$To, [string]$RuntimeFolder)", function);
        Assert.False(Regex.IsMatch(function, @"\$Runtime\b"),
            "Install-NodeVcRuntime reads the script-level $Runtime; it should use its $RuntimeFolder parameter.");
    }

    /// <summary>
    /// The quoted folders of the recipe's <c>$NodeVcRuntimeModuleFolders =
    /// @(</c> list, read line by line up to the line that closes it. A
    /// comment line is skipped; any other line that is not one quoted
    /// folder, with or without a trailing comma, fails the test by name
    /// rather than being read as a folder.
    /// </summary>
    private static List<string> ListedModuleFolders(string recipe)
    {
        const string opening = "$NodeVcRuntimeModuleFolders = @(";
        string[] lines = recipe.Replace("\r\n", "\n").Split('\n');
        int first = Array.FindIndex(lines, line => line.Trim() == opening);
        Assert.True(first >= 0, $"fetch-runtime.ps1 has no line reading {opening}");
        var listed = new List<string>();
        var folder = new Regex("^\"([^\"]+)\",?$");
        for (int index = first + 1; index < lines.Length; index++)
        {
            string trimmed = lines[index].Trim();
            if (trimmed == ")") return listed;
            if (trimmed.Length == 0 || trimmed.StartsWith("#", StringComparison.Ordinal)) continue;
            Match match = folder.Match(trimmed);
            Assert.True(match.Success, $"fetch-runtime.ps1 line {index + 1} in $NodeVcRuntimeModuleFolders is not one quoted folder: {trimmed}");
            listed.Add(match.Groups[1].Value);
        }
        Assert.Fail($"fetch-runtime.ps1's {opening} list is never closed by a line reading ).");
        return listed;
    }

    [Fact]
    public void TheBuildRefusesARuntimeWithoutIt()
    {
        string project = File.ReadAllText(Path.Combine(RepoRoot, "windows-app", "Plantoir", "Plantoir.csproj"));
        string version = CarriedFile["fileVersion"]!.ToString();
        Assert.Contains($"<_PlantoirRuntimeVcRuntime>{version}</_PlantoirRuntimeVcRuntime>", project);
        Assert.Contains("$(_PlantoirRuntimeVcRuntimePattern)", project);
        Assert.Contains($"<_PlantoirRuntimeVcRuntimeLayout>{Entry["layout"]}</_PlantoirRuntimeVcRuntimeLayout>", project);
        Assert.Contains("$(_PlantoirRuntimeVcRuntimeLayoutPattern)", project);
    }

    private static bool HasStatement(string script, string statement)
    {
        foreach (string line in script.Split('\n'))
        {
            if (line.TrimStart().TrimEnd('\r').StartsWith(statement, StringComparison.Ordinal)) return true;
        }
        return false;
    }

    // MARK: - The import reader

    /// <summary>
    /// The reader itself, on a file every run has: the test host. Off
    /// Windows the test host is not a Windows program, so it skips (#1006).
    /// </summary>
    [WindowsFact]
    public void TheImportReaderReadsTheTestHostsImports()
    {
        string host = Environment.ProcessPath!;
        var imports = PeImports.Read(host);
        _output.WriteLine($"{host}: {string.Join(", ", imports)}");
        Assert.Contains(imports, name => string.Equals(name, "kernel32.dll", StringComparison.OrdinalIgnoreCase));
    }

    // MARK: - A fetched runtime

    // MARK: - The rule, on a made-up runtime (runs on every PC)

    /// <summary>
    /// The rule itself, without a fetched runtime: a module whose library is
    /// beside node.exe only is reported (Windows reaches node.exe's folder
    /// for a module only through PATH); the same module with the library
    /// beside it is not; a Windows library is never reported.
    /// </summary>
    [Fact]
    public void AModuleWhoseLibraryIsOnlyBesideNodeIsReported()
    {
        string runtime = Path.Combine(Path.GetTempPath(), "plantoir-965-" + Guid.NewGuid().ToString("N"));
        try
        {
            string nodeDir = Path.Combine(runtime, "node");
            string moduleDir = Path.Combine(runtime, "quartz", "node_modules", "made-up-win32-x64-msvc");
            Directory.CreateDirectory(nodeDir);
            Directory.CreateDirectory(moduleDir);
            File.WriteAllText(Path.Combine(nodeDir, "node.exe"), "");
            File.WriteAllText(Path.Combine(nodeDir, "vcruntime140.dll"), "");
            string module = Path.Combine(moduleDir, "made-up.node");
            File.WriteAllText(module, "");
            var imports = new Dictionary<string, string[]>(StringComparer.OrdinalIgnoreCase)
            {
                [Path.Combine(nodeDir, "node.exe")] = new[] { "KERNEL32.dll" },
                [Path.Combine(nodeDir, "vcruntime140.dll")] = new[] { "KERNEL32.dll", "api-ms-win-crt-runtime-l1-1-0.dll" },
                [module] = new[] { "VCRUNTIME140.dll", "KERNEL32.dll", "node.exe" },
                [Path.Combine(moduleDir, "vcruntime140.dll")] = new[] { "KERNEL32.dll", "api-ms-win-crt-runtime-l1-1-0.dll" },
            };
            IReadOnlyList<string> Reader(string file) => imports[file];

            var onlyBesideNode = NativeModuleImports.Unreachable(runtime, Reader, IsSystemLibrary);
            Assert.Single(onlyBesideNode);
            Assert.Contains("made-up.node imports VCRUNTIME140.dll", onlyBesideNode[0]);

            File.WriteAllText(Path.Combine(moduleDir, "vcruntime140.dll"), "");
            Assert.Empty(NativeModuleImports.Unreachable(runtime, Reader, IsSystemLibrary));
        }
        finally
        {
            if (Directory.Exists(runtime)) Directory.Delete(runtime, recursive: true);
        }
    }

    // MARK: - A fetched runtime

    /// <summary>
    /// Every <c>.node</c> file in the runtime, and every library beside it
    /// that it pulls in, finds each import beside itself or on Windows' own
    /// list. Fails on a runtime made before #965, or with the node.exe copy
    /// alone, on ANY PC, the development PC included.
    /// </summary>
    [NativeRuntimeFact]
    public void EveryNativeModuleFindsEachLibraryItImports()
    {
        string runtime = NativeRuntime.Folder!;
        Assert.True(File.Exists(Path.Combine(runtime, "node", "node.exe")), $"{runtime} has no node\\node.exe.");
        Assert.True(Directory.GetFiles(runtime, "*.node", SearchOption.AllDirectories).Length > 0,
            $"{runtime} holds no .node file at all, which is not a runtime fetch-runtime.ps1 makes.");
        var problems = NativeModuleImports.Unreachable(runtime, file =>
        {
            var imports = PeImports.Read(file);
            _output.WriteLine($"{Path.GetRelativePath(runtime, file)}: {string.Join(", ", imports)}");
            return imports;
        }, IsSystemLibrary);
        Assert.True(problems.Count == 0,
            "A clean Windows could not load these (#965). Re-run windows-app\\Vendor\\fetch-runtime.ps1, or carry the library beside the module (contracts/toolchain.json -> windowsNodeVcRuntime -> besideModules):\n" + string.Join("\n", problems));
    }

    /// <summary>
    /// Each folder in <c>besideModules</c> holds a <c>.node</c> file that
    /// imports the carried library: the list names no folder the copy is
    /// not needed in.
    /// </summary>
    [NativeRuntimeFact]
    public void EachListedModuleFolderHoldsAModuleThatImportsTheCopy()
    {
        string runtime = NativeRuntime.Folder!;
        string name = CarriedFile["name"]!.ToString();
        foreach (string relative in ModuleFolders)
        {
            string folder = Path.Combine(runtime, relative);
            Assert.True(Directory.Exists(folder), $"{folder} does not exist: windowsNodeVcRuntime -> besideModules names a module the runtime no longer has.");
            bool imported = false;
            foreach (string module in Directory.GetFiles(folder, "*.node"))
            {
                foreach (string import in PeImports.Read(module))
                    if (string.Equals(import, name, StringComparison.OrdinalIgnoreCase)) imported = true;
            }
            Assert.True(imported, $"No .node file in {folder} imports {name}: besideModules should not carry it there.");
        }
    }

    /// <summary>
    /// The copy beside node.exe and the copy beside each listed module are
    /// the contract's file, byte for byte, and the manifest records the
    /// version and the layout.
    /// </summary>
    [NativeRuntimeFact]
    public void EveryCopyIsTheContractsFile()
    {
        string runtime = NativeRuntime.Folder!;
        string name = CarriedFile["name"]!.ToString();
        var places = new List<string> { Entry["besideNode"]!.ToString() };
        places.AddRange(ModuleFolders);
        foreach (string place in places)
        {
            string copy = Path.Combine(runtime, place, name);
            Assert.True(File.Exists(copy), $"{Path.Combine(runtime, place)} has no {name}: re-run windows-app\\Vendor\\fetch-runtime.ps1 (#965).");
            string sha = Convert.ToHexString(SHA256.HashData(File.ReadAllBytes(copy))).ToLowerInvariant();
            Assert.True(CarriedFile["sha256"]!.ToString() == sha, $"{copy} has SHA-256 {sha}, not the contract's.");
        }
        string manifest = File.ReadAllText(Path.Combine(runtime, "manifest.json"));
        var parsed = JsonNode.Parse(manifest)!;
        Assert.Equal(CarriedFile["fileVersion"]!.ToString(), parsed["nodeVcRuntime"]?.ToString());
        Assert.Equal(Entry["layout"]!.ToString(), parsed["nodeVcRuntimeLayout"]?.ToString());
    }
}

/// <summary>
/// A fact that needs Windows itself, here a Windows program to read: it
/// skips, saying so, anywhere else (#1006), as the suite's other
/// platform-bound facts do.
/// </summary>
public sealed class WindowsFactAttribute : FactAttribute
{
    public WindowsFactAttribute()
    {
        if (!OperatingSystem.IsWindows())
            Skip = "Needs Windows: the test host here is not a Windows program, so it has no import table to read.";
    }
}

/// <summary>
/// #965's rule, kept apart from the file reading so it can be tested on a
/// made-up runtime: every <c>.node</c> file under <paramref name="runtime"/>
/// (and <c>node\node.exe</c>), and every library beside it that it pulls in,
/// must find each library it imports in its OWN folder (where Windows looks
/// first when Node loads a module with <c>LOAD_WITH_ALTERED_SEARCH_PATH</c>,
/// and the application folder for node.exe itself) or among Windows' own.
/// Returns one sentence per import that would not be found.
/// </summary>
internal static class NativeModuleImports
{
    public static List<string> Unreachable(string runtime, Func<string, IReadOnlyList<string>> readImports, Func<string, bool> isSystemLibrary)
    {
        string nodeExe = Path.Combine(runtime, "node", "node.exe");
        var problems = new List<string>();
        var checkedFiles = new HashSet<string>(StringComparer.OrdinalIgnoreCase);
        var pending = new Queue<string>(Directory.GetFiles(runtime, "*.node", SearchOption.AllDirectories).Append(nodeExe));
        while (pending.Count > 0)
        {
            string file = pending.Dequeue();
            if (!checkedFiles.Add(file)) continue;
            string folder = Path.GetDirectoryName(file)!;
            foreach (string name in readImports(file))
            {
                if (string.Equals(name, "node.exe", StringComparison.OrdinalIgnoreCase)) continue;
                string beside = Path.Combine(folder, name);
                if (File.Exists(beside)) { pending.Enqueue(beside); continue; }
                if (isSystemLibrary(name)) continue;
                problems.Add($"{Path.GetRelativePath(runtime, file)} imports {name}, which is not beside it and not one of Windows' own libraries (contracts/toolchain.json -> windowsNodeVcRuntime -> windowsSystemLibraries); a copy beside node.exe is reached only through PATH");
            }
        }
        return problems;
    }
}

/// <summary>
/// The names of the libraries a Windows program or library imports, read
/// from its PE import table and its delay-load import table (a delay-loaded
/// library missing at run time fails the first call into it, so it counts).
/// </summary>
internal static class PeImports
{
    public static IReadOnlyList<string> Read(string path)
    {
        byte[] data = File.ReadAllBytes(path);
        if (data.Length < 0x40 || data[0] != (byte)'M' || data[1] != (byte)'Z')
            throw new InvalidDataException($"{path} is not a Windows program or library (no MZ header).");
        int pe = BitConverter.ToInt32(data, 0x3c);
        if (Encoding.ASCII.GetString(data, pe, 4) != "PE\0\0")
            throw new InvalidDataException($"{path} has no PE header.");
        int sectionCount = BitConverter.ToUInt16(data, pe + 6);
        int optionalSize = BitConverter.ToUInt16(data, pe + 20);
        int optional = pe + 24;
        ushort magic = BitConverter.ToUInt16(data, optional);
        int directories = optional + (magic == 0x20b ? 112 : 96);
        var sections = new List<(uint Va, uint Size, uint Raw)>();
        int sectionTable = optional + optionalSize;
        for (int i = 0; i < sectionCount; i++)
        {
            int s = sectionTable + i * 40;
            uint virtualSize = BitConverter.ToUInt32(data, s + 8);
            uint va = BitConverter.ToUInt32(data, s + 12);
            uint rawSize = BitConverter.ToUInt32(data, s + 16);
            uint raw = BitConverter.ToUInt32(data, s + 20);
            sections.Add((va, Math.Max(virtualSize, rawSize), raw));
        }
        int Offset(uint rva)
        {
            foreach (var section in sections)
                if (rva >= section.Va && rva < section.Va + section.Size) return (int)(rva - section.Va + section.Raw);
            throw new InvalidDataException($"{path}: address {rva:x} is in no section.");
        }
        string Text(int offset)
        {
            int end = Array.IndexOf(data, (byte)0, offset);
            return Encoding.ASCII.GetString(data, offset, end - offset);
        }
        var names = new List<string>();
        // Directory 1 is the import table (20-byte entries, name at 12);
        // directory 13 the delay-load table (32-byte entries, name at 4).
        foreach (var (index, size, nameAt) in new[] { (1, 20, 12), (13, 32, 4) })
        {
            uint rva = BitConverter.ToUInt32(data, directories + index * 8);
            if (rva == 0) continue;
            int entry = Offset(rva);
            while (true)
            {
                uint nameRva = BitConverter.ToUInt32(data, entry + nameAt);
                if (nameRva == 0) break;
                names.Add(Text(Offset(nameRva)));
                entry += size;
            }
        }
        return names;
    }
}
