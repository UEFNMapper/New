@echo off
chcp 65001 >nul
cd /d "%~dp0"

where python >nul 2>nul
if errorlevel 1 goto sans_python
where ffmpeg >nul 2>nul
if errorlevel 1 goto sans_ffmpeg

echo Installation des modules Python (premiere fois seulement)...
python -m pip install --quiet --disable-pip-version-check -r requirements.txt
if errorlevel 1 goto erreur
python studio.py
if errorlevel 1 goto erreur
exit /b 0

:sans_python
echo Python est introuvable.
echo Installe-le depuis https://www.python.org/downloads/
echo IMPORTANT : coche la case "Add python.exe to PATH" pendant l installation.
pause
exit /b 1

:sans_ffmpeg
echo ffmpeg est introuvable.
echo Ouvre PowerShell et tape :   winget install Gyan.FFmpeg
echo puis ferme cette fenetre et relance lancer.bat.
pause
exit /b 1

:erreur
pause
exit /b 1
