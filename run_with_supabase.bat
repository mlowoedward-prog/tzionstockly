@echo off
TITLE Tzion Stockly - Launch with Supabase Cloud Sync
COLOR 0B

echo ========================================================
echo   Tzion Stockly - Launch with Supabase Cloud Credentials
echo ========================================================
echo.

SET FLUTTER_PATH="C:\Users\user\Downloads\flutter_windows_3.47.5-stable\flutter\bin\flutter.bat"

IF EXIST %FLUTTER_PATH% (
    SET FLUTTER_CMD=%FLUTTER_PATH%
) ELSE (
    SET FLUTTER_CMD=flutter
)

SET /P SUPABASE_URL="Enter Supabase Project URL (e.g. https://xyz.supabase.co): "
SET /P SUPABASE_ANON_KEY="Enter Supabase Anon Key: "

echo.
echo Select target platform to launch:
echo [1] Chrome Web Browser (Recommended)
echo [2] Windows Native Desktop App (Requires Windows Developer Mode)
echo [3] Microsoft Edge Web Browser
echo.

SET CHOICE=1
SET /P CHOICE="Enter choice (1, 2, or 3) [Default is 1]: "

IF "%CHOICE%"=="2" (
    echo.
    echo Launching Windows Native Desktop app...
    call %FLUTTER_CMD% run -d windows --dart-define=SUPABASE_URL=%SUPABASE_URL% --dart-define=SUPABASE_ANON_KEY=%SUPABASE_ANON_KEY%
    IF %ERRORLEVEL% NEQ 0 (
        echo.
        echo NOTE: Windows Native build requires Windows Developer Mode.
        echo Opening Windows Developer Settings...
        start ms-settings:developers
        echo.
        echo Fallback: Launching in Chrome Web Browser...
        call %FLUTTER_CMD% run -d chrome --dart-define=SUPABASE_URL=%SUPABASE_URL% --dart-define=SUPABASE_ANON_KEY=%SUPABASE_ANON_KEY%
    )
) ELSE IF "%CHOICE%"=="3" (
    echo.
    echo Launching Edge Web Browser...
    call %FLUTTER_CMD% run -d edge --dart-define=SUPABASE_URL=%SUPABASE_URL% --dart-define=SUPABASE_ANON_KEY=%SUPABASE_ANON_KEY%
) ELSE (
    echo.
    echo Launching Chrome Web Browser...
    call %FLUTTER_CMD% run -d chrome --dart-define=SUPABASE_URL=%SUPABASE_URL% --dart-define=SUPABASE_ANON_KEY=%SUPABASE_ANON_KEY%
)

pause
