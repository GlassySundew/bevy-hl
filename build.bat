@echo off
setlocal

set "SCRIPT_DIR=%~dp0"
if "%SCRIPT_DIR:~-1%"=="\" set "SCRIPT_DIR=%SCRIPT_DIR:~0,-1%"
set "BUILD_DIR=%SCRIPT_DIR%\build-win"

cmake -S "%SCRIPT_DIR%" -B "%BUILD_DIR%" -G "Visual Studio 16 2019" -A x64
if errorlevel 1 exit /b %errorlevel%

cmake --build "%BUILD_DIR%" --config Release --target bevy.hdll
if errorlevel 1 exit /b %errorlevel%

echo.
echo Built bevy.hdll in:
echo   %BUILD_DIR%\bin\Release

