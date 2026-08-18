using System;
using System.IO;
using System.Text.Json.Nodes;
using Plantoir.Core.Assist;
using Xunit;

namespace Plantoir.Tests;

public class ClaudeCodeLauncherTests
{
    [Fact]
    public void GreetingWithDistinctCourseName()
    {
        string text = ClaudeCodeLauncher.Greeting("ICS3U", "Grade 11 Computer Science");
        Assert.Contains("I'm a teacher working on ICS3U (Grade 11 Computer Science) in Plantoir.", text);
        Assert.Contains("Use the plantoir tools for anything to do with this course.", text);
        Assert.Contains("Start by listing its sections so we both know what's there.", text);
        Assert.Contains("Before changing anything, use the matching plan tool first and show me what it says, in plain words, and wait for me to agree.", text);
        Assert.DoesNotContain("\"", text);
    }

    [Fact]
    public void GreetingWithIdenticalCourseName()
    {
        string text = ClaudeCodeLauncher.Greeting("ICS3U", "ICS3U");
        Assert.Contains("I'm a teacher working on ICS3U in Plantoir.", text);
        Assert.DoesNotContain("ICS3U (ICS3U)", text);
    }

    [Fact]
    public void GreetingWithEmptyCourseName()
    {
        string text = ClaudeCodeLauncher.Greeting("ICS3U", "   ");
        Assert.Contains("I'm a teacher working on ICS3U in Plantoir.", text);
        Assert.DoesNotContain("(", text);
    }

    [Fact]
    public void WriteConfigCreatesValidJsonStructure()
    {
        string tempWorkspace = @"C:\Users\teacher\Teaching";
        string courseCode = "ICS3U_TEST";
        string dummyServer = @"C:\Program Files\Plantoir\plantoir-mcp.exe";

        string configPath = ClaudeCodeLauncher.WriteConfig(tempWorkspace, courseCode, dummyServer);
        try
        {
            Assert.True(File.Exists(configPath));
            string json = File.ReadAllText(configPath);
            var parsed = JsonNode.Parse(json);
            Assert.NotNull(parsed);

            var servers = parsed["mcpServers"];
            Assert.NotNull(servers);

            var plantoir = servers["plantoir"];
            Assert.NotNull(plantoir);
            Assert.Equal(dummyServer, plantoir["command"]?.ToString());

            var args = plantoir["args"]?.AsArray();
            Assert.NotNull(args);
            Assert.Contains(args, a => a?.ToString() == "--folder");
            Assert.Contains(args, a => a?.ToString() == tempWorkspace);
            Assert.Contains(args, a => a?.ToString() == "--course");
            Assert.Contains(args, a => a?.ToString() == courseCode);
        }
        finally
        {
            try { File.Delete(configPath); } catch { }
        }
    }
}
