# Pomodoro Timer

Single-file Pomodoro timer for Windows PowerShell. No dependencies.

<img width="897" height="492" alt="image" src="https://github.com/user-attachments/assets/29b4a8c2-f8c7-49b6-a6aa-9bb5f9249b3f" />

## Usage

```powershell
powershell -ExecutionPolicy Bypass -File .\pomodoro.ps1
```

Custom durations:

```powershell
.\pomodoro.ps1 -WorkMinutes 50 -ShortBreakMinutes 10 -LongBreakMinutes 30
```

Other flags: `-NoSound`, `-NoTray`, `-LongBreakEvery 4`, `-LogPath .\log.csv`.

## Controls

Keyboard: `P` pause, `S` skip, `Q` quit. Tray: right-click the icon.

## Requirements

Windows 10+, PowerShell 5.1+ (built-in).

## License

MIT (c) 2025
