@echo off
rem Double-click this file. The first time it sets the server up; after that it opens the settings page.
rem It runs PowerShell with -ExecutionPolicy Bypass because Windows blocks downloaded .ps1 scripts otherwise.
title Wreckfest 2 server
cd /d "%~dp0"
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "scripts\launch.ps1" %*
if errorlevel 1 (
    echo.
    echo Something went wrong. Read the message above, then press a key to close.
    pause >nul
)
