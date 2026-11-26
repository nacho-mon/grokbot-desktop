#requires -Version 5.1
param([switch]$Autostart)

$ErrorActionPreference = 'Stop'
$src = (Resolve-Path (Join-Path $PSScriptRoot '..')).Path
if (-not $env:LOCALAPPDATA -and -not $env:DESKCTL_HOME -and -not $env:GROKBOT_DESKTOP_HOME) {
    throw 'This installer requires Windows.'
}
$dest = if ($env:DESKCTL_HOME) { $env:DESKCTL_HOME } elseif ($env:GROKBOT_DESKTOP_HOME) { $env:GROKBOT_DESKTOP_HOME } else { Join-Path $env:LOCALAPPDATA 'GrokBotDesktop' }
$legacy = if ($env:LOCALAPPDATA) { Join-Path $env:LOCALAPPDATA 'deskctl' } else { $null }
Write-Host 'Installing Grok Bot Desktop.'
Write-Host "Destination: $dest"
if ($legacy -and (Test-Path -LiteralPath $legacy) -and (([IO.Path]::GetFullPath($legacy)) -ne ([IO.Path]::GetFullPath($dest)))) {
    $legacyPid = Join-Path $legacy 'pid'
    if (Test-Path -LiteralPath $legacyPid) {
        try {
            $oldPid = [int][IO.File]::ReadAllText($legacyPid).Trim()
            $proc = Get-CimInstance Win32_Process -Filter "ProcessId=$oldPid" -ErrorAction SilentlyContinue
            if (-not $proc) { $proc = Get-WmiObject Win32_Process -Filter "ProcessId=$oldPid" -ErrorAction SilentlyContinue }
            if ($proc -and $proc.CommandLine -match 'Start-Deskctl\.ps1') { Stop-Process -Id $oldPid -Force -ErrorAction SilentlyContinue }
        } catch { }
    }
    try { Unregister-ScheduledTask -TaskName 'deskctl' -Confirm:$false -ErrorAction SilentlyContinue } catch { }
}
New-Item -ItemType Directory -Force -Path $dest | Out-Null
if ($legacy -and (Test-Path -LiteralPath (Join-Path $legacy 'token')) -and !(Test-Path -LiteralPath (Join-Path $dest 'token'))) {
    Copy-Item -LiteralPath (Join-Path $legacy 'token') -Destination (Join-Path $dest 'token')
}
$xd = @('.git', 'node_modules', '.smoke-home')
$xf = @('deskctl.zip', 'grokbot-desktop.zip', 'SPEC.md', 'token', 'port', 'pid')
if (Get-Command robocopy.exe -ErrorAction SilentlyContinue) {
    $rcArgs = @($src, $dest, '/E', '/R:1', '/W:1', '/NFL', '/NDL', '/NJH', '/NJS', '/nc', '/ns', '/np', '/XD') + $xd + @('/XF') + $xf
    & robocopy.exe @rcArgs | Out-Null
    if ($LASTEXITCODE -ge 8) { throw "robocopy failed with code $LASTEXITCODE" }
} else {
    Get-ChildItem -LiteralPath $src -Force | Where-Object { $_.Name -notin ($xd + $xf) } | ForEach-Object {
        Copy-Item -LiteralPath $_.FullName -Destination (Join-Path $dest $_.Name) -Recurse -Force
    }
}
. (Join-Path $dest 'server/Deskctl.Security.ps1')
$null = Ensure-DeskctlToken $dest
Set-UserOnlyAcl -Path $dest -Directory
$null = Save-GrokBotDesktopIcon -IconPath (Join-Path $dest 'grokbot-desktop.ico')
try {
    $null = & (Join-Path $dest 'scripts/build-client.ps1')
    Write-Host 'Fast client ready: gbd.exe / gbd.cmd.'
} catch {
    Write-Host "Could not build the fast client (gbd.exe): $($_.Exception.Message). The PowerShell CLI still works."
}
if ($Autostart) { & (Join-Path $dest 'scripts/register-startup.ps1') }
if ($legacy -and (Test-Path -LiteralPath $legacy) -and (([IO.Path]::GetFullPath($legacy)) -ne ([IO.Path]::GetFullPath($dest)))) { Remove-Item -LiteralPath $legacy -Recurse -Force -ErrorAction SilentlyContinue }
Write-Host ''
Write-Host 'Grok Bot Desktop is installed. Control starts off.'
Write-Host ("To start it: powershell.exe -NoProfile -ExecutionPolicy Bypass -File `"{0}`"" -f (Join-Path $dest 'scripts\start.ps1'))
Write-Host 'In the tray, right-click Grok Bot Desktop and choose Turn on.'
Write-Host ("CLI: powershell.exe -NoProfile -ExecutionPolicy Bypass -File `"{0}`" status" -f (Join-Path $dest 'grokbot-desktop.ps1'))
if (-not $Autostart) { Write-Host 'To start it when you sign in to Windows: run scripts\register-startup.ps1.' }
