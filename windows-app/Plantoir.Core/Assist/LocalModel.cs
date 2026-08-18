using System;
using System.Collections.Generic;
using System.Diagnostics;
using System.IO;
using System.Net.Http;
using System.Net.Sockets;
using System.Text;
using System.Text.Json.Nodes;
using System.Threading;
using System.Threading.Tasks;

namespace Plantoir.Core.Assist;

/// <summary>
/// The assistant that runs natively on the teacher's own computer.
///
/// Running natively on the Windows host out of WSL2 allows hardware-accelerated
/// inference via Vulkan (Intel UHD/Iris/Arc, AMD Radeon, NVIDIA) or CPU fallback,
/// collapsing prompt ingestion and generation latency from minutes to seconds.
///
/// * **Qwen2.5-1.5B-Instruct, Q4_K_M.** 1,117,320,736 bytes (~1.04 GiB).
/// * **Vulkan GPU Acceleration.** Offloads layers to the host GPU (--n-gpu-layers 999).
/// * **Thinking turned off.** Passes both --reasoning off and --reasoning-budget 0.
///
/// Nothing ships inside the app bundle. The model is fetched once, on a teacher's
/// explicit yes, and the host process only runs while a conversation window is open.
/// </summary>
public sealed class LocalModel : IChatModel, IDisposable
{
    public AssistModelTier Tier { get; }

    public string ModelFileName => Tier.FileName();

    public const string LegacyModelFileName = "Qwen2.5-1.5B-Instruct-Q4_K_M.gguf";

    public long ExpectedDownloadBytes => Tier.DownloadBytes();

    public string ModelUrl => Tier.DownloadUrl();

    public int ContextSize => Tier == AssistModelTier.Large ? 16384 : 8192;

    public LocalModel(AssistModelTier? tier = null)
    {
        Tier = tier ?? DetermineDefaultTier();
    }

    public static AssistModelTier DetermineDefaultTier()
    {
        var choice = Plantoir.Core.Models.AppSettings.Current.AssistantModelChoice;
        if (string.Equals(choice, "small", StringComparison.OrdinalIgnoreCase) ||
            string.Equals(choice, "smaller", StringComparison.OrdinalIgnoreCase))
            return AssistModelTier.Small;
        if (string.Equals(choice, "large", StringComparison.OrdinalIgnoreCase) ||
            string.Equals(choice, "larger", StringComparison.OrdinalIgnoreCase))
            return AssistModelTier.Large;

        // If automatic, prefer any model that is already fully installed on disk
        string smallPath = Path.Combine(ModelDirectory, AssistModelTier.Small.FileName());
        string legacyPath = Path.Combine(ModelDirectory, LegacyModelFileName);
        string largePath = Path.Combine(ModelDirectory, AssistModelTier.Large.FileName());

        if (File.Exists(largePath) && new FileInfo(largePath).Length == AssistModelTier.Large.DownloadBytes())
            return AssistModelTier.Large;
        if ((File.Exists(smallPath) && new FileInfo(smallPath).Length == AssistModelTier.Small.DownloadBytes()) ||
            (File.Exists(legacyPath) && new FileInfo(legacyPath).Length == AssistModelTier.Small.DownloadBytes()))
            return AssistModelTier.Small;

        return new AssistHardwareBudget().Tier;
    }

    private static readonly HttpClient Http = new() { Timeout = TimeSpan.FromMinutes(2) };

    /// <summary>Directory override for test isolation.</summary>
    public static string? ModelDirectoryOverride { get; set; }

    /// <summary>Where model weights live on the host.</summary>
    public static string ModelDirectory =>
        ModelDirectoryOverride ??
        Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.LocalApplicationData), "Plantoir", "models");

    /// <summary>The port llama-server answers on.</summary>
    public int Port { get; private set; } = 8099;

    public string Endpoint => $"http://127.0.0.1:{Port}/v1/chat/completions";

    private Process? _serverProcess;

    /// <summary>Find the model path on disk, supporting current and legacy naming.</summary>
    public static string GetModelPath(AssistModelTier? tier = null)
    {
        var effectiveTier = tier ?? DetermineDefaultTier();
        string primary = Path.Combine(ModelDirectory, effectiveTier.FileName());
        if (File.Exists(primary)) return primary;

        if (effectiveTier == AssistModelTier.Small)
        {
            string legacy = Path.Combine(ModelDirectory, LegacyModelFileName);
            if (File.Exists(legacy)) return legacy;
        }

        return primary;
    }

    /// <summary>True when the model file has already been fetched and matches expected size.</summary>
    public bool IsInstalled()
    {
        string path = GetModelPath(Tier);
        if (!File.Exists(path)) return false;
        try
        {
            return new FileInfo(path).Length == ExpectedDownloadBytes;
        }
        catch
        {
            return false;
        }
    }

    /// <summary>True when the server process is alive and responding.</summary>
    public bool IsRunning()
    {
        return _serverProcess is { HasExited: false };
    }

    /// <summary>
    /// How far the one-time download has got. <see cref="Total"/> is 0 when the
    /// server would not say how big the file is.
    /// </summary>
    public readonly record struct Fetching(long Bytes, long Total)
    {
        public bool Known => Total > 0;

        /// <summary>Clamped, because a resumed or over-long response must not read as 103%.</summary>
        public double Percent => Known ? Math.Min(100, 100.0 * Bytes / Total) : 0;

        public string Describe() => Known
            ? $"Downloading the assistant — {Mb(Bytes)} of {Mb(Total)} ({Percent:0}%)."
            : $"Downloading the assistant — {Mb(Bytes)} so far.";

        private static string Mb(long bytes) => $"{bytes / 1024.0 / 1024.0:0} MB";
    }

    /// <summary>
    /// Locate the native llama-server executable.
    /// </summary>
    public static string? FindServer()
    {
        string? beside = Path.GetDirectoryName(Environment.ProcessPath);
        if (beside is not null)
        {
            string inSubdir = Path.Combine(beside, "llama", "llama-server.exe");
            if (File.Exists(inSubdir)) return inSubdir;

            string directBeside = Path.Combine(beside, "llama-server.exe");
            if (File.Exists(directBeside)) return directBeside;

            // Walk up looking for Vendor\llama\llama-server.exe for dev/debug runs
            var directory = new DirectoryInfo(beside);
            for (int up = 0; up < 8 && directory is not null; up++, directory = directory.Parent)
            {
                string devPath = Path.Combine(directory.FullName, "Vendor", "llama", "llama-server.exe");
                if (File.Exists(devPath)) return devPath;

                string devSubPath = Path.Combine(directory.FullName, "windows-app", "Vendor", "llama", "llama-server.exe");
                if (File.Exists(devSubPath)) return devSubPath;
            }
        }

        string paths = Environment.GetEnvironmentVariable("PATH") ?? "";
        foreach (string dir in paths.Split(Path.PathSeparator, StringSplitOptions.RemoveEmptyEntries))
        {
            try
            {
                string candidate = Path.Combine(dir.Trim(), "llama-server.exe");
                if (File.Exists(candidate)) return candidate;
            }
            catch { }
        }

        return null;
    }

    /// <summary>
    /// Builds arguments passed to llama-server.exe.
    /// </summary>
    public static List<string> BuildArguments(string modelPath, int port, int threads, int ctxSize = 8192, bool useGpu = true)
    {
        var args = new List<string>
        {
            "--model", modelPath,
            "--port", port.ToString(),
            "--host", "127.0.0.1",
            "--ctx-size", ctxSize.ToString(),
            "--threads", threads.ToString(),
            "--reasoning", "off",
            "--reasoning-budget", "0",
            "--jinja",
            "--parallel", "1"
        };
        if (useGpu)
        {
            args.Add("--n-gpu-layers");
            args.Add("999");
        }
        else
        {
            args.Add("--device");
            args.Add("none");
        }
        return args;
    }

    /// <summary>
    /// Fetch the model directly onto the host with streaming progress and exact byte validation.
    /// </summary>
    public async Task<bool> Install(IProgress<Fetching>? progress, CancellationToken cancellation)
    {
        if (IsInstalled()) return true;

        Directory.CreateDirectory(ModelDirectory);
        string finalPath = Path.Combine(ModelDirectory, ModelFileName);
        string partPath = finalPath + ".part";

        if (File.Exists(partPath))
        {
            try { File.Delete(partPath); } catch { }
        }

        try
        {
            using var response = await Http.GetAsync(ModelUrl, HttpCompletionOption.ResponseHeadersRead, cancellation).ConfigureAwait(false);
            response.EnsureSuccessStatusCode();

            long total = response.Content.Headers.ContentLength ?? ExpectedDownloadBytes;
            progress?.Report(new Fetching(0, total));

            await using (var remoteStream = await response.Content.ReadAsStreamAsync(cancellation).ConfigureAwait(false))
            await using (var fileStream = new FileStream(partPath, FileMode.Create, FileAccess.Write, FileShare.None, 65536, useAsync: true))
            {
                byte[] buffer = new byte[65536];
                long totalRead = 0;
                int bytesRead;
                DateTime lastReport = DateTime.UtcNow;

                while ((bytesRead = await remoteStream.ReadAsync(buffer.AsMemory(0, buffer.Length), cancellation).ConfigureAwait(false)) > 0)
                {
                    await fileStream.WriteAsync(buffer.AsMemory(0, bytesRead), cancellation).ConfigureAwait(false);
                    totalRead += bytesRead;

                    if ((DateTime.UtcNow - lastReport).TotalMilliseconds >= 250)
                    {
                        lastReport = DateTime.UtcNow;
                        progress?.Report(new Fetching(totalRead, total));
                    }
                }

                progress?.Report(new Fetching(totalRead, total));
            }

            var info = new FileInfo(partPath);
            if (info.Length != ExpectedDownloadBytes)
            {
                try { File.Delete(partPath); } catch { }
                return false;
            }

            if (File.Exists(finalPath))
            {
                try { File.Delete(finalPath); } catch { }
            }

            File.Move(partPath, finalPath);
            return IsInstalled();
        }
        catch
        {
            if (File.Exists(partPath))
            {
                try { File.Delete(partPath); } catch { }
            }
            return false;
        }
    }

    /// <summary>
    /// Start the native llama-server process on the host and wait for health endpoint.
    /// </summary>
    public async Task<bool> Start(IProgress<string>? progress, CancellationToken cancellation)
    {
        progress?.Report("Starting the assistant…");

        if (IsRunning())
        {
            if (await CheckHealthAsync(cancellation).ConfigureAwait(false))
                return true;
            Stop();
        }

        string? serverExe = FindServer();
        if (serverExe is null)
        {
            return false;
        }

        string modelPath = GetModelPath(Tier);
        if (!IsInstalled())
        {
            return false;
        }

        Port = GetFreePort();
        int threads = Math.Max(2, Environment.ProcessorCount / 2);

        // Try GPU offloading first; fall back to multi-threaded CPU if GPU initialization fails (e.g. Vulkan OutOfDeviceMemory on Intel integrated GPUs)
        bool started = await TryStartServerProcessAsync(serverExe, modelPath, threads, useGpu: true, cancellation).ConfigureAwait(false);
        if (!started && !cancellation.IsCancellationRequested)
        {
            started = await TryStartServerProcessAsync(serverExe, modelPath, threads, useGpu: false, cancellation).ConfigureAwait(false);
        }

        return started;
    }

    private async Task<bool> TryStartServerProcessAsync(string serverExe, string modelPath, int threads, bool useGpu, CancellationToken cancellation)
    {
        Stop();
        var args = BuildArguments(modelPath, Port, threads, ctxSize: ContextSize, useGpu: useGpu);

        var startInfo = new ProcessStartInfo
        {
            FileName = serverExe,
            CreateNoWindow = true,
            UseShellExecute = false,
            RedirectStandardOutput = true,
            RedirectStandardError = true,
        };

        foreach (string arg in args)
        {
            startInfo.ArgumentList.Add(arg);
        }

        try
        {
            _serverProcess = Process.Start(startInfo);
            if (_serverProcess is null) return false;
        }
        catch
        {
            return false;
        }

        for (int i = 0; i < 60 && !cancellation.IsCancellationRequested; i++)
        {
            if (_serverProcess.HasExited)
            {
                Stop();
                return false;
            }

            if (await CheckHealthAsync(cancellation).ConfigureAwait(false))
            {
                return true;
            }

            await Task.Delay(500, cancellation).ConfigureAwait(false);
        }

        Stop();
        return false;
    }

    private async Task<bool> CheckHealthAsync(CancellationToken cancellation)
    {
        try
        {
            using var response = await Http.GetAsync($"http://127.0.0.1:{Port}/health", cancellation).ConfigureAwait(false);
            if (response.IsSuccessStatusCode)
            {
                string body = await response.Content.ReadAsStringAsync(cancellation).ConfigureAwait(false);
                return body.Contains("ok", StringComparison.OrdinalIgnoreCase);
            }
            return false;
        }
        catch
        {
            return false;
        }
    }

    /// <summary>
    /// Dynamically finds an available TCP port on localhost.
    /// </summary>
    public static int GetFreePort()
    {
        try
        {
            using var listener = new TcpListener(System.Net.IPAddress.Loopback, 0);
            listener.Start();
            int port = ((System.Net.IPEndPoint)listener.LocalEndpoint).Port;
            listener.Stop();
            return port;
        }
        catch
        {
            return 8099;
        }
    }

    /// <summary>
    /// Stop the server process, returning memory back to the machine.
    /// </summary>
    public void Stop()
    {
        if (_serverProcess is not null)
        {
            try
            {
                if (!_serverProcess.HasExited)
                {
                    _serverProcess.Kill(entireProcessTree: true);
                }
            }
            catch { }
            try { _serverProcess.Dispose(); } catch { }
            _serverProcess = null;
        }
    }

    public void Dispose()
    {
        Stop();
    }

    /// <summary>
    /// One turn of the conversation. Returns the raw assistant message.
    /// </summary>
    public async Task<JsonObject?> Ask(JsonArray messages, JsonArray tools, CancellationToken cancellation)
    {
        var request = new JsonObject
        {
            ["model"] = "local",
            ["temperature"] = 0,
            ["max_tokens"] = 512,
            ["messages"] = messages.DeepClone(),
            ["tools"] = tools.DeepClone(),
        };

        using var content = new StringContent(request.ToJsonString(), Encoding.UTF8, "application/json");
        using var response = await Http.PostAsync(Endpoint, content, cancellation).ConfigureAwait(false);
        if (!response.IsSuccessStatusCode) return null;

        string body = await response.Content.ReadAsStringAsync(cancellation).ConfigureAwait(false);
        return JsonNode.Parse(body)?["choices"]?[0]?["message"] as JsonObject;
    }
}
