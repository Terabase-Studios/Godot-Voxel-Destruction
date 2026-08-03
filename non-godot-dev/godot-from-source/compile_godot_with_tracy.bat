@echo off
setlocal EnableDelayedExpansion
cd /d "%~dp0"

title Compile Godot with Tracy

echo ============================================
echo      Compile Godot (Tracy Profiler Build)
echo ============================================
echo.

:: Tracy source
set "TRACY_PATH=%~dp0tracy"

if not exist "%TRACY_PATH%\CMakeLists.txt" (
    echo Tracy source not found at "%TRACY_PATH%".
    echo Run setup_godot_env.bat first.
    pause
    exit /b 1
)

:: Godot engine source
set "GODOT_SRC=%~dp0godot-source"

if not exist "%GODOT_SRC%\SConstruct" (
    echo Godot source not found at "%GODOT_SRC%" - no SConstruct file there.
    pause
    exit /b 1
)

echo Select build target:
echo   1. template_release
echo   2. template_debug
echo   3. editor
echo.
set /p targetchoice=Target [1]: 
if "%targetchoice%"=="" set targetchoice=1

if "%targetchoice%"=="1" set TARGET=template_release
if "%targetchoice%"=="2" set TARGET=template_debug
if "%targetchoice%"=="3" set TARGET=editor

if not defined TARGET (
    echo Invalid selection.
    pause
    exit /b 1
)

echo.
echo Running (from %GODOT_SRC%):
echo scons platform=windows target=%TARGET% debug_symbols=yes profiler=tracy profiler_path="%TRACY_PATH%" disable_path_overrides=no
echo.
 
pushd "%GODOT_SRC%"
scons platform=windows target=%TARGET% debug_symbols=yes profiler=tracy profiler_path="%TRACY_PATH%" disable_path_overrides=no
popd

echo.
pause
