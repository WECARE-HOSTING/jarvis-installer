@echo off
powershell -NoProfile -ExecutionPolicy Bypass -Command "& ([scriptblock]::Create((iwr -useb 'https://raw.githubusercontent.com/WECARE-HOSTING/jarvis-installer/main/install.ps1').Content)) 'nicole'"
pause
