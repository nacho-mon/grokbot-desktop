#requires -Version 5.1
param(
    [switch]$Headless,
    [switch]$TestEnable,
    [string]$HostName = '127.0.0.1'
)

$ErrorActionPreference = 'Stop'
try { $Host.UI.RawUI.WindowTitle = 'Grok Bot Desktop' } catch { }
. (Join-Path $PSScriptRoot 'Deskctl.Security.ps1')
. (Join-Path $PSScriptRoot 'Deskctl.Keys.ps1')
. (Join-Path $PSScriptRoot 'Deskctl.Protocol.ps1')
. (Join-Path $PSScriptRoot 'Deskctl.Win32.ps1')

if (-not (Test-DeskctlLoopback $HostName)) {
    Write-Error 'Grok Bot Desktop only listens on 127.0.0.1.'
    exit 1
}

$isWin = Test-DeskctlIsWindows
if (-not $Headless -and -not $isWin) {
    Write-Error 'The Grok Bot Desktop tray requires Windows.'
    exit 1
}

# Self-relaunch in STA when the tray UI is needed.
if ($isWin -and -not $Headless -and [Threading.Thread]::CurrentThread.GetApartmentState() -ne 'STA') {
    $pass = @('-NoProfile', '-STA', '-ExecutionPolicy', 'Bypass', '-File', $MyInvocation.MyCommand.Path)
    if ($TestEnable) { $pass += '-TestEnable' }
    if ($HostName -and $HostName -ne '127.0.0.1') { $pass += @('-HostName', $HostName) }
    & powershell.exe @pass
    exit $LASTEXITCODE
}

function Read-DeskctlHttpRequest {
    param(
        $Client,
        $Stream,
        [int]$HeaderTimeoutMs = 2000,
        [int]$MaxHeader = 16384,
        [int]$MaxBody = 1048576
    )
    $headerBytes = New-Object Collections.Generic.List[byte]
    $sw = [Diagnostics.Stopwatch]::StartNew()
    while ($sw.ElapsedMilliseconds -lt $HeaderTimeoutMs -and $headerBytes.Count -lt $MaxHeader) {
        while ($Client.Available -gt 0 -and $headerBytes.Count -lt $MaxHeader) {
            $one = $Stream.ReadByte()
            if ($one -lt 0) { break }
            $headerBytes.Add([byte]$one)
            if ($headerBytes.Count -ge 4) {
                $n = $headerBytes.Count
                if ($headerBytes[$n - 4] -eq 13 -and $headerBytes[$n - 3] -eq 10 -and $headerBytes[$n - 2] -eq 13 -and $headerBytes[$n - 1] -eq 10) {
                    break
                }
            }
        }
        $n = $headerBytes.Count
        if ($n -ge 4 -and $headerBytes[$n - 4] -eq 13 -and $headerBytes[$n - 3] -eq 10 -and $headerBytes[$n - 2] -eq 13 -and $headerBytes[$n - 1] -eq 10) {
            break
        }
        Start-Sleep -Milliseconds 15
    }
    if ($headerBytes.Count -eq 0) { return $null }

    $headerText = [Text.Encoding]::ASCII.GetString($headerBytes.ToArray())
    $lines = $headerText -split "`r`n"
    if (-not $lines -or -not $lines[0]) { return $null }
    $bits = $lines[0].Split(' ')
    if ($bits.Count -lt 2) { return $null }
    $method = $bits[0]
    $url = $bits[1]
    $path = ([Uri]('http://127.0.0.1' + $url)).AbsolutePath

    $headers = @{}
    foreach ($line in ($lines | Select-Object -Skip 1)) {
        if ([string]::IsNullOrWhiteSpace($line)) { continue }
        $colon = $line.IndexOf(':')
        if ($colon -gt 0) {
            $headers[$line.Substring(0, $colon).Trim().ToLowerInvariant()] = $line.Substring($colon + 1).Trim()
        }
    }

    $length = 0
    if ($headers.ContainsKey('content-length')) {
        [void][int]::TryParse($headers['content-length'], [ref]$length)
    }
    if ($length -gt $MaxBody) {
        return @{ Method = $method; Path = $path; Headers = $headers; TooLarge = $true }
    }

    $bodyText = ''
    if ($length -gt 0) {
        $buf = New-Object byte[] $length
        $got = 0
        $sw.Restart()
        while ($got -lt $length -and $sw.ElapsedMilliseconds -lt 5000) {
            if ($Client.Available -le 0) {
                Start-Sleep -Milliseconds 15
                continue
            }
            $n = $Stream.Read($buf, $got, $length - $got)
            if ($n -le 0) { break }
            $got += $n
        }
        $bodyText = [Text.Encoding]::UTF8.GetString($buf, 0, $got)
    }

    return @{ Method = $method; Path = $path; Headers = $headers; BodyText = $bodyText; TooLarge = $false }
}

function Write-DeskctlHttpResponse {
    param($Stream, $Result)
    $json = ConvertTo-Json -InputObject $Result.Body -Depth 8 -Compress
    $bytes = [Text.Encoding]::UTF8.GetBytes($json)
    $reason = 'OK'
    switch ($Result.Status) {
        400 { $reason = 'Bad Request' }
        401 { $reason = 'Unauthorized' }
        403 { $reason = 'Forbidden' }
        404 { $reason = 'Not Found' }
        405 { $reason = 'Method Not Allowed' }
        408 { $reason = 'Request Timeout' }
        413 { $reason = 'Payload Too Large' }
        501 { $reason = 'Not Implemented' }
        default { if ($Result.Status -ge 500) { $reason = 'Server Error' } }
    }
    $head = [Text.Encoding]::ASCII.GetBytes(("HTTP/1.1 {0} {1}`r`nContent-Type: application/json; charset=utf-8`r`nContent-Length: {2}`r`nConnection: close`r`n`r`n" -f $Result.Status, $reason, $bytes.Length))
    $Stream.Write($head, 0, $head.Length)
    $Stream.Write($bytes, 0, $bytes.Length)
}

function Get-DeskctlRequestToken {
    param($Headers)
    if ($Headers.authorization -match '^Bearer\s+(.+)$') { return $Matches[1].Trim() }
    if ($Headers.ContainsKey('x-deskctl-token')) { return $Headers['x-deskctl-token'] }
    return $null
}

$homeDir = Get-DeskctlHome
$token = Ensure-DeskctlToken $homeDir
$mutex = $null
$listener = $null
$icon = $null
$iconHandle = [IntPtr]::Zero
$script:ProductIcon = $null
if ($isWin) {
    try {
        Add-Type -AssemblyName System.Drawing
        $iconCandidates = @(
            (Join-Path (Get-DeskctlHome) 'grokbot-desktop.ico'),
            (Join-Path (Split-Path -Parent $PSScriptRoot) 'grokbot-desktop.ico')
        ) | Select-Object -Unique
        $productIconPath = $iconCandidates | Where-Object { Test-Path -LiteralPath $_ } | Select-Object -First 1
        if (-not $productIconPath) {
            $target = Join-Path (Get-DeskctlHome) 'grokbot-desktop.ico'
            if (Save-GrokBotDesktopIcon -IconPath $target) { $productIconPath = $target }
        }
        if ($productIconPath) { $script:ProductIcon = [Drawing.Icon]::new($productIconPath) }
    } catch { $script:ProductIcon = $null }
}
$form = $null
$gotMutex = $false

if ($isWin) {
    $mutexId = [Security.Principal.WindowsIdentity]::GetCurrent().User.Value
} else {
    $mutexId = [Environment]::UserName
}
$safeId = $mutexId -replace '[^A-Za-z0-9]', '_'
$mutex = New-Object Threading.Mutex($false, "Local\GrokBotDesktop-$safeId")
if (-not $mutex.WaitOne(0)) {
    [Console]::Out.WriteLine('{"ok":false,"error":"already_running","message":"Grok Bot Desktop is already running."}')
    $mutex.Dispose()
    exit 1
}
$gotMutex = $true
if ($env:LOCALAPPDATA) { Stop-GrokBotDesktopPidFile (Join-Path $env:LOCALAPPDATA 'deskctl\pid') }

# Enabled is never persisted. -TestEnable is only honored with DESKCTL_TEST=1 and never on Windows (tray is the only switch).
$script:enabled = [bool]($Headless -and $TestEnable -and $env:DESKCTL_TEST -eq '1' -and -not $isWin)
$script:quit = $false
$state = @{
    Port       = 0
    Dpi        = 'unknown'
    Virtual    = @{ x = 0; y = 0; width = 0; height = 0 }
    Monitors   = @()
    LastShot   = $null
    PrimaryDpi = 96
    # Long requests (batch, wait, launch, type) re-check the tray switch between steps.
    IsEnabled  = { [bool]($script:enabled -and -not $script:quit) }
    Pump       = $null
}
if ($isWin -and -not $Headless) {
    # Lets the tray menu (Turn off) run while a long request is in progress.
    $state.Pump = { [Windows.Forms.Application]::DoEvents() }
}
$script:inRequest = $false

function Update-DeskctlTrayIcon {
    param($NotifyIcon)
    if (-not $NotifyIcon) { return }
    $bmp = New-Object Drawing.Bitmap 32, 32, ([Drawing.Imaging.PixelFormat]::Format32bppArgb)
    $graphics = [Drawing.Graphics]::FromImage($bmp)
    $font = New-Object Drawing.Font 'Arial', 11, ([Drawing.FontStyle]::Bold)
    $format = New-Object Drawing.StringFormat
    try {
        $graphics.SmoothingMode = [Drawing.Drawing2D.SmoothingMode]::AntiAlias
        $graphics.Clear([Drawing.Color]::Transparent)
        if ($script:ProductIcon) {
            $graphics.DrawIcon($script:ProductIcon, (New-Object Drawing.Rectangle(0, 0, 32, 32)))
            if ($script:enabled) {
                $pen = New-Object Drawing.Pen([Drawing.Color]::Red, 3)
                $graphics.DrawEllipse($pen, 2, 2, 28, 28)
                $graphics.FillEllipse([Drawing.Brushes]::Red, 21, 2, 9, 9)
                $pen.Dispose()
            }
        } else {
            $graphics.Clear($(if ($script:enabled) { [Drawing.Color]::Red } else { [Drawing.Color]::DimGray }))
        }
        $format.Alignment = [Drawing.StringAlignment]::Center
        $format.LineAlignment = [Drawing.StringAlignment]::Center
        $label = if ($script:enabled) { 'ON' } else { 'OFF' }
        if (-not $script:ProductIcon) { $graphics.DrawString($label, $font, [Drawing.Brushes]::White, (New-Object Drawing.RectangleF(0, 0, 32, 32)), $format) }
        $handle = $bmp.GetHicon()
        $newIcon = [Drawing.Icon]::FromHandle($handle)
        $old = $NotifyIcon.Icon
        $oldHandle = $script:iconHandle
        $NotifyIcon.Icon = $newIcon
        $NotifyIcon.Text = "Grok Bot Desktop ($(if ($script:enabled) { 'on' } else { 'off' }))"
        $script:iconHandle = $handle
        if ($old) { $old.Dispose() }
        if ($oldHandle -ne [IntPtr]::Zero) {
            try { [void][DeskctlNative]::DestroyIcon($oldHandle) } catch { }
        }
    } finally {
        $graphics.Dispose()
        $font.Dispose()
        $format.Dispose()
        $bmp.Dispose()
    }
}

try {
    if ($isWin) {
        try {
            Initialize-DeskctlNative
            $dpiName = 'PerMonitorV2'
            try {
                $ok = [DeskctlNative]::SetProcessDpiAwarenessContext([IntPtr](-4))
                if (-not $ok) { throw 'dpi_context_failed' }
            } catch {
                try {
                    $null = [DeskctlNative]::SetProcessDpiAwareness(2)
                    $dpiName = 'PerMonitor'
                } catch {
                    $dpiName = 'unavailable'
                }
            }
            $state.Dpi = $dpiName
            Add-Type -AssemblyName System.Windows.Forms
            Add-Type -AssemblyName System.Drawing
            $v = [Windows.Forms.SystemInformation]::VirtualScreen
            $state.Virtual = @{ x = $v.X; y = $v.Y; width = $v.Width; height = $v.Height }
            $i = 0
            $state.Monitors = @([Windows.Forms.Screen]::AllScreens | ForEach-Object {
                $b = $_.Bounds
                $dx = 96
                try { $dx = [DeskctlNative]::DpiAt([int]($b.X + $b.Width / 2), [int]($b.Y + $b.Height / 2)) } catch { }
                $item = @{
                    index   = $i
                    primary = $_.Primary
                    x       = $b.X
                    y       = $b.Y
                    width   = $b.Width
                    height  = $b.Height
                    dpi     = [int]$dx
                    scale   = ([int]$dx / 96.0)
                    name    = $_.DeviceName
                }
                $i++
                $item
            })
            $primary = $state.Monitors | Where-Object { $_.primary } | Select-Object -First 1
            if ($primary) { $state.PrimaryDpi = $primary.dpi }
        } catch {
            $state.Dpi = 'unavailable'
        }
    }

    $ip = [Net.IPAddress]::Loopback
    $bound = $false
    for ($attempt = 0; $attempt -lt 64 -and -not $bound; $attempt++) {
        $candidate = Get-Random -Minimum 49152 -Maximum 65536
        try {
            $listener = New-Object Net.Sockets.TcpListener($ip, $candidate)
            $listener.Start()
            $ep = $listener.LocalEndpoint
            if (-not $ep.Address.Equals([Net.IPAddress]::Loopback)) { throw 'bind_not_loopback' }
            $state.Port = $ep.Port
            $bound = $true
        } catch {
            if ($listener) { try { $listener.Stop() } catch { } }
            $listener = $null
        }
    }
    if (-not $bound) { throw 'Could not open a port on 127.0.0.1.' }

    Write-DeskctlUserFile (Join-Path $homeDir 'port') ([string]$state.Port)
    Write-DeskctlUserFile (Join-Path $homeDir 'pid') ([string]$PID)
    [Console]::Out.WriteLine("Grok Bot Desktop escuchando en 127.0.0.1:$($state.Port)")

    function Invoke-DeskctlPending {
        # Pump in long requests can re-enter the timer tick; serve one request at a time.
        if ($script:inRequest) { return }
        if (-not $listener -or -not $listener.Pending()) { return }
        $script:inRequest = $true
        try {
            Invoke-DeskctlClient
        } finally {
            $script:inRequest = $false
        }
    }

    function Invoke-DeskctlClient {
        $client = $listener.AcceptTcpClient()
        $client.ReceiveTimeout = 2000
        $client.SendTimeout = 2000
        try {
            $stream = $client.GetStream()
            $req = Read-DeskctlHttpRequest -Client $client -Stream $stream
            if ($null -eq $req) { return }
            $auth = Get-DeskctlRequestToken $req.Headers
            if (-not (Test-DeskctlToken $token $auth)) {
                $res = New-DeskctlResult $false 'unauthorized' 'Missing or invalid token.' 401
            } elseif ($req.TooLarge) {
                $res = New-DeskctlResult $false 'body_too_large' 'El cuerpo supera 1 MiB.' 413
            } else {
                try {
                    $body = ConvertFrom-DeskctlJson $req.BodyText
                    $res = Resolve-DeskctlRoute $req.Method $req.Path $body $script:enabled $isWin $state
                } catch {
                    $res = New-DeskctlResult $false 'invalid_json' 'Invalid JSON.' 400
                }
            }
            if ($env:DESKCTL_TEST -eq '1' -and $req.Path -eq '/__test/shutdown' -and $req.Method -eq 'POST' -and (Test-DeskctlToken $token $auth)) {
                $res = New-DeskctlResult $true $null $null 200 @{}
                $script:quit = $true
            }
            Write-DeskctlHttpResponse $stream $res
        } catch {
            # Drop the connection rather than crash the tray.
        } finally {
            $client.Close()
        }
    }

    if (-not $Headless) {
        $menu = New-Object Windows.Forms.ContextMenuStrip
        $onItem = $menu.Items.Add('Turn on')
        $offItem = $menu.Items.Add('Turn off')
        $statusItem = $menu.Items.Add('Status')
        [void]$menu.Items.Add('-')
        $exitItem = $menu.Items.Add('Exit')

        $icon = New-Object Windows.Forms.NotifyIcon
        $icon.Visible = $false
        $icon.ContextMenuStrip = $menu
        $icon.Text = 'Grok Bot Desktop (off)'

        $refreshMenu = {
            $onItem.Enabled = -not $script:enabled
            $offItem.Enabled = $script:enabled
            Update-DeskctlTrayIcon $icon
        }

        $onItem.add_Click({
            if (-not $script:enabled) {
                $script:enabled = $true
                & $refreshMenu
                $icon.ShowBalloonTip(4000, 'Grok Bot Desktop', 'Grok Bot Desktop is on: it can see and control the screen.', [Windows.Forms.ToolTipIcon]::Warning)
            }
        })
        $offItem.add_Click({
            if ($script:enabled) {
                $script:enabled = $false
                & $refreshMenu
                $icon.ShowBalloonTip(3000, 'Grok Bot Desktop', 'Grok Bot Desktop is off.', [Windows.Forms.ToolTipIcon]::Info)
            }
        })
        $statusItem.add_Click({
            $text = "Grok Bot Desktop is $(if ($script:enabled) { 'ON' } else { 'off' }). Local port: $($state.Port)"
            [void][Windows.Forms.MessageBox]::Show($text, 'Grok Bot Desktop')
        })
        $exitItem.add_Click({ $script:quit = $true; if ($form) { $form.Close() } })
        $icon.add_MouseUp({
            if ($_.Button -eq [Windows.Forms.MouseButtons]::Left) {
                $menu.Show([Windows.Forms.Cursor]::Position)
            }
        })

        & $refreshMenu
        $icon.Visible = $true

        $form = New-Object Windows.Forms.Form
        $form.WindowState = [Windows.Forms.FormWindowState]::Minimized
        $form.ShowInTaskbar = $false
        $form.FormBorderStyle = [Windows.Forms.FormBorderStyle]::FixedToolWindow
        $form.Opacity = 0
        $form.Size = New-Object Drawing.Size 0, 0
        $form.add_Shown({ $form.Hide() })
        $form.add_FormClosing({ $script:quit = $true })

        $timer = New-Object Windows.Forms.Timer
        $timer.Interval = 30
        $timer.add_Tick({
            Invoke-DeskctlPending
            if ($script:quit) {
                $timer.Stop()
                $form.Close()
            }
        })
        $timer.Start()
        [Windows.Forms.Application]::Run($form)
        $timer.Stop()
        $timer.Dispose()
    } else {
        while (-not $script:quit) {
            Invoke-DeskctlPending
            Start-Sleep -Milliseconds 30
        }
    }
} catch {
    [Console]::Error.WriteLine($_.Exception.Message)
    exit 1
} finally {
    $script:enabled = $false
    if ($icon) {
        $icon.Visible = $false
        $icon.Dispose()
    }
    if ($script:ProductIcon) { $script:ProductIcon.Dispose() }
    if ($iconHandle -ne [IntPtr]::Zero -and $isWin) {
        try { [void][DeskctlNative]::DestroyIcon($iconHandle) } catch { }
    }
    if ($listener) { try { $listener.Stop() } catch { } }
    foreach ($name in @('port', 'pid')) {
        $f = Join-Path $homeDir $name
        if (Test-Path -LiteralPath $f) { Remove-Item -LiteralPath $f -Force -ErrorAction SilentlyContinue }
    }
    if ($gotMutex -and $mutex) {
        try { [void]$mutex.ReleaseMutex() } catch { }
        $mutex.Dispose()
    }
}
