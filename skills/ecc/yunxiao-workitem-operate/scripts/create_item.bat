@echo off
REM This batch file is a convenience wrapper for the PowerShell script.
REM It executes the create_item.ps1 script, passing all command-line arguments.

powershell.exe -ExecutionPolicy Bypass -NoProfile -File "%~dp0create_item.ps1" %*
