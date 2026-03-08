#Requires -Version 5.1

# pomodoro.ps1 — Pomodoro timer with tray icon, popups, keyboard controls, CSV logging.
# Usage: powershell -ExecutionPolicy Bypass -File ".\pomodoro.ps1" [-WorkMinutes 25] [-NoSound] [-NoTray]

param(
    [ValidateRange(1, 120)] [int]$WorkMinutes        = 25,
    [ValidateRange(1, 60)]  [int]$ShortBreakMinutes  = 5,
    [ValidateRange(1, 60)]  [int]$LongBreakMinutes   = 15,
    [ValidateRange(2, 20)]  [int]$LongBreakEvery     = 4,
    [string]$LogPath = (Join-Path $PSScriptRoot 'pomodoro_log.csv'),
    [switch]$NoSound,
    [switch]$NoTray
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

Add-Type -AssemblyName System.Windows.Forms
Add-Type -AssemblyName System.Drawing

# --- Phase config table (eliminates all switch/if chains) ---

$script:Phases = @{
    WORK        = @{ Duration = { $WorkMinutes * 60 };       Color = 'Red';        Beep = @(700,200,900,300) }
    SHORT_BREAK = @{ Duration = { $ShortBreakMinutes * 60 }; Color = 'Green';      Beep = @(600,150,600,150,800,250) }
    LONG_BREAK  = @{ Duration = { $LongBreakMinutes * 60 };  Color = 'Cyan';       Beep = @(500,200,600,200,800,400) }
    PAUSED      = @{ Duration = { 0 };                       Color = 'DarkYellow';  Beep = @() }
}

# --- State ---

$script:S = @{
    Mode = ''; PrevMode = ''; PomodoroCount = 0; TotalWorkSec = 0
    RemainingSec = 0; Running = $false; SessionStart = $null
}
$script:Stopwatch   = $null
$script:LastTickSec = 0
$script:TrayIcon    = $null
$script:PauseItem   = $null
$script:SavedTitle  = $Host.UI.RawUI.WindowTitle

# --- Logging ---

function Write-PomodoroLog([string]$Type, [hashtable]$Payload = @{}) {
    $row = [pscustomobject]@{
        Timestamp = (Get-Date).ToString('s')
        Type      = $Type
        Mode      = $script:S.Mode
        Count     = $script:S.PomodoroCount
        Payload   = ($Payload | ConvertTo-Json -Compress)
    }
    $exists = Test-Path $LogPath
    $row | Export-Csv -Path $LogPath -NoTypeInformation -Append:$exists
}

# --- Notification (injection-safe via EncodedCommand) ---

function Show-Popup([string]$Title, [string]$Body) {
    $safeBody  = $Body  -replace "'","''"
    $safeTitle = $Title -replace "'","''"
    $code = @"
Add-Type -AssemblyName PresentationFramework
`$w = New-Object System.Windows.Window -Property @{
    Topmost=`$true; ShowInTaskbar=`$false; WindowStyle='None'
    Width=0; Height=0; Opacity=0; ShowActivated=`$true
}
`$w.Show()
[System.Windows.MessageBox]::Show(`$w, '$safeBody', '$safeTitle', 'OK', 'Information') | Out-Null
`$w.Close()
"@
    $encoded = [Convert]::ToBase64String([Text.Encoding]::Unicode.GetBytes($code))
    Start-Process powershell -WindowStyle Hidden -ArgumentList '-NoProfile','-EncodedCommand',$encoded -ErrorAction SilentlyContinue
}

function Send-Beep([int[]]$Pattern) {
    if ($NoSound -or $Pattern.Count -eq 0) { return }
    for ($i = 0; $i -lt $Pattern.Count; $i += 2) {
        [Console]::Beep($Pattern[$i], $Pattern[$i + 1])
        if ($i + 2 -lt $Pattern.Count) { Start-Sleep -Milliseconds 80 }
    }
}

# --- Tray ---

function Initialize-Tray {
    if ($NoTray) { return }
    $script:TrayIcon = New-Object System.Windows.Forms.NotifyIcon -Property @{
        Text = 'Pomodoro'; Icon = [System.Drawing.SystemIcons]::Application; Visible = $true
    }
    $menu = New-Object System.Windows.Forms.ContextMenuStrip
    $script:PauseItem = $menu.Items.Add('Pause')
    $script:PauseItem.Add_Click({ Toggle-Pause })
    $skipItem = $menu.Items.Add('Skip')
    $skipItem.Add_Click({ Skip-Phase })
    [void]$menu.Items.Add((New-Object System.Windows.Forms.ToolStripSeparator))
    $quitItem = $menu.Items.Add('Quit')
    $quitItem.Add_Click({ $script:S.Mode = 'STOPPED'; $script:S.Running = $false })
    $script:TrayIcon.ContextMenuStrip = $menu
}

function Update-Tray {
    if (-not $script:TrayIcon) { return }
    $r = [TimeSpan]::FromSeconds([math]::Max(0, $script:S.RemainingSec)).ToString('mm\:ss')
    $tip = "Pomodoro - $($script:S.Mode -replace '_',' ') $r (#$($script:S.PomodoroCount))"
    $script:TrayIcon.Text = $tip.Substring(0, [math]::Min(63, $tip.Length))
}

function Remove-Tray {
    if ($script:TrayIcon) { $script:TrayIcon.Visible = $false; $script:TrayIcon.Dispose() }
}

# --- Core state machine (single entry point for all phase transitions) ---

function Enter-Phase([string]$Phase) {
    $cfg = $script:Phases[$Phase]
    $script:S.Mode         = $Phase
    $script:S.RemainingSec = (& $cfg.Duration)
    $script:S.Running      = $true

    Write-PomodoroLog -Type "${Phase}_STARTED"
    Send-Beep $cfg.Beep

    # Build context-aware popup message
    $msg = switch ($Phase) {
        'WORK' {
            $n = $script:S.PomodoroCount + 1
            $until = $LongBreakEvery - ($n % $LongBreakEvery)
            if ($until -eq $LongBreakEvery) { $until = 0 }
            $text = "Work session #$n ($WorkMinutes min)`n`nCompleted: $($script:S.PomodoroCount)"
            if ($until -gt 0) { $text += "`nUntil long break: $until" }
            $text
        }
        'SHORT_BREAK' {
            $until = $LongBreakEvery - ($script:S.PomodoroCount % $LongBreakEvery)
            "Pomodoro #$($script:S.PomodoroCount) done!`n`nShort break: $ShortBreakMinutes min`n$until more until long break"
        }
        'LONG_BREAK' {
            $wt = [TimeSpan]::FromSeconds($script:S.TotalWorkSec).ToString('h\h\ mm\m')
            "Pomodoro #$($script:S.PomodoroCount) done!`n`nLong break: $LongBreakMinutes min`nTotal focus: $wt`n`nStretch, walk, hydrate."
        }
    }
    Show-Popup -Title ($Phase -replace '_',' ') -Body $msg
}

function Toggle-Pause {
    if ($script:S.Mode -eq 'PAUSED') {
        $script:S.Mode    = $script:S.PrevMode
        $script:S.Running = $true
        $script:LastTickSec = [int][math]::Floor($script:Stopwatch.Elapsed.TotalSeconds)
        $script:Stopwatch.Start()
        Write-PomodoroLog -Type 'RESUMED'
    }
    elseif ($script:S.Running) {
        $script:S.PrevMode = $script:S.Mode
        $script:S.Mode     = 'PAUSED'
        $script:S.Running  = $false
        $script:Stopwatch.Stop()
        Write-PomodoroLog -Type 'PAUSED'
        $r = [TimeSpan]::FromSeconds([math]::Max(0, $script:S.RemainingSec)).ToString('mm\:ss')
        Show-Popup -Title 'PAUSED' -Body "Paused during $($script:S.PrevMode -replace '_',' ')`nRemaining: $r`n`nPress [P] to resume"
    }
    if ($script:PauseItem) {
        $script:PauseItem.Text = if ($script:S.Mode -eq 'PAUSED') { 'Resume' } else { 'Pause' }
    }
}

function Skip-Phase {
    if ($script:S.Mode -eq 'STOPPED') { return }
    $active = if ($script:S.Mode -eq 'PAUSED') {
        $script:S.Running = $true
        $script:LastTickSec = [int][math]::Floor($script:Stopwatch.Elapsed.TotalSeconds)
        $script:Stopwatch.Start()
        $script:S.PrevMode
    } else { $script:S.Mode }

    Write-PomodoroLog -Type 'PHASE_SKIPPED' -Payload @{ SkippedMode = $active }

    if ($active -eq 'WORK') {
        $script:S.PomodoroCount++
        Enter-Phase (Get-NextBreak)
    } else {
        Enter-Phase 'WORK'
    }
    if ($script:PauseItem) { $script:PauseItem.Text = 'Pause' }
}

function Get-NextBreak {
    if (($script:S.PomodoroCount % $LongBreakEvery) -eq 0) { 'LONG_BREAK' } else { 'SHORT_BREAK' }
}

# --- Tick ---

function Invoke-Tick([int]$Delta) {
    if (-not $script:S.Running) { return }
    $script:S.RemainingSec -= $Delta
    if ($script:S.Mode -eq 'WORK') { $script:S.TotalWorkSec += $Delta }
    if ($script:S.RemainingSec -gt 0) { return }

    $script:S.RemainingSec = 0

    switch ($script:S.Mode) {
        'WORK' {
            $script:S.PomodoroCount++
            Write-PomodoroLog -Type 'WORK_COMPLETED' -Payload @{ Count = $script:S.PomodoroCount }
            Enter-Phase (Get-NextBreak)
        }
        default {
            Write-PomodoroLog -Type "$($script:S.Mode)_COMPLETED"
            Enter-Phase 'WORK'
        }
    }
}

# --- Display (one line, no banners) ---

function Write-Status {
    $c   = [math]::Max(0, $script:S.RemainingSec)
    $r   = [TimeSpan]::FromSeconds($c).ToString('mm\:ss')
    $m   = $script:S.Mode
    $cfg = $script:Phases[$m]
    if (-not $cfg) { $cfg = $script:Phases[$script:S.PrevMode] }
    $total = if ($cfg) { [math]::Max(1, (& $cfg.Duration)) } else { 1 }
    $pct = [math]::Max(0, [math]::Min(100, [int]((1 - $c / $total) * 100)))

    $barW = 25
    $fill = [int]($pct / 100 * $barW)
    $bar  = '<' + ('=' * $fill) + ('.' * ($barW - $fill)) + '>'

    $color = if ($cfg) { $cfg.Color } else { 'White' }
    $label = ($m -replace '_',' ').PadRight(12)
    $line  = " {0} | {1}| {2} | {3} {4,3}% | #{5}" -f (Get-Date -Format 'HH:mm:ss'), $label, $r, $bar, $pct, $script:S.PomodoroCount

    try { $w = [Console]::BufferWidth } catch { $w = 80 }
    Write-Host ("`r" + $line.PadRight($w - 1)) -NoNewline -ForegroundColor $color

    $Host.UI.RawUI.WindowTitle = "Pomodoro | $($m -replace '_',' ') $r (#$($script:S.PomodoroCount))"
}

# --- Main ---

function Start-PomodoroSession {
    Write-Host ''
    Write-Host 'Pomodoro Timer v1.0' -ForegroundColor Cyan
    Write-Host ''
    Write-Host "Work: ${WorkMinutes}m | Short break: ${ShortBreakMinutes}m | Long break: ${LongBreakMinutes}m (x$LongBreakEvery)" -ForegroundColor DarkGray
    Write-Host "Keys: [P]ause  [S]kip  [Q]uit$(if (-not $NoTray) { '  |  Tray: right-click for menu' })" -ForegroundColor DarkGray
    Write-Host ''

    $script:S.SessionStart = Get-Date
    Initialize-Tray
    Write-PomodoroLog -Type 'SESSION_STARTED'
    Enter-Phase 'WORK'

    $script:Stopwatch   = [System.Diagnostics.Stopwatch]::StartNew()
    $script:LastTickSec = 0

    try {
        while ($script:S.Mode -ne 'STOPPED') {
            [System.Windows.Forms.Application]::DoEvents()
            Start-Sleep -Milliseconds 200

            if ($script:S.Running) {
                $elapsed = [int][math]::Floor($script:Stopwatch.Elapsed.TotalSeconds)
                $delta   = $elapsed - $script:LastTickSec
                if ($delta -ge 1) { Invoke-Tick $delta; $script:LastTickSec = $elapsed }
            }

            Write-Status
            Update-Tray

            if ([Console]::KeyAvailable) {
                switch ([Console]::ReadKey($true).KeyChar) {
                    'p' { Toggle-Pause }
                    's' { Skip-Phase }
                    'q' { $script:S.Mode = 'STOPPED'; $script:S.Running = $false }
                }
            }
        }
    }
    finally {
        Write-PomodoroLog -Type 'SESSION_STOPPED'
        if (-not $NoSound) { Send-Beep @(800,150,1000,150,1200,300) }
        Remove-Tray
        $Host.UI.RawUI.WindowTitle = $script:SavedTitle

        $elapsed  = ((Get-Date) - $script:S.SessionStart).ToString('h\h\ mm\m')
        $workTime = [TimeSpan]::FromSeconds($script:S.TotalWorkSec).ToString('h\h\ mm\m')
        Write-Host ''
        Write-Host "Done. Pomodoros: $($script:S.PomodoroCount) | Focus: $workTime | Session: $elapsed | Log: $LogPath" -ForegroundColor DarkGray
    }
}

Start-PomodoroSession
