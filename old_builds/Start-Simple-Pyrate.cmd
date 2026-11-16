@echo off
setlocal
set "PyratePowerShell=%SystemRoot%\System32\WindowsPowerShell\v1.0\powershell.exe"
if exist "%SystemRoot%\Sysnative\WindowsPowerShell\v1.0\powershell.exe" set "PyratePowerShell=%SystemRoot%\Sysnative\WindowsPowerShell\v1.0\powershell.exe"
if not exist "%PyratePowerShell%" (
  echo Windows PowerShell 5.1 is required to launch Simple Pyrate.
  pause
  exit /b 1
)
if not exist "%~dp0SimplePyrate.ps1" (
  echo Extract the whole Simple Pyrate ZIP before running this launcher.
  pause
  exit /b 1
)
start "" "%PyratePowerShell%" -NoLogo -NoProfile -STA -WindowStyle Hidden -ExecutionPolicy Bypass -File "%~dp0SimplePyrate.ps1"
endlocal
