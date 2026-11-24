@echo off
rem Starts Degree Atlas. Rebuilds when Dart sources changed; "launch.bat --rebuild" forces a rebuild.
setlocal
set "ROOT=%~dp0"
set "EXE=%ROOT%app\build\windows\x64\runner\Release\degree_atlas.exe"
set "DEGREE_ATLAS_DATA=%ROOT%data"
if exist "C:\src\flutter\bin" set "PATH=C:\src\flutter\bin;%PATH%"

if /i "%~1"=="--rebuild" goto build
if not exist "%EXE%" goto build
rem Without Flutter (prebuilt release install) never try to rebuild.
where flutter >nul 2>nul
if errorlevel 1 goto run
powershell -NoProfile -Command "$exe=(Get-Item -LiteralPath '%EXE%').LastWriteTimeUtc; $newer=Get-ChildItem -LiteralPath '%ROOT%app\lib' -Filter '*.dart' -File | Where-Object { $_.LastWriteTimeUtc -gt $exe } | Select-Object -First 1; if ($newer) { exit 1 }"
if errorlevel 1 goto build
goto run

:build
where flutter >nul 2>nul
if errorlevel 1 (
  echo App not found and Flutter is not installed. Run: python scripts\setup.py
  pause
  exit /b 1
)
echo Building Degree Atlas...
pushd "%ROOT%app"
call flutter build windows --release
if errorlevel 1 (
  echo Build failed.
  popd
  pause
  exit /b 1
)
popd

:run
start "" "%EXE%"
