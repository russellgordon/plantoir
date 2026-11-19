using System.Security.Cryptography;
using System.Text;
using System.Text.Json.Nodes;
using Xunit;
using Xunit.Abstractions;

namespace Plantoir.Tests;

/// <summary>
/// #965: on a clean Windows (no Visual C++ redistributable) the runtime's
/// native Node modules must still load. Two of them, lightningcss and the
/// Typst compiler, import <c>VCRUNTIME140.dll</c>, and the first preview on
/// a clean machine stopped with <c>ERR_DLOPEN_FAILED</c>, because the only
/// copy was in <c>runtime\python</c>, which is not on PATH. The runtime now
/// carries that file beside <c>runtime\node\node.exe</c>, copied by
/// <c>fetch-runtime.ps1</c> from the Python zip it already pins.
/// <c>contracts/toolchain.json</c> → <c>windowsNodeVcRuntime</c> holds the
/// file, its hash, the list of Windows' own libraries and the reasons;
/// <c>documentation/12-windows-app.md</c> → "The Visual C++ runtime beside
/// node.exe".
/// </summary>
/// <remarks>
/// Loading each module with a PATH that holds no copy is not a test the
/// development PC can run (its System32 has the redistributable), so the
/// honest form, as the issue says, is a check on the runtime's FILES: every
/// library each <c>.node</c> imports must sit beside it, beside
/// <c>node.exe</c>, or be on the contract's named list of libraries every
/// Windows carries. That fails on a PC that has the redistributable just as
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
        Assert.True(HasStatement(recipe, "Install-NodeVcRuntime $pyDir $nodeDir"),
            "fetch-runtime.ps1 never runs Install-NodeVcRuntime $pyDir $nodeDir: the runtime would carry no Visual C++ runtime beside node.exe (#965).");
        Assert.True(HasStatement(recipe, "$fields.nodeVcRuntime = $NodeVcRuntimeVersion"),
            "fetch-runtime.ps1 never records nodeVcRuntime in the manifest, so the build's guard cannot see it.");
    }

    [Fact]
    public void TheBuildRefusesARuntimeWithoutIt()
    {
        string project = File.ReadAllText(Path.Combine(RepoRoot, "windows-app", "Plantoir", "Plantoir.csproj"));
        string version = CarriedFile["fileVersion"]!.ToString();
        Assert.Contains($"<_PlantoirRuntimeVcRuntime>{version}</_PlantoirRuntimeVcRuntime>", project);
        Assert.Contains("$(_PlantoirRuntimeVcRuntimePattern)", project);
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

    /// <summary>The reader itself, on a file every run has: the test host.</summary>
    [Fact]
    public void TheImportReaderReadsTheTestHostsImports()
    {
        string host = Environment.ProcessPath!;
        var imports = PeImports.Read(host);
        _output.WriteLine($"{host}: {string.Join(", ", imports)}");
        Assert.Contains(imports, name => string.Equals(name, "kernel32.dll", StringComparison.OrdinalIgnoreCase));
    }

    // MARK: - A fetched runtime

    /// <summary>
    /// Every <c>.node</c> file in the runtime, and every library beside it
    /// that it pulls in, finds each import beside itself, beside
    /// <c>node.exe</c>, or on Windows' own list. Fails on a runtime made
    /// before #965 on ANY PC, the development PC included.
    /// </summary>
    [NativeRuntimeFact]
    public void EveryNativeModuleFindsEachLibraryItImports()
    {
        string runtime = NativeRuntime.Folder!;
        string nodeDir = Path.Combine(runtime, "node");
        Assert.True(File.Exists(Path.Combine(nodeDir, "node.exe")), $"{runtime} has no node\\node.exe.");

        var modules = Directory.GetFiles(runtime, "*.node", SearchOption.AllDirectories);
        Assert.True(modules.Length > 0, $"{runtime} holds no .node file at all, which is not a runtime fetch-runtime.ps1 makes.");

        var problems = new List<string>();
        var checkedFiles = new HashSet<string>(StringComparer.OrdinalIgnoreCase);
        var pending = new Queue<string>(modules.Append(Path.Combine(nodeDir, "node.exe")));
        while (pending.Count > 0)
        {
            string file = pending.Dequeue();
            if (!checkedFiles.Add(file)) continue;
            string folder = Path.GetDirectoryName(file)!;
            var imports = PeImports.Read(file);
            _output.WriteLine($"{Path.GetRelativePath(runtime, file)}: {string.Join(", ", imports)}");
            foreach (string name in imports)
            {
                if (string.Equals(name, "node.exe", StringComparison.OrdinalIgnoreCase)) continue;
                string beside = Path.Combine(folder, name);
                if (File.Exists(beside)) { pending.Enqueue(beside); continue; }
                string besideNode = Path.Combine(nodeDir, name);
                if (File.Exists(besideNode)) { pending.Enqueue(besideNode); continue; }
                if (IsSystemLibrary(name)) continue;
                problems.Add($"{Path.GetRelativePath(runtime, file)} imports {name}, which is not beside it, not beside node.exe, and not one of Windows' own libraries (contracts/toolchain.json -> windowsNodeVcRuntime -> windowsSystemLibraries)");
            }
        }
        Assert.True(problems.Count == 0,
            "A clean Windows could not load these (#965). Re-run windows-app\\Vendor\\fetch-runtime.ps1, or carry the library:\n" + string.Join("\n", problems));
    }

    /// <summary>The copy beside node.exe is the contract's file, byte for byte.</summary>
    [NativeRuntimeFact]
    public void TheCopyBesideNodeIsTheContractsFile()
    {
        string runtime = NativeRuntime.Folder!;
        string name = CarriedFile["name"]!.ToString();
        string copy = Path.Combine(runtime, "node", name);
        Assert.True(File.Exists(copy), $"{runtime}\\node has no {name}: re-run windows-app\\Vendor\\fetch-runtime.ps1 (#965).");
        string sha = Convert.ToHexString(SHA256.HashData(File.ReadAllBytes(copy))).ToLowerInvariant();
        Assert.Equal(CarriedFile["sha256"]!.ToString(), sha);
        string manifest = File.ReadAllText(Path.Combine(runtime, "manifest.json"));
        var parsed = JsonNode.Parse(manifest)!;
        Assert.Equal(CarriedFile["fileVersion"]!.ToString(), parsed["nodeVcRuntime"]?.ToString());
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
