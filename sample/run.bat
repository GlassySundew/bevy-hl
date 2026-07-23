@echo off
setlocal

set "SAMPLE_DIR=%~dp0"
if "%SAMPLE_DIR:~-1%"=="\" set "SAMPLE_DIR=%SAMPLE_DIR:~0,-1%"
set "LIB_DIR=%SAMPLE_DIR%\.."
set "HL_EXE=%LIB_DIR%\..\..\x64\Debug\hl.exe"
set "HDLL=%LIB_DIR%\build-win\bin\Release\bevy.hdll"

call "%LIB_DIR%\build.bat"
if errorlevel 1 exit /b %errorlevel%

pushd "%SAMPLE_DIR%"
haxe sample.hxml
if errorlevel 1 exit /b %errorlevel%

copy /Y "%HDLL%" "%SAMPLE_DIR%\bevy.hdll" >nul
"%HL_EXE%" sample.hl
set "RESULT=%ERRORLEVEL%"
del /Q "%SAMPLE_DIR%\bevy.hdll" >nul 2>nul
popd
exit /b %RESULT%
