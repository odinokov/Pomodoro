# Pomodoro Timer

Single-file Pomodoro timer for Windows PowerShell. No dependencies.

## Usage

```powershell
powershell -ExecutionPolicy Bypass -File .\pomodoro.ps1
```

Custom durations:

```powershell
.\pomodoro.ps1 -WorkMinutes 50 -ShortBreakMinutes 10 -LongBreakMinutes 30
```

## Parameters

| Parameter            | Default | Description                                  |
| -------------------- | ------- | -------------------------------------------- |
| `-WorkMinutes`       | 25      | Focus period length (1-120).                 |
| `-ShortBreakMinutes` | 5       | Short break length (1-60).                   |
| `-LongBreakMinutes`  | 15      | Long break length (1-60).                    |
| `-LongBreakEvery`    | 4       | Work sessions before a long break (2-20).    |
| `-LogPath`           | `pomodoro_log.csv` next to the script | CSV log file path.  |
| `-NoSound`           | off     | Disable beeps.                               |
| `-NoTray`            | off     | Disable tray icon.                           |
| `-LockScreen`        | off     | Lock the workstation after each work block.  |

## Controls

- Keyboard: `P` pause/resume, `S` skip, `Q` quit.
- Tray: right-click the icon for the same actions.

## Requirements

Windows 10+, PowerShell 5.1+ (built-in).

## License

MIT (c) 2025
