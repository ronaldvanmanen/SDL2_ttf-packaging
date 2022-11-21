@ECHO OFF
powershell.exe -NoLogo -NoProfile -ExecutionPolicy ByPass -Command "& """%~dp0nugetize-sdl2_ttf.ps1""" %*"
EXIT /B %ERRORLEVEL%
