#requires -Version 5.1
param([Parameter(ValueFromRemainingArguments = $true)][string[]]$CliArgv)

$ErrorActionPreference = 'Stop'
$cliRoot = $PSScriptRoot
if (-not $cliRoot) { $cliRoot = Split-Path -Parent $MyInvocation.MyCommand.Path }
. (Join-Path $cliRoot 'server/Deskctl.Security.ps1')
. (Join-Path $cliRoot 'server/Deskctl.Cli.ps1')

function Out-DeskctlResult {
    param($Object, [int]$Code = 1)
    [Console]::OutputEncoding = [Text.UTF8Encoding]::new($false)
    $json = ConvertTo-Json -InputObject $Object -Depth 8 -Compress
    [Console]::Out.WriteLine($json)
    exit $Code
}

$usage = @'
grokbot-desktop: controls the local desktop (127.0.0.1 only, token and tray kill switch)

Usage:
  grokbot-desktop status
  grokbot-desktop screenshot [--full] [--monitor all|N | --window active | --hwnd <id>] [--max-width N] [--format png|jpg] [--quality 1-100]
  grokbot-desktop move <x> <y> [--space screen|image]
  grokbot-desktop click <x> <y> [--button left|right|middle] [--double] [--space screen|image]
  grokbot-desktop scroll <dy> [--x N] [--y N]
  grokbot-desktop type [--paste] <text>
  grokbot-desktop key <combo>
  grokbot-desktop windows
  grokbot-desktop focus <title> | --hwnd <id>
  grokbot-desktop foreground
  grokbot-desktop wait --title <text> [--timeout ms] [--foreground] [--gone]
  grokbot-desktop launch <program|file> [--args "<arguments>"] [--wait-title <text>] [--timeout ms]
  grokbot-desktop open <app|url|uri> [--wait <title>] [--args "<arguments>"] [--timeout ms]
  grokbot-desktop selftest
  grokbot-desktop batch --file <steps.json> | --b64 <base64 json> | <json>
  grokbot-desktop stop
  grokbot-desktop help

batch: a JSON list of steps {"cmd":...} with cmd = screenshot, move, click, scroll, type, key,
windows, focus, wait, launch, open, selftest, foreground or sleep (ms). Runs everything in one call,
in order, and stops at the first error. Max 100 steps; sleep up to 10000 ms; wait/launch up to 60000 ms.
Example: [{"cmd":"open","target":"notepad"},{"cmd":"type","text":"hello"},{"cmd":"screenshot"}]
Pause between steps: 120 ms by default here; change it with {"stepDelayMs":N,"steps":[...]} (0 = none).

screenshot: light by default (active window, JPG quality 60, max 1280 px wide).
--full brings back the full capture (all monitors, PNG, real size).
open: opens an app, URL or URI, brings it to the front and returns title and hwnd, no screenshot.
URLs (https://... or x.com) open in Chrome as an argument: always a new tab.
Shortcuts: chrome, edge, notepad, calc, paint, settings, explorer, word, excel (matched by process, not title).
chrome://, edge:// and about: go to the browser: bring it forward, Ctrl+T, verify the new tab, type the URL.
type: Unicode key events per character (any keyboard layout), Enter/Tab as real keys, 8 ms apart;
--paste puts the text on the clipboard, presses Ctrl+V and restores the clipboard text (best for long text).
Held modifiers are released first; it stops if the foreground window changes. selftest: Chrome x.com, Calculator 2+2=, a new Notepad note.

Fast client (no PowerShell start-up): gbd.exe / gbd.cmd in the same folder. See gbd help.

on/off do not turn control on or off: use Turn on / Turn off in the tray icon menu.
'@

$homePath = Get-DeskctlHome
$parsed = ConvertFrom-DeskctlCliArguments $CliArgv
$cmd = $parsed.Command

if ($cmd -eq 'help') {
    [Console]::OutputEncoding = [Text.UTF8Encoding]::new($false)
    [Console]::Out.WriteLine($usage.TrimEnd())
    exit 0
}
if ($cmd -eq 'switch_ui_only') {
    Out-DeskctlResult @{ ok = $false; error = 'kill_switch_ui_only'; message = 'Control cannot be turned on or off from the CLI. Use Turn on or Turn off in the tray icon menu.' } 1
}
if ($cmd -eq 'unknown') {
    Out-DeskctlResult @{ ok = $false; error = 'usage'; message = 'Unknown command. See grokbot-desktop help.' } 2
}
if ($cmd -eq 'usage') {
    Out-DeskctlResult @{ ok = $false; error = 'usage'; message = 'Missing arguments. See grokbot-desktop help.' } 2
}

if ($cmd -eq 'stop') {
    $pidFile = Join-Path $homePath 'pid'
    try {
        if (!(Test-Path -LiteralPath $pidFile)) { throw 'missing_pid' }
        $target = [int][IO.File]::ReadAllText($pidFile).Trim()
        if ($target -eq $PID) { throw 'pid_self' }
        if (Test-DeskctlIsWindows) {
            $proc = Get-CimInstance Win32_Process -Filter "ProcessId=$target" -ErrorAction SilentlyContinue
            if (-not $proc) { $proc = Get-WmiObject Win32_Process -Filter "ProcessId=$target" -ErrorAction Stop }
            if (-not $proc -or $proc.CommandLine -notmatch 'Start-Deskctl\.ps1') { throw 'not_deskctl' }
        } else {
            $procPath = "/proc/$target/cmdline"
            if (!(Test-Path $procPath)) { throw 'not_running' }
            $cmdline = [Text.Encoding]::UTF8.GetString([IO.File]::ReadAllBytes($procPath))
            if ($cmdline -notmatch 'Start-Deskctl\.ps1') { throw 'not_deskctl' }
        }
        Stop-Process -Id $target -Force -ErrorAction Stop
        Remove-Item -LiteralPath (Join-Path $homePath 'pid'), (Join-Path $homePath 'port') -Force -ErrorAction SilentlyContinue
        Out-DeskctlResult @{ ok = $true; stopped = $target } 0
    } catch {
        Out-DeskctlResult @{ ok = $false; error = 'bridge_unavailable'; message = 'Could not find a running Grok Bot Desktop process to stop.' } 1
    }
}

$rawJson = $null
if ($cmd -eq 'request' -and $parsed.RawFile) {
    try {
        $batchFile = (Resolve-Path -LiteralPath $parsed.RawFile -ErrorAction Stop).ProviderPath
        $rawJson = [IO.File]::ReadAllText($batchFile, [Text.Encoding]::UTF8)
    } catch {
        Out-DeskctlResult @{ ok = $false; error = 'invalid_args'; message = 'Could not read the steps file.' } 2
    }
} elseif ($cmd -eq 'request' -and $parsed.RawBase64) {
    try {
        $rawJson = [Text.Encoding]::UTF8.GetString([Convert]::FromBase64String($parsed.RawBase64))
    } catch {
        Out-DeskctlResult @{ ok = $false; error = 'invalid_args'; message = 'The steps base64 is invalid.' } 2
    }
} elseif ($cmd -eq 'request' -and $null -ne $parsed.RawJson) {
    $rawJson = $parsed.RawJson
}
if ($null -ne $rawJson) {
    $rawJson = $rawJson.Trim([char]0xFEFF, ' ', "`t", "`r", "`n")
    if ($rawJson.StartsWith('[')) { $rawJson = '{"steps":' + $rawJson + '}' }
}

$token = $env:DESKCTL_TOKEN
if (-not $token) {
    $tokenFile = if ($env:DESKCTL_TOKEN_FILE) { $env:DESKCTL_TOKEN_FILE } else { Join-Path $homePath 'token' }
    if (!(Test-Path -LiteralPath $tokenFile)) {
        Out-DeskctlResult @{ ok = $false; error = 'no_token'; message = 'Grok Bot Desktop cannot find its token. Run scripts\install.ps1.' } 1
    }
    $token = ([IO.File]::ReadAllText($tokenFile)).Trim()
}

$portFile = Join-Path $homePath 'port'
if (!(Test-Path -LiteralPath $portFile)) {
    Out-DeskctlResult @{ ok = $false; error = 'bridge_unavailable'; message = 'Grok Bot Desktop is not running. Run scripts\start.ps1.' } 1
}
$port = [int]([IO.File]::ReadAllText($portFile).Trim())
$base = if ($env:DESKCTL_URL) { $env:DESKCTL_URL.TrimEnd('/') } else { "http://127.0.0.1:$port" }
try {
    $baseUri = [Uri]$base
    if ($baseUri.Scheme -ne 'http' -or $baseUri.Host -notin @('127.0.0.1', 'localhost')) {
        Out-DeskctlResult @{ ok = $false; error = 'invalid_url'; message = 'DESKCTL_URL must point to 127.0.0.1.' } 1
    }
} catch {
    Out-DeskctlResult @{ ok = $false; error = 'invalid_url'; message = 'Invalid DESKCTL_URL.' } 1
}

try {
    $timeout = 30000
    if ($env:DESKCTL_TIMEOUT_MS) { $timeout = [int]$env:DESKCTL_TIMEOUT_MS }
    elseif ($parsed.TimeoutMs) { $timeout = [int]$parsed.TimeoutMs }
    $route = $parsed.Route
    $verb = $parsed.Method
    $body = $parsed.Body
    $req = [Net.HttpWebRequest]::Create($base + $route)
    $req.Method = $verb
    $req.Timeout = $timeout
    $req.ReadWriteTimeout = $timeout
    $req.Headers.Add('X-Deskctl-Token', $token)
    $req.Headers.Add('Authorization', "Bearer $token")
    if ($verb -eq 'POST') {
        $json = if ($null -ne $rawJson) { $rawJson } elseif ($null -ne $body) { ConvertTo-Json $body -Compress -Depth 6 } else { '{}' }
        $bytes = [Text.Encoding]::UTF8.GetBytes($json)
        $req.ContentType = 'application/json; charset=utf-8'
        $req.ContentLength = $bytes.Length
        $rs = $req.GetRequestStream()
        $rs.Write($bytes, 0, $bytes.Length)
        $rs.Close()
    }
    try {
        $resp = $req.GetResponse()
    } catch [Net.WebException] {
        $resp = $_.Exception.Response
        if (-not $resp) { throw }
    }
    $sr = New-Object IO.StreamReader($resp.GetResponseStream())
    try {
        $content = $sr.ReadToEnd()
    } finally {
        $sr.Close()
        $resp.Close()
    }
    $obj = ConvertFrom-Json $content
    Out-DeskctlResult $obj $(if ($obj.ok) { 0 } else { 1 })
} catch {
    Out-DeskctlResult @{ ok = $false; error = 'bridge_unavailable'; message = 'Could not connect to Grok Bot Desktop. Is it running?' } 1
}
