@echo off
chcp 65001 >nul
setlocal

powershell.exe -NoLogo -NoProfile -ExecutionPolicy Bypass -File "%~dp0remove-deb.ps1" %*
set "REMOVE_DEB_EXIT=%ERRORLEVEL%"

echo.
if "%REMOVE_DEB_EXIT%"=="0" (
    echo Finished successfully.
) else (
    echo Stopped or failed. Exit code: %REMOVE_DEB_EXIT%
)
echo.
pause
exit /b %REMOVE_DEB_EXIT%
