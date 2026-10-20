@echo off
title Apir Desktop Companion Server
cd /d "%~dp0apir_desktop"
".venv\Scripts\python.exe" server.py %*
pause
