@echo off
rem Minecraft x Dota: double click. Settings: settings.ini (made on the first run)
chcp 65001 >nul
cd /d "%~dp0"
where python >nul 2>nul || (echo Installing Python 3.12... & winget install -e --id Python.Python.3.12 --accept-source-agreements --accept-package-agreements & echo Restart this file after the install. & pause & exit /b)
python tools\mcdota.py host
pause
