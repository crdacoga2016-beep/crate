@echo off
chcp 65001 >nul
cd /d "%~dp0"
set /p MUSIC=Carpeta a analizar (ej. G:\musica): 
if "%MUSIC%"=="" goto :eof
python tools\analyze.py --root "%MUSIC%"
echo.
pause
