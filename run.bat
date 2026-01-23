@echo off
setlocal enabledelayedexpansion

:: Change to script directory
cd /D "%~dp0"

:: Read Zig version from .zigversion file
set /p ZIG_VERSION=<.zigversion
set ZIG_FOLDER=compiler\zig
set ZIG_ARCHIVE=zig-x86_64-windows-%ZIG_VERSION%

:: Check if compiler exists
if exist "%ZIG_FOLDER%\zig.exe" (
    echo Zig compiler found!
) else (
    echo Zig compiler not found. Installing version %ZIG_VERSION%...

    :: Create compiler directory
    if not exist compiler mkdir compiler

    :: Download Zig
    echo Downloading Zig...
    curl -L -o "compiler\zig.zip" "https://ziglang.org/builds/%ZIG_ARCHIVE%.zip"

    if errorlevel 1 (
        echo Failed to download Zig compiler!
        exit /b 1
    )

    :: Extract Zig
    echo Extracting Zig...
    tar -xf "compiler\zig.zip" -C compiler

    :: Rename folder
    if exist "compiler\%ZIG_ARCHIVE%" (
        ren "compiler\%ZIG_ARCHIVE%" zig
    )

    :: Clean up
    del "compiler\zig.zip"

    echo Zig compiler installed successfully!
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
echo Running ZigZag...
if not "%OPTIMIZE_FLAG%"=="" echo Optimization mode: %OPTIMIZE_FLAG%
echo.
"%ZIG_FOLDER%\zig.exe" build run %OPTIMIZE_FLAG% %OTHER_ARGS%

if errorlevel 1 (
    echo.
    echo Build or run failed!
    exit /b 1
)