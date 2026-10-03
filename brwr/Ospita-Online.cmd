@echo off
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%~dp0tools\host_web.ps1"
if errorlevel 1 pause
