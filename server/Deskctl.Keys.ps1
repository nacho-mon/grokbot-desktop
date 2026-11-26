#requires -Version 5.1
function ConvertFrom-DeskctlCombo {
    param([string]$Combo)
    if ([string]::IsNullOrWhiteSpace($Combo)) { throw 'unknown_key' }

    $parts = @($Combo.Trim().ToLowerInvariant() -split '\s*\+\s*')
    if ($parts.Count -lt 1 -or $parts.Count -gt 5 -or $parts -contains '') {
        throw 'unknown_key'
    }

    $modMap = @{
        ctrl    = 0x11
        control = 0x11
        alt     = 0x12
        shift   = 0x10
        win     = 0x5B
        meta    = 0x5B
        cmd     = 0x5B
    }
    $keyMap = @{
        enter       = 0x0D
        return      = 0x0D
        tab         = 0x09
        esc         = 0x1B
        escape      = 0x1B
        space       = 0x20
        backspace   = 0x08
        delete      = 0x2E
        insert      = 0x2D
        home        = 0x24
        end         = 0x23
        pageup      = 0x21
        pagedown    = 0x22
        up          = 0x26
        down        = 0x28
        left        = 0x25
        right       = 0x27
        printscreen = 0x2C
        apps        = 0x5D
    }

    $mods = New-Object System.Collections.Generic.List[int]
    for ($i = 0; $i -lt ($parts.Count - 1); $i++) {
        $name = $parts[$i]
        if (-not $modMap.ContainsKey($name)) { throw 'unknown_key' }
        $vk = [int]$modMap[$name]
        if ($mods.Contains($vk)) { throw 'unknown_key' }
        $mods.Add($vk)
    }

    $keyName = $parts[$parts.Count - 1]
    $vk = $null
    if ($keyName -match '^[a-z]$') {
        $vk = [int][char]$keyName.ToUpperInvariant()
    } elseif ($keyName -match '^[0-9]$') {
        $vk = [int][char]$keyName
    } elseif ($keyName -match '^f([1-9]|1[0-9]|2[0-4])$') {
        $vk = 0x6F + [int]$Matches[1]
    } elseif ($keyMap.ContainsKey($keyName)) {
        $vk = [int]$keyMap[$keyName]
    }
    if ($null -eq $vk) { throw 'unknown_key' }

    $out = New-Object System.Collections.Generic.List[int]
    foreach ($mod in $mods) { $out.Add($mod) }
    $out.Add([int]$vk)
    $out.Add(-[int]$vk)
    for ($i = $mods.Count - 1; $i -ge 0; $i--) {
        $out.Add(-[int]$mods[$i])
    }
    return ,$out.ToArray()
}
