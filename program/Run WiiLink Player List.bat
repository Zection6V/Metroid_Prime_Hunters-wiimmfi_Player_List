@echo off
REM WiiLink WFC - MPH Player List - launcher
REM ダブルクリックで起動。追加インストール不要（Windows標準のPowerShellを使用）。
cd /d "%~dp0"
start "" /min powershell.exe -NoProfile -ExecutionPolicy Bypass -STA -WindowStyle Hidden -File "%~dp0WiiLink-PlayerList.ps1"
