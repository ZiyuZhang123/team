@echo off
setlocal

set "SCRIPT_DIR=%~dp0"
set "ARGS="

:loop
if "%~1"=="" goto run
if /I "%~1"=="--flow-id" (
  set "ARGS=%ARGS% -FlowId ""%~2"""
  shift
  shift
  goto loop
)
if /I "%~1"=="--url" (
  set "ARGS=%ARGS% -Url ""%~2"""
  shift
  shift
  goto loop
)
if /I "%~1"=="--token" (
  set "ARGS=%ARGS% -Token ""%~2"""
  shift
  shift
  goto loop
)
if /I "%~1"=="--limit-num" (
  set "ARGS=%ARGS% -LimitNum ""%~2"""
  shift
  shift
  goto loop
)
set "ARGS=%ARGS% %1"
shift
goto loop

:run
powershell -NoProfile -ExecutionPolicy Bypass -File "%SCRIPT_DIR%beta_executor.ps1" %ARGS%
set "EXIT_CODE=%ERRORLEVEL%"

endlocal & exit /b %EXIT_CODE%
