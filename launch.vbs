' ScreenGuard gizli baslatici - konsol penceresi gostermez
Dim shell, script
Set shell = CreateObject("Wscript.Shell")
script = shell.ExpandEnvironmentStrings("%LOCALAPPDATA%\ScreenGuard\watch.ps1")
shell.Run "powershell.exe -NoProfile -WindowStyle Hidden -ExecutionPolicy Bypass -File """ & script & """", 0, False
