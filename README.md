# Pomodoro Timer

[![License: MIT](https://img.shields.io/badge/license-MIT-green.svg)](LICENSE)
![Platform: Windows 10+](https://img.shields.io/badge/platform-Windows%2010%2B-blue.svg)
![PowerShell 5.1+](https://img.shields.io/badge/PowerShell-5.1%2B-5391FE.svg)

Single-file Pomodoro timer for Windows PowerShell. No dependencies. Locks your workstation after each work session by default (`-NoLockScreen` to disable).

## Usage

Double-click `pomodoro.cmd`, or run:

```powershell
powershell -ExecutionPolicy Bypass -File .\pomodoro.ps1
```

Custom durations:

```powershell
.\pomodoro.ps1 -WorkMinutes 50 -ShortBreakMinutes 10 -LongBreakMinutes 30
```

With session logging:

```powershell
.\pomodoro.ps1 -LogPath .\pomodoro_log.csv
```

## Parameters

| Parameter            | Default | Description                                                      |
| -------------------- | ------- | ---------------------------------------------------------------- |
| `-WorkMinutes`       | 25      | Focus period length (1-120).                                     |
| `-ShortBreakMinutes` | 5       | Short break length (1-60).                                       |
| `-LongBreakMinutes`  | 15      | Long break length (1-60).                                        |
| `-LongBreakEvery`    | 4       | Work sessions before a long break (2-20). Skipped sessions count. |
| `-LogPath`           | (none)  | CSV log file path. Logging is disabled unless a path is supplied. |
| `-NoSound`           | off     | Disable beeps.                                                   |
| `-NoTray`            | off     | Disable tray icon.                                               |
| `-NoLockScreen`      | off     | Disable autolock after each work block.                          |

## Controls

- Keyboard: `P` pause/resume, `S` skip, `Q` quit.
- Tray: right-click the icon for the same actions.

## Requirements

Windows 10+, PowerShell 5.1+ (built-in).

## License

[MIT](LICENSE) (c) 2025
