// windowshot <hwnd> <out.png>
//
// Photographs ONE window with Windows.Graphics.Capture and keeps it whole: the
// frame comes back with the window's own alpha, so the corners Windows 11
// rounds are already transparent and nothing has to be drawn afterwards
// (website/SCREENSHOTS.md, "The one rule"). Prints one line of JSON with the
// picture's size and the window's DPI scale, which hero_windows.py records.

using System.Runtime.InteropServices;
using Windows.Graphics.Capture;
using Windows.Graphics.DirectX;
using Windows.Graphics.DirectX.Direct3D11;
using Windows.Graphics.Imaging;
using Windows.Storage.Streams;
using WinRT;

internal static class Program
{
    [ComImport, Guid("3628E81B-3CAC-4C60-B7F4-23CE0E0C3356"), InterfaceType(ComInterfaceType.InterfaceIsIUnknown)]
    private interface IGraphicsCaptureItemInterop
    {
        IntPtr CreateForWindow(IntPtr window, in Guid iid);
        IntPtr CreateForMonitor(IntPtr monitor, in Guid iid);
    }

    [DllImport("d3d11.dll")]
    private static extern int D3D11CreateDevice(IntPtr adapter, int driverType, IntPtr software, uint flags,
        IntPtr featureLevels, uint featureLevelCount, uint sdkVersion, out IntPtr device, out int featureLevel, out IntPtr context);

    [DllImport("d3d11.dll")]
    private static extern int CreateDirect3D11DeviceFromDXGIDevice(IntPtr dxgiDevice, out IntPtr graphicsDevice);

    [DllImport("user32.dll")]
    private static extern uint GetDpiForWindow(IntPtr window);

    [DllImport("user32.dll")]
    private static extern bool IsWindow(IntPtr window);

    private static readonly Guid GraphicsCaptureItemId = new("79C3F95B-31F7-4EC2-A464-632EF5D30760");
    private static readonly Guid DxgiDeviceId = new("54EC77FA-1377-44E6-8C32-88FD5F44C84C");

    private static IDirect3DDevice MakeDevice()
    {
        const int hardware = 1, warp = 5;
        const uint bgraSupport = 0x20, sdkVersion = 7;
        int result = D3D11CreateDevice(IntPtr.Zero, hardware, IntPtr.Zero, bgraSupport, IntPtr.Zero, 0, sdkVersion, out var device, out _, out var context);
        if (result < 0)
            result = D3D11CreateDevice(IntPtr.Zero, warp, IntPtr.Zero, bgraSupport, IntPtr.Zero, 0, sdkVersion, out device, out _, out context);
        Marshal.ThrowExceptionForHR(result);
        Marshal.Release(context);
        Marshal.ThrowExceptionForHR(Marshal.QueryInterface(device, in DxgiDeviceId, out var dxgi));
        Marshal.Release(device);
        Marshal.ThrowExceptionForHR(CreateDirect3D11DeviceFromDXGIDevice(dxgi, out var inspectable));
        Marshal.Release(dxgi);
        try { return MarshalInterface<IDirect3DDevice>.FromAbi(inspectable); }
        finally { Marshal.Release(inspectable); }
    }

    private static GraphicsCaptureItem ItemFor(IntPtr window)
    {
        var interop = GraphicsCaptureItem.As<IGraphicsCaptureItemInterop>();
        var pointer = interop.CreateForWindow(window, in GraphicsCaptureItemId);
        try { return GraphicsCaptureItem.FromAbi(pointer); }
        finally { Marshal.Release(pointer); }
    }

    private static async Task<int> Main(string[] arguments)
    {
        if (arguments.Length != 2 || !long.TryParse(arguments[0], out var handle))
        {
            Console.Error.WriteLine("usage: windowshot <hwnd> <out.png>");
            return 2;
        }
        var window = new IntPtr(handle);
        if (!IsWindow(window))
        {
            Console.Error.WriteLine($"windowshot: {handle} is not a window");
            return 1;
        }

        var item = ItemFor(window);
        var device = MakeDevice();
        using var pool = Direct3D11CaptureFramePool.CreateFreeThreaded(device, DirectXPixelFormat.B8G8R8A8UIntNormalized, 2, item.Size);
        using var session = pool.CreateCaptureSession(item);
        session.IsCursorCaptureEnabled = false;
        // The yellow capture border is drawn INSIDE the frame; Windows 11 lets it be turned off.
        var border = "off";
        try { session.IsBorderRequired = false; } catch { border = "could not be turned off"; }

        // A still window sends ONE frame and then nothing (measured: a waiting
        // Plantoir window sent exactly one), while a window that is still
        // drawing sends several. So keep the newest frame that arrives within
        // a short settling time after the first, rather than counting frames.
        var gate = new object();
        SoftwareBitmap? newest = null;
        var first = new TaskCompletionSource(TaskCreationOptions.RunContinuationsAsynchronously);
        pool.FrameArrived += (sender, _) =>
        {
            using var frame = sender.TryGetNextFrame();
            if (frame is null) return;
            var copy = SoftwareBitmap.CreateCopyFromSurfaceAsync(frame.Surface, BitmapAlphaMode.Premultiplied).AsTask().GetAwaiter().GetResult();
            lock (gate) { newest?.Dispose(); newest = copy; }
            first.TrySetResult();
        };
        session.StartCapture();
        if (await Task.WhenAny(first.Task, Task.Delay(TimeSpan.FromSeconds(3))) != first.Task)
        {
            Console.Error.WriteLine("windowshot: the window sent no frame in 3 seconds (minimised?)");
            return 1;
        }
        await Task.Delay(TimeSpan.FromMilliseconds(700));
        session.Dispose();
        SoftwareBitmap bitmap;
        lock (gate) { bitmap = newest!; newest = null; }

        using var stream = new InMemoryRandomAccessStream();
        var encoder = await BitmapEncoder.CreateAsync(BitmapEncoder.PngEncoderId, stream);
        encoder.SetSoftwareBitmap(bitmap);
        await encoder.FlushAsync();
        var bytes = new byte[stream.Size];
        using (var reader = new DataReader(stream.GetInputStreamAt(0)))
        {
            await reader.LoadAsync((uint)stream.Size);
            reader.ReadBytes(bytes);
        }
        var destination = Path.GetFullPath(arguments[1]);
        Directory.CreateDirectory(Path.GetDirectoryName(destination)!);
        await File.WriteAllBytesAsync(destination, bytes);

        var scale = GetDpiForWindow(window) / 96.0;
        Console.WriteLine($"{{\"width\": {bitmap.PixelWidth}, \"height\": {bitmap.PixelHeight}, \"scale\": {scale.ToString(System.Globalization.CultureInfo.InvariantCulture)}, \"border\": \"{border}\"}}");
        return 0;
    }
}
