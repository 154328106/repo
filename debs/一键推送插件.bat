@echo off
chcp 65001 >nul
setlocal

powershell.exe -NoLogo -NoProfile -ExecutionPolicy Bypass -File "%~dp0push-deb.ps1" %*
set "PUSH_DEB_EXIT=%ERRORLEVEL%"

echo.
if "%PUSH_DEB_EXIT%"=="0" (
    echo Finished successfully.
) else (
    echo Stopped or failed. Exit code: %PUSH_DEB_EXIT%
)
echo.
pause
exit /b %PUSH_DEB_EXIT%
