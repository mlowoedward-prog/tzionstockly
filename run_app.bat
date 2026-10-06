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
echo [1] Chrome Web Browser (Recommended - Fast ^& Reliable)
echo [2] Windows Desktop App
echo [3] Microsoft Edge Web Browser
echo.

SET /P CHOICE="Enter choice (1, 2, or 3) [Default is 1]: "

IF "%CHOICE%"=="2" (
    echo.
    echo Launching Windows Desktop app...
    call %FLUTTER_CMD% run -d windows
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
