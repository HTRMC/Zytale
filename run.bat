@echo off
setlocal enabledelayedexpansion

:: Change to script directory
cd /D "%~dp0"

:: Install Zig via mise if not already installed
echo Ensuring Zig master is installed via mise...
mise install zig@master

if errorlevel 1 (
    echo Failed to install Zig via mise!
    exit /b 1
)

:: Parse optimization mode argument
set OPTIMIZE_FLAG=
set OTHER_ARGS=

:parse_args
if "%~1"=="" goto :done_parsing
if /i "%~1"=="--om" (
    set OPTIMIZE_FLAG=-Doptimize=%~2
    shift
    shift
    goto :parse_args
)
set OTHER_ARGS=%OTHER_ARGS% %1
shift
goto :parse_args

:done_parsing

:: Run the project
echo.
echo Running Zytale...
if not "%OPTIMIZE_FLAG%"=="" echo Optimization mode: %OPTIMIZE_FLAG%
echo.
mise exec zig@master -- zig build run %OPTIMIZE_FLAG% %OTHER_ARGS%

if errorlevel 1 (
    echo.
    echo Build or run failed!
    exit /b 1
)