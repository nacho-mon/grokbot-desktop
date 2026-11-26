#requires -Version 5.1
# Builds gbd.exe (fast client) from client\gbd.cs with the csc.exe that ships with .NET Framework 4.x.
# Runs as the current user, no admin, writes only inside the app folder.
$ErrorActionPreference = 'Stop'
$root = (Resolve-Path (Join-Path $PSScriptRoot '..')).Path
$src = Join-Path $root 'client\gbd.cs'
$out = Join-Path $root 'gbd.exe'
$tmp = Join-Path $root 'gbd.new.exe'
$csc = @(
    (Join-Path $env:WINDIR 'Microsoft.NET\Framework64\v4.0.30319\csc.exe'),
    (Join-Path $env:WINDIR 'Microsoft.NET\Framework\v4.0.30319\csc.exe')
) | Where-Object { Test-Path -LiteralPath $_ } | Select-Object -First 1
if (-not $csc) { throw 'Could not find csc.exe from .NET Framework 4.x.' }
if (Test-Path -LiteralPath $tmp) { Remove-Item -LiteralPath $tmp -Force }
$log = & $csc /nologo /optimize+ /target:exe /r:System.dll /r:System.Core.dll "/out:$tmp" $src 2>&1
if ($LASTEXITCODE -ne 0 -or !(Test-Path -LiteralPath $tmp)) {
    throw ("csc failed ({0}): {1}" -f $LASTEXITCODE, (($log | Where-Object { $_ -match 'error' }) -join ' | '))
}
Move-Item -LiteralPath $tmp -Destination $out -Force
& $out version
