@echo off
rem Eseguito da Windows Setup come SYSTEM, prima del primo accesso.
rem build-iso.ps1 sostituisce __ARGS__ con il profilo scelto.
if not exist "%SystemDrive%\ItsmeOS\logs" mkdir "%SystemDrive%\ItsmeOS\logs"
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%SystemDrive%\ItsmeOS\Set-ItsmeProfile.ps1" __ARGS__ -FirstBoot >> "%SystemDrive%\ItsmeOS\logs\setupcomplete.log" 2>&1
