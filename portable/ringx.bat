@echo off
rem Ringx launcher: uses the py launcher that ships with Python (pythonw).
where pyw >nul 2>nul
if %errorlevel%==0 (
    pyw "%~dp0ringx.pyw"
    exit /b
)
where pythonw >nul 2>nul
if %errorlevel%==0 (
    pythonw "%~dp0ringx.pyw"
    exit /b
)
echo.
echo  Python not found. One-time setup:
echo    1. Download Python 3.11+ x64 from https://www.python.org/downloads/
echo    2. Run the installer, tick "Add python.exe to PATH", click Install.
echo    3. Run this file again.
echo.
pause
