@echo off
title Godot Build Environment Setup

echo ============================================
echo      Godot Build Environment Setup
echo ============================================
echo.

:: Check Python
python --version >nul 2>&1
if errorlevel 1 (
    echo Python is not installed or not in PATH.
    pause
    exit /b 1
)

echo Updating pip...
python -m pip install --upgrade pip

echo Installing/Updating SCons...
python -m pip install --upgrade scons

echo.

:: Check Git
git --version >nul 2>&1
if errorlevel 1 (
    echo Git is not installed.
    echo https://git-scm.com/download/win
    pause
    exit /b 1
)

:: Find Visual Studio
set VSWHERE="%ProgramFiles(x86)%\Microsoft Visual Studio\Installer\vswhere.exe"

if not exist %VSWHERE% (
    echo Visual Studio Installer not found.
    echo Install Visual Studio 2022 Community with Desktop development with C++.
    pause
    exit /b 1
)

for /f "usebackq tokens=*" %%i in (`%VSWHERE% -latest -property installationPath`) do (
    set VSINSTALL=%%i
)

if "%VSINSTALL%"=="" (
    echo Visual Studio not found.
    pause
    exit /b 1
)

if defined VSCMD_VER (
    echo Visual Studio environment already initialized in this shell - skipping vcvars64.
) else (
    call "%VSINSTALL%\VC\Auxiliary\Build\vcvars64.bat"
)

:: Tracy
set "TRACY_VERSION=v0.14.1"
set "TRACY_DIR=%~dp0tracy"
set "TRACY_SERVER_DIR=%~dp0tracy-server"

:: Tracy client source
if exist "%TRACY_DIR%\CMakeLists.txt" (
    echo Tracy client source already present at %TRACY_DIR%
) else (
    echo Downloading Tracy client source %TRACY_VERSION%...
    git clone -b %TRACY_VERSION% --single-branch https://github.com/wolfpld/tracy.git "%TRACY_DIR%"
    if errorlevel 1 (
        echo Failed to download Tracy client source.
        pause
        exit /b 1
    )
)

:: Tracy profiler
if exist "%TRACY_SERVER_DIR%" (
    echo Tracy profiler already present at %TRACY_SERVER_DIR%
) else (
    echo Downloading Tracy Windows profiler %TRACY_VERSION%...

    mkdir "%TRACY_SERVER_DIR%"

    curl -L ^
        -o "%TRACY_SERVER_DIR%\windows-%TRACY_VERSION:~1%.zip" ^
        "https://github.com/wolfpld/tracy/releases/download/%TRACY_VERSION%/windows-%TRACY_VERSION:~1%.zip"

    if errorlevel 1 (
        echo Failed to download Tracy Windows release.
        pause
        exit /b 1
    )

    echo Extracting Tracy Windows release...

    tar -xf "%TRACY_SERVER_DIR%\windows-%TRACY_VERSION:~1%.zip" ^
        -C "%TRACY_SERVER_DIR%"

    if errorlevel 1 (
        echo Failed to extract Tracy Windows release.
        pause
        exit /b 1
    )

    del "%TRACY_SERVER_DIR%\windows-%TRACY_VERSION:~1%.zip"

    echo Tracy Windows profiler installed successfully.
)

echo Tracy %TRACY_VERSION% ready.

:: Godot Source
set GODOT_BRANCH=master
set "GODOT_DIR=%~dp0godot-source"

if exist "%GODOT_DIR%\SConstruct" (
    echo Godot source already present at %GODOT_DIR%
) else (
    if exist "%GODOT_DIR%" (
        echo Removing incomplete previous clone at %GODOT_DIR%...
        rmdir /s /q "%GODOT_DIR%"
    )
    echo Cloning Godot engine source, branch: %GODOT_BRANCH%
    git -c core.longpaths=true clone -b %GODOT_BRANCH% --single-branch https://github.com/godotengine/godot.git "%GODOT_DIR%"
    if errorlevel 1 (
        echo Failed to clone Godot source.
        pause
        exit /b 1
    )
)

:: Windows build dependencies (AccessKit, Direct3D 12) - scons defaults to
:: building both drivers in and fails without them present.
echo.
echo Installing Windows build dependencies (AccessKit, Direct3D 12 SDK)...
pushd "%GODOT_DIR%"
python misc\scripts\install_accesskit.py
python misc\scripts\install_d3d12_sdk_windows.py
python misc\scripts\install_angle.py
popd

echo.
echo ============================================
echo Environment Ready!
echo.
python --version
scons --version
git --version
cl
echo Tracy source: %TRACY_DIR%
echo Godot source: %GODOT_DIR%
echo ============================================

cmd