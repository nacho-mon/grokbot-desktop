#requires -Version 5.1
param([switch]$KeepToken)

$ErrorActionPreference = 'Stop'
$homes = @()
if ($env:DESKCTL_HOME) { $homes += $env:DESKCTL_HOME }
if ($env:GROKBOT_DESKTOP_HOME) { $homes += $env:GROKBOT_DESKTOP_HOME }
if ($env:LOCALAPPDATA) { $homes += (Join-Path $env:LOCALAPPDATA 'GrokBotDesktop'); $homes += (Join-Path $env:LOCALAPPDATA 'deskctl') }
if (-not $homes.Count) { $homes += (Resolve-Path (Join-Path $PSScriptRoot '..')).Path }
$homes = @($homes | Select-Object -Unique)
$securityScript = Join-Path $PSScriptRoot '..\server\Deskctl.Security.ps1'
if (Test-Path -LiteralPath $securityScript) { . $securityScript }
foreach ($homePath in $homes) {
    foreach ($cliName in @('grokbot-desktop.ps1', 'deskctl.ps1')) {
        $cli = Join-Path $homePath $cliName
        if (Test-Path -LiteralPath $cli) {
            try { & powershell.exe -NoProfile -ExecutionPolicy Bypass -File $cli stop | Out-Null } catch { }
        }
    }
    if (Get-Command Stop-GrokBotDesktopPidFile -ErrorAction SilentlyContinue) {
        Stop-GrokBotDesktopPidFile (Join-Path $homePath 'pid')
    }
}
if ($env:APPDATA) { Remove-Item -LiteralPath (Join-Path $env:APPDATA 'Microsoft\Windows\Start Menu\Programs\Startup\Grok Bot Desktop.lnk') -Force -ErrorAction SilentlyContinue }
try { Unregister-ScheduledTask -TaskName 'deskctl' -Confirm:$false -ErrorAction SilentlyContinue } catch { }
if ($KeepToken) {
    $newHome = if ($env:DESKCTL_HOME) { $env:DESKCTL_HOME } elseif ($env:GROKBOT_DESKTOP_HOME) { $env:GROKBOT_DESKTOP_HOME } elseif ($env:LOCALAPPDATA) { Join-Path $env:LOCALAPPDATA 'GrokBotDesktop' } else { $homes[0] }
    $sourceToken = Join-Path $newHome 'token'
    if (!(Test-Path -LiteralPath $sourceToken)) {
        foreach ($h in $homes) { $candidate = Join-Path $h 'token'; if (Test-Path -LiteralPath $candidate) { New-Item -ItemType Directory -Force -Path $newHome | Out-Null; Copy-Item -LiteralPath $candidate -Destination $sourceToken -Force; break } }
    }
    if ((Test-Path -LiteralPath $sourceToken) -and (Get-Command Set-UserOnlyAcl -ErrorAction SilentlyContinue)) { Set-UserOnlyAcl -Path $sourceToken }
    foreach ($h in $homes) {
        if (([IO.Path]::GetFullPath($h)) -eq ([IO.Path]::GetFullPath($newHome))) {
            Get-ChildItem -LiteralPath $h -Force -ErrorAction SilentlyContinue | Where-Object { $_.Name -ne 'token' } | Remove-Item -Recurse -Force -ErrorAction SilentlyContinue
        } else { Remove-Item -LiteralPath $h -Recurse -Force -ErrorAction SilentlyContinue }
    }
    Write-Host "Grok Bot Desktop was uninstalled. The token was kept at $sourceToken."
} else {
    foreach ($h in $homes) { Remove-Item -LiteralPath $h -Recurse -Force -ErrorAction SilentlyContinue }
    Write-Host 'Grok Bot Desktop was uninstalled.'
}
