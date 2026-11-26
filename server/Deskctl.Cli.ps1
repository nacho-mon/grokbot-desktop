#requires -Version 5.1
function ConvertFrom-DeskctlCliArguments {
    param([string[]]$Arguments)

    if (-not $Arguments -or $Arguments.Count -eq 0) {
        return @{ Command = 'help' }
    }

    $cmd = $Arguments[0].ToLowerInvariant()
    $a = @($Arguments | Select-Object -Skip 1)

    switch ($cmd) {
        'on'  { return @{ Command = 'switch_ui_only' } }
        'off' { return @{ Command = 'switch_ui_only' } }
        'stop' { return @{ Command = 'stop' } }
        'help' { return @{ Command = 'help' } }
        'status' {
            return @{ Command = 'request'; Route = '/status'; Method = 'GET'; Body = $null }
        }
        'screenshot' {
            $body = @{}
            for ($i = 0; $i -lt $a.Count; $i++) {
                if ($a[$i] -eq '--monitor' -and ($i + 1) -lt $a.Count) { $body.monitor = $a[++$i] }
                elseif ($a[$i] -eq '--max-width' -and ($i + 1) -lt $a.Count) { $body.maxWidth = $a[++$i] }
                elseif ($a[$i] -eq '--format' -and ($i + 1) -lt $a.Count) { $body.format = $a[++$i].ToLowerInvariant() }
                elseif ($a[$i] -eq '--quality' -and ($i + 1) -lt $a.Count) { $body.quality = $a[++$i] }
                elseif ($a[$i] -eq '--window' -and ($i + 1) -lt $a.Count) { $body.window = $a[++$i].ToLowerInvariant() }
                elseif ($a[$i] -eq '--hwnd' -and ($i + 1) -lt $a.Count) { $body.hwnd = $a[++$i] }
                elseif ($a[$i] -eq '--full') { $body.full = $true }
                else { return @{ Command = 'usage' } }
            }
            return @{ Command = 'request'; Route = '/screenshot'; Method = 'POST'; Body = $body }
        }
        'move' {
            if ($a.Count -lt 2) { return @{ Command = 'usage' } }
            $body = @{ x = $a[0]; y = $a[1] }
            for ($i = 2; $i -lt $a.Count; $i++) {
                if ($a[$i] -eq '--space' -and ($i + 1) -lt $a.Count) { $body.space = $a[++$i] }
                else { return @{ Command = 'usage' } }
            }
            return @{ Command = 'request'; Route = '/move'; Method = 'POST'; Body = $body }
        }
        'click' {
            if ($a.Count -lt 2) { return @{ Command = 'usage' } }
            $body = @{ x = $a[0]; y = $a[1] }
            for ($i = 2; $i -lt $a.Count; $i++) {
                if ($a[$i] -eq '--button' -and ($i + 1) -lt $a.Count) { $body.button = $a[++$i] }
                elseif ($a[$i] -eq '--space' -and ($i + 1) -lt $a.Count) { $body.space = $a[++$i] }
                elseif ($a[$i] -eq '--double') { $body.double = $true }
                else { return @{ Command = 'usage' } }
            }
            return @{ Command = 'request'; Route = '/click'; Method = 'POST'; Body = $body }
        }
        'scroll' {
            if ($a.Count -lt 1) { return @{ Command = 'usage' } }
            $body = @{ dy = $a[0] }
            for ($i = 1; $i -lt $a.Count; $i++) {
                if ($a[$i] -eq '--x' -and ($i + 1) -lt $a.Count) { $body.x = $a[++$i] }
                elseif ($a[$i] -eq '--y' -and ($i + 1) -lt $a.Count) { $body.y = $a[++$i] }
                else { return @{ Command = 'usage' } }
            }
            return @{ Command = 'request'; Route = '/scroll'; Method = 'POST'; Body = $body }
        }
        'type' {
            if ($a.Count -lt 1) { return @{ Command = 'usage' } }
            $body = @{}
            if ($a[0] -eq '--paste') { $body.paste = $true; $a = @($a | Select-Object -Skip 1) }
            if ($a.Count -lt 1) { return @{ Command = 'usage' } }
            $body.text = ($a -join ' ')
            return @{ Command = 'request'; Route = '/type'; Method = 'POST'; Body = $body; TimeoutMs = 120000 }
        }
        'key' {
            if ($a.Count -lt 1) { return @{ Command = 'usage' } }
            return @{ Command = 'request'; Route = '/key'; Method = 'POST'; Body = @{ combo = ($a -join ' ') } }
        }
        'windows' {
            return @{ Command = 'request'; Route = '/windows'; Method = 'GET'; Body = $null }
        }
        'focus' {
            if ($a.Count -eq 0) { return @{ Command = 'usage' } }
            $idx = [Array]::IndexOf($a, '--hwnd')
            if ($idx -ge 0 -and ($idx + 1) -lt $a.Count) {
                return @{ Command = 'request'; Route = '/focus'; Method = 'POST'; Body = @{ hwnd = $a[$idx + 1] } }
            }
            return @{ Command = 'request'; Route = '/focus'; Method = 'POST'; Body = @{ title = ($a -join ' ') } }
        }
        'foreground' {
            return @{ Command = 'request'; Route = '/foreground'; Method = 'GET'; Body = $null }
        }
        'wait' {
            $body = @{}
            $words = @()
            for ($i = 0; $i -lt $a.Count; $i++) {
                if ($a[$i] -eq '--title' -and ($i + 1) -lt $a.Count) { $body.title = $a[++$i] }
                elseif ($a[$i] -eq '--timeout' -and ($i + 1) -lt $a.Count) { $body.timeoutMs = $a[++$i] }
                elseif ($a[$i] -eq '--foreground') { $body.foreground = $true }
                elseif ($a[$i] -eq '--gone') { $body.gone = $true }
                elseif ($a[$i] -like '--*') { return @{ Command = 'usage' } }
                else { $words += $a[$i] }
            }
            if (-not $body.ContainsKey('title') -and $words.Count -gt 0) { $body.title = ($words -join ' ') }
            elseif ($words.Count -gt 0) { return @{ Command = 'usage' } }
            if (-not $body.title) { return @{ Command = 'usage' } }
            $wait = 5000
            if ($body.timeoutMs -match '^\d{1,6}$') { $wait = [int]$body.timeoutMs }
            return @{ Command = 'request'; Route = '/wait'; Method = 'POST'; Body = $body; TimeoutMs = ($wait + 15000) }
        }
        'launch' {
            $body = @{}
            $words = @()
            for ($i = 0; $i -lt $a.Count; $i++) {
                if ($a[$i] -eq '--args' -and ($i + 1) -lt $a.Count) { $body.args = $a[++$i].Trim() }
                elseif ($a[$i] -eq '--wait-title' -and ($i + 1) -lt $a.Count) { $body.waitTitle = $a[++$i] }
                elseif ($a[$i] -eq '--timeout' -and ($i + 1) -lt $a.Count) { $body.timeoutMs = $a[++$i] }
                elseif ($a[$i] -like '--*') { return @{ Command = 'usage' } }
                else { $words += $a[$i] }
            }
            if ($words.Count -eq 0) { return @{ Command = 'usage' } }
            $body.path = ($words -join ' ')
            $wait = 10000
            if ($body.timeoutMs -match '^\d{1,6}$') { $wait = [int]$body.timeoutMs }
            return @{ Command = 'request'; Route = '/launch'; Method = 'POST'; Body = $body; TimeoutMs = ($wait + 15000) }
        }
        'open' {
            $body = @{}
            $words = @()
            for ($i = 0; $i -lt $a.Count; $i++) {
                if ($a[$i] -eq '--args' -and ($i + 1) -lt $a.Count) { $body.args = $a[++$i].Trim() }
                elseif ($a[$i] -in @('--wait', '--wait-title') -and ($i + 1) -lt $a.Count) { $body.waitTitle = $a[++$i] }
                elseif ($a[$i] -eq '--timeout' -and ($i + 1) -lt $a.Count) { $body.timeoutMs = $a[++$i] }
                elseif ($a[$i] -like '--*') { return @{ Command = 'usage' } }
                else { $words += $a[$i] }
            }
            if ($words.Count -eq 0) { return @{ Command = 'usage' } }
            $body.target = ($words -join ' ')
            $wait = 10000
            if ($body.timeoutMs -match '^\d{1,6}$') { $wait = [int]$body.timeoutMs }
            return @{ Command = 'request'; Route = '/open'; Method = 'POST'; Body = $body; TimeoutMs = ($wait + 15000) }
        }
        'selftest' {
            return @{ Command = 'request'; Route = '/selftest'; Method = 'POST'; Body = @{}; TimeoutMs = 130000 }
        }
        'batch' {
            if ($a.Count -eq 0) { return @{ Command = 'usage' } }
            if ($a[0] -eq '--file') {
                if ($a.Count -ne 2) { return @{ Command = 'usage' } }
                return @{ Command = 'request'; Route = '/batch'; Method = 'POST'; Body = $null; RawFile = $a[1]; TimeoutMs = 200000 }
            }
            if ($a[0] -eq '--b64') {
                if ($a.Count -ne 2) { return @{ Command = 'usage' } }
                return @{ Command = 'request'; Route = '/batch'; Method = 'POST'; Body = $null; RawBase64 = $a[1]; TimeoutMs = 200000 }
            }
            return @{ Command = 'request'; Route = '/batch'; Method = 'POST'; Body = $null; RawJson = ($a -join ' '); TimeoutMs = 200000 }
        }
        default { return @{ Command = 'unknown' } }
    }
}
