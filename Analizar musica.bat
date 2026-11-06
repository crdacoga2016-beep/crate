@echo off
chcp 65001 >nul
cd /d "%~dp0"
python tools\analyze.py --library
echo.
pause
