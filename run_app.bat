@echo off
TITLE Tzion Stockly - Launch Application
COLOR 0A

echo ========================================================
echo         Tzion Stockly - Tanzania Inventory App
echo ========================================================
echo.

SET FLUTTER_PATH="C:\Users\user\Downloads\flutter_windows_3.47.5-stable\flutter\bin\flutter.bat"

IF EXIST %FLUTTER_PATH% (
    SET FLUTTER_CMD=%FLUTTER_PATH%
) ELSE (
    SET FLUTTER_CMD=flutter
)

echo Select target platform to launch:
echo [1] Chrome Web Browser (Recommended - Instant ^& Works Everywhere)
echo [2] Windows Native Desktop App (Requires Windows Developer Mode)
echo [3] Microsoft Edge Web Browser
echo.

SET CHOICE=1
SET /P CHOICE="Enter choice (1, 2, or 3) [Default is 1]: "

IF "%CHOICE%"=="2" (
    echo.
    echo Launching Windows Native Desktop app...
    call %FLUTTER_CMD% run -d windows
    IF %ERRORLEVEL% NEQ 0 (
        echo.
        echo NOTE: Windows Native build requires Windows Developer Mode for C++ plugin symlinks.
        echo Opening Windows Developer Settings...
        start ms-settings:developers
        echo.
        echo Fallback: Launching in Chrome Web Browser...
        call %FLUTTER_CMD% run -d chrome
    )
) ELSE IF "%CHOICE%"=="3" (
    echo.
    echo Launching Edge Web Browser...
    call %FLUTTER_CMD% run -d edge
) ELSE (
    echo.
    echo Launching Chrome Web Browser...
    call %FLUTTER_CMD% run -d chrome
)

pause
