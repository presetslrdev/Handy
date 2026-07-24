@echo off
setlocal EnableDelayedExpansion

REM ============================================================================
REM Handy - Redirect model downloads to a custom directory
REM ============================================================================
REM
REM By default, Handy stores downloaded models in two locations on the C: drive:
REM
REM   1. Legacy models:     %%APPDATA%%\com.pais.handy\models\
REM   2. HuggingFace cache: %%USERPROFILE%%\.cache\huggingface\hub\  (v0.9.4+)
REM
REM This script redirects both locations to a directory of your choice,
REM so all models live there instead of consuming space on C:.
REM
REM HOW IT WORKS:
REM   - Creates a directory junction (symlink) so the AppData\models folder
REM     points to <target_dir>\models
REM   - Sets the HF_HOME environment variable so HuggingFace downloads go
REM     to <target_dir>\hf_cache
REM   - Moves any already-downloaded models to the new locations
REM
REM USAGE:
REM   redirect_models.bat              - stores models next to handy.exe
REM   redirect_models.bat D:\MyModels  - stores models in D:\MyModels
REM
REM   1. Close Handy (check the system tray!)
REM   2. Run this script (admin rights may be needed for directory junctions)
REM   3. Restart Handy
REM
REM NOTE: This script is safe to run multiple times.
REM ============================================================================

REM ---------------------------------------------------------------------------
REM Determine target directory: use argument if provided, otherwise script dir
REM ---------------------------------------------------------------------------
if "%~1"=="" (
    set "TARGET_DIR=%~dp0"
) else (
    set "TARGET_DIR=%~1"
)
REM Remove trailing backslash
if "!TARGET_DIR:~-1!"=="\" set "TARGET_DIR=!TARGET_DIR:~0,-1!"

set "APPDATA_HANDY=%APPDATA%\com.pais.handy"
set "APPDATA_MODELS=%APPDATA_HANDY%\models"
set "TARGET_MODELS=!TARGET_DIR!\models"
set "HF_DEFAULT_CACHE=%USERPROFILE%\.cache\huggingface\hub"
set "HF_NEW_HOME=!TARGET_DIR!\hf_cache"
set "HF_NEW_HUB=!HF_NEW_HOME!\hub"

echo.
echo  ========================================
echo   Handy - Model Storage Redirect Script
echo  ========================================
echo.
echo  Target directory  : !TARGET_DIR!
echo  AppData directory : %APPDATA_HANDY%
echo.

REM ---------------------------------------------------------------------------
REM Step 0: Check that Handy is not running
REM ---------------------------------------------------------------------------
tasklist /FI "IMAGENAME eq handy.exe" 2>nul | find /I "handy.exe" >nul
if %errorlevel%==0 (
    echo  [ERROR] Handy is currently running.
    echo          Please close it first, then re-run this script.
    echo.
    pause
    exit /b 1
)
echo  [OK] Handy is not running.

REM ---------------------------------------------------------------------------
REM Validate target directory
REM ---------------------------------------------------------------------------
if not exist "!TARGET_DIR!" (
    mkdir "!TARGET_DIR!" 2>nul
    if errorlevel 1 (
        echo  [ERROR] Cannot create target directory: !TARGET_DIR!
        echo          Check that the path is valid and you have write access.
        echo.
        pause
        exit /b 1
    )
    echo  [OK] Created target directory: !TARGET_DIR!
)

REM ---------------------------------------------------------------------------
REM Step 1: Redirect legacy models (AppData\models -> target_dir\models)
REM ---------------------------------------------------------------------------
echo.
echo  --- Step 1: Legacy models directory ---
echo.

REM Ensure the target models directory exists
if not exist "!TARGET_MODELS!" (
    mkdir "!TARGET_MODELS!"
    echo  [OK] Created: !TARGET_MODELS!
)

REM Check if the junction already exists
fsutil reparsepoint query "%APPDATA_MODELS%" >nul 2>&1
if %errorlevel%==0 (
    echo  [SKIP] Junction already exists: %APPDATA_MODELS%
    goto step2
)

REM If the AppData models folder exists as a regular directory, move its contents
if exist "%APPDATA_MODELS%" (
    echo  [INFO] Moving existing models from AppData to target directory...
    for %%F in ("%APPDATA_MODELS%\*") do (
        if exist "%%F" (
            echo         Moving: %%~nxF
            move /Y "%%F" "!TARGET_MODELS!\" >nul
        )
    )
    REM Remove the now-empty directory
    rmdir /S /Q "%APPDATA_MODELS%" 2>nul
    echo  [OK] Existing models moved.
)

REM Create the directory junction
mklink /J "%APPDATA_MODELS%" "!TARGET_MODELS!" >nul 2>&1
if %errorlevel%==0 (
    echo  [OK] Junction created:
    echo       %APPDATA_MODELS%
    echo       ==^> !TARGET_MODELS!
) else (
    echo  [ERROR] Failed to create junction. Try running as Administrator.
)

REM ---------------------------------------------------------------------------
REM Step 2: Redirect HuggingFace cache via HF_HOME environment variable
REM ---------------------------------------------------------------------------
:step2
echo.
echo  --- Step 2: HuggingFace model cache ---
echo.

REM Create the HF cache directory structure
if not exist "!HF_NEW_HUB!" (
    mkdir "!HF_NEW_HUB!"
    echo  [OK] Created: !HF_NEW_HUB!
)

REM Move existing HF-cached models if present
if exist "%HF_DEFAULT_CACHE%" (
    set "FOUND_MODELS=0"
    for /D %%D in ("%HF_DEFAULT_CACHE%\models--*") do (
        set "FOUND_MODELS=1"
        echo  [INFO] Moving HF cached model: %%~nxD
        if not exist "!HF_NEW_HUB!\%%~nxD" (
            move /Y "%%D" "!HF_NEW_HUB!\" >nul
        ) else (
            echo         [SKIP] Already exists in target, removing old copy...
            rmdir /S /Q "%%D" 2>nul
        )
    )
    if "!FOUND_MODELS!"=="0" (
        echo  [SKIP] No HuggingFace cached models found to move.
    ) else (
        echo  [OK] HuggingFace models moved.
    )
) else (
    echo  [SKIP] No existing HuggingFace cache found at default location.
)

REM Set HF_HOME environment variable (user-level, persists across reboots)
set "CURRENT_HF_HOME="
for /F "tokens=2*" %%A in ('reg query "HKCU\Environment" /v HF_HOME 2^>nul ^| find "HF_HOME"') do set "CURRENT_HF_HOME=%%B"

if /I "!CURRENT_HF_HOME!"=="!HF_NEW_HOME!" (
    echo  [SKIP] HF_HOME already set to: !HF_NEW_HOME!
) else (
    setx HF_HOME "!HF_NEW_HOME!" >nul 2>&1
    if %errorlevel%==0 (
        echo  [OK] HF_HOME environment variable set:
        echo       HF_HOME = !HF_NEW_HOME!
    ) else (
        echo  [ERROR] Failed to set HF_HOME. Try running as Administrator.
    )
)

REM ---------------------------------------------------------------------------
REM Done
REM ---------------------------------------------------------------------------
echo.
echo  ========================================
echo   Done! All models will now be stored in:
echo.
echo   Legacy:  !TARGET_MODELS!\
echo   HF Hub:  !HF_NEW_HUB!\
echo  ========================================
echo.
echo  You can now start Handy.
echo.
pause
