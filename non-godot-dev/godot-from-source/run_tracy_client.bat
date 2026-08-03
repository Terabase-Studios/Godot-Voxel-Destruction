@echo off
setlocal EnableDelayedExpansion
cd /d "%~dp0"

title Run Godot (Tracy Build)

echo ============================================
echo      Run Godot (Tracy Profiler Build)
echo ============================================
echo.

:: Project lives two folders up from this script.
set "PROJECT_PATH=%~dp0..\.."

if not exist "%PROJECT_PATH%\project.godot" (
    echo No project.godot found at "%PROJECT_PATH%".
    pause
    exit /b 1
)

set "EXE_NAME=godot.windows.template_release.x86_64.console.exe"
set "GODOT_EXE=%~dp0godot-source\bin\%EXE_NAME%"

if not exist "%GODOT_EXE%" (
    echo Build not found at "%GODOT_EXE%".
    echo Run compile_godot_with_tracy.bat first.
    pause
    exit /b 1
)

echo Project: %PROJECT_PATH%
echo Binary:  %GODOT_EXE%
echo.

"%GODOT_EXE%" --path "%PROJECT_PATH%"

echo.
pause