using System;
using System.Collections.Generic;
using System.IO;
using Xunit;

namespace Plantoir.Tests;

/// <summary>
/// #964. On a Python without python-frontmatter the oracle's process pool
/// recreated its workers for ever (each died importing <c>frontmatter</c> in
/// its initializer), so <c>CopyAPageFuzzTests</c> hung the suite for half an
/// hour instead of failing. This test makes that Python on demand, without
/// uninstalling anything: a folder on <c>PYTHONPATH</c> whose
/// <c>sitecustomize.py</c> refuses the import, in the parent and in every
/// worker alike. The oracle must then end by itself and name the package.
/// </summary>
public class BuildFrontmatterOracleTests : IDisposable
{
    private readonly string _refusal = RunOwnedTempFolders.Create("plantoir-964-refuse-");

    public void Dispose()
    {
        try { Directory.Delete(_refusal, recursive: true); } catch { }
    }

    [Fact]
    public void APythonWithoutFrontmatterFailsByItselfNamingThePackage()
    {
        File.WriteAllText(Path.Combine(_refusal, "sitecustomize.py"), string.Join("\n",
            "import sys",
            "class RefuseFrontmatter:",
            "    def find_spec(self, name, path=None, target=None):",
            "        if name == 'frontmatter' or name.startswith('frontmatter.'):",
            "            raise ModuleNotFoundError(\"No module named 'frontmatter'\", name='frontmatter')",
            "        return None",
            "sys.meta_path.insert(0, RefuseFrontmatter())",
            ""));
        var environment = new Dictionary<string, string> { ["PYTHONPATH"] = _refusal };
        var pages = new List<string> { "---\ntitle: One\n---\nBody\n" };

        // The bound only turns the old hang into a failure; a fixed oracle exits in seconds.
        var refused = Assert.Throws<InvalidOperationException>(() =>
            BuildFrontmatterOracle.Ask(pages, environment, hangBound: TimeSpan.FromMinutes(5)));

        Assert.Contains("No module named 'frontmatter'", refused.Message);
        Assert.Contains("python-frontmatter", refused.Message);
    }
}
