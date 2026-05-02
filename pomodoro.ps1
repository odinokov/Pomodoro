#Requires -Version 5.1
<#
.SYNOPSIS
  Simple, robust Pomodoro timer for Windows (no admin rights).
.DESCRIPTION
  Runs a 25-minute work session, then a 5-minute break, and every 4th break becomes 15 min.
  Tray icon with Pause/Resume, Skip, Quit.  Console keyboard: P, S, Q.
  Locks the workstation after each work session by default (-NoLockScreen to disable).  Logs sessions to CSV.
.PARAMETER WorkMinutes
  Focus period length (default 25).
.PARAMETER ShortBreakMinutes
  Short break length (default 5).
.PARAMETER LongBreakMinutes
  Long break length (default 15).
.PARAMETER LongBreakEvery
  How many work sessions before a long break (default 4).
.PARAMETER LogPath
  Optional CSV log file path. Logging is disabled unless this is supplied.
.PARAMETER NoSound
  Disable beep sounds.
.PARAMETER NoTray
  Disable tray icon.
.PARAMETER NoLockScreen
  Disable locking the workstation after each work block (locking is on by default).
.EXAMPLE
  powershell.exe -NoProfile -ExecutionPolicy Bypass -File ./pomodoro.ps1 -WorkMinutes 30 -NoLockScreen
#>

param(
    [ValidateRange(1, 120)][int]$WorkMinutes       = 25,
    [ValidateRange(1, 60)][int]$ShortBreakMinutes = 5,
    [ValidateRange(1, 60)][int]$LongBreakMinutes  = 15,
    [ValidateRange(2, 20)][int]$LongBreakEvery    = 4,
    [string]$LogPath,
    [switch]$NoSound,
    [switch]$NoTray,
    [switch]$NoLockScreen
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

Add-Type -AssemblyName System.Windows.Forms
Add-Type -AssemblyName System.Drawing

# ----- globals --------------------------------------------------------
$script:PomodoroCount = 0
$script:TotalWorkSec  = 0
$script:SessionStart  = $null
$script:TrayIcon      = $null
$script:TrayAction    = $null

# ----- logging (never fatal) ------------------------------------------
function Write-Log([string]$Event, [string]$Phase = '', [string]$Detail = '') {
    if ([string]::IsNullOrWhiteSpace($LogPath)) { return }
    try {
        $row = [pscustomobject]@{
            Timestamp = (Get-Date).ToString('s')
            Event     = $Event
            Phase     = $Phase
            Count     = $script:PomodoroCount
            Detail    = $Detail
        }
        if (Test-Path $LogPath) {
            $row | Export-Csv $LogPath -NoTypeInformation -Append
        } else {
            $row | Export-Csv $LogPath -NoTypeInformation
        }
    } catch { }
}

# ----- sound (never fatal) --------------------------------------------
# Pattern is an array of @(frequency, durationMs) pairs.
function Send-Beep([int[][]]$Pattern) {
    if ($NoSound) { return }
    try {
        foreach ($tone in $Pattern) {
            [Console]::Beep($tone[0], $tone[1])
        }
    } catch { }
}

# ----- notification ----------------------------------------------------
function Show-Notification([string]$Title, [string]$Body) {
    if ($script:TrayIcon) {
        try {
            $script:TrayIcon.BalloonTipTitle = $Title
            $script:TrayIcon.BalloonTipText  = $Body
            $script:TrayIcon.BalloonTipIcon  = 'Info'
            $script:TrayIcon.ShowBalloonTip(5000)
        } catch { }
    } else {
        Write-Host "`n  [$Title] $Body`n" -ForegroundColor Yellow
    }
}

# ----- tray icon -------------------------------------------------------
function Initialize-Tray {
    if ($NoTray) { return }
    try {
        $script:TrayIcon = New-Object System.Windows.Forms.NotifyIcon -Property @{
            Text    = 'Pomodoro'
            Icon    = [System.Drawing.SystemIcons]::Application
            Visible = $true
        }
        $menu = New-Object System.Windows.Forms.ContextMenuStrip
        $menu.Items.Add('Pause / Resume').Add_Click({ $script:TrayAction = 'PAUSE' })
        $menu.Items.Add('Skip').Add_Click({ $script:TrayAction = 'SKIP' })
        [void]$menu.Items.Add((New-Object System.Windows.Forms.ToolStripSeparator))
        $menu.Items.Add('Quit').Add_Click({ $script:TrayAction = 'QUIT' })
        $script:TrayIcon.ContextMenuStrip = $menu
    } catch { $script:TrayIcon = $null }
}

function Update-TrayTip([string]$Phase, [int]$RemainSec) {
    if (-not $script:TrayIcon) { return }
    try {
        $r   = [TimeSpan]::FromSeconds($RemainSec).ToString('mm\:ss')
        $tip = "Pomodoro - $Phase $r  (#$($script:PomodoroCount))"
        $script:TrayIcon.Text = $tip.Substring(0, [Math]::Min(63, $tip.Length))
    } catch { }
}

function Remove-Tray {
    if ($script:TrayIcon) {
        try { $script:TrayIcon.Visible = $false; $script:TrayIcon.Dispose() } catch { }
        $script:TrayIcon = $null
    }
}

# ----- countdown engine ------------------------------------------------
function Start-Countdown([string]$Phase, [int]$Seconds) {
    $deadline     = (Get-Date).AddSeconds($Seconds)
    $paused       = $false
    $frozenRemain = 0

    while ($true) {
        try { [System.Windows.Forms.Application]::DoEvents() } catch { }

        if ($paused) {
            $remain = $frozenRemain
        } else {
            $remain = [int][Math]::Ceiling(($deadline - (Get-Date)).TotalSeconds)
            if ($remain -lt 0) { $remain = 0 }
        }

        $displayPhase = if ($paused) { 'PAUSED' } else { $Phase }
        $percent = [Math]::Max(0, [Math]::Min(100, [int]((1 - $remain / $Seconds) * 100)))
        $r = [TimeSpan]::FromSeconds($remain).ToString('mm\:ss')

        Write-Progress -Activity "$displayPhase  $r  (#$($script:PomodoroCount))" `
                       -Status "Time remaining: $r" `
                       -PercentComplete $percent
        Update-TrayTip -Phase $displayPhase -RemainSec $remain
        try { $Host.UI.RawUI.WindowTitle = "Pomodoro | $displayPhase $r (#$($script:PomodoroCount))" } catch { }

        if (-not $paused -and $remain -le 0) {
            Write-Progress -Activity "$displayPhase" -Completed
            return 'DONE'
        }

        # keyboard input
        $key = $null
        try { if ([Console]::KeyAvailable) { $key = [Console]::ReadKey($true).KeyChar } } catch { }
        # tray menu actions
        if ($script:TrayAction) {
            $key = switch ($script:TrayAction) {
                'PAUSE' { 'p' } 'SKIP' { 's' } 'QUIT' { 'q' }
            }
            $script:TrayAction = $null
        }

        switch ($key) {
            'p' {
                if ($paused) {
                    $deadline = (Get-Date).AddSeconds($frozenRemain)
                    $paused   = $false
                    Write-Log -Event 'RESUME' -Phase $Phase
                } else {
                    $frozenRemain = $remain
                    $paused       = $true
                    Write-Log -Event 'PAUSE' -Phase $Phase
                }
            }
            's' {
                Write-Log -Event 'SKIP' -Phase $Phase
                Write-Progress -Activity "$Phase" -Completed
                return 'SKIP'
            }
            'q' {
                Write-Progress -Activity "$Phase" -Completed
                return 'QUIT'
            }
        }

        Start-Sleep -Milliseconds 250
    }
}

# ----- main session ----------------------------------------------------
function Start-Pomodoro {
    Write-Host "`n  Pomodoro Timer  --  Work: ${WorkMinutes}m  |  Short: ${ShortBreakMinutes}m  |  Long: ${LongBreakMinutes}m (every $LongBreakEvery)`n  Keys: [P]ause  [S]kip  [Q]uit`n  Tray: right-click`n  Lock: $(if($NoLockScreen){'OFF'}else{'ON'})`n" -ForegroundColor DarkGray

    $script:SessionStart = Get-Date
    Initialize-Tray
    Write-Log -Event 'SESSION_START'

    try {
        while ($true) {
            # Work phase
            Write-Log -Event 'PHASE_START' -Phase 'WORK'
            Send-Beep @(@(700,200),@(900,200),@(1100,300))

            $result = Start-Countdown -Phase 'WORK' -Seconds ($WorkMinutes * 60)
            if ($result -eq 'QUIT') { break }

            $script:PomodoroCount++
            if ($result -eq 'DONE') { $script:TotalWorkSec += ($WorkMinutes * 60) }
            Write-Log -Event "WORK_$result" -Detail "count=$($script:PomodoroCount)"

            # Break phase
            $isLong    = ($script:PomodoroCount % $LongBreakEvery) -eq 0
            $breakName = if ($isLong) { 'LONG BREAK' }  else { 'SHORT BREAK' }
            $breakSec  = if ($isLong) { $LongBreakMinutes * 60 } else { $ShortBreakMinutes * 60 }
            $breakBeep = if ($isLong) { @(@(500,200),@(600,200),@(800,400)) } else { @(@(600,150),@(600,150),@(800,250)) }

            if (-not $NoLockScreen) {
                Write-Log -Event 'SCREEN_LOCKED'
                try { rundll32.exe user32.dll,LockWorkStation } catch { }
            } else {
                $wt = [TimeSpan]::FromSeconds($script:TotalWorkSec).ToString('h\h\ mm\m')
                Show-Notification -Title $breakName `
                    -Body "Pomodoro #$($script:PomodoroCount) done!`n$breakName`nTotal focus: $wt"
            }

            Write-Log -Event 'PHASE_START' -Phase $breakName
            Send-Beep $breakBeep

            $result = Start-Countdown -Phase $breakName -Seconds $breakSec
            if ($result -eq 'QUIT') { break }

            Write-Log -Event "BREAK_$result" -Phase $breakName
            Show-Notification -Title 'WORK' `
                -Body "Break over! Session #$($script:PomodoroCount + 1) starting."
        }
    }
    finally {
        Write-Log -Event 'SESSION_END'
        if (-not $NoSound) { Send-Beep @(@(800,150),@(1000,150),@(1200,300)) }
        Remove-Tray

        $elapsed  = ((Get-Date) - $script:SessionStart).ToString('h\h\ mm\m')
        $workTime = [TimeSpan]::FromSeconds($script:TotalWorkSec).ToString('h\h\ mm\m')
        $logPart  = if ([string]::IsNullOrWhiteSpace($LogPath)) { '' } else { "  |  Log: $LogPath" }
        Write-Host "`n  Done.  Pomodoros: $($script:PomodoroCount)  |  Focus: $workTime  |  Session: $elapsed$logPart`n" -ForegroundColor DarkGray
    }
}

# ----- entry point -----------------------------------------------------
try {
    Start-Pomodoro
}
catch {
    Write-Host "`n  FATAL: $_" -ForegroundColor Red
    Write-Host "  $($_.ScriptStackTrace)" -ForegroundColor DarkRed
    Write-Host ""
    Read-Host "  Press Enter to exit"
}
