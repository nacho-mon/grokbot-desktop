#requires -Version 5.1
function Get-DeskctlHome {
    if ($env:DESKCTL_HOME) {
        return [IO.Path]::GetFullPath($env:DESKCTL_HOME)
    }
    if ($env:GROKBOT_DESKTOP_HOME) {
        return [IO.Path]::GetFullPath($env:GROKBOT_DESKTOP_HOME)
    }
    if ($env:LOCALAPPDATA) {
        return (Join-Path $env:LOCALAPPDATA 'GrokBotDesktop')
    }
    $base = if ($env:XDG_CONFIG_HOME) { $env:XDG_CONFIG_HOME } else { Join-Path $HOME '.config' }
    return (Join-Path $base 'GrokBotDesktop')
}

function Test-DeskctlIsWindows {
    return ($env:OS -eq 'Windows_NT')
}

function Set-UserOnlyAcl {
    param(
        [Parameter(Mandatory = $true)][string]$Path,
        [switch]$Directory
    )
    if (Test-DeskctlIsWindows) {
        # Fresh DACL-only security object: avoids reading/writing the SACL (needs SeSecurityPrivilege).
        $acl = if ($Directory) { New-Object Security.AccessControl.DirectorySecurity } else { New-Object Security.AccessControl.FileSecurity }
        $acl.SetAccessRuleProtection($true, $false)
        $sid = [Security.Principal.WindowsIdentity]::GetCurrent().User
        $inherit = if ($Directory) {
            [Security.AccessControl.InheritanceFlags]::ContainerInherit -bor [Security.AccessControl.InheritanceFlags]::ObjectInherit
        } else {
            [Security.AccessControl.InheritanceFlags]::None
        }
        $rule = New-Object Security.AccessControl.FileSystemAccessRule(
            $sid,
            'FullControl',
            $inherit,
            [Security.AccessControl.PropagationFlags]::None,
            [Security.AccessControl.AccessControlType]::Allow
        )
        $acl.AddAccessRule($rule)
        (Get-Item -LiteralPath $Path -Force).SetAccessControl($acl)
    } else {
        if ($Directory) { & chmod 700 -- $Path } else { & chmod 600 -- $Path }
    }
}

function New-DeskctlToken {
    $bytes = New-Object byte[] 32
    $rng = [Security.Cryptography.RandomNumberGenerator]::Create()
    try {
        $rng.GetBytes($bytes)
    } finally {
        $rng.Dispose()
    }
    return ([BitConverter]::ToString($bytes).Replace('-', '').ToLowerInvariant())
}

function Ensure-DeskctlToken {
    param([Parameter(Mandatory = $true)][string]$HomePath)
    if (!(Test-Path -LiteralPath $HomePath)) {
        [void](New-Item -ItemType Directory -Path $HomePath -Force)
    }
    Set-UserOnlyAcl -Path $HomePath -Directory
    $path = Join-Path $HomePath 'token'
    if (!(Test-Path -LiteralPath $path)) {
        [IO.File]::WriteAllText($path, (New-DeskctlToken), [Text.Encoding]::ASCII)
    }
    Set-UserOnlyAcl -Path $path
    $token = ([IO.File]::ReadAllText($path)).Trim()
    if ($token -notmatch '^[0-9a-fA-F]{64}$') {
        throw 'The token file is invalid. Reinstall Grok Bot Desktop, or delete the token and start it again.'
    }
    return $token
}

function ConvertTo-DeskctlTokenBytes {
    param([string]$Value)
    $bytes = New-Object byte[] 32
    if ($Value -match '^[0-9a-fA-F]{64}$') {
        for ($i = 0; $i -lt 32; $i++) {
            $bytes[$i] = [Convert]::ToByte($Value.Substring($i * 2, 2), 16)
        }
    }
    return ,$bytes
}

function Test-DeskctlToken {
    param(
        [string]$Expected,
        [string]$Actual
    )
    # Always compare 32 bytes so length/format mismatches don't short-circuit the compare.
    $validExpected = $Expected -match '^[0-9a-fA-F]{64}$'
    $validActual = $Actual -match '^[0-9a-fA-F]{64}$'
    $a = ConvertTo-DeskctlTokenBytes $Expected
    $b = ConvertTo-DeskctlTokenBytes $Actual
    $equal = $false
    $ct = [Type]::GetType('System.Security.Cryptography.CryptographicOperations, System.Security.Cryptography.Algorithms', $false)
    if ($ct) {
        $equal = [bool]$ct.GetMethod('FixedTimeEquals', [type[]]@([byte[]], [byte[]])).Invoke($null, @($a, $b))
    } else {
        $diff = 0
        for ($i = 0; $i -lt 32; $i++) {
            $diff = $diff -bor ($a[$i] -bxor $b[$i])
        }
        $equal = ($diff -eq 0)
    }
    return [bool]($equal -and $validExpected -and $validActual)
}

function Test-DeskctlLoopback {
    param([string]$HostName)
    return ($HostName -eq '127.0.0.1' -or $HostName -eq 'localhost')
}

function ConvertTo-DeskctlScreenPoint {
    param(
        [int]$X,
        [int]$Y,
        [int]$OriginX,
        [int]$OriginY,
        [double]$Scale
    )
    if ($Scale -le 0) { throw 'invalid_scale' }
    return @{
        x = [int][Math]::Round($OriginX + ($X / $Scale))
        y = [int][Math]::Round($OriginY + ($Y / $Scale))
    }
}

function Write-DeskctlUserFile {
    param(
        [Parameter(Mandatory = $true)][string]$Path,
        [Parameter(Mandatory = $true)][string]$Text
    )
    $dir = Split-Path -Parent $Path
    if ($dir -and !(Test-Path -LiteralPath $dir)) {
        [void](New-Item -ItemType Directory -Path $dir -Force)
        Set-UserOnlyAcl -Path $dir -Directory
    }
    [IO.File]::WriteAllText($Path, $Text, [Text.Encoding]::ASCII)
    Set-UserOnlyAcl -Path $Path
}

function Get-GrokBotAppExecutable {
    if (-not (Test-DeskctlIsWindows)) { return $null }
    $patterns = @(
        (Join-Path $env:LOCALAPPDATA 'Programs\*grok*\*.exe'),
        (Join-Path $env:LOCALAPPDATA 'Programs\Grok Bot\*.exe')
    )
    if ($env:ProgramFiles) { $patterns += (Join-Path $env:ProgramFiles '*grok*\*.exe') }
    if (${env:ProgramFiles(x86)}) { $patterns += (Join-Path ${env:ProgramFiles(x86)} '*grok*\*.exe') }
    $candidates = @()
    foreach ($pattern in $patterns) {
        $candidates += @(Get-ChildItem -Path $pattern -File -ErrorAction SilentlyContinue)
    }
    $chosen = $candidates |
        Where-Object { $_.Name -notmatch '(?i)uninstall|uninst|^setup' } |
        Sort-Object @{ Expression = { if ($_.BaseName -match 'grok') { 0 } else { 1 } } }, @{ Expression = { $_.FullName.Length } }, FullName |
        Select-Object -First 1
    if ($chosen) { return $chosen.FullName }
    return $null
}

function Save-GrokBotDesktopIcon {
    param([Parameter(Mandatory = $true)][string]$IconPath)
    if (-not (Test-DeskctlIsWindows)) { return $false }
    try {
        Add-Type -AssemblyName System.Drawing
        $exe = Get-GrokBotAppExecutable
        if (-not $exe) { return $false }
        $dir = Split-Path -Parent $IconPath
        if ($dir -and !(Test-Path -LiteralPath $dir)) {
            [void](New-Item -ItemType Directory -Path $dir -Force)
        }
        $extracted = [Drawing.Icon]::ExtractAssociatedIcon($exe)
        if (-not $extracted) { return $false }
        $stream = [IO.File]::Create($IconPath)
        try {
            $extracted.Save($stream)
        } finally {
            $stream.Dispose()
            $extracted.Dispose()
        }
        Set-UserOnlyAcl -Path $IconPath
        return $true
    } catch {
        return $false
    }
}

function Stop-GrokBotDesktopPidFile {
    param([string]$PidFile)
    if (-not $PidFile -or !(Test-Path -LiteralPath $PidFile)) { return }
    try {
        $targetPid = [int][IO.File]::ReadAllText($PidFile).Trim()
        if ($targetPid -le 0 -or $targetPid -eq $PID) { return }
        if (Test-DeskctlIsWindows) {
            $proc = Get-CimInstance Win32_Process -Filter "ProcessId=$targetPid" -ErrorAction SilentlyContinue
            if (-not $proc) { $proc = Get-WmiObject Win32_Process -Filter "ProcessId=$targetPid" -ErrorAction SilentlyContinue }
            if ($proc -and $proc.CommandLine -match 'Start-Deskctl\.ps1') {
                Stop-Process -Id $targetPid -Force -ErrorAction SilentlyContinue
            }
        } else {
            $procPath = "/proc/$targetPid/cmdline"
            if (Test-Path $procPath) {
                $cmdline = [Text.Encoding]::UTF8.GetString([IO.File]::ReadAllBytes($procPath))
                if ($cmdline -match 'Start-Deskctl\.ps1') {
                    Stop-Process -Id $targetPid -Force -ErrorAction SilentlyContinue
                }
            }
        }
    } catch { }
}
