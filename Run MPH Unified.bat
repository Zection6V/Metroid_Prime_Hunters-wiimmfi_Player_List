@echo off
REM MPH Unified Player List (Wiimmfi + WiiLink) - launcher
REM ダブルクリックで起動。追加インストール不要（Windows標準のPowerShellを使用）。
cd /d "%~dp0"
start "" /min powershell.exe -NoProfile -ExecutionPolicy Bypass -STA -WindowStyle Hidden -File "%~dp0MPH-Unified.ps1"
