using Microsoft.Extensions.DependencyInjection;
using Microsoft.Extensions.Hosting;
using Microsoft.Extensions.Logging;
using ModelContextProtocol.Protocol;
using Plantoir.Core.Assist;
using Plantoir.Mcp;

// plantoir-mcp — an MCP server over one Plantoir working folder.
//
//   plantoir-mcp --folder "C:\Users\me\Documents\Teaching"
//
// The folder is fixed at startup and never changes afterwards. A server that
// could be pointed anywhere mid-session would make every path check meaningless.

string? folder = null;
string? course = null;
for (int i = 0; i < args.Length; i++)
{
    if ((args[i] == "--folder" || args[i] == "-f") && i + 1 < args.Length) folder = args[++i];
    else if (args[i].StartsWith("--folder=", StringComparison.Ordinal)) folder = args[i]["--folder=".Length..];
    else if ((args[i] == "--course" || args[i] == "-c") && i + 1 < args.Length) course = args[++i];
    // outsideAgents.serverArguments: `--mcp-stdio <folder>`, the shape the
    // contract gives every door, and the one the Codex door passes (#210).
    else if (args[i] == "--mcp-stdio" && i + 1 < args.Length) folder = args[++i];
    else if (args[i].StartsWith("--course=", StringComparison.Ordinal)) course = args[i]["--course=".Length..];
}

folder ??= Environment.GetEnvironmentVariable("PLANTOIR_FOLDER");
course ??= Environment.GetEnvironmentVariable("PLANTOIR_COURSE");

if (string.IsNullOrWhiteSpace(folder))
{
    // stderr, not stdout: stdout belongs to the protocol.
    await Console.Error.WriteLineAsync(
        "plantoir-mcp needs the working folder to serve.\n\n" +
        "  plantoir-mcp --folder \"<path to your Plantoir working folder>\"\n\n" +
        "That is the folder holding your courses — the one Plantoir opens.");
    return 2;
}

AssistWorkspace workspace;
try
{
    // --course locks the session to one course. Plantoir passes it when a
    // teacher starts an assistant from that course's menu: the request was
    // about that course, so a lock is a stronger guarantee than an
    // instruction in a prompt the model might drift from.
    // The undo history lives for the life of this process, which is the life
    // of the teacher's conversation — so "undo that" works for as long as they
    // are talking, and nothing accumulates on disk afterwards.
    workspace = new AssistWorkspace(folder, new LauncherRunner(), course, new UndoHistory())
    {
        ServesTheLocalWindow = Environment.GetEnvironmentVariable(AssistWorkspace.LocalWindowVariable) == "1",
    };
}
catch (Exception error)
{
    await Console.Error.WriteLineAsync(error.Message);
    return 2;
}

// Tell the app this course is being worked on, so Preview, Publish and Add
// Section decline while the session is open — otherwise both would build into
// the same output folder. Only when locked to a course: an unrestricted
// session has no single course to claim.
IDisposable? lease = workspace.LockedCourse is { } locked
    ? Plantoir.Core.Assist.WorkLease.Take(workspace.FolderPath, locked,
        Plantoir.Core.Assist.WorkLease.Assisting)
    : null;
// Its own work stops BEFORE any lease goes (#289): a build this server started
// must not keep writing the section's folder after the course reads as free.
AppDomain.CurrentDomain.ProcessExit += (_, _) =>
{
    LauncherRunner.StopEverythingItStarted();
    lease?.Dispose();
};

var builder = Host.CreateApplicationBuilder();

// Every log line goes to stderr. stdout carries JSON-RPC frames and nothing
// else; one stray line on it corrupts the session for the whole client.
builder.Logging.AddConsole(options => options.LogToStandardErrorThreshold = LogLevel.Trace);

builder.Services.AddSingleton(workspace);
builder.Services.AddMcpServer(options =>
        options.ServerInfo = new Implementation { Name = "plantoir", Version = "0.1.0" })
    .WithStdioServerTransport()
    .WithToolsFromAssembly();

try { await builder.Build().RunAsync(); }
finally
{
    LauncherRunner.StopEverythingItStarted();
    lease?.Dispose();
}
return 0;
