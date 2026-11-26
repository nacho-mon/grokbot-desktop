#requires -Version 5.1
$script:DeskctlVersion = '1.2.6'
$script:DeskctlBatchMaxSteps = 100
$script:DeskctlBatchMaxMs = 120000
$script:DeskctlSleepMaxMs = 10000
$script:DeskctlWaitMaxMs = 60000
$script:DeskctlStepDelayDefaultMs = 120
$script:DeskctlStepDelayMaxMs = 5000
$script:DeskctlBatchCommands = @('screenshot', 'move', 'click', 'scroll', 'type', 'key', 'windows', 'focus', 'wait', 'launch', 'foreground', 'sleep', 'open', 'selftest')

function New-DeskctlResult {
    param(
        [bool]$Ok,
        [string]$ErrorCode,
        [string]$Message,
        [int]$Status = 200,
        [hashtable]$Data = @{}
    )
    $body = [ordered]@{ ok = $Ok }
    if ($ErrorCode) { $body.error = $ErrorCode }
    if ($Message) { $body.message = $Message }
    if ($Data) {
        foreach ($key in $Data.Keys) {
            $body[$key] = $Data[$key]
        }
    }
    return @{ Status = $Status; Body = $body }
}

function ConvertFrom-DeskctlJson {
    param([string]$Text)
    if ([string]::IsNullOrWhiteSpace($Text)) { return [pscustomobject]@{} }
    try {
        return (ConvertFrom-Json -InputObject $Text -ErrorAction Stop)
    } catch {
        throw 'invalid_json'
    }
}

function Test-DeskctlInteger {
    param($Value)
    if ($null -eq $Value) { return $false }
    $n = 0
    return [int]::TryParse([string]$Value, [ref]$n)
}

function Test-DeskctlLong {
    param($Value)
    if ($null -eq $Value) { return $false }
    $n = [long]0
    return [long]::TryParse([string]$Value, [ref]$n)
}

function Test-DeskctlRange {
    param($Value, [int]$Min, [int]$Max)
    if (-not (Test-DeskctlInteger $Value)) { return $false }
    $n = [int]$Value
    return ($n -ge $Min -and $n -le $Max)
}

function Test-DeskctlFlag {
    param($Value)
    return ($null -eq $Value -or $Value -is [bool])
}

function Get-DeskctlProperty {
    param($Object, [string]$Name)
    if ($null -eq $Object) { return $null }
    if ($Object -is [hashtable]) {
        if ($Object.ContainsKey($Name)) { return $Object[$Name] }
        return $null
    }
    $prop = $Object.PSObject.Properties[$Name]
    if ($null -eq $prop) { return $null }
    return $prop.Value
}

# True while the tray switch is still on. Pumps the tray message loop first so a click on
# Turn off during a long batch/wait/type is seen before the next action.
function Test-DeskctlLive {
    param($State)
    if ($null -eq $State -or $null -eq $State.IsEnabled) { return $true }
    if ($State.Pump) { & $State.Pump }
    return [bool](& $State.IsEnabled)
}

# Sleeps in short slices; returns $false as soon as the switch goes off.
function Wait-DeskctlInterval {
    param($State, [int]$Milliseconds)
    $sw = [Diagnostics.Stopwatch]::StartNew()
    while ($true) {
        if (-not (Test-DeskctlLive $State)) { return $false }
        $left = $Milliseconds - [int]$sw.ElapsedMilliseconds
        if ($left -le 0) { return $true }
        Start-Sleep -Milliseconds ([Math]::Min(50, $left))
    }
}

function New-DeskctlKillSwitchResult {
    return New-DeskctlResult $false 'kill_switch_off' 'Grok Bot Desktop is off. Turn it on from the tray icon.' 403
}

# Argument checks shared by single requests and batch steps. Returns $null when valid.
function Test-DeskctlCommandArgs {
    param([string]$Path, $Body)

    $monitor = Get-DeskctlProperty $Body 'monitor'
    $maxWidth = Get-DeskctlProperty $Body 'maxWidth'
    $format = Get-DeskctlProperty $Body 'format'
    $quality = Get-DeskctlProperty $Body 'quality'
    $window = Get-DeskctlProperty $Body 'window'
    $x = Get-DeskctlProperty $Body 'x'
    $y = Get-DeskctlProperty $Body 'y'
    $space = Get-DeskctlProperty $Body 'space'
    $button = Get-DeskctlProperty $Body 'button'
    $dy = Get-DeskctlProperty $Body 'dy'
    $text = Get-DeskctlProperty $Body 'text'
    $combo = Get-DeskctlProperty $Body 'combo'
    $title = Get-DeskctlProperty $Body 'title'
    $hwnd = Get-DeskctlProperty $Body 'hwnd'
    $timeoutMs = Get-DeskctlProperty $Body 'timeoutMs'
    $launchPath = Get-DeskctlProperty $Body 'path'
    $launchArgs = Get-DeskctlProperty $Body 'args'
    $waitTitle = Get-DeskctlProperty $Body 'waitTitle'
    $reuseAfterMs = Get-DeskctlProperty $Body 'reuseAfterMs'
    $ms = Get-DeskctlProperty $Body 'ms'
    $target = Get-DeskctlProperty $Body 'target'

    switch ($Path) {
        '/screenshot' {
            if ($null -ne $maxWidth -and (!(Test-DeskctlInteger $maxWidth) -or [int]$maxWidth -lt 1)) {
                return New-DeskctlResult $false 'invalid_args' 'Invalid maxWidth.' 400
            }
            if ($null -ne $monitor -and [string]$monitor -ne 'all' -and -not (Test-DeskctlInteger $monitor)) {
                return New-DeskctlResult $false 'invalid_args' 'monitor must be all or an index.' 400
            }
            if ($null -ne $format -and [string]$format -notin @('png', 'jpg', 'jpeg')) {
                return New-DeskctlResult $false 'invalid_args' 'format must be png or jpg.' 400
            }
            if ($null -ne $quality -and -not (Test-DeskctlRange $quality 1 100)) {
                return New-DeskctlResult $false 'invalid_args' 'quality must be 1 to 100.' 400
            }
            if ($null -ne $window -and [string]$window -ne 'active') {
                return New-DeskctlResult $false 'invalid_args' 'window only accepts active.' 400
            }
            if ($null -ne $hwnd -and (-not (Test-DeskctlLong $hwnd) -or [long]$hwnd -le 0)) {
                return New-DeskctlResult $false 'invalid_args' 'Invalid hwnd.' 400
            }
            if (-not (Test-DeskctlFlag (Get-DeskctlProperty $Body 'full'))) {
                return New-DeskctlResult $false 'invalid_args' 'full must be true or false.' 400
            }
            if (($null -ne $window -and $null -ne $hwnd) -or (($null -ne $window -or $null -ne $hwnd) -and $null -ne $monitor)) {
                return New-DeskctlResult $false 'invalid_args' 'Use only one of monitor, window or hwnd.' 400
            }
        }
        '/move' {
            if (-not (Test-DeskctlInteger $x) -or -not (Test-DeskctlInteger $y) -or ($null -ne $space -and $space -notin @('screen', 'image'))) {
                return New-DeskctlResult $false 'invalid_args' 'Invalid x, y or space.' 400
            }
        }
        '/click' {
            if (-not (Test-DeskctlInteger $x) -or -not (Test-DeskctlInteger $y) -or ($null -ne $space -and $space -notin @('screen', 'image')) -or ($null -ne $button -and $button -notin @('left', 'right', 'middle'))) {
                return New-DeskctlResult $false 'invalid_args' 'Invalid click arguments.' 400
            }
        }
        '/scroll' {
            $hasX = $null -ne $x
            $hasY = $null -ne $y
            if (-not (Test-DeskctlInteger $dy) -or ($hasX -xor $hasY) -or ($hasX -and -not (Test-DeskctlInteger $x)) -or ($hasY -and -not (Test-DeskctlInteger $y))) {
                return New-DeskctlResult $false 'invalid_args' 'Invalid dy or optional x/y.' 400
            }
        }
        '/type' {
            if ($null -eq $text -or $text -isnot [string]) {
                return New-DeskctlResult $false 'invalid_args' 'text must be a string.' 400
            }
            if ($text.Length -gt 8192) {
                return New-DeskctlResult $false 'invalid_args' 'Text is too long.' 400
            }
            if (-not (Test-DeskctlFlag (Get-DeskctlProperty $Body 'paste'))) {
                return New-DeskctlResult $false 'invalid_args' 'paste must be true or false.' 400
            }
            $gapMs = Get-DeskctlProperty $Body 'gapMs'
            if ($null -ne $gapMs -and -not (Test-DeskctlRange $gapMs 0 50)) {
                return New-DeskctlResult $false 'invalid_args' 'gapMs must be 0 to 50.' 400
            }
        }
        '/key' {
            try {
                $null = ConvertFrom-DeskctlCombo ([string]$combo)
            } catch {
                return New-DeskctlResult $false 'unknown_key' 'Unknown key or combination.' 400
            }
        }
        '/focus' {
            if (-not $hwnd -and [string]::IsNullOrWhiteSpace([string]$title)) {
                return New-DeskctlResult $false 'invalid_args' 'Pass title or hwnd.' 400
            }
        }
        '/wait' {
            if ($null -eq $title -or $title -isnot [string] -or [string]::IsNullOrWhiteSpace($title) -or $title.Length -gt 512) {
                return New-DeskctlResult $false 'invalid_args' 'title must be a non-empty string.' 400
            }
            if ($null -ne $timeoutMs -and -not (Test-DeskctlRange $timeoutMs 0 $script:DeskctlWaitMaxMs)) {
                return New-DeskctlResult $false 'invalid_args' "timeoutMs must be 0 to $($script:DeskctlWaitMaxMs)." 400
            }
            if (-not (Test-DeskctlFlag (Get-DeskctlProperty $Body 'foreground')) -or -not (Test-DeskctlFlag (Get-DeskctlProperty $Body 'gone'))) {
                return New-DeskctlResult $false 'invalid_args' 'foreground y gone deben ser true o false.' 400
            }
        }
        '/launch' {
            if ($null -eq $launchPath -or $launchPath -isnot [string] -or [string]::IsNullOrWhiteSpace($launchPath) -or $launchPath.Length -gt 1024) {
                return New-DeskctlResult $false 'invalid_args' 'path must be a program or file.' 400
            }
            if ($null -ne $launchArgs -and ($launchArgs -isnot [string] -or $launchArgs.Length -gt 4096)) {
                return New-DeskctlResult $false 'invalid_args' 'args must be a string (max 4096).' 400
            }
            if ($null -ne $waitTitle -and ($waitTitle -isnot [string] -or [string]::IsNullOrWhiteSpace($waitTitle) -or $waitTitle.Length -gt 512)) {
                return New-DeskctlResult $false 'invalid_args' 'waitTitle must be a non-empty string.' 400
            }
            if ($null -ne $timeoutMs -and -not (Test-DeskctlRange $timeoutMs 0 $script:DeskctlWaitMaxMs)) {
                return New-DeskctlResult $false 'invalid_args' "timeoutMs must be 0 to $($script:DeskctlWaitMaxMs)." 400
            }
            if ($null -ne $reuseAfterMs -and -not (Test-DeskctlRange $reuseAfterMs 0 $script:DeskctlWaitMaxMs)) {
                return New-DeskctlResult $false 'invalid_args' "reuseAfterMs must be 0 to $($script:DeskctlWaitMaxMs)." 400
            }
        }
        '/open' {
            if ($null -eq $target -or $target -isnot [string] -or [string]::IsNullOrWhiteSpace($target) -or $target.Length -gt 2048) {
                return New-DeskctlResult $false 'invalid_args' 'target must be an app, URL or URI.' 400
            }
            if ($null -ne $launchArgs -and ($launchArgs -isnot [string] -or $launchArgs.Length -gt 4096)) {
                return New-DeskctlResult $false 'invalid_args' 'args must be a string (max 4096).' 400
            }
            if ($null -ne $waitTitle -and ($waitTitle -isnot [string] -or [string]::IsNullOrWhiteSpace($waitTitle) -or $waitTitle.Length -gt 512)) {
                return New-DeskctlResult $false 'invalid_args' 'waitTitle must be a non-empty string.' 400
            }
            if ($null -ne $timeoutMs -and -not (Test-DeskctlRange $timeoutMs 0 $script:DeskctlWaitMaxMs)) {
                return New-DeskctlResult $false 'invalid_args' "timeoutMs must be 0 to $($script:DeskctlWaitMaxMs)." 400
            }
        }
        '/sleep' {
            if (-not (Test-DeskctlRange $ms 0 $script:DeskctlSleepMaxMs)) {
                return New-DeskctlResult $false 'invalid_args' "ms must be 0 to $($script:DeskctlSleepMaxMs)." 400
            }
        }
    }
    return $null
}

function Invoke-DeskctlCommand {
    param([string]$Path, $Body, $State)
    switch ($Path) {
        '/screenshot' { return Invoke-DeskctlScreenshot $Body $State }
        '/move'       { return Invoke-DeskctlMove $Body $State }
        '/click'      { return Invoke-DeskctlClick $Body $State }
        '/scroll'     { return Invoke-DeskctlScroll $Body $State }
        '/type'       { return Invoke-DeskctlType $Body $State }
        '/key'        { return Invoke-DeskctlKey $Body $State }
        '/windows'    { return Invoke-DeskctlWindows $State }
        '/focus'      { return Invoke-DeskctlFocus $Body $State }
        '/wait'       { return Invoke-DeskctlWait $Body $State }
        '/launch'     { return Invoke-DeskctlLaunch $Body $State }
        '/open'       { return Invoke-DeskctlOpen $Body $State }
        '/selftest'   { return Invoke-DeskctlSelftest $Body $State }
        '/foreground' { return Invoke-DeskctlForeground $State }
        '/sleep' {
            $ms = [int](Get-DeskctlProperty $Body 'ms')
            if (-not (Wait-DeskctlInterval $State $ms)) { return New-DeskctlKillSwitchResult }
            return New-DeskctlResult $true $null $null 200 @{ ms = $ms }
        }
    }
    return New-DeskctlResult $false 'not_found' 'Unknown route.' 404
}

# Body: {"steps":[...], "stepDelayMs": N} or a plain array of steps. stepDelayMs (default 120,
# 0 = off) is a pause between steps so one window can settle before the next action; it is
# skipped next to an explicit sleep step and the kill switch is checked during it.
function Invoke-DeskctlBatch {
    param($Body, $State)
    $delayMs = $script:DeskctlStepDelayDefaultMs
    if ($Body -is [Array] -or $Body -is [Collections.IList]) {
        $raw = $Body
    } elseif ($null -ne (Get-DeskctlProperty $Body 'cmd') -and $null -eq (Get-DeskctlProperty $Body 'steps')) {
        # A one-step array can arrive unrolled as the step itself.
        $raw = @(, $Body)
    } else {
        $raw = Get-DeskctlProperty $Body 'steps'
        $delayArg = Get-DeskctlProperty $Body 'stepDelayMs'
        if ($null -ne $delayArg) {
            if ($delayArg -is [bool] -or -not (Test-DeskctlRange $delayArg 0 $script:DeskctlStepDelayMaxMs)) {
                return New-DeskctlResult $false 'invalid_args' "stepDelayMs must be 0 to $($script:DeskctlStepDelayMaxMs)." 400
            }
            $delayMs = [int]$delayArg
        }
    }
    if ($null -eq $raw -or $raw -is [string]) {
        return New-DeskctlResult $false 'invalid_args' 'steps must be a list of steps.' 400
    }
    $steps = @($raw)
    if ($steps.Count -lt 1 -or $steps.Count -gt $script:DeskctlBatchMaxSteps) {
        return New-DeskctlResult $false 'invalid_args' "steps must have 1 to $($script:DeskctlBatchMaxSteps) steps." 400
    }

    # Validate every step before running any, so a typo never leaves a half-done sequence.
    $paths = New-Object string[] $steps.Count
    for ($i = 0; $i -lt $steps.Count; $i++) {
        $step = $steps[$i]
        $cmd = Get-DeskctlProperty $step 'cmd'
        if ($null -eq $step -or $step -is [string] -or $step -is [ValueType] -or $cmd -isnot [string] -or $cmd.ToLowerInvariant() -notin $script:DeskctlBatchCommands) {
            return New-DeskctlResult $false 'invalid_args' "Step $i`: invalid cmd. Valid: $($script:DeskctlBatchCommands -join ', ')." 400 @{ failedStep = $i }
        }
        $paths[$i] = '/' + $cmd.ToLowerInvariant()
        $bad = Test-DeskctlCommandArgs $paths[$i] $step
        if ($bad) {
            $bad.Body.message = "Step $i ($cmd): $($bad.Body.message)"
            $bad.Body.failedStep = $i
            return $bad
        }
    }

    $results = New-Object Collections.ArrayList
    $total = [Diagnostics.Stopwatch]::StartNew()
    for ($i = 0; $i -lt $steps.Count; $i++) {
        $cmd = $paths[$i].Substring(1)
        $paused = $true
        if ($i -gt 0 -and $delayMs -gt 0 -and $cmd -ne 'sleep' -and $paths[$i - 1] -ne '/sleep') {
            $paused = Wait-DeskctlInterval $State $delayMs
        }
        if (-not $paused -or -not (Test-DeskctlLive $State)) {
            $res = New-DeskctlKillSwitchResult
        } elseif ($total.ElapsedMilliseconds -gt $script:DeskctlBatchMaxMs) {
            $res = New-DeskctlResult $false 'batch_timeout' "The batch took longer than $($script:DeskctlBatchMaxMs) ms." 408
        } else {
            $sw = [Diagnostics.Stopwatch]::StartNew()
            try {
                $res = Invoke-DeskctlCommand $paths[$i] $steps[$i] $State
            } catch {
                $res = New-DeskctlResult $false 'step_failed' $_.Exception.Message 500
            }
            $sw.Stop()
            if ($res -and $res.Body) { $res.Body.ms = [int]$sw.ElapsedMilliseconds }
        }
        $entry = [ordered]@{ step = $i; cmd = $cmd }
        foreach ($key in $res.Body.Keys) { $entry[$key] = $res.Body[$key] }
        [void]$results.Add($entry)
        if (-not $res.Body.ok) {
            return New-DeskctlResult $false ([string]$res.Body.error) "Step $i ($cmd) failed: $($res.Body.message)" $res.Status @{
                steps      = $steps.Count
                completed  = $i
                failedStep = $i
                elapsedMs  = [int]$total.ElapsedMilliseconds
                stepDelayMs = $delayMs
                results    = $results
            }
        }
    }
    return New-DeskctlResult $true $null $null 200 @{
        steps     = $steps.Count
        completed = $steps.Count
        elapsedMs = [int]$total.ElapsedMilliseconds
        stepDelayMs = $delayMs
        results   = $results
    }
}

function Resolve-DeskctlRoute {
    param(
        [string]$Method,
        [string]$Path,
        $Body,
        [bool]$Enabled,
        [bool]$NativeAvailable,
        [hashtable]$State
    )
    if ($Path -match '\?') { $Path = $Path.Split('?')[0] }

    if ($Path -eq '/status' -and $Method -eq 'GET') {
        return New-DeskctlResult -Ok $true -Status 200 -Data @{
            version        = $script:DeskctlVersion
            enabled        = $Enabled
            host           = '127.0.0.1'
            port           = $State.Port
            pid            = $PID
            dpiAwareness   = $State.Dpi
            virtualScreen  = $State.Virtual
            monitors       = $State.Monitors
            killSwitch     = $(if ($Enabled) { 'on' } else { 'off' })
            platform       = $(if ($NativeAvailable) { 'windows' } else { 'linux' })
            features       = @('batch', 'wait', 'launch', 'foreground', 'screenshot-jpg', 'screenshot-window', 'step-delay', 'cloak-aware', 'uri-launch', 'open', 'light-screenshot', 'fast-client', 'open-by-process', 'no-input-open', 'f24-unlock', 'attach-foreground', 'native-type', 'selftest', 'unicode-type', 'paste')
        }
    }

    $post = @('/screenshot', '/move', '/click', '/scroll', '/type', '/key', '/focus', '/batch', '/wait', '/launch', '/open', '/selftest')
    $get  = @('/windows', '/foreground')
    $known = $post + $get
    if ($Path -in $known -and (( $Method -eq 'POST' -and $Path -notin $post) -or ($Method -eq 'GET' -and $Path -notin $get) -or ($Method -notin @('GET', 'POST')))) {
        return New-DeskctlResult $false 'method_not_allowed' 'Method not allowed.' 405
    }
    if ($Path -notin $known) {
        return New-DeskctlResult $false 'not_found' 'Unknown route.' 404
    }

    # Kill switch has priority over not_windows.
    if (-not $Enabled) {
        return New-DeskctlKillSwitchResult
    }
    if (-not $NativeAvailable) {
        return New-DeskctlResult $false 'not_windows' 'This action requires Windows.' 501
    }

    if ($Path -eq '/batch') {
        return Invoke-DeskctlBatch $Body $State
    }
    $bad = Test-DeskctlCommandArgs $Path $Body
    if ($bad) { return $bad }
    return Invoke-DeskctlCommand $Path $Body $State
}
