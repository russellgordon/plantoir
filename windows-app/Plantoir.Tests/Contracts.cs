using System.IO;
using System.Text.Json;
using System.Text.Json.Nodes;

namespace Plantoir.Tests;

public static class ContractLoader
{
    /// <summary>
    /// The repository root, found by walking up from the test binary until the
    /// Dockerfile appears.
    /// </summary>
    /// <remarks>
    /// <para>Anchored on the Dockerfile because it is at the root, is not
    /// generated, and is not a folder name that could appear again on the way
    /// up. Walking rather than counting <c>..</c> segments, because the depth
    /// differs between a plain <c>dotnet test</c> and an x64 build.</para>
    ///
    /// <para><b>Three test files already have a private copy of this</b> —
    /// <c>AssistSurfaceContractTests</c>, <c>ExampleContentContractTests</c>
    /// and <c>FileFormatContractTests</c>. This is here so a fourth was not
    /// written; migrating those three is a tidy-up rather than part of any
    /// change that has needed it so far.</para>
    /// </remarks>
    public static string RepositoryRoot
    {
        get
        {
            var dir = new DirectoryInfo(AppContext.BaseDirectory);
            for (int i = 0; i < 8 && dir is not null; i++, dir = dir.Parent)
            {
                if (File.Exists(Path.Combine(dir.FullName, "Dockerfile")))
                    return dir.FullName;
            }
            throw new DirectoryNotFoundException("Could not find repository root containing Dockerfile.");
        }
    }

    public static string GetContractPath(string fileName)
    {
        string local = Path.Combine(AppContext.BaseDirectory, "contracts", fileName);
        if (File.Exists(local)) return local;

        string parentLocal = Path.Combine(AppContext.BaseDirectory, fileName);
        if (File.Exists(parentLocal)) return parentLocal;

        // Fallback relative to repository root if running in different test runners
        string repoPath = Path.GetFullPath(Path.Combine(AppContext.BaseDirectory, "..", "..", "..", "..", "contracts", fileName));
        if (File.Exists(repoPath)) return repoPath;

        throw new FileNotFoundException($"Could not find contract file: {fileName}");
    }

    public static string GetSupportPath(string fileName)
    {
        string local = Path.Combine(AppContext.BaseDirectory, "support", fileName);
        if (File.Exists(local)) return local;

        string parentLocal = Path.Combine(AppContext.BaseDirectory, fileName);
        if (File.Exists(parentLocal)) return parentLocal;

        string repoPath = Path.GetFullPath(Path.Combine(AppContext.BaseDirectory, "..", "..", "..", "..", "..", "support", fileName));
        if (File.Exists(repoPath)) return repoPath;

        throw new FileNotFoundException($"Could not find support file: {fileName}");
    }

    public static JsonNode LoadJson(string fileName)
    {
        string path = GetContractPath(fileName);
        string content = File.ReadAllText(path);
        return JsonNode.Parse(content) ?? throw new InvalidOperationException($"Failed to parse {fileName}");
    }

    public static JsonDocument LoadDocument(string fileName)
    {
        string path = GetContractPath(fileName);
        string content = File.ReadAllText(path);
        return JsonDocument.Parse(content);
    }
}
