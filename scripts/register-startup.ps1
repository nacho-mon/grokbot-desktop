#requires -Version 5.1
$ErrorActionPreference = 'Stop'
$homePath = if ($env:DESKCTL_HOME) { $env:DESKCTL_HOME } elseif ($env:GROKBOT_DESKTOP_HOME) { $env:GROKBOT_DESKTOP_HOME } elseif ($env:LOCALAPPDATA -and (Test-Path -LiteralPath (Join-Path $env:LOCALAPPDATA 'GrokBotDesktop\scripts\start.ps1'))) { Join-Path $env:LOCALAPPDATA 'GrokBotDesktop' } else { (Resolve-Path (Join-Path $PSScriptRoot '..')).Path }
$script = Join-Path $homePath 'scripts\start.ps1'
if (!(Test-Path -LiteralPath $script)) { throw "Grok Bot Desktop is not installed in $homePath. Run scripts\install.ps1 first." }
$startup = Join-Path $env:APPDATA 'Microsoft\Windows\Start Menu\Programs\Startup'
New-Item -ItemType Directory -Force -Path $startup | Out-Null
$linkPath = Join-Path $startup 'Grok Bot Desktop.lnk'
$shell = New-Object -ComObject WScript.Shell
$link = $shell.CreateShortcut($linkPath)
$link.TargetPath = (Join-Path $env:SystemRoot 'System32\WindowsPowerShell\v1.0\powershell.exe')
$link.Arguments = "-NoProfile -STA -WindowStyle Hidden -ExecutionPolicy Bypass -File `"$script`""
$link.Description = 'Grok Bot Desktop'
$ico = Join-Path $homePath 'grokbot-desktop.ico'
if (Test-Path -LiteralPath $ico) { $link.IconLocation = $ico }
$link.Save()
try { Unregister-ScheduledTask -TaskName 'deskctl' -Confirm:$false -ErrorAction SilentlyContinue } catch { }
Write-Host "Grok Bot Desktop will start, off, when you sign in. Shortcut: $linkPath"
