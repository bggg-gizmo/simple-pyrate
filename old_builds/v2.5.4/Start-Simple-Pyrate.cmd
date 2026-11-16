@echo off
setlocal DisableDelayedExpansion
set "PyratePowerShell=%SystemRoot%\System32\WindowsPowerShell\v1.0\powershell.exe"
if exist "%SystemRoot%\Sysnative\WindowsPowerShell\v1.0\powershell.exe" set "PyratePowerShell=%SystemRoot%\Sysnative\WindowsPowerShell\v1.0\powershell.exe"
set "PyrateScript=%~dp0SimplePyrate.ps1"
if not exist "%PyratePowerShell%" (
  echo Windows PowerShell 5.1 is required to launch Simple Pyrate. 1>&2
  if "%~1"=="" pause
  exit /b 1
)
if not exist "%PyrateScript%" (
  echo Extract the whole Simple Pyrate ZIP before running this launcher. 1>&2
  if "%~1"=="" pause
  exit /b 1
)
if not exist "%~dp0VERSION" (
  echo Missing VERSION. Extract the complete Simple Pyrate ZIP, then launch again. 1>&2
  if "%~1"=="" pause
  exit /b 1
)
if /i "%~1"=="-SmokeTest" goto smoke
if /i "%~1"=="-Diagnose" goto diagnose
if /i "%~1"=="-Setup" goto setup
if not "%~1"=="" goto usage

start "" /wait "%PyratePowerShell%" -NoLogo -NoProfile -STA -WindowStyle Hidden -ExecutionPolicy Bypass -File "%PyrateScript%"
set "PyrateExit=%errorlevel%"
if not "%PyrateExit%"=="0" (
  echo Simple Pyrate exited with code %PyrateExit%. 1>&2
  echo Run Start-Simple-Pyrate.cmd -Diagnose in Command Prompt for details. 1>&2
  echo Startup log, if available: "%LOCALAPPDATA%\BGGG\Blackwake\startup-error.log" 1>&2
  pause
)
exit /b %PyrateExit%

:smoke
if not "%~2"=="" goto usage
"%PyratePowerShell%" -NoLogo -NoProfile -NonInteractive -STA -ExecutionPolicy Bypass -File "%PyrateScript%" -SmokeTest
set "PyrateExit=%errorlevel%"
if not "%PyrateExit%"=="0" echo Startup log, if available: "%LOCALAPPDATA%\BGGG\Blackwake\startup-error.log" 1>&2
exit /b %PyrateExit%

:diagnose
if not "%~2"=="" goto usage
"%PyratePowerShell%" -NoLogo -NoProfile -STA -ExecutionPolicy Bypass -File "%PyrateScript%"
exit /b %errorlevel%

:setup
if not "%~2"=="" goto usage
"%PyratePowerShell%" -NoLogo -NoProfile -STA -ExecutionPolicy Bypass -File "%PyrateScript%" -SetupWizard
exit /b %errorlevel%

:usage
echo Usage: Start-Simple-Pyrate.cmd [-SmokeTest ^| -Diagnose ^| -Setup] 1>&2
exit /b 2
