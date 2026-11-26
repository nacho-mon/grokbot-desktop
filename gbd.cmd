@echo off
rem gbd.cmd - fast Grok Bot Desktop client (wraps gbd.exe; builds it once with the .NET Framework csc if missing).
setlocal
set "GBD_HOME=%~dp0"
if not exist "%GBD_HOME%gbd.exe" (
  powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%GBD_HOME%scripts\build-client.ps1" >nul 2>&1
)
if not exist "%GBD_HOME%gbd.exe" (
  echo {"ok":false,"error":"client_missing","message":"Could not build gbd.exe. Use scripts\\build-client.ps1 or grokbot-desktop.ps1."}
  exit /b 1
)
"%GBD_HOME%gbd.exe" %*
exit /b %ERRORLEVEL%
