#requires -Version 5.1
param([switch]$Console, [switch]$Headless)

$ErrorActionPreference = 'Stop'
$installRoot = if ($env:DESKCTL_HOME) {
    $env:DESKCTL_HOME
} elseif ($env:GROKBOT_DESKTOP_HOME) {
    $env:GROKBOT_DESKTOP_HOME
} elseif ($env:LOCALAPPDATA -and (Test-Path -LiteralPath (Join-Path $env:LOCALAPPDATA 'GrokBotDesktop\server\Start-Deskctl.ps1'))) {
    Join-Path $env:LOCALAPPDATA 'GrokBotDesktop'
} else {
    (Resolve-Path (Join-Path $PSScriptRoot '..')).Path
}
$server = Join-Path $installRoot 'server\Start-Deskctl.ps1'
if (!(Test-Path -LiteralPath $server)) { throw "Cannot find Start-Deskctl.ps1 in $installRoot. Run scripts\install.ps1 first." }
$security = Join-Path $installRoot 'server\Deskctl.Security.ps1'
if (Test-Path -LiteralPath $security) { . $security }
$iconPath = Join-Path $installRoot 'grokbot-desktop.ico'
if ((Get-Command Save-GrokBotDesktopIcon -ErrorAction SilentlyContinue) -and !(Test-Path -LiteralPath $iconPath)) {
    $null = Save-GrokBotDesktopIcon -IconPath $iconPath
}
$exeArgs = @('-NoProfile', '-ExecutionPolicy', 'Bypass', '-STA')
if (-not $Console -and -not $Headless) { $exeArgs += @('-WindowStyle', 'Hidden') }
$exeArgs += @('-File', $server)
if ($Headless) { $exeArgs += '-Headless' }
if ($Console -or $Headless) { & powershell.exe @exeArgs; exit $LASTEXITCODE }
Start-Process -FilePath 'powershell.exe' -ArgumentList $exeArgs -WindowStyle Hidden
Write-Host 'Grok Bot Desktop started, off (tray icon). To turn it on: right-click it, then Turn on.'
