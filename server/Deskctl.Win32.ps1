#requires -Version 5.1
$script:DeskctlNativeReady = $false

function Initialize-DeskctlNative {
    if ($script:DeskctlNativeReady) { return }

    $inputOffset = if ([IntPtr]::Size -eq 8) { 8 } else { 4 }
    $inputSize   = if ([IntPtr]::Size -eq 8) { 40 } else { 28 }

    # INPUT union offsets/sizes follow native alignment: 8/40 bytes on x64, 4/28 on x86.
    $nativeSource = @"
using System;
using System.Collections.Generic;
using System.Runtime.InteropServices;
using System.Text;

public static class DeskctlNative {
    [StructLayout(LayoutKind.Sequential)]
    public struct POINT { public int X; public int Y; }

    [StructLayout(LayoutKind.Sequential)]
    public struct RECT { public int Left; public int Top; public int Right; public int Bottom; }

    [StructLayout(LayoutKind.Sequential)]
    public struct MOUSEINPUT {
        public int dx;
        public int dy;
        public uint mouseData;
        public uint dwFlags;
        public uint time;
        public IntPtr extra;
    }

    [StructLayout(LayoutKind.Sequential)]
    public struct KEYBDINPUT {
        public ushort vk;
        public ushort scan;
        public uint flags;
        public uint time;
        public IntPtr extra;
    }

    [StructLayout(LayoutKind.Explicit, Size = $inputSize)]
    public struct INPUT {
        [FieldOffset(0)] public uint type;
        [FieldOffset($inputOffset)] public MOUSEINPUT mi;
        [FieldOffset($inputOffset)] public KEYBDINPUT ki;
    }

    public static INPUT Mouse(uint flags, uint data) { INPUT i = new INPUT(); i.type = 0; i.mi.dwFlags = flags; i.mi.mouseData = data; return i; }
    public static INPUT Key(ushort vk, ushort scan, uint flags) { INPUT i = new INPUT(); i.type = 1; i.ki.vk = vk; i.ki.scan = scan; i.ki.flags = flags; return i; }

    public class WindowInfo {
        public long Hwnd;
        public string Title;
        public uint Pid;
        public bool Minimized;
        public int X;
        public int Y;
        public int Width;
        public int Height;
        public bool Cloaked;
    }

    public class CoverInfo {
        public bool Checked;
        public bool Covered;
        public bool TargetCloaked;
        public long ByHwnd;
        public string ByTitle;
        public int X;
        public int Y;
    }

    public delegate bool EnumProc(IntPtr h, IntPtr l);

    [DllImport("user32.dll", SetLastError = true)] public static extern bool SetCursorPos(int x, int y);
    [DllImport("user32.dll")] public static extern bool GetCursorPos(out POINT p);
    [DllImport("user32.dll", SetLastError = true)] public static extern uint SendInput(uint n, INPUT[] inputs, int size);
    [DllImport("user32.dll")] public static extern void keybd_event(byte vk, byte scan, uint flags, UIntPtr extra);
    [DllImport("user32.dll")] public static extern bool EnumWindows(EnumProc cb, IntPtr l);
    [DllImport("user32.dll", CharSet = CharSet.Unicode)] public static extern int GetWindowText(IntPtr h, StringBuilder s, int n);
    [DllImport("user32.dll")] public static extern bool IsWindowVisible(IntPtr h);
    [DllImport("user32.dll")] public static extern bool IsIconic(IntPtr h);
    [DllImport("user32.dll")] public static extern bool ShowWindow(IntPtr h, int c);
    [DllImport("user32.dll")] public static extern bool SetForegroundWindow(IntPtr h);
    [DllImport("user32.dll")] public static extern uint GetWindowThreadProcessId(IntPtr h, out uint p);
    [DllImport("user32.dll")] public static extern IntPtr GetForegroundWindow();
    [DllImport("user32.dll")] public static extern bool AttachThreadInput(uint a, uint b, bool c);
    [DllImport("user32.dll")] public static extern bool BringWindowToTop(IntPtr h);
    [DllImport("user32.dll")] public static extern bool SetWindowPos(IntPtr h, IntPtr after, int x, int y, int cx, int cy, uint flags);
    [DllImport("user32.dll")] public static extern bool GetWindowRect(IntPtr h, out RECT r);
    [DllImport("user32.dll")] public static extern bool SetProcessDpiAwarenessContext(IntPtr c);
    [DllImport("shcore.dll")] public static extern int SetProcessDpiAwareness(int awareness);
    [DllImport("shcore.dll")] public static extern int GetProcessDpiAwareness(IntPtr process, out int awareness);
    [DllImport("user32.dll")] public static extern int GetSystemMetrics(int i);
    [DllImport("user32.dll")] public static extern IntPtr MonitorFromPoint(POINT p, uint flags);
    [DllImport("shcore.dll")] public static extern int GetDpiForMonitor(IntPtr monitor, int type, out uint dpiX, out uint dpiY);
    [DllImport("user32.dll", SetLastError = true)] public static extern bool DestroyIcon(IntPtr handle);
    [DllImport("user32.dll")] public static extern bool IsWindow(IntPtr h);
    [DllImport("dwmapi.dll")] public static extern int DwmGetWindowAttribute(IntPtr h, int attr, out RECT r, int size);
    [DllImport("dwmapi.dll", EntryPoint = "DwmGetWindowAttribute")] public static extern int DwmGetWindowAttributeInt(IntPtr h, int attr, out int v, int size);
    [DllImport("user32.dll")] public static extern IntPtr WindowFromPoint(POINT p);
    [DllImport("user32.dll")] public static extern IntPtr GetAncestor(IntPtr h, uint flags);
    [DllImport("user32.dll")] public static extern IntPtr GetWindow(IntPtr h, uint cmd);
    [DllImport("user32.dll")] public static extern bool EnumChildWindows(IntPtr parent, EnumProc cb, IntPtr l);
    [DllImport("user32.dll", CharSet = CharSet.Unicode)] public static extern int GetClassName(IntPtr h, StringBuilder s, int n);

    [DllImport("kernel32.dll")] public static extern uint GetCurrentThreadId();
    [DllImport("user32.dll", CharSet = CharSet.Unicode)] public static extern short VkKeyScanEx(char ch, IntPtr hkl);
    [DllImport("user32.dll")] public static extern IntPtr GetKeyboardLayout(uint thread);
    [DllImport("user32.dll")] public static extern uint MapVirtualKeyEx(uint code, uint mapType, IntPtr hkl);
    [DllImport("user32.dll")] public static extern short GetKeyState(int vk);

    [DllImport("user32.dll")] public static extern short GetAsyncKeyState(int vk);

    // 1.2.5: events for one character. Every printable character is a KEYEVENTF_UNICODE
    // down + up pair (independent of the keyboard layout and of Shift). Enter (\n) and Tab are
    // real keys; \r is skipped. (1.2.4 planned real keys + Shift per layout, which garbled text.)
    public static List<INPUT> PlanChar(char c, Func<uint, uint> scanOf) {
        List<INPUT> list = new List<INPUT>();
        if (c == '\r') return list;
        if (c == '\n' || c == '\t') {
            ushort vk = (ushort)(c == '\n' ? 0x0D : 0x09);
            ushort sc = (ushort)scanOf(vk);
            list.Add(Key(vk, sc, 0));
            list.Add(Key(vk, sc, 2));
            return list;
        }
        list.Add(Key(0, (ushort)c, 4));
        list.Add(Key(0, (ushort)c, 4 | 2));
        return list;
    }

    // Sends a key-up for every modifier Windows reports as held (Shift, Ctrl, Alt, Win, left and
    // right), so a stuck modifier can't change typed text. Returns how many were released.
    public static int ReleaseModifiers() {
        int[] mods = new int[] { 0xA0, 0xA1, 0xA2, 0xA3, 0xA4, 0xA5, 0x5B, 0x5C };
        List<INPUT> ups = new List<INPUT>();
        foreach (int vk in mods) {
            if ((GetAsyncKeyState(vk) & 0x8000) != 0) ups.Add(Key((ushort)vk, 0, 2));
        }
        if (ups.Count > 0) {
            INPUT[] arr = ups.ToArray();
            SendInput((uint)arr.Length, arr, Marshal.SizeOf(typeof(INPUT)));
        }
        return ups.Count;
    }

    public static string TypeError;

    // Types a chunk: one SendInput per character, then gapMs (Stopwatch wait, so 8 ms is 8 ms
    // and not the 15.6 ms timer tick). Stops before a character if the foreground window is no
    // longer expectHwnd (when expectHwnd != 0). Returns how many characters were sent.
    public static int TypeChunk(string text, int gapMs, long expectHwnd) {
        TypeError = null;
        Func<uint, uint> scanOf = delegate(uint v) { return MapVirtualKeyEx(v, 0, IntPtr.Zero); };
        int size = Marshal.SizeOf(typeof(INPUT));
        int n = 0;
        System.Diagnostics.Stopwatch gap = new System.Diagnostics.Stopwatch();
        foreach (char c in text) {
            if (expectHwnd != 0 && GetForegroundWindow().ToInt64() != expectHwnd) { TypeError = "focus_changed"; return n; }
            List<INPUT> evs = PlanChar(c, scanOf);
            if (evs.Count > 0) {
                INPUT[] arr = evs.ToArray();
                if (SendInput((uint)arr.Length, arr, size) != (uint)arr.Length) { TypeError = "sendinput_failed"; return n; }
            }
            n++;
            if (gapMs > 0) {
                gap.Restart();
                while (gap.ElapsedMilliseconds < gapMs) System.Threading.Thread.Sleep(0);
            }
        }
        return n;
    }

    // Joins this thread's input queue to the foreground thread's, then asks for the foreground.
    // Sharing the foreground queue is what lets a background process (the hidden server) pass
    // Windows' foreground lock; attaching the target's thread instead (1.2.0-1.2.2) did not.
    // No keystrokes, no clicks.
    public static bool ForceForeground(IntPtr h) {
        IntPtr fg = GetForegroundWindow();
        if (fg == h) return true;
        uint p;
        uint fgThread = fg == IntPtr.Zero ? 0 : GetWindowThreadProcessId(fg, out p);
        uint me = GetCurrentThreadId();
        bool a1 = fgThread != 0 && fgThread != me && AttachThreadInput(me, fgThread, true);
        try {
            BringWindowToTop(h);
            SetForegroundWindow(h);
        } finally {
            if (a1) AttachThreadInput(me, fgThread, false);
        }
        return GetForegroundWindow() == h;
    }

    public static string ClassOf(IntPtr h) {
        StringBuilder sb = new StringBuilder(256);
        GetClassName(h, sb, 256);
        return sb.ToString();
    }

    // Process that owns the window's content. Store apps live in an ApplicationFrameHost frame;
    // their real process owns a child window (CoreWindow), so return that pid when there is one.
    public static uint HostedPid(IntPtr h) {
        uint framePid;
        GetWindowThreadProcessId(h, out framePid);
        uint found = 0;
        EnumChildWindows(h, delegate(IntPtr c, IntPtr l) {
            uint p;
            GetWindowThreadProcessId(c, out p);
            if (p != 0 && p != framePid) { found = p; return false; }
            return true;
        }, IntPtr.Zero);
        return found != 0 ? found : framePid;
    }

    public static uint DpiAt(int x, int y) {
        POINT p = new POINT();
        p.X = x;
        p.Y = y;
        IntPtr m = MonitorFromPoint(p, 2);
        uint dx = 96, dy = 96;
        if (m != IntPtr.Zero) {
            GetDpiForMonitor(m, 0, out dx, out dy);
        }
        return dx;
    }

    public static WindowInfo Describe(IntPtr h) {
        if (h == IntPtr.Zero || !IsWindow(h)) return null;
        StringBuilder sb = new StringBuilder(512);
        GetWindowText(h, sb, 512);
        RECT r;
        GetWindowRect(h, out r);
        uint pid;
        GetWindowThreadProcessId(h, out pid);
        WindowInfo w = new WindowInfo();
        w.Hwnd = h.ToInt64();
        w.Title = sb.ToString();
        w.Pid = pid;
        w.Minimized = IsIconic(h);
        w.X = r.Left;
        w.Y = r.Top;
        w.Width = r.Right - r.Left;
        w.Height = r.Bottom - r.Top;
        w.Cloaked = IsCloaked(h);
        return w;
    }

    public static List<WindowInfo> ListWindows() {
        List<WindowInfo> list = new List<WindowInfo>();
        EnumWindows(delegate(IntPtr h, IntPtr l) {
            if (!IsWindowVisible(h)) return true;
            StringBuilder sb = new StringBuilder(512);
            if (GetWindowText(h, sb, 512) <= 0 || sb.Length == 0) return true;
            WindowInfo w = Describe(h);
            if (w != null) list.Add(w);
            return true;
        }, IntPtr.Zero);
        return list;
    }

    // Hidden UWP/suspended windows report visible but are cloaked by DWM (DWMWA_CLOAKED = 14).
    public static bool IsCloaked(IntPtr h) {
        try {
            int v;
            return DwmGetWindowAttributeInt(h, 14, out v, 4) == 0 && v != 0;
        } catch (Exception) { return false; }
    }

    // Visible, non-cloaked matches in z-order (EnumWindows walks top to bottom).
    public static List<WindowInfo> FindByTitle(string part) {
        List<WindowInfo> found = new List<WindowInfo>();
        foreach (WindowInfo w in ListWindows()) {
            if (!w.Cloaked && w.Title.IndexOf(part, StringComparison.OrdinalIgnoreCase) >= 0) found.Add(w);
        }
        return found;
    }

    // One window for focus/reuse: exact title before substring, restored before minimized,
    // and among duplicates the one highest in z-order. Cloaked windows never match.
    public static WindowInfo BestByTitle(string part) {
        WindowInfo exactMin = null, subVis = null, subMin = null;
        foreach (WindowInfo w in FindByTitle(part)) {
            bool exact = string.Equals(w.Title, part, StringComparison.OrdinalIgnoreCase);
            if (exact && !w.Minimized) return w;
            if (exact) { if (exactMin == null) exactMin = w; }
            else if (!w.Minimized) { if (subVis == null) subVis = w; }
            else if (subMin == null) subMin = w;
        }
        if (exactMin != null) return exactMin;
        if (subVis != null) return subVis;
        return subMin;
    }

    public static WindowInfo ForegroundMatching(string part) {
        IntPtr f = GetForegroundWindow();
        if (f == IntPtr.Zero || !IsWindowVisible(f) || IsCloaked(f)) return null;
        WindowInfo w = Describe(f);
        if (w == null || w.Title.IndexOf(part, StringComparison.OrdinalIgnoreCase) < 0) return null;
        return w;
    }

    public static IntPtr RootOf(IntPtr h) {
        if (h == IntPtr.Zero) return h;
        IntPtr r = GetAncestor(h, 2);
        return r == IntPtr.Zero ? h : r;
    }

    // The hit window is the target, one of its children, or a popup/dialog it owns.
    public static bool BelongsTo(IntPtr target, IntPtr hit) {
        if (hit == IntPtr.Zero) return false;
        IntPtr root = RootOf(hit);
        if (root == target || root == RootOf(target)) return true;
        IntPtr o = root;
        for (int i = 0; i < 8; i++) {
            o = GetWindow(o, 4);
            if (o == IntPtr.Zero) break;
            if (o == target) return true;
        }
        return false;
    }

    // Visual check that the target is really on top: hit-tests its visible center and four inner
    // points with WindowFromPoint. Covered only if no point lands on the target and at least one
    // lands on another non-cloaked window. Reports the window found at the first such point.
    public static CoverInfo CheckCovered(IntPtr target) {
        CoverInfo c = new CoverInfo();
        if (target == IntPtr.Zero || !IsWindow(target)) return c;
        if (IsCloaked(target)) {
            c.Checked = true;
            c.Covered = true;
            c.TargetCloaked = true;
            return c;
        }
        if (IsIconic(target)) return c;
        int[] b = FrameBounds(target);
        if (b == null) return c;
        int vx = GetSystemMetrics(76), vy = GetSystemMetrics(77), vw = GetSystemMetrics(78), vh = GetSystemMetrics(79);
        int l = Math.Max(b[0], vx), t = Math.Max(b[1], vy);
        int r = Math.Min(b[2], vx + vw), bt = Math.Min(b[3], vy + vh);
        if (r - l < 8 || bt - t < 8) return c;
        int qx = (r - l) / 4, qy = (bt - t) / 4;
        int[,] pts = { { (l + r) / 2, (t + bt) / 2 }, { l + qx, t + qy }, { r - qx, t + qy }, { l + qx, bt - qy }, { r - qx, bt - qy } };
        c.Checked = true;
        IntPtr by = IntPtr.Zero;
        for (int i = 0; i < 5; i++) {
            POINT p = new POINT();
            p.X = pts[i, 0];
            p.Y = pts[i, 1];
            IntPtr hit = WindowFromPoint(p);
            if (BelongsTo(target, hit)) return c;
            IntPtr root = RootOf(hit);
            if (by == IntPtr.Zero && root != IntPtr.Zero && !IsCloaked(root)) {
                by = root;
                c.X = p.X;
                c.Y = p.Y;
            }
        }
        if (by == IntPtr.Zero) return c;
        c.Covered = true;
        c.ByHwnd = by.ToInt64();
        StringBuilder sb = new StringBuilder(512);
        GetWindowText(by, sb, 512);
        c.ByTitle = sb.ToString();
        return c;
    }

    // Visible frame without the invisible resize borders; falls back to GetWindowRect.
    public static int[] FrameBounds(IntPtr h) {
        RECT r;
        bool ok = false;
        try {
            ok = DwmGetWindowAttribute(h, 9, out r, Marshal.SizeOf(typeof(RECT))) == 0 && r.Right > r.Left && r.Bottom > r.Top;
        } catch (Exception) { r = new RECT(); }
        if (!ok && !GetWindowRect(h, out r)) return null;
        return new int[] { r.Left, r.Top, r.Right, r.Bottom };
    }
}
"@
    Add-Type -TypeDefinition $nativeSource -Language CSharp
    $script:DeskctlNativeReady = $true
}

function Get-DeskctlBodyValue {
    param($Body, [string]$Name)
    if ($null -eq $Body) { return $null }
    if ($Body -is [hashtable]) {
        if ($Body.ContainsKey($Name)) { return $Body[$Name] }
        return $null
    }
    $prop = $Body.PSObject.Properties[$Name]
    if ($null -eq $prop) { return $null }
    return $prop.Value
}

function Resolve-DeskctlPoint {
    param($Body, $State)
    $x = [int](Get-DeskctlBodyValue $Body 'x')
    $y = [int](Get-DeskctlBodyValue $Body 'y')
    $space = Get-DeskctlBodyValue $Body 'space'
    if ([string]$space -eq 'image') {
        if (-not $State.LastShot) {
            return @{ ok = $false; result = (New-DeskctlResult $false 'no_screenshot' 'Take a screenshot first.' 400) }
        }
        $p = ConvertTo-DeskctlScreenPoint $x $y $State.LastShot.X $State.LastShot.Y $State.LastShot.Scale
        $x = $p.x
        $y = $p.y
    }
    return @{ ok = $true; x = $x; y = $y }
}

function Invoke-DeskctlScreenshot {
    param($Body, $State)
    try {
        Add-Type -AssemblyName System.Drawing
        Add-Type -AssemblyName System.Windows.Forms
        $screens = [Windows.Forms.Screen]::AllScreens
        $label = 'all'
        $monitor = Get-DeskctlBodyValue $Body 'monitor'
        $windowArg = Get-DeskctlBodyValue $Body 'window'
        $hwndArg = Get-DeskctlBodyValue $Body 'hwnd'
        # 1.2.0: light by default (active window, JPG 60, max 1280 px wide); full = true brings
        # back the old default (all monitors, PNG, full size). Each value can still be overridden.
        $full = [bool](Get-DeskctlBodyValue $Body 'full')
        $format = [string](Get-DeskctlBodyValue $Body 'format')
        if (-not $format) { $format = $(if ($full) { 'png' } else { 'jpg' }) }
        if ($format -eq 'jpeg') { $format = 'jpg' }
        $quality = $(if ($full) { 70 } else { 60 })
        if ($null -ne (Get-DeskctlBodyValue $Body 'quality')) { $quality = [int](Get-DeskctlBodyValue $Body 'quality') }
        $maxWidth = Get-DeskctlBodyValue $Body 'maxWidth'
        if ($null -eq $maxWidth -and -not $full) { $maxWidth = 1280 }
        $autoWindow = $false
        if (-not $full -and $null -eq $monitor -and $null -eq $windowArg -and $null -eq $hwndArg) {
            $windowArg = 'active'
            $autoWindow = $true
        }
        $windowInfo = $null
        $rect = $null
        if ($null -ne $windowArg -or $null -ne $hwndArg) {
            Initialize-DeskctlNative
            $h = if ($null -ne $hwndArg) { [IntPtr]([long]$hwndArg) } else { [DeskctlNative]::GetForegroundWindow() }
            $windowInfo = [DeskctlNative]::Describe($h)
            $windowError = $null
            if ($null -eq $windowInfo) {
                $windowError = New-DeskctlResult $false 'window_not_found' 'Window not found.' 404
            } elseif ($windowInfo.Minimized) {
                $windowError = New-DeskctlResult $false 'window_minimized' 'The window is minimized.' 400
            } elseif ($autoWindow -and [string]::IsNullOrWhiteSpace($windowInfo.Title)) {
                # Desktop or taskbar in front: a whole-screen shot is more useful.
                $windowError = New-DeskctlResult $false 'window_not_found' 'No active window.' 404
            } else {
                $b = [DeskctlNative]::FrameBounds($h)
                if ($null -eq $b) {
                    $windowError = New-DeskctlResult $false 'window_not_found' 'Could not read the window size.' 404
                } else {
                    $rect = [Drawing.Rectangle]::Intersect(
                        [Drawing.Rectangle]::FromLTRB($b[0], $b[1], $b[2], $b[3]),
                        [Windows.Forms.SystemInformation]::VirtualScreen)
                    if ($rect.Width -le 0 -or $rect.Height -le 0) {
                        $windowError = New-DeskctlResult $false 'window_offscreen' 'The window is off screen.' 400
                    }
                }
            }
            if ($windowError) {
                if (-not $autoWindow) { return $windowError }
                # Light default with no usable active window: fall back to all monitors.
                $windowInfo = $null
                $rect = [Windows.Forms.SystemInformation]::VirtualScreen
            } else {
                $label = 'window'
            }
        } elseif ($null -ne $monitor -and [string]$monitor -ne 'all') {
            $index = [int]$monitor
            if ($index -lt 0 -or $index -ge $screens.Count) {
                return New-DeskctlResult $false 'invalid_args' 'Invalid monitor.' 400
            }
            $rect = $screens[$index].Bounds
            $label = [string]$index
        } else {
            $rect = [Windows.Forms.SystemInformation]::VirtualScreen
        }

        $screenW = $rect.Width
        $screenH = $rect.Height
        # 24bpp is enough for JPEG and encodes faster; PNG keeps the original 32bpp output.
        $bmp = if ($format -eq 'jpg') {
            New-Object Drawing.Bitmap($screenW, $screenH, [Drawing.Imaging.PixelFormat]::Format24bppRgb)
        } else {
            New-Object Drawing.Bitmap($screenW, $screenH)
        }
        $g = [Drawing.Graphics]::FromImage($bmp)
        try {
            $g.CopyFromScreen($rect.X, $rect.Y, 0, 0, $bmp.Size)
        } finally {
            $g.Dispose()
        }

        $scale = 1.0
        if ($null -ne $maxWidth -and [int]$maxWidth -gt 0 -and $bmp.Width -gt [int]$maxWidth) {
            $scale = [int]$maxWidth / [double]$bmp.Width
            $newW = [int]$maxWidth
            $newH = [int][Math]::Round($bmp.Height * $scale)
            $scaled = New-Object Drawing.Bitmap($newW, $newH, $bmp.PixelFormat)
            $sg = [Drawing.Graphics]::FromImage($scaled)
            try {
                $sg.InterpolationMode = [Drawing.Drawing2D.InterpolationMode]::HighQualityBicubic
                $sg.DrawImage($bmp, 0, 0, $newW, $newH)
            } finally {
                $sg.Dispose()
                $bmp.Dispose()
            }
            $bmp = $scaled
        }

        $folder = if ($env:DESKCTL_TEMP) {
            $env:DESKCTL_TEMP
        } elseif ($env:DESKCTL_HOME) {
            Join-Path $env:DESKCTL_HOME 'temp'
        } else {
            Join-Path ([IO.Path]::GetTempPath()) 'deskctl'
        }
        [void](New-Item -ItemType Directory -Force -Path $folder)
        Get-ChildItem -LiteralPath $folder -Filter 'shot-*' -ErrorAction SilentlyContinue |
            Where-Object { $_.Extension -in @('.png', '.jpg') -and $_.LastWriteTime -lt (Get-Date).AddHours(-24) } |
            Remove-Item -Force -ErrorAction SilentlyContinue

        $path = Join-Path $folder ('shot-' + (Get-Date -Format 'yyyyMMddHHmmssfff') + '.' + $format)
        try {
            if ($format -eq 'jpg') {
                $codec = [Drawing.Imaging.ImageCodecInfo]::GetImageEncoders() | Where-Object { $_.MimeType -eq 'image/jpeg' } | Select-Object -First 1
                $encoderParams = New-Object Drawing.Imaging.EncoderParameters(1)
                try {
                    $encoderParams.Param[0] = New-Object Drawing.Imaging.EncoderParameter([Drawing.Imaging.Encoder]::Quality, [long]$quality)
                    $bmp.Save($path, $codec, $encoderParams)
                } finally {
                    $encoderParams.Dispose()
                }
            } else {
                $bmp.Save($path, [Drawing.Imaging.ImageFormat]::Png)
            }
            $w = $bmp.Width
            $h = $bmp.Height
        } finally {
            $bmp.Dispose()
        }

        $State.LastShot = @{ X = $rect.X; Y = $rect.Y; Scale = $scale }

        $dpi = 96
        if ($label -eq 'window') {
            try { $dpi = [int][DeskctlNative]::DpiAt([int]($rect.X + $rect.Width / 2), [int]($rect.Y + $rect.Height / 2)) } catch { }
        } elseif ($label -eq 'all') {
            if ($State.PrimaryDpi) { $dpi = [int]$State.PrimaryDpi }
        } elseif ($State.Monitors -and $State.Monitors.Count -gt [int]$label) {
            $dpi = [int]$State.Monitors[[int]$label].dpi
        }

        $data = @{
            path         = $path
            width        = $w
            height       = $h
            screenWidth  = $screenW
            screenHeight = $screenH
            originX      = $rect.X
            originY      = $rect.Y
            scale        = $scale
            dpi          = $dpi
            dpiScale     = ($dpi / 96.0)
            monitor      = $label
            format       = $format
            preset       = $(if ($full) { 'full' } else { 'light' })
            bytes        = ([IO.FileInfo]$path).Length
        }
        if ($format -eq 'jpg') { $data.quality = $quality }
        if ($windowInfo) {
            $data.hwnd = [string]$windowInfo.Hwnd
            $data.title = $windowInfo.Title
        }
        return New-DeskctlResult $true $null $null 200 $data
    } catch {
        return New-DeskctlResult $false 'screenshot_failed' $_.Exception.Message 500
    }
}

function Invoke-DeskctlMove {
    param($Body, $State)
    try {
        Initialize-DeskctlNative
        $resolved = Resolve-DeskctlPoint $Body $State
        if (-not $resolved.ok) { return $resolved.result }
        [void][DeskctlNative]::SetCursorPos($resolved.x, $resolved.y)
        return New-DeskctlResult $true $null $null 200 @{ x = $resolved.x; y = $resolved.y }
    } catch {
        return New-DeskctlResult $false 'invalid_args' $_.Exception.Message 400
    }
}

function Send-DeskctlInput {
    param([DeskctlNative+INPUT[]]$Inputs)
    $size = [Runtime.InteropServices.Marshal]::SizeOf([type][DeskctlNative+INPUT])
    $sent = [DeskctlNative]::SendInput([uint32]$Inputs.Length, $Inputs, $size)
    if ($sent -ne $Inputs.Length) {
        throw 'SendInput could not send all events.'
    }
}

function Invoke-DeskctlClick {
    param($Body, $State)
    $moved = Invoke-DeskctlMove $Body $State
    if (-not $moved.Body.ok) { return $moved }
    Initialize-DeskctlNative
    $map = @{ left = 0x0002; right = 0x0008; middle = 0x0020 }
    $button = Get-DeskctlBodyValue $Body 'button'
    if (-not $button) { $button = 'left' }
    if (-not $map.ContainsKey([string]$button)) {
        return New-DeskctlResult $false 'invalid_args' 'Invalid button.' 400
    }
    $times = if (Get-DeskctlBodyValue $Body 'double') { 2 } else { 1 }
    for ($i = 0; $i -lt $times; $i++) {
        $arr = New-Object DeskctlNative+INPUT[] 2
        $arr[0] = [DeskctlNative]::Mouse([uint32]$map[[string]$button], 0)
        $arr[1] = [DeskctlNative]::Mouse([uint32]($map[[string]$button] -shl 1), 0)
        Send-DeskctlInput $arr
        if ($times -eq 2) { Start-Sleep -Milliseconds 70 }
    }
    return New-DeskctlResult $true $null $null 200 @{ x = $moved.Body.x; y = $moved.Body.y; button = [string]$button; double = ($times -eq 2) }
}

function Invoke-DeskctlScroll {
    param($Body, $State)
    $x = Get-DeskctlBodyValue $Body 'x'
    $y = Get-DeskctlBodyValue $Body 'y'
    if ($null -ne $x -and $null -ne $y) {
        $moved = Invoke-DeskctlMove $Body $State
        if (-not $moved.Body.ok) { return $moved }
    }
    Initialize-DeskctlNative
    $delta = [int](-([int](Get-DeskctlBodyValue $Body 'dy')) * 120)
    $arr = New-Object DeskctlNative+INPUT[] 1
    $arr[0] = [DeskctlNative]::Mouse([uint32]0x0800, [BitConverter]::ToUInt32([BitConverter]::GetBytes($delta), 0))
    Send-DeskctlInput $arr
    return New-DeskctlResult $true $null $null 200 @{ dy = (Get-DeskctlBodyValue $Body 'dy') }
}

# Clipboard helpers for type --paste. Text only: non-text clipboard content is left alone
# (not saved, so it can't be restored) and reported. The saved text never leaves the server.
function Invoke-DeskctlClipboardRetry([scriptblock]$Action) {
    for ($i = 0; $i -lt 8; $i++) {
        try { return (& $Action) } catch { Start-Sleep -Milliseconds 50 }
    }
    throw 'clipboard_busy'
}

# 1.2.5 type: modifiers released first; then either
#  - keys: one KEYEVENTF_UNICODE down+up per character (Enter/Tab as real keys), 8 ms apart
#    (gapMs 0-50), chunks of 32 with the tray switch checked between them; or
#  - paste: save the clipboard text, put the text on the clipboard, Ctrl+V, wait 300 ms, restore.
# Both stop with focus_changed if the foreground window changes.
function Invoke-DeskctlType {
    param($Body, $State)
    $text = [string](Get-DeskctlBodyValue $Body 'text')
    if ($text.Length -gt 8192) {
        return New-DeskctlResult $false 'invalid_args' 'Text is too long.' 400
    }
    Initialize-DeskctlNative
    $released = [DeskctlNative]::ReleaseModifiers()
    $expect = [DeskctlNative]::GetForegroundWindow().ToInt64()

    if ([bool](Get-DeskctlBodyValue $Body 'paste')) {
        Add-Type -AssemblyName System.Windows.Forms
        $clip = 'restored'
        $saved = $null
        try {
            $hasText = Invoke-DeskctlClipboardRetry { [Windows.Forms.Clipboard]::ContainsText() }
            if ($hasText) {
                $saved = Invoke-DeskctlClipboardRetry { [Windows.Forms.Clipboard]::GetText() }
            } else {
                $obj = Invoke-DeskctlClipboardRetry { [Windows.Forms.Clipboard]::GetDataObject() }
                $clip = if ($obj -and @($obj.GetFormats()).Count -gt 0) { 'not_saved_non_text' } else { 'cleared' }
            }
            $paste = $text -replace "`r?`n", "`r`n"
            Invoke-DeskctlClipboardRetry { [Windows.Forms.Clipboard]::SetText($paste) } | Out-Null
        } catch {
            return New-DeskctlResult $false 'clipboard_failed' 'Could not use the clipboard.' 500 @{ characters = 0 }
        }
        $result = $null
        if (-not (Test-DeskctlLive $State)) { $result = New-DeskctlKillSwitchResult }
        elseif ([DeskctlNative]::GetForegroundWindow().ToInt64() -ne $expect) {
            $result = New-DeskctlResult $false 'focus_changed' 'The foreground window changed before pasting; nothing was pasted.' 409 @{ characters = 0 }
        } else {
            $k = Invoke-DeskctlKey @{ combo = 'ctrl+v' } $State
            if (-not $k.Body.ok) { $result = $k }
            else { [void](Wait-DeskctlInterval $State 300) }
        }
        try {
            if ($null -ne $saved) { Invoke-DeskctlClipboardRetry { [Windows.Forms.Clipboard]::SetText($saved) } | Out-Null }
            elseif ($clip -eq 'cleared') { Invoke-DeskctlClipboardRetry { [Windows.Forms.Clipboard]::Clear() } | Out-Null }
        } catch { $clip = 'restore_failed' }
        if ($result) { $result.Body.clipboard = $clip; return $result }
        $data = @{ characters = $text.Length; method = 'paste'; clipboard = $clip; modifiersReleased = $released }
        if ($clip -eq 'not_saved_non_text') { $data.warning = 'The clipboard held non-text data; it was replaced by the pasted text and could not be restored.' }
        return New-DeskctlResult $true $null $null 200 $data
    }

    $gap = 8
    if ($null -ne (Get-DeskctlBodyValue $Body 'gapMs')) { $gap = [int](Get-DeskctlBodyValue $Body 'gapMs') }
    $typed = 0
    for ($i = 0; $i -lt $text.Length; $i += 32) {
        if (-not (Test-DeskctlLive $State)) {
            $off = New-DeskctlKillSwitchResult
            $off.Body.characters = $typed
            return $off
        }
        $chunk = $text.Substring($i, [Math]::Min(32, $text.Length - $i))
        $n = [DeskctlNative]::TypeChunk($chunk, $gap, $expect)
        $typed += $n
        if ($n -lt $chunk.Length) {
            if ([DeskctlNative]::TypeError -eq 'focus_changed') {
                return New-DeskctlResult $false 'focus_changed' 'The foreground window changed while typing; stopped.' 409 @{ characters = $typed; total = $text.Length }
            }
            return New-DeskctlResult $false 'type_failed' 'SendInput could not send all events.' 500 @{ characters = $typed; total = $text.Length }
        }
    }
    return New-DeskctlResult $true $null $null 200 @{ characters = $text.Length; method = 'keys'; gapMs = $gap; modifiersReleased = $released }
}

function Invoke-DeskctlKey {
    param($Body, $State)
    try {
        $codes = ConvertFrom-DeskctlCombo ([string](Get-DeskctlBodyValue $Body 'combo'))
        Initialize-DeskctlNative
        foreach ($value in $codes) {
            $up = $value -lt 0
            $vk = [Math]::Abs($value)
            $arr = New-Object DeskctlNative+INPUT[] 1
            $arr[0] = [DeskctlNative]::Key([uint16]$vk, 0, [uint32]$(if ($up) { 2 } else { 0 }))
            Send-DeskctlInput $arr
        }
        return New-DeskctlResult $true $null $null 200 @{ combo = (Get-DeskctlBodyValue $Body 'combo') }
    } catch {
        return New-DeskctlResult $false 'unknown_key' 'Unknown key or combination.' 400
    }
}

function ConvertTo-DeskctlWindowData {
    param($Window)
    return @{
        hwnd      = [string]$Window.Hwnd
        title     = $Window.Title
        pid       = [int]$Window.Pid
        minimized = [bool]$Window.Minimized
        cloaked   = [bool]$Window.Cloaked
        rect      = @{
            x      = $Window.X
            y      = $Window.Y
            width  = $Window.Width
            height = $Window.Height
        }
    }
}

function Invoke-DeskctlWindows {
    param($State)
    Initialize-DeskctlNative
    $list = @()
    foreach ($w in [DeskctlNative]::ListWindows()) {
        $list += ConvertTo-DeskctlWindowData $w
    }
    return New-DeskctlResult $true $null $null 200 @{ windows = $list }
}

function Invoke-DeskctlForeground {
    param($State)
    Initialize-DeskctlNative
    $fgHandle = [DeskctlNative]::GetForegroundWindow()
    $w = [DeskctlNative]::Describe($fgHandle)
    if ($null -eq $w) {
        return New-DeskctlResult $true $null $null 200 @{ hwnd = $null; title = '' }
    }
    $data = ConvertTo-DeskctlWindowData $w
    # Foreground per Windows is not always what is visible (cloaked UWP duplicates); add the hit test.
    $cover = [DeskctlNative]::CheckCovered($fgHandle)
    $data.covered = [bool]$cover.Covered
    if ($cover.Covered) { $data.coveredBy = ConvertTo-DeskctlCoverData $cover }
    return New-DeskctlResult $true $null $null 200 $data
}

function ConvertTo-DeskctlCoverData {
    param($Cover)
    if ($Cover.TargetCloaked) { return @{ cloaked = $true } }
    return @{ hwnd = [string]$Cover.ByHwnd; title = [string]$Cover.ByTitle; x = $Cover.X; y = $Cover.Y }
}

# Polls every ~100 ms. Without -Gone: first visible window whose title contains Title
# (and is foreground with -Foreground). With -Gone: until no such window remains.
function Invoke-DeskctlWait {
    param($Body, $State)
    Initialize-DeskctlNative
    $title = [string](Get-DeskctlBodyValue $Body 'title')
    $timeout = 5000
    if ($null -ne (Get-DeskctlBodyValue $Body 'timeoutMs')) { $timeout = [int](Get-DeskctlBodyValue $Body 'timeoutMs') }
    $foreground = [bool](Get-DeskctlBodyValue $Body 'foreground')
    $gone = [bool](Get-DeskctlBodyValue $Body 'gone')
    $sw = [Diagnostics.Stopwatch]::StartNew()
    while ($true) {
        $match = if ($foreground) {
            [DeskctlNative]::ForegroundMatching($title)
        } else {
            [DeskctlNative]::FindByTitle($title) | Select-Object -First 1
        }
        if ($gone -and $null -eq $match) {
            return New-DeskctlResult $true $null $null 200 @{ gone = $true; title = $title; elapsedMs = [int]$sw.ElapsedMilliseconds }
        }
        if (-not $gone -and $null -ne $match) {
            $data = ConvertTo-DeskctlWindowData $match
            $data.elapsedMs = [int]$sw.ElapsedMilliseconds
            return New-DeskctlResult $true $null $null 200 $data
        }
        if ($sw.ElapsedMilliseconds -ge $timeout) {
            return New-DeskctlResult $false 'timeout' $(if ($gone) { "The window '$title' did not close in time." } else { "No window with '$title' appeared." }) 408 @{ elapsedMs = [int]$sw.ElapsedMilliseconds }
        }
        if (-not (Wait-DeskctlInterval $State 100)) { return New-DeskctlKillSwitchResult }
    }
}

# Scheme targets (ms-settings:, http:, shell:, mailto:, ...). Two or more letters before ':'
# so drive paths such as C:\ never match.
function Test-DeskctlShellTarget {
    param([string]$Path)
    return ($Path -match '^[A-Za-z][A-Za-z0-9+.\-]+:' -and $Path -notmatch '^[A-Za-z]:[\\/]')
}

# ShellExecute as the current user. Verb stays empty: never "runas", never elevated.
function Start-DeskctlShellExecute {
    param([string]$Target, [string]$Arguments)
    $psi = New-Object Diagnostics.ProcessStartInfo
    $psi.FileName = $Target
    if (-not [string]::IsNullOrWhiteSpace($Arguments)) { $psi.Arguments = $Arguments }
    $psi.UseShellExecute = $true
    $psi.Verb = ''
    # Returns $null when an already running process handles the target (common for URIs).
    return [Diagnostics.Process]::Start($psi)
}

function Get-DeskctlErrorText {
    param($ErrorRecord)
    $e = $ErrorRecord.Exception
    if ($e.InnerException) { return $e.InnerException.Message }
    return $e.Message
}

# Starts a program, document, URI or app alias as the current (non-elevated) user, never with
# a Verb. Programs go through Start-Process, then ShellExecute if that fails. Scheme targets
# (ms-settings: and the like) go through ShellExecute, then explorer.exe <uri>.
# With waitTitle, waits for a new matching window, or an existing one that comes to the
# front with a new title (apps such as Notepad on Windows 11 open a tab in the same window).
# If none shows up, an existing visible matching window is brought to the front and returned
# with reused = true: after reuseAfterMs (default 1500 ms for scheme targets, the full timeout
# for programs).
function Invoke-DeskctlLaunch {
    param($Body, $State)
    Initialize-DeskctlNative
    $path = ([string](Get-DeskctlBodyValue $Body 'path')).Trim()
    $argText = [string](Get-DeskctlBodyValue $Body 'args')
    $waitTitle = [string](Get-DeskctlBodyValue $Body 'waitTitle')
    $timeout = 10000
    if ($null -ne (Get-DeskctlBodyValue $Body 'timeoutMs')) { $timeout = [int](Get-DeskctlBodyValue $Body 'timeoutMs') }
    $isUri = Test-DeskctlShellTarget $path
    $reuseAfter = if ($isUri) { [Math]::Min(1500, $timeout) } else { $timeout }
    if ($null -ne (Get-DeskctlBodyValue $Body 'reuseAfterMs')) { $reuseAfter = [Math]::Min([int](Get-DeskctlBodyValue $Body 'reuseAfterMs'), $timeout) }

    $before = @{}
    $fgBefore = [long]0
    if ($waitTitle) {
        foreach ($w in [DeskctlNative]::FindByTitle($waitTitle)) { $before[[string]$w.Hwnd] = $w.Title }
        $fgBefore = [DeskctlNative]::GetForegroundWindow().ToInt64()
    }

    $proc = $null
    $method = $null
    $firstError = $null
    if ($isUri) {
        try {
            $proc = Start-DeskctlShellExecute $path $argText
            $method = 'shellexecute'
        } catch {
            $firstError = Get-DeskctlErrorText $_
        }
        if (-not $method) {
            try {
                [void](Start-DeskctlShellExecute 'explorer.exe' ('"' + $path.Replace('"', '') + '"'))
                $method = 'explorer'
            } catch {
                $second = Get-DeskctlErrorText $_
                return New-DeskctlResult $false 'launch_failed' "Could not open '$path': $firstError / explorer: $second" 400
            }
        }
    } else {
        $startArgs = @{ FilePath = $path; PassThru = $true; ErrorAction = 'Stop' }
        if (-not [string]::IsNullOrWhiteSpace($argText)) { $startArgs.ArgumentList = $argText }
        try {
            $proc = Start-Process @startArgs
            $method = 'start-process'
        } catch {
            $firstError = Get-DeskctlErrorText $_
        }
        if (-not $method) {
            # App aliases and other shell names Start-Process could not resolve.
            try {
                $proc = Start-DeskctlShellExecute $path $argText
                $method = 'shellexecute'
            } catch {
                return New-DeskctlResult $false 'launch_failed' "Could not open '$path': $firstError" 400
            }
        }
    }
    $procId = $null
    if ($proc -and $method -ne 'explorer') { try { $procId = [int]$proc.Id } catch { } }
    if (-not $waitTitle) {
        return New-DeskctlResult $true $null $null 200 @{ pid = $procId; path = $path; method = $method }
    }

    $sw = [Diagnostics.Stopwatch]::StartNew()
    while ($true) {
        foreach ($w in [DeskctlNative]::FindByTitle($waitTitle)) {
            if (-not $before.ContainsKey([string]$w.Hwnd)) {
                return New-DeskctlResult $true $null $null 200 @{ pid = $procId; path = $path; method = $method; window = (ConvertTo-DeskctlWindowData $w); newWindow = $true; reused = $false; elapsedMs = [int]$sw.ElapsedMilliseconds }
            }
        }
        $fg = [DeskctlNative]::ForegroundMatching($waitTitle)
        if ($null -ne $fg -and ($fg.Hwnd -ne $fgBefore -or $before[[string]$fg.Hwnd] -ne $fg.Title)) {
            return New-DeskctlResult $true $null $null 200 @{ pid = $procId; path = $path; method = $method; window = (ConvertTo-DeskctlWindowData $fg); newWindow = $false; reused = $true; elapsedMs = [int]$sw.ElapsedMilliseconds }
        }
        $elapsed = [int]$sw.ElapsedMilliseconds
        if ($elapsed -ge $reuseAfter -or $elapsed -ge $timeout) {
            $existing = [DeskctlNative]::BestByTitle($waitTitle)
            if ($null -ne $existing) {
                $focused = Invoke-DeskctlFocusWindow $existing $State
                $focused.Body.pid = $procId
                $focused.Body.path = $path
                $focused.Body.method = $method
                $focused.Body.newWindow = $false
                $focused.Body.reused = $true
                $focused.Body.elapsedMs = [int]$sw.ElapsedMilliseconds
                if ($focused.Body.ok) { $focused.Body.window = ConvertTo-DeskctlWindowData ([DeskctlNative]::Describe([IntPtr]([long]$existing.Hwnd))) }
                return $focused
            }
        }
        if ($elapsed -ge $timeout) {
            return New-DeskctlResult $false 'timeout' "Opened '$path' but no window with '$waitTitle' appeared." 408 @{ pid = $procId; path = $path; method = $method; elapsedMs = $elapsed }
        }
        if (-not (Wait-DeskctlInterval $State 100)) { return New-DeskctlKillSwitchResult }
    }
}

function Invoke-DeskctlFocus {
    param($Body, $State)
    Initialize-DeskctlNative
    $hwnd = Get-DeskctlBodyValue $Body 'hwnd'
    $title = [string](Get-DeskctlBodyValue $Body 'title')
    $found = $null
    if ($hwnd) {
        $h = [IntPtr]([long]$hwnd)
        if ([DeskctlNative]::IsWindowVisible($h)) { $found = [DeskctlNative]::Describe($h) }
    } else {
        # Skips cloaked duplicates (e.g. Calculator's hidden second 'Calculadora' window).
        $found = [DeskctlNative]::BestByTitle($title)
    }
    if (-not $found) {
        $hidden = 0
        if (-not $hwnd) {
            foreach ($w in [DeskctlNative]::ListWindows()) {
                if ($w.Cloaked -and $w.Title.IndexOf($title, [StringComparison]::OrdinalIgnoreCase) -ge 0) { $hidden++ }
            }
        }
        if ($hidden -gt 0) {
            return New-DeskctlResult $false 'window_not_found' 'Only hidden (cloaked) windows have that title.' 404 @{ cloakedMatches = $hidden }
        }
        return New-DeskctlResult $false 'window_not_found' 'Window not found.' 404
    }
    return Invoke-DeskctlFocusWindow $found $State
}

# Brings one window to the front and then verifies it visually with a hit test, so a window
# Windows reports as foreground but that is still hidden behind another fails with 'covered'.
# Browsers never get synthetic input from focus: Chrome's top bar has buttons (Gemini, tab
# search) where the title-bar click fallback used to land, and a stray Alt can reach it.
$script:DeskctlBrowserProcesses = @('chrome', 'msedge', 'firefox', 'brave', 'opera', 'vivaldi')

# F24 down + up: unassigned on standard keyboards, so no app or shortcut reacts to it.
function Send-DeskctlUnlockInput {
    $f24 = New-Object DeskctlNative+INPUT[] 2
    $f24[0] = [DeskctlNative]::Key([uint16]0x87, 0, [uint32]0)
    $f24[1] = [DeskctlNative]::Key([uint16]0x87, 0, [uint32]2)
    try { Send-DeskctlInput $f24 } catch { }
}

function Invoke-DeskctlFocusWindow {
    param($Info, $State, [switch]$NoInput)
    $h = [IntPtr]([long]$Info.Hwnd)
    if (-not $NoInput -and ((Get-DeskctlWindowProcessName $Info.Hwnd) -in $script:DeskctlBrowserProcesses)) { $NoInput = $true }
    if ($Info.Minimized) {
        [void][DeskctlNative]::ShowWindow($h, 9)
        if (-not (Wait-DeskctlInterval $State 150)) { return New-DeskctlKillSwitchResult }
        $again = [DeskctlNative]::Describe($h)
        if ($null -ne $again) { $Info = $again }
    }
    $fallback = $false
    if ([DeskctlNative]::GetForegroundWindow() -ne $h) {
        [uint32]$procId = 0
        $targetThread = [DeskctlNative]::GetWindowThreadProcessId($h, [ref]$procId)
        $fg = [DeskctlNative]::GetForegroundWindow()
        [uint32]$fgProc = 0
        $fgThread = [DeskctlNative]::GetWindowThreadProcessId($fg, [ref]$fgProc)
        # 1.2.2: an F24 tap (VK 0x87, no app binds it) makes this process the last input source,
        # which lifts Windows' foreground lock so SetForegroundWindow is honored. It replaces the
        # old Alt tap, which could reach the target app (Alt opens menus; Alt+G is Gemini in Chrome).
        Send-DeskctlUnlockInput
        # 1.2.3: attach THIS thread to the foreground thread (verified live: passes the lock
        # from a process without foreground rights), in one native call on one thread.
        [void][DeskctlNative]::ForceForeground($h)
        if ([DeskctlNative]::GetForegroundWindow() -ne $h) {
            # Retry without clicks: TOPMOST toggle, then the same native call again.
            [void][DeskctlNative]::SetWindowPos($h, [IntPtr](-1), 0, 0, 0, 0, [uint32]0x0013)
            [void][DeskctlNative]::SetWindowPos($h, [IntPtr](-2), 0, 0, 0, 0, [uint32]0x0013)
            Start-Sleep -Milliseconds 50
            [void][DeskctlNative]::ForceForeground($h)
        }
    }
    $cover = $null
    if ([DeskctlNative]::GetForegroundWindow() -eq $h) {
        $cover = [DeskctlNative]::CheckCovered($h)
    }
    if (-not $NoInput -and ([DeskctlNative]::GetForegroundWindow() -ne $h -or ($null -ne $cover -and $cover.Covered -and -not $cover.TargetCloaked))) {
        # Fallback: raise it above everything, then click its title bar (real input is always allowed).
        $fallback = $true
        [void][DeskctlNative]::SetWindowPos($h, [IntPtr](-1), 0, 0, 0, 0, [uint32]0x0013)
        [void][DeskctlNative]::SetWindowPos($h, [IntPtr](-2), 0, 0, 0, 0, [uint32]0x0013)
        $cx = [int]($Info.X + [Math]::Max(40, $Info.Width - 280))
        $cy = [int]($Info.Y + 14)
        [DeskctlNative+POINT]$old = New-Object DeskctlNative+POINT
        [void][DeskctlNative]::GetCursorPos([ref]$old)
        [void][DeskctlNative]::SetCursorPos($cx, $cy)
        $clk = New-Object DeskctlNative+INPUT[] 2
        $clk[0] = [DeskctlNative]::Mouse([uint32]0x0002, 0)
        $clk[1] = [DeskctlNative]::Mouse([uint32]0x0004, 0)
        try { Send-DeskctlInput $clk } catch { }
        Start-Sleep -Milliseconds 120
        [void][DeskctlNative]::SetCursorPos($old.X, $old.Y)
    }
    if ([DeskctlNative]::GetForegroundWindow() -ne $h) {
        return New-DeskctlResult $false 'focus_failed' 'Windows did not allow focusing the window. If it runs elevated (UAC), Grok Bot Desktop cannot control it.' 403 @{ hwnd = [string]$Info.Hwnd; title = $Info.Title; fallback = $fallback }
    }
    # Give animations (restore, uncloak) up to ~400 ms before calling it covered.
    $cover = [DeskctlNative]::CheckCovered($h)
    $settle = [Diagnostics.Stopwatch]::StartNew()
    while ($cover.Covered -and $settle.ElapsedMilliseconds -lt 400) {
        if (-not (Wait-DeskctlInterval $State 50)) { return New-DeskctlKillSwitchResult }
        $cover = [DeskctlNative]::CheckCovered($h)
    }
    if ($cover.Covered) {
        $msg = if ($cover.TargetCloaked) {
            'Windows reports the window in front, but it is hidden (cloaked).'
        } else {
            "Windows reports the window in front, but '$($cover.ByTitle)' covers it."
        }
        return New-DeskctlResult $false 'covered' $msg 409 @{ hwnd = [string]$Info.Hwnd; title = $Info.Title; fallback = $fallback; coveredBy = (ConvertTo-DeskctlCoverData $cover) }
    }
    return New-DeskctlResult $true $null $null 200 @{ hwnd = [string]$Info.Hwnd; title = $Info.Title; fallback = $fallback; covered = $false; verified = [bool]$cover.Checked }
}

# Process name of a window's content (Store apps resolved through ApplicationFrameHost).
function Get-DeskctlWindowProcessName {
    param($Hwnd)
    try {
        $procId = [DeskctlNative]::HostedPid([IntPtr]([long]$Hwnd))
        if ($procId -eq 0) { return '' }
        return ([Diagnostics.Process]::GetProcessById([int]$procId).ProcessName).ToLowerInvariant()
    } catch { return '' }
}

# Shortcuts for open. Windows are matched by process name (and window class), never by title,
# so they work on any Windows display language. --wait <title> still matches by title.
$script:DeskctlOpenAliases = @{
    'chrome'      = @{ path = 'chrome'; procs = @('chrome'); browser = $true }
    'edge'        = @{ path = 'msedge'; procs = @('msedge'); browser = $true }
    'msedge'      = @{ path = 'msedge'; procs = @('msedge'); browser = $true }
    'notepad'     = @{ path = 'notepad'; procs = @('notepad') }
    'calc'        = @{ path = 'calc'; procs = @('calculatorapp', 'calculator') }
    'calculator'  = @{ path = 'calc'; procs = @('calculatorapp', 'calculator') }
    'paint'       = @{ path = 'mspaint'; procs = @('mspaint') }
    'mspaint'     = @{ path = 'mspaint'; procs = @('mspaint') }
    'settings'    = @{ path = 'ms-settings:'; procs = @('systemsettings') }
    'explorer'    = @{ path = 'explorer'; procs = @('explorer'); class = 'CabinetWClass' }
    'word'        = @{ path = 'winword'; procs = @('winword') }
    'winword'     = @{ path = 'winword'; procs = @('winword') }
    'excel'       = @{ path = 'excel'; procs = @('excel') }
}

# Turns an open target into a launch plan. URLs (http(s)://... or a bare domain such as
# x.com/foo) open in Chrome as an argument, which always makes a new tab and never types over
# an existing one.
function ConvertTo-DeskctlOpenPlan {
    param([string]$Target, [string]$Arguments, [string]$WaitTitle)
    $t = $Target.Trim()
    $url = $null
    $title = if ($WaitTitle) { $WaitTitle } else { $null }
    if ($t -match '^(?i)(chrome|edge|about|brave|vivaldi|opera):\S*$') {
        # Browser-internal pages (chrome://settings, edge://flags, about:blank). Never ShellExecute
        # them: Windows would route them elsewhere (chrome://settings opened Windows Settings).
        $proc = if ($t -match '^(?i)edge:') { 'msedge' } else { 'chrome' }
        return @{ Kind = 'internal'; Path = $proc; Args = $null; Procs = @($proc); Class = $null; Browser = $true; Title = $null; Url = $t; Host = '' }
    }
    if ($t -match '^(?i)https?://\S+$') {
        $url = $t
    } elseif ($t -notmatch '[\\\s]' -and $t -notmatch '(?i)\.(exe|lnk|bat|cmd|msc|ps1|txt|pdf|docx?|xlsx?|zip|png|jpe?g)$' -and $t -match '^(?i)(www\.)?[a-z0-9][a-z0-9\-]*(\.[a-z0-9\-]+)*\.[a-z]{2,}(:\d+)?([/?#]\S*)?$') {
        $url = 'https://' + $t
    }
    if ($url) {
        $hostName = ''
        try { $hostName = ([Uri]$url).Host.ToLowerInvariant() -replace '^www\.', '' } catch { }
        return @{ Kind = 'url'; Path = 'chrome'; Args = ('"' + $url.Replace('"', '%22') + '"'); Procs = @('chrome'); Class = $null; Browser = $true; Title = $title; Url = $url; Host = $hostName }
    }
    $alias = $script:DeskctlOpenAliases[($t.ToLowerInvariant() -replace '\.exe$', '')]
    if ($alias) {
        return @{ Kind = 'app'; Path = $alias.path; Args = $Arguments; Procs = $alias.procs; Class = $alias.class; Browser = [bool]$alias.browser; Title = $title; Url = $null; Host = '' }
    }
    $kind = if (Test-DeskctlShellTarget $t) { 'uri' } else { 'app' }
    return @{ Kind = $kind; Path = $t; Args = $Arguments; Procs = $null; Class = $null; Browser = $false; Title = $title; Url = $null; Host = '' }
}

function Test-DeskctlOpenMatch {
    param($Plan, $Window)
    if ($null -eq $Window -or $Window.Cloaked -or [string]::IsNullOrWhiteSpace($Window.Title)) { return $false }
    if ($Plan.Title) { return ($Window.Title.IndexOf($Plan.Title, [StringComparison]::OrdinalIgnoreCase) -ge 0) }
    if ($Plan.Procs) {
        if ((Get-DeskctlWindowProcessName $Window.Hwnd) -notin $Plan.Procs) { return $false }
        if ($Plan.Class -and [DeskctlNative]::ClassOf([IntPtr]([long]$Window.Hwnd)) -ne $Plan.Class) { return $false }
    }
    return $true
}

# open: launch + bring to front + read the window title back. No screenshot, no clicks and no
# real keystrokes: focus uses an F24 tap (unlocks the foreground lock), SetForegroundWindow,
# a thread-input attach to the foreground thread, SetForegroundWindow and a TOPMOST toggle. URLs: done as soon as a Chrome window is in front with the host in its title
# or a changed title; if Chrome was already showing that page, done after ~1.5 s. Shortcuts for
# an app that is already open: reuse its window after 2.5 s. The tray switch is checked every 50 ms.
function Invoke-DeskctlOpen {
    param($Body, $State)
    Initialize-DeskctlNative
    $sw = [Diagnostics.Stopwatch]::StartNew()
    $target = [string](Get-DeskctlBodyValue $Body 'target')
    $plan = ConvertTo-DeskctlOpenPlan $target ([string](Get-DeskctlBodyValue $Body 'args')) ([string](Get-DeskctlBodyValue $Body 'waitTitle'))
    $timeout = 10000
    if ($null -ne (Get-DeskctlBodyValue $Body 'timeoutMs')) { $timeout = [int](Get-DeskctlBodyValue $Body 'timeoutMs') }
    if ($plan.Kind -eq 'internal') { return Invoke-DeskctlOpenInternal $plan $target $timeout $State $sw }

    $before = @{}
    $hadMatch = $false
    foreach ($w in [DeskctlNative]::ListWindows()) {
        if ($w.Cloaked) { continue }
        $before[[string]$w.Hwnd] = $w.Title
        if (-not $hadMatch -and ($plan.Procs -or $plan.Title) -and (Test-DeskctlOpenMatch $plan $w)) { $hadMatch = $true }
    }
    $fgBefore = [DeskctlNative]::GetForegroundWindow().ToInt64()
    $fgBeforeTitle = [string]$before[[string]$fgBefore]

    $launchBody = @{ path = $plan.Path }
    if (-not [string]::IsNullOrWhiteSpace($plan.Args)) { $launchBody.args = $plan.Args }
    $res = Invoke-DeskctlLaunch $launchBody $State
    if (-not $res.Body.ok -and $plan.Kind -eq 'url' -and [string]$res.Body.error -eq 'launch_failed') {
        # No Chrome: the default browser opens the URL (also in a new tab).
        if (-not (Test-DeskctlLive $State)) { return New-DeskctlKillSwitchResult }
        $res = Invoke-DeskctlLaunch @{ path = $plan.Url } $State
        $plan.Procs = $null
        $hadMatch = $false
    }
    $base = @{ target = $target; kind = $plan.Kind; path = $plan.Path }
    if ($plan.Url) { $base.url = $plan.Url }
    if (-not $res.Body.ok) {
        foreach ($k in $base.Keys) { $res.Body[$k] = $base[$k] }
        $res.Body.elapsedMs = [int]$sw.ElapsedMilliseconds
        return $res
    }

    $reuseAfter = if ($plan.Kind -eq 'url' -and $hadMatch) { 1500 } elseif ($hadMatch) { 2500 } else { $timeout }
    $hostLabel = $null
    if ($plan.Host) {
        $hostLabel = $plan.Host
        $first = $plan.Host.Split('.')[0]
        if ($first.Length -ge 4) { $hostLabel = $first }
    }
    $found = $null
    $how = $null
    $nextScan = 0
    while ($true) {
        if (-not (Test-DeskctlLive $State)) { return New-DeskctlKillSwitchResult }
        $elapsed = [int]$sw.ElapsedMilliseconds
        $fg = [DeskctlNative]::Describe([DeskctlNative]::GetForegroundWindow())
        if ($fg -and -not [DeskctlNative]::IsWindowVisible([IntPtr]([long]$fg.Hwnd))) { $fg = $null }
        if ($fg -and (Test-DeskctlOpenMatch $plan $fg)) {
            $isNew = -not $before.ContainsKey([string]$fg.Hwnd)
            if ($hostLabel -and $fg.Title.IndexOf($hostLabel, [StringComparison]::OrdinalIgnoreCase) -ge 0) { $found = $fg; $how = 'host'; break }
            if ($isNew) { $found = $fg; $how = 'new'; break }
            if ($fg.Hwnd -ne $fgBefore -or $fg.Title -ne $fgBeforeTitle) { $found = $fg; $how = 'changed'; break }
            if ($elapsed -ge $reuseAfter -and ($plan.Procs -or $plan.Title)) { $found = $fg; $how = 'reused'; break }
        }
        if ($elapsed -ge $nextScan) {
            $nextScan = $elapsed + 200
            $best = $null
            foreach ($w in [DeskctlNative]::ListWindows()) {
                if (-not (Test-DeskctlOpenMatch $plan $w)) { continue }
                if (-not $before.ContainsKey([string]$w.Hwnd)) { $found = $w; $how = 'new'; break }
                if ($null -eq $best -or ($best.Minimized -and -not $w.Minimized)) { $best = $w }
            }
            if ($found) { break }
            if ($elapsed -ge $reuseAfter -and $best -and ($plan.Procs -or $plan.Title)) { $found = $best; $how = 'reused'; break }
        }
        if ($elapsed -ge $timeout) { break }
        if (-not (Wait-DeskctlInterval $State 50)) { return New-DeskctlKillSwitchResult }
    }
    if ($null -eq $found) {
        $data = @{ pid = $res.Body.pid; method = $res.Body.method; elapsedMs = [int]$sw.ElapsedMilliseconds }
        foreach ($k in $base.Keys) { $data[$k] = $base[$k] }
        return New-DeskctlResult $false 'no_window' "Opened '$target' but no matching window came up. Pass --wait <title> or take a screenshot." 408 $data
    }

    $focus = $null
    if ([DeskctlNative]::GetForegroundWindow().ToInt64() -ne $found.Hwnd) {
        if (-not (Test-DeskctlLive $State)) { return New-DeskctlKillSwitchResult }
        $focus = Invoke-DeskctlFocusWindow $found $State -NoInput
        if (-not $focus.Body.ok -and -not $plan.Browser) {
            # Apps only (never a browser): the regular helper may use the Alt tap / title-bar click.
            if (-not (Test-DeskctlLive $State)) { return New-DeskctlKillSwitchResult }
            $focus = Invoke-DeskctlFocusWindow $found $State
        }
        if (-not $focus.Body.ok) {
            foreach ($k in $base.Keys) { $focus.Body[$k] = $base[$k] }
            $focus.Body.elapsedMs = [int]$sw.ElapsedMilliseconds
            return $focus
        }
    }

    # A brand-new app window may still be setting its title: wait up to 400 ms for it to settle.
    $h = [IntPtr]([long]$found.Hwnd)
    if ($how -eq 'new' -and $plan.Kind -ne 'url') {
        $settle = [Diagnostics.Stopwatch]::StartNew()
        $last = $found.Title
        $stableSince = 0
        while ($settle.ElapsedMilliseconds -lt 400) {
            if (-not (Wait-DeskctlInterval $State 50)) { return New-DeskctlKillSwitchResult }
            $now = [DeskctlNative]::Describe($h)
            if ($null -eq $now) { break }
            if ($now.Title -ne $last) { $last = $now.Title; $stableSince = [int]$settle.ElapsedMilliseconds }
            elseif (([int]$settle.ElapsedMilliseconds - $stableSince) -ge 150) { break }
        }
    }
    $final = [DeskctlNative]::Describe($h)
    if ($null -eq $final) { $final = $found }
    $cover = [DeskctlNative]::CheckCovered($h)
    $data = @{
        hwnd       = [string]$final.Hwnd
        title      = $final.Title
        process    = (Get-DeskctlWindowProcessName $final.Hwnd)
        windowPid  = [int]$final.Pid
        pid        = $res.Body.pid
        method     = $res.Body.method
        match      = $how
        titleBefore = $(if ($before.ContainsKey([string]$final.Hwnd)) { [string]$before[[string]$final.Hwnd] } else { $null })
        reused     = (-not ($how -eq 'new'))
        newWindow  = ($how -eq 'new')
        foreground = ([DeskctlNative]::GetForegroundWindow().ToInt64() -eq $final.Hwnd)
        covered    = [bool]$cover.Covered
        focused    = ($null -ne $focus)
        input      = $false
        elapsedMs  = [int]$sw.ElapsedMilliseconds
    }
    if ($focus -and $focus.Body.fallback) { $data.input = $true }
    if ($cover.Covered) { $data.coveredBy = ConvertTo-DeskctlCoverData $cover }
    foreach ($k in $base.Keys) { $data[$k] = $base[$k] }
    return New-DeskctlResult $true $null $null 200 $data
}

# Waits for a window that matches the plan (by process) and returns it, or $null. Kill switch aware.
function Wait-DeskctlOpenWindow {
    param($Plan, [int]$TimeoutMs, $State, [hashtable]$Before)
    $sw = [Diagnostics.Stopwatch]::StartNew()
    while ($true) {
        $best = $null
        foreach ($w in [DeskctlNative]::ListWindows()) {
            if (-not (Test-DeskctlOpenMatch $Plan $w)) { continue }
            if ($Before -and $Before.ContainsKey([string]$w.Hwnd)) { if (-not $best) { $best = $w }; continue }
            return $w
        }
        if (-not $Before -and $best) { return $best }
        if ($Before -and $best -and $sw.ElapsedMilliseconds -ge 1500) { return $best }
        if ($sw.ElapsedMilliseconds -ge $TimeoutMs) { return $null }
        if (-not (Wait-DeskctlInterval $State 100)) { return 'off' }
    }
}

# chrome://, edge://, about: pages. Chrome ignores chrome:// URLs passed on its command line (a
# security rule), and ShellExecute sends them to whatever owns the scheme, so: bring the
# browser window to the front without input, Ctrl+T, verify that a new tab took the
# foreground (same browser window, title changed), and only then type the URL + Enter.
# If the new tab can't be verified nothing is typed, so an open tab is never typed over.
function Invoke-DeskctlOpenInternal {
    param($Plan, [string]$Target, [int]$Timeout, $State, $Sw)
    $base = @{ target = $Target; kind = 'internal'; path = $Plan.Path; url = $Plan.Url }
    function Fail-Open($code, $msg, $status, $extra) {
        $d = @{ elapsedMs = [int]$Sw.ElapsedMilliseconds }
        foreach ($k in $base.Keys) { $d[$k] = $base[$k] }
        if ($extra) { foreach ($k in $extra.Keys) { $d[$k] = $extra[$k] } }
        return New-DeskctlResult $false $code $msg $status $d
    }
    $win = Wait-DeskctlOpenWindow $Plan 0 $State $null
    $launched = $false
    if ($null -eq $win) {
        $before = @{}
        foreach ($w in [DeskctlNative]::ListWindows()) { $before[[string]$w.Hwnd] = $w.Title }
        $res = Invoke-DeskctlLaunch @{ path = $Plan.Path } $State
        if (-not $res.Body.ok) { foreach ($k in $base.Keys) { $res.Body[$k] = $base[$k] }; return $res }
        $launched = $true
        $win = Wait-DeskctlOpenWindow $Plan $Timeout $State $before
    }
    if ($win -eq 'off') { return New-DeskctlKillSwitchResult }
    if ($null -eq $win) { return (Fail-Open 'no_window' "No $($Plan.Path) window to open '$Target' in." 408 $null) }
    if (-not (Test-DeskctlLive $State)) { return New-DeskctlKillSwitchResult }

    $h = [IntPtr]([long]$win.Hwnd)
    if ([DeskctlNative]::GetForegroundWindow() -ne $h) {
        $focus = Invoke-DeskctlFocusWindow $win $State -NoInput
        if (-not $focus.Body.ok) { foreach ($k in $base.Keys) { $focus.Body[$k] = $base[$k] }; return $focus }
    }
    if ([DeskctlNative]::GetForegroundWindow() -ne $h) {
        return (Fail-Open 'focus_failed' 'The browser window is not in front; nothing was typed.' 403 @{ hwnd = [string]$win.Hwnd })
    }
    $titleBefore = ([DeskctlNative]::Describe($h)).Title
    if (-not (Test-DeskctlLive $State)) { return New-DeskctlKillSwitchResult }
    $k = Invoke-DeskctlKey @{ combo = 'ctrl+t' } $State
    if (-not $k.Body.ok) { return $k }

    # New tab check: same browser process in front and a different title.
    $newTab = $null
    $check = [Diagnostics.Stopwatch]::StartNew()
    while ($check.ElapsedMilliseconds -lt 1500) {
        if (-not (Wait-DeskctlInterval $State 50)) { return New-DeskctlKillSwitchResult }
        $fg = [DeskctlNative]::Describe([DeskctlNative]::GetForegroundWindow())
        if ($fg -and (Get-DeskctlWindowProcessName $fg.Hwnd) -in $Plan.Procs -and $fg.Title -ne $titleBefore) { $newTab = $fg; break }
    }
    if ($null -eq $newTab) {
        return (Fail-Open 'new_tab_unverified' 'Sent Ctrl+T but could not verify a new tab (the title did not change); nothing was typed. If the current tab is already a new tab, type the URL there by hand or retry.' 409 @{ hwnd = [string]$win.Hwnd; title = $titleBefore })
    }
    if (-not (Test-DeskctlLive $State)) { return New-DeskctlKillSwitchResult }
    $typed = Invoke-DeskctlType @{ text = $Plan.Url } $State
    if (-not $typed.Body.ok) { return $typed }
    if (-not (Test-DeskctlLive $State)) { return New-DeskctlKillSwitchResult }
    $k = Invoke-DeskctlKey @{ combo = 'enter' } $State
    if (-not $k.Body.ok) { return $k }

    $nh = [IntPtr]([long]$newTab.Hwnd)
    $tabTitle = $newTab.Title
    $settle = [Diagnostics.Stopwatch]::StartNew()
    while ($settle.ElapsedMilliseconds -lt 1500) {
        if (-not (Wait-DeskctlInterval $State 50)) { return New-DeskctlKillSwitchResult }
        $now = [DeskctlNative]::Describe($nh)
        if ($null -eq $now -or $now.Title -ne $tabTitle) { break }
    }
    $final = [DeskctlNative]::Describe($nh)
    if ($null -eq $final) { $final = $newTab }
    $data = @{
        hwnd       = [string]$final.Hwnd
        title      = $final.Title
        process    = (Get-DeskctlWindowProcessName $final.Hwnd)
        match      = 'ctrl+t'
        newTab     = $true
        newWindow  = $launched
        reused     = (-not $launched)
        foreground = ([DeskctlNative]::GetForegroundWindow().ToInt64() -eq $final.Hwnd)
        input      = $true
        elapsedMs  = [int]$Sw.ElapsedMilliseconds
    }
    foreach ($key in $base.Keys) { $data[$key] = $base[$key] }
    return New-DeskctlResult $true $null $null 200 $data
}

# Post-install self test. Exact note text, LF line endings (typed as Enter).
$script:DeskctlSelftestNote = @'
WinDesk Bot was installed successfully!

This test just opened x.com in Chrome, solved 2 + 2 on the Calculator, and wrote this note.

What's next:
- Ask your bot to do anything on your PC, for example "open Excel" or "take a screenshot".
- Two ways to work: say "auto mode" for fast runs with no screenshots, or "manual mode" to have it check each step with a screenshot. Manual is the default.
- Turn control on and off anytime from the tray icon.

You can close this note without saving.

Made by @nachomon
'@

# selftest: Chrome on x.com, Calculator 2+2=, a NEW Notepad note with the welcome text.
# Each step must pass before the next one runs; it stops at the first failure and never types
# unless the expected window (by process and hwnd) is in front. Kill switch checked between steps.
function Invoke-DeskctlSelftest {
    param($Body, $State)
    Initialize-DeskctlNative
    $total = [Diagnostics.Stopwatch]::StartNew()
    $steps = New-Object Collections.ArrayList
    $note = $script:DeskctlSelftestNote -replace "`r`n", "`n"

    function Add-Step([string]$Name, [bool]$Ok, [int]$Ms, [hashtable]$Data, [string]$Why) {
        $e = [ordered]@{ step = $Name; ok = $Ok; ms = $Ms }
        if ($Why) { $e.error = $Why }
        if ($Data) { foreach ($k in $Data.Keys) { $e[$k] = $Data[$k] } }
        [void]$steps.Add($e)
    }
    function Done([bool]$Ok, [string]$Code, [string]$Msg) {
        $data = @{ steps = $steps; elapsedMs = [int]$total.ElapsedMilliseconds; passed = @($steps | Where-Object { $_.ok }).Count; total = 4 }
        if ($Ok) { return New-DeskctlResult $true $null $null 200 $data }
        return New-DeskctlResult $false $Code $Msg 200 $data
    }
    function Test-Front($Hwnd) { return ([DeskctlNative]::GetForegroundWindow().ToInt64() -eq [long]$Hwnd) }

    # a. Chrome on x.com
    if (-not (Test-DeskctlLive $State)) { return New-DeskctlKillSwitchResult }
    $sw = [Diagnostics.Stopwatch]::StartNew()
    $r = (Invoke-DeskctlOpen @{ target = 'x.com' } $State).Body
    $ok = [bool]($r.ok -and $r.foreground -and $r.process -eq 'chrome')
    Add-Step 'chrome' $ok ([int]$sw.ElapsedMilliseconds) @{ hwnd = $r.hwnd; title = $r.title; match = $r.match } $(if (-not $ok) { [string]$(if ($r.error) { $r.error } else { 'not_in_front' }) })
    if (-not $ok) { return (Done $false 'selftest_failed' 'Step chrome failed.') }

    # b. Calculator: Escape, then 2+2=
    if (-not (Test-DeskctlLive $State)) { return New-DeskctlKillSwitchResult }
    $sw.Restart()
    $r = (Invoke-DeskctlOpen @{ target = 'calc' } $State).Body
    $ok = [bool]($r.ok -and $r.foreground -and $r.process -in @('calculatorapp', 'calculator'))
    $why = $null
    $shot = $null
    if ($ok) {
        $calc = $r.hwnd
        if (-not (Test-DeskctlLive $State)) { return New-DeskctlKillSwitchResult }
        if (-not (Test-Front $calc)) { $ok = $false; $why = 'not_in_front' }
        else {
            $k = (Invoke-DeskctlKey @{ combo = 'esc' } $State).Body
            if (-not $k.ok) { $ok = $false; $why = [string]$k.error }
        }
        if ($ok) {
            if (-not (Test-DeskctlLive $State)) { return New-DeskctlKillSwitchResult }
            if (-not (Test-Front $calc)) { $ok = $false; $why = 'not_in_front' }
            else {
                $t = (Invoke-DeskctlType @{ text = '2+2=' } $State).Body
                if (-not $t.ok) { $ok = $false; $why = [string]$t.error }
            }
        }
        if ($ok) {
            if (-not (Wait-DeskctlInterval $State 250)) { return New-DeskctlKillSwitchResult }
            $shot = (Invoke-DeskctlScreenshot @{} $State).Body
        }
    } else { $why = [string]$(if ($r.error) { $r.error } else { 'not_calculator' }) }
    Add-Step 'calculator' $ok ([int]$sw.ElapsedMilliseconds) @{ hwnd = $r.hwnd; title = $r.title; process = $r.process; screenshot = $(if ($shot) { $shot.path } else { $null }) } $why
    if (-not $ok) { return (Done $false 'selftest_failed' 'Step calculator failed.') }

    # c. Notepad: must be a new window, or a new tab (same Notepad window whose title changed
    # right after launch), never an existing or modified note.
    if (-not (Test-DeskctlLive $State)) { return New-DeskctlKillSwitchResult }
    $sw.Restart()
    $r = (Invoke-DeskctlOpen @{ target = 'notepad' } $State).Body
    # New tab = the same Notepad window now shows a different title than before the launch.
    $fresh = [bool]($r.newWindow -or ($null -ne $r.titleBefore -and [string]$r.title -ne [string]$r.titleBefore))
    $ok = [bool]($r.ok -and $r.foreground -and $r.process -eq 'notepad' -and $fresh -and -not ([string]$r.title).StartsWith('*'))
    $why = $null
    if (-not $ok) {
        $why = if (-not $r.ok) { [string]$r.error } elseif ($r.process -ne 'notepad') { 'not_notepad' } elseif (-not $fresh) { 'not_a_new_note' } elseif (([string]$r.title).StartsWith('*')) { 'note_has_changes' } else { 'not_in_front' }
    }
    Add-Step 'notepad' $ok ([int]$sw.ElapsedMilliseconds) @{ hwnd = $r.hwnd; title = $r.title; newWindow = [bool]$r.newWindow; newTab = [bool](-not $r.newWindow -and $fresh) } $why
    if (-not $ok) { return (Done $false 'selftest_failed' 'Step notepad failed; nothing was typed.') }
    $pad = $r.hwnd

    # d. Type the welcome note.
    if (-not (Test-DeskctlLive $State)) { return New-DeskctlKillSwitchResult }
    $sw.Restart()
    $ok = $true
    $why = $null
    $shot = $null
    $typed = 0
    $clip = $null
    if (-not (Test-Front $pad)) { $ok = $false; $why = 'not_in_front' }
    else {
        $t = (Invoke-DeskctlType @{ text = $note; paste = $true } $State).Body
        $typed = [int]$t.characters
        $clip = $t.clipboard
        if (-not $t.ok) { $ok = $false; $why = [string]$t.error }
    }
    # Verify: Notepad titles an unsaved note with (a cut of) its first line.
    $first = ($note -split "`n")[0]
    $title = $null
    if ($ok) {
        $verify = [Diagnostics.Stopwatch]::StartNew()
        $verified = $false
        while ($verify.ElapsedMilliseconds -lt 2000) {
            $w = [DeskctlNative]::Describe([IntPtr]([long]$pad))
            if ($w) { $title = $w.Title }
            if ($title) {
                # Language-independent: "*<first line><sep><app name>", where sep is ' - ' or ': '
                # (e.g. ': Bloc de notas'). Win11 Notepad cuts the first line with no ellipsis.
                $core = $title.TrimStart('*')
                $cut = [Math]::Max($core.LastIndexOf(' - '), $core.LastIndexOf(': '))
                if ($cut -ge 0) { $core = $core.Substring(0, $cut) }
                if ($core.Length -ge 20 -and $first.StartsWith($core, [StringComparison]::Ordinal)) { $verified = $true; break }
            }
            if (-not (Wait-DeskctlInterval $State 100)) { return New-DeskctlKillSwitchResult }
        }
        if (-not $verified) { $ok = $false; $why = 'note_not_verified' }
        $shot = (Invoke-DeskctlScreenshot @{} $State).Body
    }
    Add-Step 'note' $ok ([int]$sw.ElapsedMilliseconds) @{ hwnd = $pad; method = 'paste'; characters = $typed; total = $note.Length; title = $title; expectedTitleStart = $first; clipboard = $clip; screenshot = $(if ($shot) { $shot.path } else { $null }) } $why
    if (-not $ok) { return (Done $false 'selftest_failed' 'Step note failed.') }
    return (Done $true $null $null)
}
